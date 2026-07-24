"""Static server for the manual test pages, with caching disabled.

Safari caches aggressively and *will* serve a stale copy of a test page — that
cost us a false "L3 is fine" result during bring-up (2026-07-24). Every response
here is `no-store`; still add a `?cb=<random>` when navigating by hand.

Bound to 0.0.0.0 so the physical iPhone can reach it over the LAN or Tailscale.
"""

import functools
import http.server
import pathlib
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
ROOT = pathlib.Path(__file__).resolve().parent.parent / "Tests" / "pages"


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        super().end_headers()


def main() -> None:
    handler = functools.partial(NoCacheHandler, directory=str(ROOT))
    server = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), handler)
    print(f"serving {ROOT} on http://0.0.0.0:{PORT} (no-store)")
    server.serve_forever()


if __name__ == "__main__":
    main()
