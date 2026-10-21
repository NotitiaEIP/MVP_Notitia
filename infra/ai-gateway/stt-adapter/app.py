"""
NOTITIA — Adaptateur de transcription (interne à la passerelle)

DeepInfra n'expose Whisper que via son API native (/v1/inference/<modèle>,
champ `audio`). LiteLLM, lui, parle le format OpenAI (/v1/audio/transcriptions,
champ `file`). Ce petit service traduit l'un vers l'autre.

- Aucune dépendance : bibliothèque standard Python uniquement.
- Aucun secret ici : la clé DeepInfra arrive dans l'en-tête Authorization
  envoyé par LiteLLM, qui reste seul juge des clés virtuelles et des budgets.
- Aucun port publié : seul LiteLLM l'appelle, sur le réseau Docker interne.
"""

import json
import os
import urllib.error
import urllib.request
import uuid
from email.parser import BytesParser
from email.policy import default as email_policy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = os.environ.get("DEEPINFRA_INFERENCE_URL", "https://api.deepinfra.com/v1/inference")
MAX_BODY = 50 * 1024 * 1024  # 50 Mo ≈ 25 min de WAV 16 kHz mono


def parse_multipart(content_type: str, body: bytes) -> tuple[dict, tuple | None]:
    """Renvoie (champs texte, (nom_fichier, type, octets) | None)."""
    message = BytesParser(policy=email_policy).parsebytes(
        b"Content-Type: " + content_type.encode() + b"\r\n\r\n" + body
    )
    fields, upload = {}, None
    for part in message.iter_parts():
        name = part.get_param("name", header="content-disposition")
        payload = part.get_payload(decode=True) or b""
        if part.get_filename() is not None or name == "file":
            upload = (part.get_filename() or "audio.wav", part.get_content_type(), payload)
        elif name:
            fields[name] = payload.decode("utf-8", errors="replace")
    return fields, upload


def build_multipart(fields: dict, upload: tuple) -> tuple[str, bytes]:
    boundary = uuid.uuid4().hex
    chunks = []
    for name, value in fields.items():
        chunks.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
        )
    filename, ctype, data = upload
    chunks.append(
        f'--{boundary}\r\nContent-Disposition: form-data; name="audio"; filename="{filename}"\r\n'
        f"Content-Type: {ctype}\r\n\r\n".encode()
        + data
        + b"\r\n"
    )
    chunks.append(f"--{boundary}--\r\n".encode())
    return f"multipart/form-data; boundary={boundary}", b"".join(chunks)


def to_deepinfra_fields(fields: dict) -> dict:
    out = {"task": "transcribe"}
    if fields.get("language"):
        out["language"] = fields["language"][:2].lower()
    if fields.get("prompt"):
        out["initial_prompt"] = fields["prompt"]
    if fields.get("temperature"):
        out["temperature"] = fields["temperature"]
    return out


def to_openai_response(result: dict, response_format: str):
    """Renvoie (content_type, corps) au format OpenAI."""
    text = (result.get("text") or "").strip()
    if response_format == "text":
        return "text/plain; charset=utf-8", text.encode()
    if response_format == "verbose_json":
        payload = {
            "task": "transcribe",
            "text": text,
            "language": result.get("language"),
            "duration": result.get("duration"),
            "segments": result.get("segments") or [],
        }
    else:
        payload = {"text": text}
    return "application/json", json.dumps(payload, ensure_ascii=False).encode()


class Handler(BaseHTTPRequestHandler):
    def _send(self, status: int, content_type: str, body: bytes):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status: int, message: str):
        body = json.dumps({"error": {"message": message, "type": "upstream_error"}}).encode()
        self._send(status, "application/json", body)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, "application/json", b'{"status":"ok"}')
        else:
            self._error(404, "not found")

    def do_POST(self):
        if not self.path.endswith("/audio/transcriptions"):
            return self._error(404, "not found")
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            return self._error(413, "audio manquant ou trop volumineux")

        fields, upload = parse_multipart(self.headers.get("Content-Type", ""), self.rfile.read(length))
        model = fields.get("model")
        if not upload or not model:
            return self._error(400, "champs 'file' et 'model' requis")

        ctype, body = build_multipart(to_deepinfra_fields(fields), upload)
        headers = {"Content-Type": ctype}
        if self.headers.get("Authorization"):
            headers["Authorization"] = self.headers["Authorization"]
        request = urllib.request.Request(f"{UPSTREAM}/{model}", data=body, headers=headers)

        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                result = json.loads(response.read())
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                detail = json.loads(raw).get("detail") or raw.decode(errors="replace")
            except ValueError:
                detail = raw.decode(errors="replace")
            return self._error(e.code, str(detail))
        except Exception as e:  # réseau, timeout
            return self._error(502, f"DeepInfra injoignable: {e}")

        self._send(200, *to_openai_response(result, fields.get("response_format", "json")))

    def log_message(self, fmt, *args):
        print("[stt-adapter]", self.address_string(), fmt % args, flush=True)


if __name__ == "__main__":
    print("[stt-adapter] écoute sur :8080", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
