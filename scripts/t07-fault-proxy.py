"""Loopback-only HTTP proxy with deterministic T07 fault injection.

The proxy never logs headers or bodies.  It is intended only for repeatable
local resilience tests and has no role in the delivered migration path.
"""

import argparse
import json
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


MAX_BODY_BYTES = 2 * 1024 * 1024
FORWARDED_HEADERS = {"accept", "authorization", "content-type"}


class FaultState:
    def __init__(self, mode, match_path, fault_count):
        self.mode = mode
        self.match_path = match_path
        self.fault_count = fault_count
        self.triggered = 0
        self.lock = threading.Lock()

    def take(self, method, path):
        if self.mode == "pass" or not path.startswith(self.match_path):
            return False
        with self.lock:
            if self.triggered >= self.fault_count:
                return False
            self.triggered += 1
            attempt = self.triggered
        print(f"FAULT mode={self.mode} method={method} path={path} attempt={attempt}", flush=True)
        return True


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        self._handle()

    def do_POST(self):
        self._handle()

    def log_message(self, _format, *_args):
        return

    def _handle(self):
        path = urlsplit(self.path).path
        fault = self.server.fault_state.take(self.command, path)
        if fault and self.server.mode == "status-once":
            self._read_body()
            self._json_error(self.server.fault_status)
            return
        if fault and self.server.mode in ("delay-once", "timeout-once"):
            time.sleep(self.server.delay_seconds)

        try:
            status, content_type, body = self._forward()
            if fault and self.server.mode == "corrupt-digest-once" and status == 200:
                body = self._corrupt_digest(body)
            self._send(status, content_type, body)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            return
        except Exception:
            try:
                self._json_error(502)
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                return

    def _read_body(self):
        raw_length = self.headers.get("Content-Length", "0")
        try:
            length = int(raw_length)
        except ValueError as error:
            raise RuntimeError("Invalid length") from error
        if length < 0 or length > MAX_BODY_BYTES:
            raise RuntimeError("Body too large")
        return self.rfile.read(length) if length else None

    def _forward(self):
        body = self._read_body()
        headers = {
            name: value
            for name, value in self.headers.items()
            if name.lower() in FORWARDED_HEADERS
        }
        request = urllib.request.Request(
            self.server.upstream.rstrip("/") + self.path,
            data=body,
            headers=headers,
            method=self.command,
        )
        try:
            response = urllib.request.urlopen(request, timeout=self.server.upstream_timeout)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            response_body = response.read(MAX_BODY_BYTES + 1)
            if len(response_body) > MAX_BODY_BYTES:
                raise RuntimeError("Response too large")
            return (
                response.status,
                response.headers.get("Content-Type", "application/json; charset=utf-8"),
                response_body,
            )

    @staticmethod
    def _corrupt_digest(body):
        payload = json.loads(body.decode("utf-8"))
        if not isinstance(payload, dict) or "digest" not in payload:
            raise RuntimeError("Digest missing")
        payload["digest"] = "0" * 64
        return json.dumps(
            payload, ensure_ascii=False, separators=(",", ":")
        ).encode("utf-8")

    def _json_error(self, status):
        body = json.dumps(
            {
                "apiVersion": "1.0",
                "error": {
                    "code": "INJECTED_TEMPORARY_FAILURE",
                    "message": "Errore temporaneo di collaudo.",
                },
            },
            separators=(",", ":"),
        ).encode("utf-8")
        self._send(status, "application/json; charset=utf-8", body)

    def _send(self, status, content_type, body):
        self.close_connection = True
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen-port", required=True, type=int)
    parser.add_argument("--upstream", required=True)
    parser.add_argument(
        "--mode",
        choices=(
            "pass",
            "delay-once",
            "timeout-once",
            "status-once",
            "corrupt-digest-once",
        ),
        default="pass",
    )
    parser.add_argument("--match-path", default="/")
    parser.add_argument("--fault-count", type=int, default=1)
    parser.add_argument("--fault-status", type=int, default=503)
    parser.add_argument("--delay-seconds", type=float, default=2.0)
    parser.add_argument("--upstream-timeout", type=float, default=120.0)
    args = parser.parse_args()
    if not 1 <= args.listen_port <= 65535 or not 1 <= args.fault_count <= 10:
        parser.error("Porta o numero guasti non valido.")
    if args.fault_status < 400 or args.fault_status > 599:
        parser.error("Stato HTTP di guasto non valido.")
    if args.delay_seconds < 0 or args.delay_seconds > 120:
        parser.error("Ritardo non valido.")
    if urlsplit(args.upstream).scheme not in ("http", "https"):
        parser.error("Upstream non valido.")

    server = ThreadingHTTPServer(("127.0.0.1", args.listen_port), ProxyHandler)
    server.upstream = args.upstream
    server.mode = args.mode
    server.delay_seconds = args.delay_seconds
    server.fault_status = args.fault_status
    server.upstream_timeout = args.upstream_timeout
    server.fault_state = FaultState(args.mode, args.match_path, args.fault_count)
    print(
        f"READY port={args.listen_port} mode={args.mode} match={args.match_path}",
        flush=True,
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
