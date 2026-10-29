#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Mock greetd server for testing greeter-backend.py without touching the real
greetd. Implements just enough of the greetd IPC protocol to exercise the auth
flow. Records the start_session request so tests can assert on it.

Usage: mock-greetd.py <socket-path> <expected-user> <expected-password>
"""
import json
import os
import socket
import struct
import sys


def recv_exact(conn, count):
    data = b""
    while len(data) < count:
        chunk = conn.recv(count - len(data))
        if not chunk:
            return None
        data += chunk
    return data


def recv_msg(conn):
    header = recv_exact(conn, 4)
    if header is None:
        return None
    (length,) = struct.unpack("=I", header)
    payload = recv_exact(conn, length)
    if payload is None:
        return None
    return json.loads(payload.decode("utf-8"))


def send_msg(conn, message):
    payload = json.dumps(message).encode("utf-8")
    conn.sendall(struct.pack("=I", len(payload)) + payload)


def main():
    path, expected_user, expected_password = sys.argv[1], sys.argv[2], sys.argv[3]
    if os.path.exists(path):
        os.unlink(path)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(1)
    log = open(os.environ.get("MOCK_GREETD_LOG", "/tmp/mock-greetd.log"), "w")
    server.settimeout(20)
    try:
        conn, _ = server.accept()
    except socket.timeout:
        log.write("TIMEOUT waiting for connection\n")
        log.close()
        return 1
    conn.settimeout(20)
    try:
        while True:
            msg = recv_msg(conn)
            if msg is None:
                break
            log.write("REQ " + json.dumps(msg) + "\n")
            log.flush()
            mtype = msg.get("type")
            if mtype == "create_session":
                if msg.get("username") == expected_user:
                    send_msg(conn, {"type": "auth_message",
                                    "auth_message_type": "secret",
                                    "auth_message": "Password:"})
                else:
                    send_msg(conn, {"type": "error", "error_type": "error",
                                    "description": "unknown user"})
            elif mtype == "post_auth_message_response":
                if msg.get("response") == expected_password:
                    send_msg(conn, {"type": "success"})
                else:
                    send_msg(conn, {"type": "error", "error_type": "auth_error",
                                    "description": "Authentication failed"})
            elif mtype == "start_session":
                send_msg(conn, {"type": "success"})
                log.write("STARTED " + json.dumps({"cmd": msg.get("cmd"),
                                                   "env": msg.get("env")}) + "\n")
                log.close()
                conn.close()
                server.close()
                return 0
            else:
                send_msg(conn, {"type": "error", "error_type": "error",
                                "description": "unsupported"})
    finally:
        try:
            conn.close()
        except OSError:
            pass
        try:
            server.close()
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
