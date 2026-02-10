#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${ROOT}/.context/DerivedData"
SIDECAR_DIR="${ROOT}/sidecar"

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

echo "[dev] Launching Flux..."
"${APP_BIN}" &
app_pid="$!"

echo "[dev] Running. Ctrl-C to stop."
wait "${app_pid}"

