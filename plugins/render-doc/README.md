
# render-doc

Turn a markdown document into one self-contained HTML file you can read in a
browser: sticky table of contents, collapsible sections, styled tables,
schema-aware layouts for plans and decisions, and a feedback composer that
emits standard annotation tags (`@COMMENT:`, `@QUESTION:`, `@CONCERN:`,
`@APPROVE:`, `@EVIDENCE:`). The markdown stays the document of record; the
HTML is a disposable derived view.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install render-doc@clam
```

No configuration required. python3 is a soft requirement — it powers the
`--open` annotation server, so edits made through the browser composer get
written straight back into the source markdown. Without python3, `--open`
degrades to a plain `file://` open: the page still renders and the composer
still works, but annotations stay in-memory in the browser and "Copy all
feedback" becomes the export path instead of an automatic write-back.

## What to expect

Installing this plugin changes nothing until you render a document — it is
inert until you run `/render-doc:render <file>` or invoke
`scripts/render.sh` directly. No hooks, no injected context, no settings
written.

When you do render a document:

- A sibling `.html` file is written next to the input (`.local/PLAN.md` ->
  `.local/PLAN.html`). This is the only file render.sh itself writes.
- With `--open` and python3 available, the shared annotation server
  (`scripts/serve.py`) starts on its fixed port (or is reused if a copy is
  already bound there). From then on, "Add" clicks in the browser composer
  write `@TAG: note` lines back into the source markdown — the only other
  file this plugin modifies, and only in response to an explicit
  annotation.
- Other plugins never see this plugin unless they choose to: automatic
  rendering at their checkpoints is gated by checking whether the
  `render-doc:render` skill is available, and skipping silently when it is
  not.
- While the annotation server is serving a page (`--open`), the page polls
  `/raw` (conditional on `ETag`/`If-None-Match`) roughly every 1.5s and
  re-renders itself in place when the source markdown changes; an open
  annotation composer draft is never destroyed by this — the update is
  held until the composer closes. A plain `file://` open never polls.

## Common workflows

### Render a plan or decision file for review

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/render.sh .local/PLAN.md --open
```

Opens a dark-theme HTML view in the browser. The H1 selects the layout:
`Plan:` gets approach cards, edge-case treatment, and a changelog timeline;
`Decision:` gets side-by-side option cards, a recommendation banner, and
status pills; `Design Questions:` gets, per `## DQ<n>:` section, side-by-side
option cards with pros/cons and an inline recommendation banner (a
non-conforming DQ section falls back to baseline rendering for that section
only); `# Work Graph` — the shape defined by the work-graph document format
(`docs/protocols/work-graph.md`) — gets a tree of node cards nested by their
Parent edges, a dependency badge for each entry in a node's Deps list, a
three-way status pill (open, done, or dropped) per node, and a focus banner
naming the `Focus:` node when one is set. A node missing a required field or
shaped wrong falls back to baseline rendering for that node only — a
per-node fallback that keeps one bad entry from breaking the rest of the
tree. A topbar "Graph" toggle switches a Work Graph document from that card
tree to a node-and-edge view rendered with cytoscape and a dagre layout:
nodes are status-colored, Parent and Deps edges get distinct edge styles,
and the Focus node gets a highlight. Clicking a node jumps back to its card,
and the graph view is the default on load for Work Graph documents, with
the card tree one toggle away. Any other H1 gets baseline rendering: TOC
with scroll tracking, collapsible h2 sections, styled GFM tables. A topbar
toggle switches to generic rendering at any time.

### Leave feedback that writes back into the source

Hover a section heading for `+ annotate`, or hover a paragraph/bullet/row for
a gutter `+`, then pick a tag (`@COMMENT:`, `@QUESTION:`, `@CONCERN:`,
`@APPROVE:`, `@EVIDENCE:`) and type a note. When the document was opened via
the annotation server (`--open` with python3), each "Add" POSTs to the
server, which writes the `@TAG: note` line directly into the source `.md`:
section-level annotations insert after the `## heading` line, block-level
annotations insert after the line containing a verbatim excerpt of the
paragraph/bullet/row. No clipboard paste needed — the agent just re-reads
the markdown. On a plain `file://` open (no server), annotations live in
the browser only; "Copy all feedback" puts one line per item on the
clipboard, section-anchored (`§ Proposed Approach — @CONCERN: ...`) or
block-anchored with the excerpt (`§ Proposed Approach ¶ "..." — @CONCERN:
...`).

### Render without opening a browser

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/render.sh .local/PLAN.md
```

Writes the sibling `.html` and prints its path; nothing is opened. Useful
when you just want the artifact, or when checking exit status
programmatically — a non-zero exit means "fall back to the plain-markdown
flow," never a reason to block review.

## Commands

### Skills

**render** — `/render-doc:render <file>` (also model-invoked at feedback
checkpoints, e.g. a plan ready for review or a decision just parked, and
whenever the user asks for an HTML view of a document). Runs
`scripts/render.sh` under the hood; see Common workflows above for what the
rendered view provides.

### Scripts

**`scripts/render.sh <doc.md> [--open]`** — the command the `render` skill
wraps. Splices `assets/template.html`'s three slot lines
(`__MARKED_SPLICE__`, `__DOC_B64_SPLICE__`, `__SOURCE_PATH_SPLICE__`) with
the vendored parser, the base64-encoded document, and the document's
absolute path, then writes the sibling `.html`. The output self-checks
before anything is written: any leftover slot marker fails the render
(template drift). Base64 embedding means the document can never contain a
sequence — like a closing `</script>` tag — that breaks the page; the
rendered file closes exactly as many `</script>` elements as the template.
Exits non-zero with a message on stderr for any failure (missing input,
missing template or parser, splice failure); no output is written on
failure.

**`scripts/serve.py`** — the shared local annotation server behind
`render.sh --open`, on `127.0.0.1` only (never exposed to the network).
Takes no arguments and needs none: it binds the fixed port 27183 (override
with `RENDER_DOC_PORT`), and that bind is itself the singleton lock — the
first session to reach the port owns it for every session and every agent
on the machine afterward, and a process that loses the race just prints a
diagnostic and exits, so nobody fights over it. Every rendered document
lives at a deterministic address, `/doc/<absolute path to the .md>`, so a
given file's URL never changes and survives a server restart; a request
re-renders the sibling `.html` on demand whenever the source `.md` or
`assets/template.html` is newer than it, and serves the existing file
untouched otherwise. Before touching any file, `/doc` and `/annotate` both
resolve the requested path's realpath and check it against the same scope
rule: it must end in `.md`, must exist, must resolve under `$HOME`, and
must sit inside a git worktree — checked on the realpath before any read,
so a symlink cannot smuggle in a file the rule would otherwise reject.
Every request also carries a `Host` header pinned to `127.0.0.1:<port>`;
anything else is rejected before routing, so a page loaded from another
origin cannot drive this server through the reader's browser. Annotations
arrive via POST `/annotate` with `{md, section, excerpt, tag, note}` and
are written straight into the markdown named in the request, subject to
that same scope check.

Three more routes ride the same server. `GET /raw/<path>` returns the
*source* markdown's current bytes — never the rendered sibling — with a
quoted `sha256` digest of those bytes as the `ETag`; a request whose
`If-None-Match` carries that ETag (quoted or bare) gets a `304` with no
body, so an open page can poll cheaply for live updates instead of a full
re-fetch each time. `/raw` is checked under the identical scope rule as
`/doc` — realpath, `.md`, under `$HOME`, inside a git worktree.

Every successful `/doc` or `/raw` serve is remembered in a served-doc
registry, persisted best-effort to `/tmp/render-doc-registry-<port>.json`
(one file per port). `GET /docs.json` returns that registry as
`{"docs": [...]}`, scope-pruned on every read so a path that has since
left scope never lingers in the listing.

`GET /` is the project index: one self-contained page listing every
registered document, grouped by worktree/project into a collapsible
`<details>` section per group (expanded by default). A group whose
documents include a `WORKGRAPH.md` shows it as the group's headline, with
its open-node count and Focus id read from the work-graph protocol's
markers; every other document in the group lists as a path relative to
the worktree root, all linking to their live `/doc` views.

### Failure modes

| Scenario | Behavior |
|----------|----------|
| Missing input / template / parser | Exit 1, message on stderr, no output written |
| Markdown parser throws in-browser | Error card with the raw markdown shown as text |
| Schema section missing or reshaped | That transform silently falls back to baseline rendering |
| `open` fails or is absent | Render still succeeds; path printed for manual viewing |
| python3 unavailable | `--open` falls back to `file://` open; annotations are in-memory only |
| Annotation server unreachable | "Add" still works in-memory; no save confirmation shown |
| Port 27183 (or `RENDER_DOC_PORT`) held by another process, not this server | A stderr note names the port; `--open` falls back to `file://` |
| `/raw` requested for a file that fails to read (permissions, vanished mid-request) | `500` with a JSON `{"error": ...}`; no traceback, no crash |
| The registry file can't be written (`/tmp` unwritable, deleted mid-run) | Persistence is silent and best-effort; the in-memory registry and `/docs.json` keep working |
| A registered document's `WORKGRAPH.md` (or any listed file) can't be read for the project index | That entry's open-node count and Focus id show as unavailable; the rest of the index renders normally |

### Maintenance

- The parser is `marked` v18.0.6 (MIT), vendored byte-identical from the npm
  tarball as `assets/marked.min.js`; the file header records provenance and
  the upgrade procedure.
- The graph rendering layer is `cytoscape@3.34.0` (MIT), vendored
  byte-identical from the npm tarball as `assets/cytoscape.min.js`; the
  file header records provenance and the upgrade procedure.
- The graph layout engine is `cytoscape-dagre@4.0.0` (MIT), vendored
  byte-identical from the npm tarball as `assets/cytoscape-dagre.min.js`
  (bundles dagre internally); the file header records provenance and the
  upgrade procedure.
- `scripts/render.test.sh` renders all four fixtures (`plan`, `decision`,
  `design-questions`, `work-graph`) in a temp directory and asserts: parser
  spliced, doc round-trips byte-for-byte through base64, no slot markers
  remain, script-element count unchanged (the `</script>` proof), no
  external resource references, and `render.sh` fails loudly on bad input.
  Run it after any template or script change.
- `scripts/server.test.sh` and `scripts/open.test.sh` cover the annotation
  server and the `--open` client end to end — run them after any change to
  `serve.py` or the `--open` block in `render.sh`.

## Tests

```bash
bash plugins/render-doc/scripts/render.test.sh
bash plugins/render-doc/scripts/server.test.sh
bash plugins/render-doc/scripts/server-docs.test.sh
bash plugins/render-doc/scripts/server-raw.test.sh
bash plugins/render-doc/scripts/server-registry.test.sh
bash plugins/render-doc/scripts/server-index.test.sh
bash plugins/render-doc/scripts/open.test.sh
bash plugins/render-doc/scripts/save-status.test.sh
bash plugins/render-doc/scripts/structure.test.sh
bash plugins/render-doc/scripts/registration.test.sh
bash plugins/render-doc/scripts/migration.test.sh
bash plugins/render-doc/scripts/workgraph-docs.test.sh
bash plugins/render-doc/scripts/workgraph-graph.test.sh
bash plugins/render-doc/scripts/workgraph-render.test.sh
bash plugins/render-doc/scripts/live-update.test.sh
bash plugins/render-doc/scripts/graph-default.test.sh
bash plugins/render-doc/scripts/graph-always-docs.test.sh
```

## Provenance

Ported from clam-code, adapted to run as a standalone plugin: paths resolve
relative to the plugin's own install location instead of a fixed skills
directory, and cross-skill references degrade gracefully for skills not yet
ported.

## Update

```
/plugin marketplace update clam
claude plugin update render-doc@clam
```

Both commands are needed: refreshing the catalog never touches an installed
plugin, and updating one is CLI-only — there is no `/plugin update`.
Afterwards run `/reload-plugins` to pick the new version up in the current
session, or restart the session if this plugin ships hooks or agents.

Auto-update is off by default for third-party marketplaces. Even with it
enabled, a plugin that ships hooks stays pinned to the last explicitly
installed version until you run the update command yourself
(anthropics/claude-code#52218).

## Relationships to other plugins

None required. This plugin is fully standalone and works with only itself
installed — no reference anywhere in it to the pre-plugin skills layout or
to another plugin's files; every script resolves its own location.

**Consumed by decision-log (soft integration):** `/decision-log:rundown`
renders the decision file with `--open` after writing it at park time, when
this plugin is installed. The dependency runs one way and by skill name
only — decision-log checks whether the `render-doc:render` skill is
available and skips the render silently when it is not; render-doc carries
no knowledge of decision-log in either direction.

## Uninstalling

```
/plugin uninstall render-doc@clam
```

No other cleanup needed for a normal install. The annotation server has no
automatic shutdown: uninstalling the plugin does not stop it, and it keeps
running until the machine reboots or you kill it by hand. To stop it,
read the pid from `curl -s http://127.0.0.1:27183/health` (swap in your
`RENDER_DOC_PORT` if you set one) — or from the pidfile at
`/tmp/render-doc-serve-27183.pid` — and `kill` it. Rendered `.html` files
under `.local/` are disposable derived views, not tracked by the plugin —
remove them yourself if you don't want to keep them around.
