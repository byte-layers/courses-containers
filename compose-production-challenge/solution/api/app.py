import os, socket
from http.server import BaseHTTPRequestHandler, HTTPServer

REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
PASSWORD_FILE = os.environ.get("REDIS_PASSWORD_FILE")

def redis_call(command):
    with socket.create_connection((REDIS_HOST, 6379), timeout=2) as redis:
        if PASSWORD_FILE:
            password = open(PASSWORD_FILE).read().strip()
            redis.sendall(f"AUTH {password}\r\n".encode())
            redis.recv(64)
        redis.sendall(command + b"\r\n")
        return redis.recv(64).decode().strip()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/crash":
            os._exit(1)
        if self.path == "/health":
            if redis_call(b"PING") != "+PONG":
                raise RuntimeError("Redis ne répond pas PONG")
            body = "ok\n"
        else:
            body = f"Visites : {redis_call(b'INCR visits').lstrip(':')}\n"
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body.encode())

HTTPServer(("", 8000), Handler).serve_forever()
