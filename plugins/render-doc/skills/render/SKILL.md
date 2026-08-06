---
name: render
description: "Render a planning or decision markdown file into a single self-contained dark-theme HTML view and optionally open it in the browser. Use at feedback checkpoints (plan ready for review, decision parked), or when the user asks for an HTML view of a document: `/render-doc:render <file>`."
---

# Render Doc

Turn a markdown document into one self-contained HTML file the user can read in a browser: sticky table of contents, collapsible sections, styled tables, schema-aware layouts for plans and decisions, and a feedback composer that emits the standard annotation tags. The markdown stays the document of record; the HTML is a disposable derived view.

## Usage

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/render.sh <doc.md> [--open|--serve]
```

- Writes a sibling `.html` next to the input (`.local/PLAN.md` → `.local/PLAN.html`).
- `--open` starts the shared local annotation server (if python3 is available) and opens the rendered view on `http://127.0.0.1:<port>/doc/<absolute path of the .md>`, where `<port>` is 27183 unless `RENDER_DOC_PORT` overrides it. Falls back to a plain `file://` open when python3 is unavailable. The server is a single shared instance, and the fixed port is what makes that work: the first `--open` call binds it, every later call on the machine reuses it. See "## Annotation server" below.
- `--serve` registers the document on that same shared server without opening anything: it starts or reuses the server exactly as `--open` does, then makes one request against it so the document is rendered server-side and recorded in the server's registry. It prints exactly one line, `serving: http://127.0.0.1:<port>/doc/<absolute path of the .md>`, and opens no browser, ever. Unlike `--open`, `--serve` never degrades to `file://` — registration is the point — so any failure exits non-zero with a stderr note naming the reason, and callers should skip silently on that exit.
- Exits non-zero with a message on stderr for any failure (missing input, missing template or parser, splice failure). Callers MUST treat a non-zero exit as "fall back to the markdown flow", never as a reason to block review.

The rendered HTML is self-contained (vendored parser, no CDNs, system fonts). When served via the annotation server, the feedback composer writes `@TAG:` lines directly into the source markdown on each "Add" click; when opened as `file://`, annotations live in browser memory only and "Copy all feedback" is the export path.

While the annotation server is serving a page, it polls `/raw` (conditional on `ETag`/`If-None-Match`) roughly every 1.5s and re-renders itself in place when the source markdown changes; an open annotation composer draft is never destroyed by this — the update is held until the composer closes. A plain `file://` open never polls.

## What the view provides

| Layer | Behavior |
|-------|----------|
| Baseline | TOC with scroll tracking, collapsible h2 sections, styled GFM tables, `@TAG:` chips highlighted in prose (never inside `pre`/`code`) |
| Schema-aware | Keyed on the H1: `Plan:` gets approach cards, edge-case treatment, changelog timeline; `Decision:` gets side-by-side option cards, a recommendation banner, status pills; `Design Questions:` gets, per `## DQ<n>:` section, side-by-side option cards with pros/cons and an inline recommendation banner (a non-conforming DQ falls back to baseline for that section only); `# Work Graph` gets a tree of node cards nested by Parent edges, a dependency badge per Deps entry, a three-way status pill (open, done, or dropped) per node, and a focus banner for the Focus node, with per-node fallback to baseline for a non-conforming node — a topbar "Graph" toggle switches that card tree to a node-and-edge view rendered with cytoscape and a dagre layout (status-colored nodes, distinct Parent/Deps edge styles, a Focus highlight, click-a-node back to its card), with the graph view the default on load and the card tree one toggle away. A topbar toggle switches to generic rendering; unrecognized H1s get baseline only |
| Feedback composer | Hover a section heading → `+ annotate`, or hover a paragraph/bullet/row → gutter `+`, then pick a tag and type a note. "Copy all feedback" puts a block on the clipboard, one line per item: section-anchored (`§ Proposed Approach — @CONCERN: ...`) or block-anchored with a verbatim excerpt greppable in the source (`§ Proposed Approach ¶ "..." — @CONCERN: ...`) |

The composer emits exactly this annotation vocabulary: `@COMMENT:`, `@QUESTION:`, `@CONCERN:`, `@APPROVE:`, `@EVIDENCE:`. Reading without annotating requires nothing — the composer stays out of the way until used.

| Layer | Behavior |
|-------|----------|
| Save to markdown | When served via the annotation server (`--open`), each "Add" POSTs to the server, which writes the `@TAG: note` line directly into the source `.md` file. Section-level annotations insert after the `## heading` line; block-level annotations insert after the line containing the excerpt. The agent reads the markdown and sees annotations inline, no clipboard paste needed. On `file://` (no server), annotations are in-memory only and "Copy all feedback" remains the export path. |

## Checkpoint integration

Automatic rendering at checkpoints is gated by plugin presence: callers check whether the `render-doc:render` skill is available and skip silently when it is not. `/decision-log:rundown` renders the decision file with `--open` after writing it at park time when this plugin is installed.

Callers fall back to the plain-markdown flow with a one-line notice when a render fails.

## How the splice works

`render.sh` replaces three slot lines in `assets/template.html`:

- `__MARKED_SPLICE__` → the vendored parser (`assets/marked.min.js`).
- `__DOC_B64_SPLICE__` → the document, base64-encoded into a data block. Base64 cannot contain `<`, so a document containing `</script>` (or any other markup) can never terminate the page's scripts. The page decodes and parses client-side, entirely offline.
- `__SOURCE_PATH_SPLICE__` → the absolute path of the source `.md` file, placed in a `<script type="text/plain">` block (inert text, no injection risk). Sent by the template JS in annotation POST requests so the server knows which file to write.

The output self-checks: leftover slot markers fail the render before anything is written.

## Failure modes

| Scenario | Behavior |
|----------|----------|
| Missing input / template / parser | Exit 1, message on stderr, no output written |
| Markdown parser throws in-browser | Error card with the raw markdown shown as text |
| Schema section missing or reshaped | That transform silently falls back to baseline rendering |
| `open` fails or is absent | Render still succeeds; path printed for manual viewing |
| python3 unavailable | `--open` falls back to `file://` open; annotations are in-memory only |
| Annotation server unreachable | "Add" still works in-memory; no save confirmation shown |

## Maintenance

- The parser is `marked` v18.0.6 (MIT), vendored byte-identical from the npm tarball as `assets/marked.min.js`; the file header records provenance and the upgrade procedure.
- The graph rendering layer is `cytoscape@3.34.0` (MIT), vendored byte-identical from the npm tarball as `assets/cytoscape.min.js`; the file header records provenance and the upgrade procedure.
- The graph layout engine is `cytoscape-dagre@4.0.0` (MIT), vendored byte-identical from the npm tarball as `assets/cytoscape-dagre.min.js` (bundles dagre internally); the file header records provenance and the upgrade procedure.
- `scripts/render.test.sh` renders all four fixtures (`plan`, `decision`, `design-questions`, `work-graph`) in a temp dir and asserts: parser spliced, doc round-trips byte-for-byte through base64, no slot markers remain, script-element count unchanged (the `</script>` proof), no external resource references, and render.sh fails loudly on bad input. Run it after any template or script change.

## Annotation server

`scripts/serve.py` is a single shared HTTP server on `127.0.0.1` (never exposed to the network), bound to the fixed port 27183 by default — override with `RENDER_DOC_PORT`. It takes no arguments and keeps no state file: the bind itself is the singleton lock, so whichever session gets there first serves every session and every agent on the machine afterward, and a process that loses the race just exits.

- `render.sh --open` starts it if nothing is bound to the port, reuses it if a copy of this server is already alive there (health-checked via `/health`).
- Documents are addressed deterministically at `GET /doc/<absolute path to the .md>` — the URL for a given file never changes and survives a server restart. The handler re-renders the sibling `.html` on demand whenever the `.md` or the template is newer than it, otherwise serves the existing file untouched.
- Every path-bearing request is checked on the realpath of the markdown it names, before any read: it must be a `.md` file, must exist, must resolve under `$HOME`, and must sit inside a git worktree.
- Every request must also carry a `Host` header of exactly `127.0.0.1:<port>`; anything else is rejected before routing, so no other origin can drive the server through the reader's browser.
- POST `/annotate` with `{md, section, excerpt, tag, note}` writes the annotation into the markdown, subject to the same scope check.

One server handles all concurrent sessions. There is no automatic shutdown — it runs until the machine reboots or someone kills it by hand; no user action is needed to start it.

Each worktree that has served or discovered documents also gets its own landing page at `GET /project/<worktree root>` — the same kind of listing as `/`, scoped to just that worktree's `.local/` documents, with `GET /project/for?path=<doc>` resolving any document (served or not) to its owning worktree's page. A document page served through this server (not opened as `file://`) shows two topbar links to reach that navigation: "Index" back to `/`, and "Worktree" to the document's own landing page via the resolver above; a page opened straight from disk shows neither.

## Boundaries

- Write only the sibling `.html` of the input file. The annotation server writes `@TAG:` lines into the source markdown; this is the only intentional modification of source files.
- Do not add network fetches to the template or server; no CDNs, no web fonts.
- Generated HTML under `.local/` is disposable; never commit it.
