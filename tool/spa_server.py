"""Serves build/web the way a real host must: every unknown path falls back to
index.html, so a deep link like /game/ABC/player loads the app instead of 404ing.

The app uses real paths (usePathUrlStrategy), which means the *server* has to
answer every app route with the shell document - a plain static file server
answers those with 404 and the router never gets a chance to run.
"""

import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8899
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")


class SpaHandler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        # Serve real files (main.dart.js, assets/, canvaskit/) directly.
        return super().translate_path(path)

    def do_GET(self):
        path = self.translate_path(self.path)
        if os.path.exists(path) and not os.path.isdir(path):
            return super().do_GET()
        # Anything that is not a real file is a client-side route: hand back
        # the shell so go_router can resolve it.
        self.path = "/index.html"
        return super().do_GET()


if __name__ == "__main__":
    os.chdir(ROOT)
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), SpaHandler).serve_forever()
