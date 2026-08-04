#!/usr/bin/env python3
"""Single shared render-doc server: fixed port, deterministic path routes.

One instance serves every rendered document for every session on this
machine. The kernel's bind exclusivity is the singleton lock: a losing
racer gets EADDRINUSE and exits 0. There is no state file and no idle
timeout: the server lives until reboot, an explicit kill, or a
version-mismatch restart driven by the client, which compares /health's
sha256 of this file against the copy on disk. See the "Contract: B01"
docblock immediately below for the full behavioral spec.

Usage: serve.py   (port from RENDER_DOC_PORT, default 27183)
"""

# Contract: B01 fixed-port server (plan 001-render-doc-fixed-port-server)
#
# Reference implementation to port from:
#   /home/cwilliamson/github/clam-code @ origin/master (41442a2),
#   general/skills/render-doc/scripts/serve.py  (commit 50ccb32)
# Port it rather than re-deriving the design. Adapt only where this repo's
# conventions differ; this file must name no other plugin.
#
# Behavior:
#   One HTTP server instance serves every rendered document for every
#   session on this machine.
#
#   1. Binding and singleton. Binds 127.0.0.1 on the port from
#      RENDER_DOC_PORT, default 27183. The bind IS the lock: when the port
#      is already bound, the process prints a diagnostic to stderr and
#      exits 0 (NOT non-zero — a losing race is a normal outcome, and the
#      winner serves everyone). Any other OSError propagates.
#      Writes its pid to /tmp/render-doc-serve-<port>.pid best-effort;
#      failure to write the pidfile is not fatal, because /health also
#      carries the pid. Removes the pidfile on SIGTERM/SIGINT and exits 0.
#      There is no state file and no idle timeout: the server lives until
#      reboot, an explicit kill, or a version-mismatch restart driven by
#      the client.
#
#   2. GET /health -> 200 with JSON {"app", "version", "pid", "port"}.
#      "app" is exactly the string "render-doc" — the marker a client uses
#      to tell this server apart from a foreign process on the same port.
#      "version" is the sha256 hex digest of THIS FILE's bytes, computed at
#      import; a client compares it against the digest of serve.py on disk
#      to detect a server running outdated code. "pid" is an int, "port"
#      the bound port.
#
#   3. GET /doc/<abs-md-path> -> 200 text/html of the sibling .html for
#      that markdown file. The path after /doc is percent-decoded and is an
#      absolute filesystem path (so the route is deterministic per file and
#      survives restarts). Before serving, re-run render.sh on the markdown
#      when the sibling .html is missing, older than the .md, or older than
#      assets/template.html; otherwise serve the existing .html untouched.
#      render.sh runs with a 30s timeout.
#
#   4. POST /annotate with a JSON body {md, section, excerpt, tag, note}
#      -> 200 {"ok": true} after inserting a line "@<tag>: <note>" (or
#      "@<tag>:" when note is empty) into the markdown at md. Insertion
#      point: the line after the "## <section>" or "### <section>" heading
#      whose text matches section case-insensitively with inline markdown
#      stripped and whitespace collapsed; when excerpt is non-empty, the
#      line after the first line at or below that heading containing the
#      excerpt (trailing "…" removed, truncated to 40 chars, compared with
#      inline markdown stripped), stopping at the next ##/### heading; when
#      the section is not found at all, the end of the file. The
#      read-modify-write is serialized by a lock so concurrent annotates
#      cannot lose each other's lines.
#
#   5. Scope rules, enforced on os.path.realpath of the requested markdown
#      path BEFORE ANY READ, on both /doc and /annotate, so a symlink
#      cannot smuggle in a file from outside scope. In order: not a .md ->
#      403; not an existing file -> 404; not under the realpath of $HOME ->
#      403; not inside a git worktree -> 403. "Inside a git worktree" means
#      some ancestor directory contains a .git entry — a directory for a
#      normal repo, a plain file for a linked worktree; both count.
#      Each violation returns JSON {"error": <message naming the rule>}.
#
#   6. Host pinning: every request whose Host header is not exactly
#      "127.0.0.1:<port>" gets 403 {"error": ...} before any routing, which
#      defeats DNS rebinding.
#
# Inputs:
#   - RENDER_DOC_PORT (optional): the port to bind. Default 27183.
#   - HTTP requests on the three routes above.
#   - Sibling files resolved from this script's own directory:
#     ./render.sh and ../assets/template.html.
#   - No arguments. (The previous design took a state-file path argument;
#     it is gone, and passing one must not be required.)
#
# Outputs:
#   - JSON bodies for /health, /annotate, and every error.
#   - text/html with a correct Content-Length for /doc.
#   - Request logging is suppressed entirely (no stderr noise per request).
#
# Errors:
#   - Port already bound -> stderr diagnostic, exit 0.
#   - Unknown route, or POST to anything but /annotate -> 404.
#   - Malformed JSON body -> 400 {"error": "invalid JSON body"}.
#   - render.sh times out -> 500 {"error": "render timed out"}.
#   - render.sh fails to start -> 500 naming the OSError.
#   - render.sh exits non-zero -> 500 whose message ends with the last line
#     of its stderr.
#   - Rendered .html unreadable -> 500 naming the OSError.
#   - Any exception during annotate -> 500 {"error": str(exception)}.
#   - No error path may leak a traceback to the client or crash the server.
#
# Invariants:
#   - Binds 127.0.0.1 only; never 0.0.0.0, never a routable interface.
#   - Scope checks run on the realpath, before any file read, on every
#     path-bearing route.
#   - The only file this server ever writes outside /tmp is the source
#     markdown named in an /annotate request, and only in response to one.
#   - Threading server; a per-request socket timeout of 30s means a silent
#     connection cannot wedge a thread forever.
#   - Serving a document never mutates it.
#
# Edge cases:
#   - Two instances started concurrently: exactly one binds, the other
#     exits 0, and the winner keeps answering /health.
#   - Markdown path containing spaces or non-ASCII (percent-encoded in the
#     URL, decoded before use).
#   - Sibling .html newer than the .md but older than the template: still
#     stale, re-render.
#   - Annotating a section that appears only as a ### heading.
#   - Annotating when the section heading is absent: append at end of file.
#   - Query string on any route: stripped before routing.
#   - Empty note: the inserted line is "@TAG:" with no trailing space.

import errno
import hashlib
import http.server
import json
import os
import re
import signal
import subprocess
import sys
import threading
import urllib.parse

PORT = int(os.environ.get('RENDER_DOC_PORT', '27183'))
PIDFILE = f"/tmp/render-doc-serve-{PORT}.pid"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RENDER_SH = os.path.join(SCRIPT_DIR, 'render.sh')
TEMPLATE = os.path.realpath(os.path.join(SCRIPT_DIR, '..', 'assets', 'template.html'))
RENDER_TIMEOUT = 30  # seconds for one render.sh run

with open(os.path.abspath(__file__), 'rb') as f:
    VERSION = hashlib.sha256(f.read()).hexdigest()


def in_git_worktree(path):
    """True when some ancestor directory of path contains a .git entry."""
    d = os.path.dirname(path)
    while True:
        if os.path.exists(os.path.join(d, '.git')):
            return True
        parent = os.path.dirname(d)
        if parent == d:
            return False
        d = parent


def scope_error(md_real):
    """Return (status, message) when md_real violates a scope rule, else None."""
    if not md_real.endswith('.md'):
        return 403, "scope: not a .md file"
    if not os.path.isfile(md_real):
        return 404, "markdown not found"
    home = os.path.realpath(os.path.expanduser('~'))
    if not md_real.startswith(home + os.sep):
        return 403, "scope: outside the home directory"
    if not in_git_worktree(md_real):
        return 403, "scope: not inside a git worktree"
    return None


annotate_lock = threading.Lock()


def strip_inline_md(text):
    """Return text with inline markdown punctuation removed."""
    return re.sub(r'[*_`~\[\]()]+', '', text).strip()


def find_insertion_point(lines, section, excerpt):
    """Return the index at which the annotation line should be inserted."""
    norm = re.sub(r'\s+', ' ', section).strip().lower()
    sec_idx = -1
    for i, line in enumerate(lines):
        m = re.match(r'^#{2,3}\s+(.+)$', line)
        if m and strip_inline_md(m.group(1)).lower() == norm:
            sec_idx = i
            break
    if sec_idx == -1:
        return len(lines)
    if not excerpt:
        return sec_idx + 1
    search = re.sub(r'…$', '', excerpt).strip()
    if len(search) > 40:
        search = search[:40]
    for j in range(sec_idx + 1, len(lines)):
        if re.match(r'^#{2,3}\s', lines[j]):
            break
        if search in strip_inline_md(lines[j]):
            return j + 1
    return sec_idx + 1


class Handler(http.server.BaseHTTPRequestHandler):
    timeout = 30  # per-request socket timeout: a silent connection cannot wedge a thread forever

    def log_message(self, fmt, *args):
        pass

    def send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _check_host(self):
        if self.headers.get('Host') != f'127.0.0.1:{PORT}':
            self.send_json(403, {"error": "bad Host header"})
            return False
        return True

    def do_GET(self):
        if not self._check_host():
            return
        raw = self.path.split('?', 1)[0]

        if raw == '/health':
            self.send_json(200, {"app": "render-doc", "version": VERSION,
                                 "pid": os.getpid(), "port": PORT})
            return

        if raw.startswith('/doc/'):
            self._serve_doc(urllib.parse.unquote(raw[len('/doc'):]))
            return

        self.send_error(404)

    def _serve_doc(self, md_path):
        md_real = os.path.realpath(md_path)
        err = scope_error(md_real)
        if err:
            self.send_json(err[0], {"error": err[1]})
            return

        html = md_real[:-3] + '.html'
        try:
            stale = (not os.path.isfile(html)
                     or os.path.getmtime(html) < os.path.getmtime(md_real)
                     or os.path.getmtime(html) < os.path.getmtime(TEMPLATE))
        except OSError:
            stale = True
        if stale:
            try:
                proc = subprocess.run([RENDER_SH, md_real], capture_output=True,
                                      text=True, timeout=RENDER_TIMEOUT)
            except subprocess.TimeoutExpired:
                self.send_json(500, {"error": "render timed out"})
                return
            except OSError as e:
                self.send_json(500, {"error": f"render failed to start: {e}"})
                return
            if proc.returncode != 0:
                tail = (proc.stderr or '').strip().splitlines()
                self.send_json(500, {"error": "render failed: "
                                     + (tail[-1] if tail else "no stderr")})
                return

        try:
            with open(html, 'rb') as f:
                content = f.read()
        except OSError as e:
            self.send_json(500, {"error": f"could not read rendered html: {e}"})
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def do_POST(self):
        if not self._check_host():
            return
        if self.path.split('?', 1)[0] != '/annotate':
            self.send_error(404)
            return
        body = self._read_json()
        if body is None:
            return

        md = body.get('md', '')
        section = body.get('section', '')
        tag = body.get('tag', 'COMMENT')
        note = body.get('note', '')
        excerpt = body.get('excerpt', '')

        md_real = os.path.realpath(md)
        err = scope_error(md_real)
        if err:
            self.send_json(err[0], {"error": err[1]})
            return

        try:
            # The lock serializes the read-modify-write: concurrent annotates
            # under the threading server must not lose each other's lines.
            with annotate_lock:
                with open(md_real, 'r', encoding='utf-8') as f:
                    content = f.read()
                lines = content.split('\n')
                idx = find_insertion_point(lines, section, excerpt)
                annotation = f"@{tag}:" + (f" {note}" if note else "")
                lines.insert(idx, annotation)
                with open(md_real, 'w', encoding='utf-8') as f:
                    f.write('\n'.join(lines))
            self.send_json(200, {"ok": True})
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def _read_json(self):
        try:
            length = int(self.headers.get('Content-Length', 0))
            return json.loads(self.rfile.read(length))
        except Exception:
            self.send_json(400, {"error": "invalid JSON body"})
            return None


def main():
    """Bind the fixed port and serve until killed; exit 0 if already bound."""
    try:
        server = http.server.ThreadingHTTPServer(('127.0.0.1', PORT), Handler)
    except OSError as e:
        if e.errno == errno.EADDRINUSE:
            print(f"render-doc serve: port {PORT} already bound; "
                  "another instance owns it", file=sys.stderr)
            sys.exit(0)
        raise

    try:
        with open(PIDFILE, 'w') as f:
            f.write(str(os.getpid()))
    except OSError:
        pass  # best-effort; /health carries the pid too

    def on_signal(signum, frame):
        try:
            os.unlink(PIDFILE)
        except OSError:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)
    server.serve_forever()


if __name__ == '__main__':
    main()
