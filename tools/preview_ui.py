"""Read-only local preview of the frontend (no backend credentials loaded)."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1] / 'frontend'

class Preview(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == '/':
            self.path = '/index.html'
        elif '/' not in path[1:] and (ROOT / (path[1:] + '.html')).is_file():
            self.path = path + '.html'
        super().do_GET()

ThreadingHTTPServer(('127.0.0.1', 8765), Preview).serve_forever()
