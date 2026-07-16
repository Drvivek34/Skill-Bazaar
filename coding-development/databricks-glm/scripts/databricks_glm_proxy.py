#!/usr/bin/env python3
"""Local OpenAI-compatible proxy for Databricks AI Gateway + Grok CLI.

Databricks omits the `model` field on some streaming chunks (notably the
tool_calls finish chunk). Grok deserializes stream events strictly and
fails with:

  serialization error: missing field `model` ...

This proxy forwards all traffic to Databricks and injects
`"model": <DEFAULT_MODEL>` into any chat.completion.chunk that lacks it.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = os.environ.get(
    "DATABRICKS_UPSTREAM",
    "https://dbc-3bbcd3f6-452e.cloud.databricks.com/ai-gateway/mlflow/v1",
).rstrip("/")
TOKEN = os.environ.get("DATABRICKS_TOKEN", "")
DEFAULT_MODEL = os.environ.get("DATABRICKS_DEFAULT_MODEL", "system.ai.glm-5-2")
HOST = os.environ.get("PROXY_HOST", "127.0.0.1")
PORT = int(os.environ.get("PROXY_PORT", "8787"))


def inject_model_json(payload: bytes) -> bytes:
    try:
        obj = json.loads(payload)
    except json.JSONDecodeError:
        return payload
    if not isinstance(obj, dict):
        return payload
    if "model" not in obj or not obj["model"]:
        obj["model"] = DEFAULT_MODEL
        return json.dumps(obj, separators=(",", ":")).encode("utf-8")
    return payload


def patch_sse_line(line: bytes) -> bytes:
    """Patch one full SSE line (without trailing newline)."""
    # Accept "data: {...}" / "data:{...}"
    if not line.startswith(b"data:"):
        return line
    rest = line[5:]
    if rest.startswith(b" "):
        rest = rest[1:]
    rest = rest.strip()
    if not rest.startswith(b"{") or rest == b"[DONE]":
        return line
    fixed = inject_model_json(rest)
    return b"data: " + fixed


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        print(f"[proxy] {self.address_string()} {fmt % args}")

    def _read_body(self) -> bytes:
        n = int(self.headers.get("Content-Length", "0") or "0")
        return self.rfile.read(n) if n else b""

    def _forward(self, method: str) -> None:
        if not TOKEN:
            self.send_error(500, "DATABRICKS_TOKEN env var not set")
            return

        path = self.path
        if not path.startswith("/"):
            path = "/" + path
        url = UPSTREAM + path
        body = self._read_body() if method in ("POST", "PUT", "PATCH") else None

        headers = {
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": self.headers.get("Content-Type", "application/json"),
            "Accept": self.headers.get("Accept", "*/*"),
            "User-Agent": self.headers.get("User-Agent", "databricks-glm-proxy/1.0"),
        }

        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=600) as resp:
                status = resp.status
                resp_headers = dict(resp.headers.items())
                content_type = resp_headers.get("Content-Type", "")

                self.send_response(status)
                skip = {
                    "transfer-encoding",
                    "content-length",
                    "connection",
                    "keep-alive",
                    "proxy-authenticate",
                    "proxy-authorization",
                    "te",
                    "trailers",
                    "upgrade",
                }
                for k, v in resp_headers.items():
                    if k.lower() in skip:
                        continue
                    self.send_header(k, v)

                # Databricks returns text/event-stream for stream=true. Be liberal:
                # also treat unknown types as stream when Accept asked for SSE.
                accept = self.headers.get("Accept", "")
                body_wants_stream = bool(body) and b'"stream"' in body and b"true" in body
                is_stream = (
                    "text/event-stream" in content_type
                    or "stream" in content_type
                    or "text/event-stream" in accept
                    or body_wants_stream
                )
                print(
                    f"[proxy] {method} {path} status={status} "
                    f"ct={content_type!r} stream={is_stream} body_stream={body_wants_stream}"
                )
                if is_stream:
                    self.send_header("Cache-Control", "no-cache")
                    self.send_header("Connection", "close")
                    self.end_headers()

                    # Buffer across TCP reads so we only patch complete SSE lines.
                    buf = b""
                    while True:
                        chunk = resp.read(4096)
                        if not chunk:
                            break
                        buf += chunk
                        while True:
                            nl = buf.find(b"\n")
                            if nl < 0:
                                break
                            raw_line = buf[:nl]  # without \n
                            buf = buf[nl + 1 :]
                            # Preserve \r if present (CRLF)
                            if raw_line.endswith(b"\r"):
                                core = raw_line[:-1]
                                ending = b"\r\n"
                            else:
                                core = raw_line
                                ending = b"\n"
                            self.wfile.write(patch_sse_line(core) + ending)
                            self.wfile.flush()
                    if buf:
                        # Trailing partial without newline
                        self.wfile.write(patch_sse_line(buf))
                        self.wfile.flush()
                else:
                    data = resp.read()
                    if data.lstrip().startswith(b"data:"):
                        # SSE misclassified as non-stream — still patch lines
                        fixed_lines = []
                        for raw_line in data.splitlines():
                            fixed_lines.append(patch_sse_line(raw_line))
                        data = b"\n".join(fixed_lines)
                        if data and not data.endswith(b"\n"):
                            data += b"\n"
                    elif data.lstrip().startswith(b"{"):
                        data = inject_model_json(data)
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
        except urllib.error.HTTPError as e:
            err_body = e.read()
            self.send_response(e.code)
            self.send_header(
                "Content-Type", e.headers.get("Content-Type", "application/json")
            )
            self.send_header("Content-Length", str(len(err_body)))
            self.end_headers()
            self.wfile.write(err_body)
        except Exception as e:  # noqa: BLE001
            msg = json.dumps(
                {"error": {"message": str(e), "type": "proxy_error"}}
            ).encode()
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)

    def do_GET(self) -> None:  # noqa: N802
        self._forward("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._forward("POST")

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.end_headers()


def main() -> None:
    if not TOKEN:
        raise SystemExit("Set DATABRICKS_TOKEN before starting the proxy.")
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Databricks GLM proxy on http://{HOST}:{PORT}")
    print(f"  upstream: {UPSTREAM}")
    print(f"  inject model: {DEFAULT_MODEL}")
    print("Point Grok base_url at this proxy, then /model databricks-glm")
    server.serve_forever()


if __name__ == "__main__":
    main()
