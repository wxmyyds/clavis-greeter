#!/usr/bin/python3
"""Clavis Greeter -- greetd IPC backend.

Speaks the greetd IPC protocol (see `man 7 greetd-ipc`) and exposes a tiny
line-oriented JSON protocol on stdin/stdout so the QML frontend stays dumb.

greetd -> greeter protocol
--------------------------
Framing: <u32 native byte order length><UTF-8 JSON payload>
Requests:
    {"type": "create_session", "username": <str>}
    {"type": "post_auth_message_response", "response": <str>?}
    {"type": "start_session", "cmd": [<str>...], "env": [<str>...]}
    {"type": "cancel_session"}
Responses:
    {"type": "success"}
    {"type": "error", "error_type": "auth_error"|"error", "description": <str>}
    {"type": "auth_message", "auth_message_type": "visible"|"secret"|"info"|"error",
                               "auth_message": <str>}

QML frontend <-> backend (stdin/stdout, one JSON object per line)
----------------------------------------------------------------
frontend -> backend:
    {"cmd": "login", "username": <str>, "password": <str>}
    {"cmd": "cancel"}
backend -> frontend:
    {"event": "ready"}
    {"event": "prompt", "kind": "secret"|"visible"|"info"|"error", "message": <str>}
    {"event": "auth_error", "message": <str>}
    {"event": "fatal", "message": <str>}
    {"event": "success"}                 # about to start the session and exit
"""

from __future__ import annotations

import json
import os
import socket
import struct
import sys

SESSION_CMD = ["niri-session"]
SESSION_ENV = [
    "XDG_SESSION_TYPE=wayland",
    "XDG_CURRENT_DESKTOP=niri",
    "XDG_SESSION_DESKTOP=niri",
]

def default_user() -> str:
    """Username to prefill: explicit env override, else first regular user."""
    explicit = os.environ.get("CLAVIS_GREETER_USER", "").strip()
    if explicit:
        return explicit
    try:
        import pwd
        for entry in pwd.getpwall():
            if 1000 <= entry.pw_uid < 60000 and "nologin" not in entry.pw_shell:
                return entry.pw_name
    except Exception:
        pass
    return os.environ.get("USER", "")


def emit(event: dict) -> None:
    """Write one JSON line to the frontend and flush immediately."""
    sys.stdout.write(json.dumps(event, ensure_ascii=False) + "\n")
    sys.stdout.flush()


class GreetdError(Exception):
    pass


class GreetdClient:
    """Minimal blocking client for the greetd IPC socket."""

    def __init__(self, path: str) -> None:
        self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._sock.settimeout(30)
        self._sock.connect(path)

    def close(self) -> None:
        try:
            self._sock.close()
        except OSError:
            pass

    def _send(self, message: dict) -> None:
        payload = json.dumps(message).encode("utf-8")
        # Native byte order, u32 length prefix.
        self._sock.sendall(struct.pack("=I", len(payload)) + payload)

    def _recv_exact(self, count: int) -> bytes:
        chunks = []
        remaining = count
        while remaining > 0:
            chunk = self._sock.recv(remaining)
            if not chunk:
                raise GreetdError("greetd closed the connection unexpectedly")
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    def recv(self) -> dict:
        header = self._recv_exact(4)
        (length,) = struct.unpack("=I", header)
        if length == 0 or length > 1 << 20:
            raise GreetdError(f"implausible payload length: {length}")
        payload = self._recv_exact(length)
        try:
            return json.loads(payload.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise GreetdError(f"malformed JSON from greetd: {exc}") from exc

    def request(self, message: dict) -> dict:
        self._send(message)
        return self.recv()


def _describe(response: dict) -> str:
    """Human-readable text for an error/auth_message response."""
    kind = response.get("type")
    if kind == "auth_message":
        return str(response.get("auth_message") or "")
    if kind == "error":
        return str(response.get("description") or response.get("error_type") or "error")
    return ""


def authenticate(client: GreetdClient, username: str, password: str) -> None:
    """Run create_session + post_auth_message_response until greetd is satisfied.

    Raises GreetdError on failure; returns normally when the session may start.
    """
    response = client.request({"type": "create_session", "username": username})

    # greetd may prompt for credentials (usually one secret prompt) before it
    # reports success. We already hold the password, so answer any secret or
    # visible prompt with it. Informational messages are echoed to the UI but
    # do not need a response.
    password_sent = False
    for _ in range(8):  # hard bound; real flows use 1-3 round trips
        kind = response.get("type")

        if kind == "success":
            return

        if kind == "error":
            raise GreetdError(_describe(response))

        if kind == "auth_message":
            message_type = response.get("auth_message_type")

            if message_type in ("info", "error"):
                emit({"event": "prompt", "kind": message_type,
                      "message": _describe(response)})
                response = client.request({"type": "post_auth_message_response"})
                continue

            # visible / secret -> needs the password
            emit({"event": "prompt", "kind": message_type,
                  "message": _describe(response)})
            if password_sent:
                raise GreetdError("greetd requested the password more than once")
            response = client.request({
                "type": "post_auth_message_response",
                "response": password,
            })
            password_sent = True
            continue

        raise GreetdError(f"unexpected greetd response: {response!r}")

    raise GreetdError("too many authentication round trips")


def start_session(client: GreetdClient) -> None:
    response = client.request({
        "type": "start_session",
        "cmd": SESSION_CMD,
        "env": SESSION_ENV,
    })
    if response.get("type") != "success":
        raise GreetdError(_describe(response) or "greetd refused to start the session")


def mark_success() -> None:
    """Tell the wrapper that authentication succeeded and the session was
    requested, so it must NOT fall back to a text greeter."""
    path = os.environ.get("CLAVIS_GREETER_OK_FILE", "")
    if not path:
        return
    try:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("ok\n")
    except OSError:
        pass


def handle_login(sock_path: str, username: str, password: str) -> bool:
    """Perform a full login. Returns True when the session was started."""
    client = None
    try:
        client = GreetdClient(sock_path)
        authenticate(client, username, password)
        start_session(client)
        mark_success()
        emit({"event": "success"})
        return True
    except GreetdError as exc:
        emit({"event": "auth_error", "message": str(exc)})
        return False
    except OSError as exc:
        emit({"event": "fatal", "message": f"cannot reach greetd: {exc}"})
        return False
    finally:
        if client is not None:
            client.close()


def main() -> int:
    sock_path = os.environ.get("GREETD_SOCK", "")
    if not sock_path:
        emit({"event": "fatal", "message": "GREETD_SOCK is not set"})
        return 1

    emit({"event": "ready", "defaultUser": default_user(),
          "startupMode": os.environ.get("CLAVIS_GREETER_STARTUP", "clock")})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            emit({"event": "fatal", "message": "malformed request from frontend"})
            continue

        cmd = message.get("cmd")
        if cmd == "login":
            username = str(message.get("username") or "").strip()
            password = str(message.get("password") or "")
            if not username:
                emit({"event": "auth_error", "message": "请输入用户名"})
                continue
            if handle_login(sock_path, username, password):
                return 0
        elif cmd == "cancel":
            return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
