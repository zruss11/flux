#!/usr/bin/env bash
set -euo pipefail

# ── Resolve script directory ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VENV_DIR="$HOME/.flux/transcriber-venv"
export HF_HOME="${HF_HOME:-$HOME/.flux/hf}"
export HF_HUB_DISABLE_PROGRESS_BARS=1
export TOKENIZERS_PARALLELISM=false

echo "==> Creating virtual environment at ${VENV_DIR} ..."
python3 -m venv "${VENV_DIR}"

echo "==> Activating virtual environment ..."
source "${VENV_DIR}/bin/activate"

echo "==> Upgrading pip ..."
pip install --upgrade pip

echo "==> Installing dependencies ..."
pip install -r "${SCRIPT_DIR}/requirements.txt"

echo "==> Pre-downloading Parakeet model ..."
python3 -c "
from transformers import pipeline
pipe = pipeline('automatic-speech-recognition', model='nvidia/parakeet-ctc-0.6b', device='cpu')
print('Model downloaded successfully.')
"

# Write a stamp so dev.sh can detect stale venvs when requirements change.
cp "${SCRIPT_DIR}/requirements.txt" "${VENV_DIR}/.requirements-stamp"

echo ""
echo "Setup complete. Start the server with:"
echo "  source ${VENV_DIR}/bin/activate && python ${SCRIPT_DIR}/server.py"
