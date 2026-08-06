#!/usr/bin/env python3
"""Single shared render-doc server: fixed port, deterministic path routes.

One instance serves every rendered document for every session on this
machine. The kernel's bind exclusivity is the singleton lock: a losing
racer gets EADDRINUSE and exits 0. There is no state file and no idle
timeout: the server lives until reboot, an explicit kill, or a
version-mismatch restart driven by the client, which compares /health's
sha256 of this file against the copy on disk. See the "Contract: B01"
docblock immediately below for the full behavioral spec.

The project index (GET /) does not stop at what has been served: it also
discovers markdown documents under a served worktree's .local/, at any
depth, and across every one of that worktree's sibling checkouts, listing
never-served documents alongside the rest. That discovery scan degrades
to the registry-only listing whenever it fails for an environmental
reason (git missing, a failing subprocess, an unreadable directory).

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
import html
import http.server
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
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


# Contract: B02 served-doc registry (plan 001-render-graph-always)
#
# DELIBERATELY UNIMPLEMENTED. The two functions below raise; implementing
# them — and wiring registry_record into the serve paths — is the block's
# implementation. Nothing above this comment changes for B02 except that
# wiring.
#
# Behavior:
#   The server remembers which documents it has served, so the index page
#   (B03) can list every served document, grouped by project, with no
#   other discovery mechanism.
#   1. After EVERY successful serve — a 200 from /doc, or a 200 or 304 from
#      /raw — registry_record(md_real) upserts that realpath with the
#      current epoch seconds as its last-served time: one entry per path,
#      newest time wins.
#   2. The registry lives in memory and is persisted best-effort to
#      /tmp/render-doc-registry-<port>.json after each change, as a JSON
#      object mapping realpath -> last-served epoch (a number). A failed
#      write is silent; the in-memory registry keeps working.
#   3. At import/startup the file, when present and parseable as that
#      shape, seeds the in-memory registry; a missing, corrupt, or
#      wrong-shape file is silently treated as empty.
#   4. registry_entries() returns the current entries as a list of dicts
#      {"path": <realpath>, "lastServed": <epoch>}, sorted by lastServed
#      descending, PRUNING — from both the returned list and the registry
#      itself, persisting the prune — every path that now fails the same
#      scope rules /doc enforces (scope_error non-None).
#   5. GET /docs.json responds 200 application/json with exactly
#      {"docs": <registry_entries() result>}.
# Inputs: successful serves; the /tmp seed file; GET /docs.json requests.
# Outputs: /docs.json body as above; the /tmp persistence file.
# Errors: /docs.json never 500s for registry reasons — an empty or wholly
#   pruned registry yields {"docs": []}; registry failures never fail or
#   block a serve.
# Invariants:
#   - A lock serializes every registry read-modify-write (the threading
#     server makes concurrent serves routine), like annotate_lock does for
#     annotations.
#   - Entries are realpaths (the same md_real the scope check ran on).
#   - Recording is fire-and-forget from the serve paths: an exception in
#     registry code must never turn a successful serve into an error.
# Edge cases: concurrent serves of one doc (single entry, latest time);
#   the /tmp file deleted while running (recreated on next change); two
#   servers on different ports (separate files, keyed by port); a seeded
#   entry whose file has since vanished (pruned at first
#   registry_entries() call).
REGISTRY_FILE = f"/tmp/render-doc-registry-{PORT}.json"
registry_lock = threading.Lock()


def _load_registry():
    """Read the persisted registry file; empty dict for anything but the
    documented shape (a missing, corrupt, or wrong-shape file is silent)."""
    try:
        with open(REGISTRY_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    out = {}
    for k, v in data.items():
        if isinstance(k, str) and isinstance(v, (int, float)) and not isinstance(v, bool):
            out[k] = v
    return out


_registry = _load_registry()


def _persist_registry():
    """Best-effort write of the in-memory registry to disk; a failure is silent."""
    try:
        with open(REGISTRY_FILE, 'w', encoding='utf-8') as f:
            json.dump(_registry, f)
    except OSError:
        pass


def registry_record(md_real):
    try:
        with registry_lock:
            _registry[md_real] = time.time()
            _persist_registry()
    except Exception:
        pass


def registry_entries():
    with registry_lock:
        stale = [p for p in _registry if scope_error(p) is not None]
        for p in stale:
            del _registry[p]
        if stale:
            _persist_registry()
        entries = [{"path": p, "lastServed": t} for p, t in _registry.items()]
    entries.sort(key=lambda e: e["lastServed"], reverse=True)
    return entries


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


# --- Project index (B03) support ---------------------------------------------
# Pure helpers behind Handler._serve_index: grouping registered documents by
# worktree and reading a group's WORKGRAPH.md headline via the work-graph
# protocol's machine-read markers (docs/protocols/work-graph.md).

_OPEN_NODE_RE = re.compile(r'^- Status: open\s*$')
_FOCUS_RE = re.compile(r'^Focus: (N[0-9]+|none)\s*$')


def worktree_label(md_real):
    """(worktree root realpath, ~-abbreviated label) for md_real's nearest
    git-ancestor directory. (None, None) only when no ancestor carries a
    .git entry, which scope_error already rules out for any path reaching
    the registry."""
    d = os.path.dirname(md_real)
    while True:
        if os.path.exists(os.path.join(d, '.git')):
            root = os.path.realpath(d)
            home = os.path.realpath(os.path.expanduser('~'))
            if root == home or root.startswith(home + os.sep):
                return root, '~' + root[len(home):]
            return root, root
        parent = os.path.dirname(d)
        if parent == d:
            return None, None
        d = parent


def read_workgraph(path):
    """(open_count, focus_id) read via the work-graph protocol's machine-read
    markers, or None when the file cannot be read or carries no Focus line."""
    try:
        with open(path, 'r', encoding='utf-8') as f:
            lines = f.read().split('\n')
    except (OSError, UnicodeDecodeError):
        return None
    open_count = sum(1 for ln in lines if _OPEN_NODE_RE.match(ln))
    focus = None
    for ln in lines:
        m = _FOCUS_RE.match(ln)
        if m:
            focus = m.group(1)
            break
    if focus is None:
        return None
    return open_count, focus


def render_headline(entry):
    """A group's WORKGRAPH.md headline: its /doc link, open-node count and
    Focus id — or "unavailable" for both when the file can't be parsed."""
    href = '/doc' + urllib.parse.quote(entry['path'], safe='/')
    info = read_workgraph(entry['path'])
    if info is None:
        count_text, focus_text = 'unavailable', 'unavailable'
    else:
        open_count, focus = info
        count_text, focus_text = str(open_count), focus
    href_esc = html.escape(href, quote=True)
    count_esc = html.escape(count_text)
    focus_esc = html.escape(focus_text)
    return (f'<div class="headline"><a href="{href_esc}">WORKGRAPH.md</a> '
            f'<span class="meta">{count_esc} open nodes | Focus: {focus_esc}'
            f'</span></div>')


def render_group(root, label, entries):
    """The <details> block for one worktree's group of registered documents:
    the WORKGRAPH.md headline (if present) followed by every other document
    as a worktree-relative link, expanded by default."""
    headline = None
    others = []
    for e in entries:
        if headline is None and os.path.basename(e['path']) == 'WORKGRAPH.md':
            headline = e
        else:
            others.append(e)

    parts = ['<details open><summary>', html.escape(label), '</summary>']
    if headline is not None:
        parts.append(render_headline(headline))
    if others:
        parts.append('<ul class="docs">')
        for e in others:
            rel = os.path.relpath(e['path'], root)
            href_esc = html.escape(
                '/doc' + urllib.parse.quote(e['path'], safe='/'), quote=True)
            mark = (' <span class="unserved">(unserved)</span>'
                    if e.get('lastServed') is None else '')
            parts.append(f'<li><a href="{href_esc}">{html.escape(rel)}</a>{mark}</li>')
        parts.append('</ul>')
    parts.append('</details>')
    return ''.join(parts)


# --- Discovery (plan 002-discovery-landing-dns) -------------------------------
# Filesystem discovery: the index and landing pages list documents that
# exist on disk but have never been served. Everything here references
# docs/protocols/ conventions only; no plugin is named or assumed.


def worktree_siblings(root):
    """Contract: 002-B01 discovery scan — worktree_siblings

    DELIBERATELY UNIMPLEMENTED. Raises NotImplementedError("002-B01").

    Behavior: Return the worktree root realpaths of every worktree of the
      repository that `root` belongs to, `root` itself included, by running
      `git worktree list --porcelain` with cwd=root and taking each
      `worktree <path>` line.
    Inputs: root — an absolute realpath of a directory that is a git
      worktree root (carries a .git entry). Not re-validated here; callers
      pass roots produced by worktree_label().
    Outputs: list of unique realpaths, `root` first, the rest in the order
      git reports them; every returned path is a directory existing at
      return time (a reported-but-vanished worktree is dropped); a listed
      path whose directory carries no .git entry (e.g. a bare-repo control
      dir) is excluded.
    Errors: NEVER raises for environmental reasons — git missing from
      PATH, subprocess failure (nonzero exit, OSError), a timeout capped
      at 5 seconds, or unparseable output all degrade to returning [root].
    Invariants: read-only (no filesystem writes, no registry access); no
      shell=True; the subprocess always runs with an explicit timeout.
    Edge cases: a single-worktree repo (returns [root]); root missing from
      git's own output (still first in the result); duplicate paths in the
      output (deduplicated, first occurrence wins).
    """
    try:
        proc = subprocess.run(
            ['git', 'worktree', 'list', '--porcelain'],
            cwd=root, capture_output=True, text=True, timeout=5)
        if proc.returncode != 0:
            return [root]
        paths = [line[len('worktree '):] for line in proc.stdout.split('\n')
                 if line.startswith('worktree ')]
    except Exception:
        return [root]

    result = [root]
    seen = {root}
    for path in paths:
        if path in seen:
            continue
        seen.add(path)
        try:
            if os.path.isdir(path) and os.path.exists(os.path.join(path, '.git')):
                result.append(path)
        except OSError:
            continue
    return result


def discover_docs(root):
    """Contract: 002-B01 discovery scan — discover_docs

    DELIBERATELY UNIMPLEMENTED. Raises NotImplementedError("002-B01").

    Behavior: Return the markdown documents under `root`/.local — every
      file matching .local/**/*.md at any depth — as candidates for the
      index (B02) and the worktree landing page (B04).
    Inputs: root — an absolute worktree root realpath.
    Outputs: list of dicts {"path": <realpath>, "mtime": <epoch number>},
      sorted by mtime descending. Only paths for which scope_error(path)
      returns None are included — the same rules every serve route
      enforces (.md file, under $HOME, inside a git worktree).
    Errors: NEVER raises — a missing .local returns []; an unreadable
      directory or a file vanishing mid-walk is skipped silently; the walk
      does not follow symlinked directories, so a symlink cycle cannot
      hang it.
    Invariants: read-only; only names and stat results are examined — file
      CONTENTS are never read here; no path outside root/.local is ever
      returned; no directory name below .local is treated specially.
    Edge cases: .local exists with no .md files (returns []); .md files at
      nested depth (included); rendered .html siblings (excluded by the
      .md filter); a .local that is a file rather than a directory
      (returns []).
    """
    local_root = os.path.join(root, '.local')
    entries = []
    try:
        for dirpath, dirnames, filenames in os.walk(local_root, followlinks=False):
            for fname in filenames:
                if not fname.endswith('.md'):
                    continue
                full = os.path.join(dirpath, fname)
                try:
                    real = os.path.realpath(full)
                    if real != local_root and not real.startswith(local_root + os.sep):
                        continue
                    if scope_error(real) is not None:
                        continue
                    mtime = os.stat(real).st_mtime
                except OSError:
                    continue
                entries.append({"path": real, "mtime": mtime})
    except Exception:
        return []
    entries.sort(key=lambda e: e["mtime"], reverse=True)
    return entries


def index_doc_entries():
    """Contract: 002-B02 index discovery integration

    DELIBERATELY UNIMPLEMENTED. Raises NotImplementedError("002-B02"). Wiring
    _serve_index to consume this function IS part of the block's
    implementation; until then GET / stays registry-only.

    Behavior: The document set for GET / — the registry united with
      filesystem discovery:
      1. Start from registry_entries() (already scope-pruned, sorted by
         last-served descending).
      2. For every distinct worktree root among those entries (per
         worktree_label), collect worktree_siblings(root); for every
         sibling root, collect discover_docs(sibling).
      3. Merge: a discovered path already registered keeps its registry
         entry untouched; a discovered path NOT registered joins as
         {"path": ..., "lastServed": None, "mtime": <epoch number>}.
      With this wired, GET / groups exactly as today (worktree_label,
      headline, details/summary), except: unserved entries (lastServed
      None) list AFTER every served entry in their group, each visibly
      marked with text containing "unserved"; and groups may now exist
      for worktrees that never served a doc, rendering exactly like
      served groups (label, headline when .local/WORKGRAPH.md exists).
    Inputs: none (module state: the registry; the filesystem).
    Outputs: list of dicts as above — served entries first in
      registry_entries() order, then unserved entries sorted by mtime
      descending; each path appears exactly once.
    Errors: NEVER raises — any failure of sibling enumeration or
      discovery degrades to the registry-only entries (today's exact
      behavior); GET / never 500s for discovery reasons.
    Invariants: discovery never modifies registry state (no
      registry_record); read-only beyond registry_entries()'s own
      documented pruning.
    Edge cases: empty registry and nothing discoverable (empty index,
      existing empty state); one repo reached via two registered
      worktrees (each root appears once); a doc discovered now and served
      moments later (the next request shows it served — no caching is
      promised).
    """
    entries = registry_entries()
    seen_paths = {e['path'] for e in entries}

    seen_roots = set()
    ordered_roots = []
    for e in entries:
        root, _ = worktree_label(e['path'])
        if root is None or root in seen_roots:
            continue
        seen_roots.add(root)
        ordered_roots.append(root)

    discovered = []
    for root in ordered_roots:
        try:
            siblings = worktree_siblings(root)
        except Exception:
            continue
        for sib in siblings:
            try:
                docs = discover_docs(sib)
            except Exception:
                continue
            for d in docs:
                if d['path'] in seen_paths:
                    continue
                seen_paths.add(d['path'])
                discovered.append(
                    {"path": d['path'], "lastServed": None, "mtime": d['mtime']})

    discovered.sort(key=lambda e: e['mtime'], reverse=True)
    return entries + discovered


# --- Worktree landing page (002-B04) support ----------------------------------
# Pure helpers behind Handler._serve_project: this root's own document set
# (never a sibling worktree's — that is the isolation the landing page is for),
# grouped by .local subdirectory, each entry annotated from the two protocol
# fields only.

_STATE_RE = re.compile(r'^State:[ \t]*(.+)$')
_STATUS_RE = re.compile(r'^Status:[ \t]*(.+)$')


def project_doc_entries(root):
    """The document set for one worktree's landing page: THIS root's registry
    entries united with THIS root's discover_docs — never
    index_doc_entries()'s sibling-worktree expansion. Served entries first in
    registry (last-served descending) order, then unserved entries by mtime
    descending."""
    served = []
    seen_paths = set()
    for e in registry_entries():
        e_root, _ = worktree_label(e['path'])
        if e_root != root:
            continue
        served.append(e)
        seen_paths.add(e['path'])

    try:
        discovered = discover_docs(root)
    except Exception:
        discovered = []

    unserved = []
    for d in discovered:
        if d['path'] in seen_paths:
            continue
        seen_paths.add(d['path'])
        unserved.append({"path": d['path'], "lastServed": None, "mtime": d['mtime']})
    unserved.sort(key=lambda e: e['mtime'], reverse=True)

    return served + unserved


def _entry_mtime(entry):
    """mtime for a merged entry: discovered entries already carry one; a
    registry-only entry falls back to a fresh stat, or 0 when that fails."""
    if 'mtime' in entry:
        return entry['mtime']
    try:
        return os.stat(entry['path']).st_mtime
    except OSError:
        return 0


def read_doc_annotation(path):
    """(field, value) read from the first 100 lines of path via the two
    protocol fields — "State" (todo-format) preferred, else "Status"
    (decision-file) — or None when neither matches or the file cannot be
    read. Only these two anchored fields are ever parsed."""
    try:
        with open(path, 'r', encoding='utf-8') as f:
            lines = []
            for i, line in enumerate(f):
                if i >= 100:
                    break
                lines.append(line.rstrip('\n'))
    except (OSError, UnicodeDecodeError):
        return None
    for line in lines:
        m = _STATE_RE.match(line)
        if m:
            return 'State', m.group(1)
    for line in lines:
        m = _STATUS_RE.match(line)
        if m:
            return 'Status', m.group(1)
    return None


def render_project_entry(entry, rel_text):
    """One <li> for a landing-page document: its /doc link (text = the
    caller-supplied relative path), an "unserved" mark when unregistered, and
    its protocol-field annotation when it has one — all file-derived text
    escaped."""
    href = '/doc' + urllib.parse.quote(entry['path'], safe='/')
    href_esc = html.escape(href, quote=True)
    text_esc = html.escape(rel_text)
    mark = (' <span class="unserved">(unserved)</span>'
            if entry.get('lastServed') is None else '')
    ann_html = ''
    annotation = read_doc_annotation(entry['path'])
    if annotation is not None:
        field, value = annotation
        value_esc = html.escape(value[:60])
        ann_html = f' <span class="ann">{html.escape(field)}: {value_esc}</span>'
    return f'<li><a href="{href_esc}">{text_esc}</a>{mark}{ann_html}</li>'


def render_project_group(name, items):
    """One COLLAPSED <details> group for a .local subdirectory: name is the
    top-level subdirectory, items a list of (entry, subdirectory-relative
    text) pairs."""
    parts = ['<details><summary>', html.escape(name), '</summary><ul class="docs">']
    for entry, rel in items:
        parts.append(render_project_entry(entry, rel))
    parts.append('</ul></details>')
    return ''.join(parts)


INDEX_STYLE = (
    "body{background:#12141c;color:#e8e8ec;"
    "font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;"
    "margin:2rem;}"
    "h1{font-weight:600;font-size:1.3rem;}"
    "details{border:1px solid #2a2d3a;border-radius:8px;margin-bottom:1rem;"
    "padding:.75rem 1rem;background:#181b26;}"
    "summary{cursor:pointer;font-weight:600;color:#9fb4ff;}"
    ".headline{margin:.5rem 0;padding:.5rem;border-left:3px solid #5b7fff;}"
    ".headline a{color:#e8e8ec;text-decoration:none;font-weight:600;}"
    ".meta{color:#9098a8;margin-left:.5rem;}"
    "ul.docs{list-style:none;padding-left:.5rem;margin:.5rem 0 0 0;}"
    "ul.docs li{padding:.15rem 0;}"
    "ul.docs a{color:#c7d0e0;text-decoration:none;}"
    "ul.docs a:hover{text-decoration:underline;}"
    ".unserved{color:#9098a8;font-style:italic;}"
    ".empty{color:#9098a8;padding:2rem 0;}"
)


def build_index_html(groups):
    """The full self-contained index page for a root -> group mapping."""
    body = ['<h1>render-doc: served documents</h1>']
    if not groups:
        body.append(
            '<p class="empty">No documents have been served yet. A document '
            'appears here after any render or serve of it through this '
            'server.</p>')
    else:
        for root, g in groups.items():
            body.append(render_group(root, g['label'], g['entries']))
    return ('<!DOCTYPE html><html><head><meta charset="utf-8">'
            '<title>render-doc served documents</title>'
            '<style>' + INDEX_STYLE + '</style></head><body>'
            + ''.join(body) + '</body></html>')


PROJECT_STYLE = INDEX_STYLE + ".ann{color:#9fb4ff;margin-left:.4rem;font-size:.9em;}"


def build_project_html(label, headline_entry, flat_entries, group_order, groups):
    """The full self-contained landing page for one worktree: its headline
    (if any), its flat top-level documents, then one collapsed group per
    .local subdirectory that holds a listed document, newest member first."""
    body = [f'<h1>{html.escape(label)}</h1>']
    if headline_entry is not None:
        body.append(render_headline(headline_entry))
    if not flat_entries and not group_order:
        body.append(
            f'<p class="empty">No documents found for <strong>'
            f'{html.escape(label)}</strong>. A document appears here once it '
            'exists under this worktree\'s .local/ directory, or has been '
            'served through this server.</p>')
    else:
        if flat_entries:
            body.append('<ul class="docs">')
            for entry, rel in flat_entries:
                body.append(render_project_entry(entry, rel))
            body.append('</ul>')
        for name in group_order:
            body.append(render_project_group(name, groups[name]))
    return ('<!DOCTYPE html><html><head><meta charset="utf-8">'
            '<title>' + html.escape(label) + ' — render-doc</title>'
            '<style>' + PROJECT_STYLE + '</style></head><body>'
            + ''.join(body) + '</body></html>')


# Contract: 002-B07 hostname allowlist + dual bind (plan 002-discovery-landing-dns)
#
# DELIBERATELY UNIMPLEMENTED — host_allowed raises. Wiring _check_host to
# call it, and the [::1] listener in main(), are this block's
# implementation; until then the exact-match Host check stands.
#
# Behavior:
#   host_allowed(host) decides whether a request's Host header value is an
#   acceptable name for this server. Accepted, ALL with the explicit
#   :<PORT> suffix and nothing else:
#     1. 127.0.0.1:<PORT>          (today's only form)
#     2. localhost:<PORT>
#     3. [::1]:<PORT>              (bracketed IPv6 loopback literal)
#     4. <label>.localhost:<PORT>  — exactly ONE DNS label before
#        .localhost: 1-63 chars of [A-Za-z0-9-], no leading or trailing
#        hyphen. Names match case-insensitively; the port digits must
#        match exactly.
#   Everything else is rejected: no bare names without the port, no other
#   IPs, no multi-label subdomains (a.b.localhost), no trailing dot, no
#   userinfo or path smuggling. Rejection semantics in _check_host stay
#   exactly today's: 403 {"error": "bad Host header"} before any routing.
#
#   main() additionally binds a second ThreadingHTTPServer to ('::1',
#   PORT) sharing this Handler, served on a daemon thread, so clients
#   whose resolver takes *.localhost to ::1 (curl on this machine) reach
#   the same server. The v6 bind is BEST-EFFORT: any OSError (IPv6
#   disabled, ::1 taken) leaves the v4 server fully functional, at most a
#   one-line stderr note. The v4 bind keeps today's singleton semantics
#   (EADDRINUSE -> exit 0) unchanged; the v6 listener never affects the
#   exit code, the pidfile, or shutdown beyond being closed alongside the
#   v4 server.
# Inputs: host — the raw Host header string, or None when absent.
# Outputs: True or False; total over its input domain, never raises.
# Errors: none — malformed input is simply False.
# Invariants: DNS-rebinding defense holds with zero configuration: every
#   accepted form can only ever reach loopback under RFC 6761 (localhost
#   and *.localhost are special-use — compliant resolvers and browsers
#   answer them with loopback or NXDOMAIN), so no name needs registering
#   and no allowlist needs configuring.
# Edge cases: None (False); "CLAM.LOCALHOST:27183" (True — case); a
#   correct name with the wrong port (False); "clam.localhost" without a
#   port (False); "a.b.localhost:27183" (False); "-x.localhost:27183" and
#   "x-.localhost:27183" (False); a 64-char label (False);
#   "127.0.0.1:27183extra" (False).
def host_allowed(host):
    raise NotImplementedError("002-B07")


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

        if raw == '/':
            self._serve_index()
            return

        if raw == '/docs.json':
            self._serve_docs_json()
            return

        if raw == '/project/for':
            self._serve_project_for()
            return

        if raw.startswith('/project/'):
            self._serve_project(urllib.parse.unquote(raw[len('/project'):]))
            return

        if raw.startswith('/raw/'):
            self._serve_raw(urllib.parse.unquote(raw[len('/raw'):]))
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
        registry_record(md_real)
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    # Contract: B01 raw-doc route (plan 001-render-graph-always)
    #
    # DELIBERATELY UNIMPLEMENTED — the method body raises.
    #
    # Behavior:
    #   GET /raw/<abs-md-path> serves the CURRENT bytes of the source
    #   markdown file itself (never the rendered sibling), so an open page
    #   can poll for changes and re-render client-side.
    #   1. The path after /raw is percent-decoded and treated as an
    #      absolute filesystem path, exactly like /doc's (the do_GET wiring
    #      above already does this).
    #   2. Scope rules are IDENTICAL to /doc and /annotate and run on the
    #      realpath BEFORE any read — reuse scope_error; each violation
    #      returns the same JSON {"error": ...} shape and status.
    #   3. A successful response is 200 with Content-Type
    #      text/plain; charset=utf-8, a correct Content-Length, body = the
    #      file's raw bytes, and an ETag header whose value is the sha256
    #      hex digest of exactly those bytes wrapped in double quotes.
    #   4. When the request carries If-None-Match equal to the current
    #      ETag (matched with or without the surrounding quotes), respond
    #      304 with the same ETag header and NO body. Any other
    #      If-None-Match value gets the full 200.
    #   5. /raw never writes, renders, or mutates anything — the sibling
    #      .html is not touched, not even when stale.
    #   6. On success (200 and 304 alike) the serve is recorded via
    #      registry_record (B02) — fire-and-forget, per B02's invariants.
    # Inputs: GET /raw/<percent-encoded abs path>; optional If-None-Match
    #   header. Host pinning has already run before routing.
    # Outputs: 200 + bytes + ETag; 304 + ETag, no body; or a JSON error.
    # Errors: scope violations per scope_error (403/404 JSON); a file that
    #   passes scope but cannot be read -> 500 {"error": ...} naming the
    #   OSError; no traceback may leak to the client or crash the server.
    # Invariants: read-only; the bytes hashed for the ETag are the same
    #   bytes sent (one read, no re-encoding); 127.0.0.1 only.
    # Edge cases: empty .md (200, ETag of the empty hash, empty body);
    #   file replaced between poll cycles (each request reads once —
    #   hash and body always agree); paths with spaces/non-ASCII
    #   (percent-decoded before realpath); query strings already stripped.
    def _serve_raw(self, md_path):
        md_real = os.path.realpath(md_path)
        err = scope_error(md_real)
        if err:
            self.send_json(err[0], {"error": err[1]})
            return

        try:
            with open(md_real, 'rb') as f:
                content = f.read()
        except OSError as e:
            self.send_json(500, {"error": f"could not read markdown: {e}"})
            return

        digest = hashlib.sha256(content).hexdigest()
        etag = '"' + digest + '"'
        registry_record(md_real)

        inm = self.headers.get('If-None-Match')
        if inm is not None and inm.strip().strip('"') == digest:
            self.send_response(304)
            self.send_header('ETag', etag)
            self.end_headers()
            return

        self.send_response(200)
        self.send_header('Content-Type', 'text/plain;charset=utf-8')
        self.send_header('Content-Length', str(len(content)))
        self.send_header('ETag', etag)
        self.end_headers()
        self.wfile.write(content)

    # Contract: B02 served-doc registry — /docs.json handler; see the
    # module-level B02 contract above registry_record for the full spec.
    # DELIBERATELY UNIMPLEMENTED — raises.
    def _serve_docs_json(self):
        try:
            docs = registry_entries()
        except Exception:
            docs = []
        self.send_json(200, {"docs": docs})

    # Contract: B03 project index (plan 001-render-graph-always)
    #
    # DELIBERATELY UNIMPLEMENTED — the method body raises.
    #
    # Behavior:
    #   GET / responds 200 text/html; charset=utf-8 with ONE self-contained
    #   page (inline CSS only; no external resources; works with scripting
    #   disabled) listing EVERY registered document, grouped by project:
    #   1. Source of truth: registry_entries() (B02) — already scope-pruned
    #      and sorted by last-served descending.
    #   2. A project is a worktree: an entry's group is the nearest
    #      ancestor directory of the file containing a .git entry (every
    #      in-scope path has one — the scope rules require it); the group
    #      label is that path, abbreviated with a leading ~ when under
    #      $HOME.
    #   3. Groups are ordered by their most recently served member;
    #      within a group, entries keep the registry's last-served order.
    #   4. A group containing a document whose basename is exactly
    #      WORKGRAPH.md shows that document as the group's headline: its
    #      /doc link plus the open-node count and Focus id, read from the
    #      file via the work-graph protocol's machine-read markers
    #      (docs/protocols/work-graph.md): open nodes are lines matching
    #      ^- Status: open[[:space:]]*$ and Focus is the line matching
    #      ^Focus: (N[0-9]+|none)[[:space:]]*$.
    #   5. Every other document in the group is listed beneath that as
    #      its path relative to the worktree root, linking to
    #      /doc/<percent-encoded realpath> (the live view).
    #   6. Each group is independently expandable/collapsible without
    #      scripting (details/summary), so a reader can select one
    #      project and see only that project's documents; every group
    #      renders expanded by default (the open attribute).
    #   7. A listed file that cannot be read, or whose markers cannot be
    #      parsed, is STILL listed (label + link) with its count and Focus
    #      shown as unavailable — one bad file never drops an entry and
    #      never produces a 500.
    #   8. Zero registered documents -> 200 with an empty-state message
    #      explaining that a document appears here after any render or
    #      serve of it through this server.
    # Inputs: GET /; the registry; the registered files on disk.
    # Outputs: 200 text/html with a correct Content-Length.
    # Errors: none observable beyond the per-entry degradation above; a
    #   registry failure yields the empty state, not a 500.
    # Invariants: read-only beyond B02's specified pruning; Host pinning
    #   applies as on every route; ALL entry-derived text (paths, Focus
    #   ids) is HTML-escaped — file contents and names are untrusted.
    # Edge cases: a workgraph with zero nodes (count 0, Focus none); a
    #   Focus id naming a missing node (shown as recorded — the protocol
    #   tells readers to tolerate it); several worktrees of one repo (one
    #   group each, distinct labels); a group with no workgraph (a plain
    #   document list, no headline).
    def _serve_index(self):
        try:
            entries = index_doc_entries()
        except Exception:
            entries = []

        groups = {}
        for e in entries:
            root, label = worktree_label(e['path'])
            if root is None:
                continue
            g = groups.setdefault(root, {'label': label, 'entries': []})
            g['entries'].append(e)

        content = build_index_html(groups).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'text/html;charset=utf-8')
        self.send_header('Content-Length', str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    # Contract: 002-B04 worktree landing page (plan 002-discovery-landing-dns)
    #
    # DELIBERATELY UNIMPLEMENTED — both method bodies raise
    # NotImplementedError("002-B04"). The do_GET route wiring is present at
    # scaffold so requests reach these stubs.
    #
    # Behavior:
    #   GET /project/<abs worktree root> responds 200 text/html;
    #   charset=utf-8 with ONE self-contained page (inline CSS only, no
    #   external resources, works with scripting disabled) for that single
    #   worktree:
    #   1. Validation: the decoded path is realpath'd and must be an
    #      existing directory under $HOME carrying a .git entry. Failures
    #      mirror scope_error's shape: 403 {"error": ...} for outside-home
    #      or not-a-worktree, 404 {"error": ...} for a missing directory.
    #   2. Document set: discover_docs(root) united with the registry's
    #      entries whose worktree_label root is this root — same merge
    #      semantics as B02: a registered path keeps its registry entry,
    #      others join unserved. Served docs list first (last-served
    #      order), then unserved by mtime descending, each unserved doc
    #      visibly marked with text containing "unserved".
    #   3. Headline: exactly <root>/.local/WORKGRAPH.md (the protocol's
    #      named path, docs/protocols/work-graph.md), when present: its
    #      /doc link plus open-node count and Focus id via the protocol's
    #      machine-read markers; unreadable/unparseable -> both shown
    #      "unavailable", never an error. A WORKGRAPH.md elsewhere in the
    #      tree is an ordinary doc.
    #   4. Layout: docs directly in .local/ list flat, first, always
    #      visible; each SUBDIRECTORY of .local/ that contains listed docs
    #      becomes one collapsible details/summary group labelled with its
    #      .local-relative path (nested docs group under their top-level
    #      subdirectory; the label is the subdirectory name, the entry
    #      text the doc's subdirectory-relative path). Groups order by
    #      their newest member mtime descending and render COLLAPSED by
    #      default (no open attribute). No directory name is ever treated
    #      specially.
    #   5. Annotations — protocol fields only, each degrading silently to
    #      a plain link: a doc containing, within its first 100 lines, a
    #      line matching ^State:[ \t]*(.+)$ (todo-format) shows
    #      "State: <value>"; otherwise a line matching
    #      ^Status:[ \t]*(.+)$ (decision-file) shows "Status: <value>";
    #      values render truncated to 60 characters. No other content is
    #      parsed.
    #   6. Every doc links to /doc/<percent-encoded realpath>. ALL
    #      file-derived text is HTML-escaped — names and contents are
    #      untrusted.
    #   7. A worktree with no .local or no listable docs -> 200 with an
    #      empty-state message naming the worktree label.
    #
    #   GET /project/for?path=<percent-encoded absolute doc path> responds
    #   302 with Location: /project/<percent-encoded root>, root =
    #   worktree_label(realpath(path))[0]. The doc itself need not pass
    #   full scope (it may be unserved or even absent); but no query or an
    #   empty path is 400 {"error": ...}, a path outside $HOME is 403, and
    #   a path with no worktree ancestor is 403 — all JSON.
    # Inputs: the two GETs above; the filesystem; the registry.
    # Outputs: 200 text/html with correct Content-Length; 302 with a
    #   Location header; JSON errors as specified.
    # Errors: per-document failures degrade to plain listings; only
    #   validation failures produce non-200/302 responses; never a 500 for
    #   a bad document.
    # Invariants: read-only — visiting a landing page never registers
    #   anything (no registry_record) and writes nothing; Host pinning
    #   applies as on every route; no plugin is named in the emitted page —
    #   labels and annotations derive only from paths and protocol fields.
    # Edge cases: root with a trailing slash (normalized by realpath); a
    #   .local subdirectory with only non-.md files (no group emitted); a
    #   doc both registered and discovered (one entry, served); $HOME
    #   itself as the requested root (403 unless it carries a .git entry);
    #   percent-encoded UTF-8 in paths (decoded, escaped on output).
    def _serve_project(self, root_path):
        root_real = os.path.realpath(root_path)
        if not os.path.isdir(root_real):
            self.send_json(404, {"error": "worktree not found"})
            return
        home = os.path.realpath(os.path.expanduser('~'))
        if not (root_real == home or root_real.startswith(home + os.sep)):
            self.send_json(403, {"error": "scope: outside the home directory"})
            return
        if not os.path.exists(os.path.join(root_real, '.git')):
            self.send_json(403, {"error": "scope: not inside a git worktree"})
            return

        label = '~' + root_real[len(home):]

        try:
            entries = project_doc_entries(root_real)
        except Exception:
            entries = []

        local_root = os.path.join(root_real, '.local')
        workgraph_path = os.path.realpath(os.path.join(local_root, 'WORKGRAPH.md'))

        headline_entry = None
        flat_entries = []
        groups = {}
        for entry in entries:
            if headline_entry is None and entry['path'] == workgraph_path:
                headline_entry = entry
                continue
            rel = os.path.relpath(entry['path'], local_root)
            parts = rel.split(os.sep) if not rel.startswith(os.pardir) else None
            if parts and len(parts) > 1:
                top = parts[0]
                groups.setdefault(top, []).append((entry, os.sep.join(parts[1:])))
            else:
                flat_entries.append((entry, os.path.relpath(entry['path'], root_real)))

        group_order = sorted(
            groups.keys(),
            key=lambda name: max(_entry_mtime(e) for e, _ in groups[name]),
            reverse=True)

        content = build_project_html(
            label, headline_entry, flat_entries, group_order, groups).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'text/html;charset=utf-8')
        self.send_header('Content-Length', str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def _serve_project_for(self):
        query = urllib.parse.urlsplit(self.path).query
        params = urllib.parse.parse_qs(query)
        path_values = params.get('path')
        if not path_values or not path_values[0]:
            self.send_json(400, {"error": "missing path parameter"})
            return

        doc_real = os.path.realpath(path_values[0])
        home = os.path.realpath(os.path.expanduser('~'))
        if not (doc_real == home or doc_real.startswith(home + os.sep)):
            self.send_json(403, {"error": "scope: outside the home directory"})
            return

        root, _ = worktree_label(doc_real)
        if root is None:
            self.send_json(403, {"error": "scope: not inside a git worktree"})
            return

        location = '/project' + urllib.parse.quote(root, safe='/')
        self.send_response(302)
        self.send_header('Location', location)
        self.send_header('Content-Length', '0')
        self.end_headers()

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
