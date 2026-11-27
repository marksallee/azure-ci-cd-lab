"""Tiny stdlib-only HTTP service used as the deployable for the CI/CD lab.

It reports where it is running (APP_ENV / APP_PLATFORM) and which build it is
(APP_VERSION = git SHA), so a smoke test can prove that the *same* image is
running in dev, staging, prod and on the non-Azure VM.
"""
import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def build_info() -> dict:
    return {
        "app": "azure-ci-cd-lab",
        "environment": os.environ.get("APP_ENV", "local"),
        "platform": os.environ.get("APP_PLATFORM", "unknown"),
        "version": os.environ.get("APP_VERSION", "dev"),
        "host": socket.gethostname(),
    }


class Handler(BaseHTTPRequestHandler):
    def _send(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 (stdlib naming)
        if self.path == "/healthz":
            self._send(200, {"status": "ok"})
        elif self.path in ("/", "/version"):
            self._send(200, build_info())
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, fmt: str, *args) -> None:  # keep container logs terse
        print(f"{self.address_string()} {fmt % args}", flush=True)


def make_server(port: int) -> ThreadingHTTPServer:
    return ThreadingHTTPServer(("0.0.0.0", port), Handler)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    print(f"listening on :{port} {build_info()}", flush=True)
    make_server(port).serve_forever()
