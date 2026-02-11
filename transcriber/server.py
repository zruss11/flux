"""Flux Transcription Server — local speech-to-text via Parakeet CTC."""

import json
import os
import tempfile
from http.server import HTTPServer, BaseHTTPRequestHandler

MODEL_NAME = "nvidia/parakeet-ctc-0.6b"
HOST = "127.0.0.1"
PORT = 7848

# Keep model cache stable and avoid re-downloading across runs.
os.environ.setdefault("HF_HOME", os.path.join(os.path.expanduser("~"), ".flux", "hf"))
os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

# Load model once at startup
print(f"Loading ASR model: {MODEL_NAME} ...")
from transformers import pipeline
from transformers.utils import logging as tlogging

tlogging.disable_progress_bar()

try:
    # Prevent any runtime downloads; `transcriber/setup.sh` pre-downloads the model.
    pipe = pipeline(
        "automatic-speech-recognition",
        model=MODEL_NAME,
        device="cpu",
        model_kwargs={"local_files_only": True},
    )
except Exception as exc:
    print(
        "Failed to load ASR model from local cache. Run transcriber/setup.sh to download it.\n"
        f"Error: {exc}"
    )
    raise
print("Model loaded successfully.")


class TranscribeHandler(BaseHTTPRequestHandler):
    """Handles /health and /transcribe endpoints."""

    def _send_json(self, status_code: int, data: dict) -> None:
        body = json.dumps(data).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # ── GET /health ──────────────────────────────────────────────────────
    def do_GET(self) -> None:
        if self.path == "/health":
            self._send_json(200, {"status": "ready"})
        else:
            self._send_json(404, {"error": "not found"})

    # ── POST /transcribe ─────────────────────────────────────────────────
    def do_POST(self) -> None:
        if self.path != "/transcribe":
            self._send_json(404, {"error": "not found"})
            return

        tmp_path = None
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            audio_data = self.rfile.read(content_length)

            # Write audio to a temporary WAV file
            fd, tmp_path = tempfile.mkstemp(suffix=".wav")
            with os.fdopen(fd, "wb") as f:
                f.write(audio_data)

            # Run inference
            result = pipe(tmp_path)
            text = result["text"] if result else ""

            self._send_json(200, {"text": text})
        except Exception as exc:
            self._send_json(500, {"error": str(exc)})
        finally:
            if tmp_path and os.path.exists(tmp_path):
                os.remove(tmp_path)

    # Silence default stderr request logging
    def log_message(self, format, *args) -> None:
        pass


def main() -> None:
    server = HTTPServer((HOST, PORT), TranscribeHandler)
    print(f"Transcription server listening on http://{HOST}:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down transcription server.")
        server.server_close()


if __name__ == "__main__":
    main()
