#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${ROOT}/.context/DerivedData"
SIDECAR_DIR="${ROOT}/sidecar"
DEV_APP_BUNDLE="${FLUX_DEV_APP_BUNDLE:-$HOME/Applications/Flux Dev.app}"

mkdir -p "${DERIVED_DATA}"

sidecar_pid=""
app_pid=""

cleanup() {
  set +e
  if [[ -n "${app_pid}" ]]; then
    kill "${app_pid}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${sidecar_pid}" ]]; then
    kill "${sidecar_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

if ! command -v npm >/dev/null 2>&1; then
  echo "npm not found (need Node.js installed)." >&2
  exit 1
fi

# Avoid EADDRINUSE if a previous sidecar is still running.
if lsof -nP -iTCP:7847 -sTCP:LISTEN >/dev/null 2>&1; then
  pid="$(lsof -nP -iTCP:7847 -sTCP:LISTEN -t | head -n1 || true)"
  cmd=""
  if [[ -n "${pid}" ]]; then
    cmd="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
  fi

  if [[ "${cmd}" == *"/sidecar/"* ]] || [[ "${cmd}" == *"tsx src/index.ts"* ]]; then
    echo "[dev] Port 7847 in use by previous sidecar (pid ${pid}). Stopping it..."
    kill "${pid}" >/dev/null 2>&1 || true
    sleep 0.3
  else
    echo "[dev] Port 7847 is already in use (pid ${pid}). Stop that process and re-run." >&2
    echo "[dev] Listener command: ${cmd}" >&2
    exit 1
  fi
fi

# Avoid EADDRINUSE if a previous transcriber is still running on port 7849.
if lsof -nP -iTCP:7849 -sTCP:LISTEN >/dev/null 2>&1; then
  tpid="$(lsof -nP -iTCP:7849 -sTCP:LISTEN -t | head -n1 || true)"
  if [[ -n "${tpid}" ]]; then
    echo "[dev] Port 7849 in use by previous transcriber (pid ${tpid}). Stopping it..."
    kill "${tpid}" >/dev/null 2>&1 || true
    sleep 0.3
  fi
fi

# Auto-setup transcriber if venv doesn't exist or requirements changed
TRANSCRIBER_VENV="${HOME}/.flux/transcriber-venv"
NEEDS_SETUP=false
if [[ ! -d "${TRANSCRIBER_VENV}" ]]; then
  NEEDS_SETUP=true
  echo "[dev] Transcriber venv not found. Running first-time setup..."
elif ! diff -q "${ROOT}/transcriber/requirements.txt" "${TRANSCRIBER_VENV}/.requirements-stamp" >/dev/null 2>&1; then
  NEEDS_SETUP=true
  echo "[dev] Transcriber requirements changed. Re-running setup..."
fi

if [[ "${NEEDS_SETUP}" == "true" ]]; then
  echo "[dev] This will download the Parakeet model (~600MB). This only happens once."
  if [[ -x "${ROOT}/transcriber/setup.sh" ]]; then
    bash "${ROOT}/transcriber/setup.sh"
  else
    echo "[dev] Warning: transcriber/setup.sh not found or not executable. Voice transcription will be unavailable." >&2
  fi
else
  echo "[dev] Transcriber venv found."
fi

echo "[dev] Starting sidecar (ws://localhost:7847)..."
(
  cd "${SIDECAR_DIR}"
  if [[ ! -d node_modules ]]; then
    npm install
  fi
  npm start
) &
sidecar_pid="$!"

# Wait for sidecar to be ready before building/launching the app
echo "[dev] Waiting for sidecar..."
for i in $(seq 1 30); do
  if curl -s -o /dev/null -w '' "http://localhost:7847" 2>/dev/null; then
    echo "[dev] Sidecar ready."
    break
  fi
  if ! kill -0 "${sidecar_pid}" 2>/dev/null; then
    echo "[dev] Sidecar process exited unexpectedly." >&2
    exit 1
  fi
  sleep 0.5
done

echo "[dev] Building Flux (Debug)..."
(
  cd "${ROOT}/Flux"
  xcodebuild \
    -scheme Flux \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "${DERIVED_DATA}" \
    build
)

APP_BIN="${DERIVED_DATA}/Build/Products/Debug/Flux"
if [[ ! -x "${APP_BIN}" ]]; then
  echo "[dev] Expected app binary not found at: ${APP_BIN}" >&2
  exit 1
fi

# Install/update a stable dev .app bundle location.
# TCC permissions (Accessibility/Screen Recording) can be finicky when the app path changes.
APP_BUNDLE="${DEV_APP_BUNDLE}"
mkdir -p "$(dirname "${APP_BUNDLE}")"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${APP_BIN}" "${APP_BUNDLE}/Contents/MacOS/Flux"
cp "${ROOT}/Flux/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Package repo skills into the dev app bundle so the Skills UI can discover them
# without requiring per-machine installation into ~/.agents or ~/.claude.
if [[ -d "${ROOT}/.agents/skills" ]]; then
  mkdir -p "${APP_BUNDLE}/Contents/Resources/agents"
  rm -rf "${APP_BUNDLE}/Contents/Resources/agents/skills" >/dev/null 2>&1 || true
  cp -R "${ROOT}/.agents/skills" "${APP_BUNDLE}/Contents/Resources/agents/skills"
fi

# Codesign the bundle so TCC permissions (Accessibility / Screen Recording) stick across rebuilds.
# Prefer Apple Development; fall back to Developer ID; finally fall back to ad-hoc.
SIGN_IDENTITY="${FLUX_CODESIGN_IDENTITY:-}"
if [[ -z "${SIGN_IDENTITY}" ]]; then
  # NOTE: Avoid searching the System keychain here; it can trigger repeated
  # admin-password prompts. We only search user keychains.
  USER_KEYCHAINS=()
  while IFS= read -r kc; do
    # Explicitly exclude system keychains; they can prompt for admin credentials.
    case "${kc}" in
      /Library/Keychains/*|/System/Library/Keychains/*) continue ;;
    esac
    USER_KEYCHAINS+=("${kc}")
  done < <(
    (security list-keychains -d user 2>/dev/null || true) \
      | sed -E 's/^[[:space:]]*"([^"]+)".*/\1/' \
      | awk 'NF { print }'
  )

  # Filter to keychains that exist on disk, to avoid noisy errors.
  EXISTING_USER_KEYCHAINS=()
  if [[ ${#USER_KEYCHAINS[@]} -gt 0 ]]; then
    for kc in "${USER_KEYCHAINS[@]}"; do
      if [[ -f "${kc}" ]]; then
        EXISTING_USER_KEYCHAINS+=("${kc}")
      fi
    done
  fi

  if [[ "${#EXISTING_USER_KEYCHAINS[@]}" -eq 0 ]]; then
    # Fallback: the default login keychain path on modern macOS.
    if [[ -f "${HOME}/Library/Keychains/login.keychain-db" ]]; then
      EXISTING_USER_KEYCHAINS=("${HOME}/Library/Keychains/login.keychain-db")
    elif [[ -f "${HOME}/Library/Keychains/login.keychain" ]]; then
      EXISTING_USER_KEYCHAINS=("${HOME}/Library/Keychains/login.keychain")
    fi
  fi

  IDENTITIES=""
  if [[ "${#EXISTING_USER_KEYCHAINS[@]}" -gt 0 ]]; then
    IDENTITIES="$(
      security find-identity -p codesigning -v ${EXISTING_USER_KEYCHAINS[@]+"${EXISTING_USER_KEYCHAINS[@]}"} 2>/dev/null || true
    )"
  fi

  SIGN_IDENTITY="$(echo "${IDENTITIES}" | awk -F'\"' '/Apple Development:/{print $2; exit}')"
  if [[ -z "${SIGN_IDENTITY}" ]]; then
    SIGN_IDENTITY="$(echo "${IDENTITIES}" | awk -F'\"' '/Developer ID Application:/{print $2; exit}')"
  fi
fi
if [[ -z "${SIGN_IDENTITY}" ]]; then
  SIGN_IDENTITY="-"
  echo "[dev] Warning: no codesigning identity found; using ad-hoc signing (TCC may not persist permissions)." >&2
else
  echo "[dev] Codesigning app with: ${SIGN_IDENTITY}"
fi

codesign --force --deep --sign "${SIGN_IDENTITY}" --timestamp=none "${APP_BUNDLE}" >/dev/null 2>&1 || {
  echo "[dev] codesign failed for identity: ${SIGN_IDENTITY}" >&2
  exit 1
}

codesign --verify --deep --strict "${APP_BUNDLE}" >/dev/null 2>&1 || {
  echo "[dev] codesign verification failed" >&2
  exit 1
}

echo "[dev] Launching Flux..."
open -W "${APP_BUNDLE}" &
app_pid="$!"

echo "[dev] Running. Ctrl-C to stop."
wait "${app_pid}"
