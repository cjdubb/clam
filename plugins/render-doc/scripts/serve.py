#!/usr/bin/env python3
"""Single shared annotation server for render-doc.

One instance serves all rendered documents. render.sh starts it on first
--open call and reuses it for subsequent renders. Documents are registered
dynamically via POST /register and served by ID via GET /d/{id}.

Binds to 127.0.0.1 only. Auto-shuts down after 30 minutes of inactivity.
Writes {"pid": N, "port": N} to a state file so render.sh can discover it.

Usage: serve.py [<state-file>]
       Default state file: /tmp/render-doc-serve.json
"""

import hashlib, http.server, json, os, re, signal, sys, threading

STATE_FILE = sys.argv[1] if len(sys.argv) > 1 else "/tmp/render-doc-serve.json"
IDLE_TIMEOUT = 1800  # 30 minutes

# --- Document registry -------------------------------------------------------
docs = {}  # id -> {"html": abs_path, "md": abs_path}

def doc_id(html_path):
    return hashlib.sha256(html_path.encode()).hexdigest()[:12]

# --- Annotation insertion -----------------------------------------------------
def strip_inline_md(text):
    return re.sub(r'[*_`~\[\]()]+', '', text).strip()

def find_insertion_point(lines, section, excerpt):
    norm = re.sub(r'\s+', ' ', section).strip().lower()
    sec_idx = -1
    for i, line in enumerate(lines):
        m = re.match(r'^##\s+(.+)$', line)
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
        if re.match(r'^##\s', lines[j]):
            break
        if search in strip_inline_md(lines[j]):
            return j + 1
    return sec_idx + 1

# --- Idle timer ---------------------------------------------------------------
idle_timer = None
timer_lock = threading.Lock()

def reset_idle(server):
    global idle_timer
    with timer_lock:
        if idle_timer:
            idle_timer.cancel()
        idle_timer = threading.Timer(IDLE_TIMEOUT, lambda: shutdown(server))
        idle_timer.daemon = True
        idle_timer.start()

def shutdown(server):
    try:
        os.unlink(STATE_FILE)
    except OSError:
        pass
    server.shutdown()

# --- HTTP handler -------------------------------------------------------------
class Handler(http.server.BaseHTTPRequestHandler):
    server_ref = None

    def log_message(self, fmt, *args):
        pass

    def send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        reset_idle(self.server_ref)

        if self.path == '/health':
            self.send_json(200, {"ok": True, "docs": len(docs)})
            return

        # /d/{id} — serve a registered document's HTML
        if self.path.startswith('/d/'):
            did = self.path[3:].split('?')[0]
            entry = docs.get(did)
            if not entry or not os.path.isfile(entry['html']):
                self.send_error(404, 'Document not registered or HTML missing')
                return
            try:
                with open(entry['html'], 'rb') as f:
                    content = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Content-Length', str(len(content)))
                self.end_headers()
                self.wfile.write(content)
            except Exception as e:
                self.send_error(500, str(e))
            return

        self.send_error(404)

    def do_POST(self):
        reset_idle(self.server_ref)
        body = self._read_json()
        if body is None:
            return

        if self.path == '/register':
            html = body.get('html', '')
            md = body.get('md', '')
            if not html or not md:
                self.send_json(400, {"error": "html and md paths required"})
                return
            if not os.path.isfile(html):
                self.send_json(400, {"error": f"html not found: {html}"})
                return
            if not os.path.isfile(md):
                self.send_json(400, {"error": f"md not found: {md}"})
                return
            did = doc_id(html)
            docs[did] = {"html": os.path.abspath(html), "md": os.path.abspath(md)}
            self.send_json(200, {"id": did, "url": f"/d/{did}"})
            return

        if self.path == '/annotate':
            md = body.get('md', '')
            section = body.get('section', '')
            tag = body.get('tag', 'COMMENT')
            note = body.get('note', '')
            excerpt = body.get('excerpt', '')

            # Validate: the md path must be registered
            registered = any(e['md'] == md for e in docs.values())
            if not registered:
                self.send_json(403, {"error": "markdown path not registered"})
                return

            try:
                with open(md, 'r', encoding='utf-8') as f:
                    content = f.read()
                lines = content.split('\n')
                idx = find_insertion_point(lines, section, excerpt)
                annotation = f"@{tag}:" + (f" {note}" if note else "")
                lines.insert(idx, annotation)
                with open(md, 'w', encoding='utf-8') as f:
                    f.write('\n'.join(lines))
                self.send_json(200, {"ok": True})
            except Exception as e:
                self.send_json(500, {"error": str(e)})
            return

        self.send_error(404)

    def _read_json(self):
        try:
            length = int(self.headers.get('Content-Length', 0))
            return json.loads(self.rfile.read(length))
        except Exception:
            self.send_json(400, {"error": "invalid JSON body"})
            return None

# --- Main ---------------------------------------------------------------------
server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
Handler.server_ref = server
port = server.server_address[1]

state = {"pid": os.getpid(), "port": port}
try:
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f)
except Exception as e:
    print(f"serve: could not write state file: {e}", file=sys.stderr)
    sys.exit(1)

def on_signal(*_):
    shutdown(server)

signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)

reset_idle(server)
print(f"http://127.0.0.1:{port}/")
sys.stdout.flush()
server.serve_forever()
