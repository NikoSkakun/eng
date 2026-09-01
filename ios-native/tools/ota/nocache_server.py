#!/usr/bin/env python3
"""Loopback static server that sends no-store headers, so iOS/Safari can never
reuse a stale manifest or IPA from a previous (failed) OTA attempt.

  python3 nocache_server.py <port> <dir>
"""
import os, sys, http.server, socketserver

port = int(sys.argv[1])
os.chdir(sys.argv[2])


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, *args):  # quiet
        pass


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", port), Handler) as httpd:
    httpd.serve_forever()
