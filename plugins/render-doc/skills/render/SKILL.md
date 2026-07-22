---
name: render
description: "Render a planning or decision markdown file into a single self-contained dark-theme HTML view and optionally open it in the browser. Use at feedback checkpoints (plan ready for review, decision parked), or when the user asks for an HTML view of a document: `/render-doc:render <file>`."
---

# Render Doc

Turn a markdown document into one self-contained HTML file the user can read in a browser: sticky table of contents, collapsible sections, styled tables, schema-aware layouts for plans and decisions, and a feedback composer that emits the standard annotation tags. The markdown stays the document of record; the HTML is a disposable derived view.

## Usage

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/render.sh <doc.md> [--open]
```

- Writes a sibling `.html` next to the input (`.local/PLAN.md` → `.local/PLAN.html`).
- `--open` starts a shared local annotation server (if python3 is available) and opens the rendered view on `http://127.0.0.1:<port>/d/<id>`. Falls back to a plain `file://` open when python3 is unavailable. The server is a single shared instance: the first `--open` call starts it, subsequent calls reuse it. It auto-shuts down after 30 minutes of inactivity.
- Exits non-zero with a message on stderr for any failure (missing input, missing template or parser, splice failure). Callers MUST treat a non-zero exit as "fall back to the markdown flow", never as a reason to block review.

The rendered HTML is self-contained (vendored parser, no CDNs, system fonts). When served via the annotation server, the feedback composer writes `@TAG:` lines directly into the source markdown on each "Add" click; when opened as `file://`, annotations live in browser memory only and "Copy all feedback" is the export path.

## What the view provides

| Layer | Behavior |
|-------|----------|
| Baseline | TOC with scroll tracking, collapsible h2 sections, styled GFM tables, `@TAG:` chips highlighted in prose (never inside `pre`/`code`) |
| Schema-aware | Keyed on the H1: `Plan:` gets approach cards, edge-case treatment, changelog timeline; `Decision:` gets side-by-side option cards, a recommendation banner, status pills; `Design Questions:` gets, per `## DQ<n>:` section, side-by-side option cards with pros/cons and an inline recommendation banner (a non-conforming DQ falls back to baseline for that section only). A topbar toggle switches to generic rendering; unrecognized H1s get baseline only |
| Feedback composer | Hover a section heading → `+ annotate`, or hover a paragraph/bullet/row → gutter `+`, then pick a tag and type a note. "Copy all feedback" puts a block on the clipboard, one line per item: section-anchored (`§ Proposed Approach — @CONCERN: ...`) or block-anchored with a verbatim excerpt greppable in the source (`§ Proposed Approach ¶ "..." — @CONCERN: ...`) |

The composer emits exactly this annotation vocabulary: `@COMMENT:`, `@QUESTION:`, `@CONCERN:`, `@APPROVE:`, `@EVIDENCE:`. Reading without annotating requires nothing — the composer stays out of the way until used.

| Layer | Behavior |
|-------|----------|
| Save to markdown | When served via the annotation server (`--open`), each "Add" POSTs to the server, which writes the `@TAG: note` line directly into the source `.md` file. Section-level annotations insert after the `## heading` line; block-level annotations insert after the line containing the excerpt. The agent reads the markdown and sees annotations inline, no clipboard paste needed. On `file://` (no server), annotations are in-memory only and "Copy all feedback" remains the export path. |

## Checkpoint integration

Automatic rendering at checkpoints is opt-in via `CLAM_RENDER_DOC=enabled` (exported by the user in their shell profile; unset means disabled). Explicit `/render-doc:render <file>` invocations always work regardless of the flag. When the flag is enabled, `/decision-log:rundown` renders the decision file with `--open` after writing it at park time.

Callers skip the render silently when the flag is not `enabled` (the markdown flow is the default experience), and fall back to the plain-markdown flow with a one-line notice when an enabled render fails.

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
- `scripts/render.test.sh` renders all three fixtures (`plan`, `decision`, `design-questions`) in a temp dir and asserts: parser spliced, doc round-trips byte-for-byte through base64, no slot markers remain, script-element count unchanged (the `</script>` proof), no external resource references, and render.sh fails loudly on bad input. Run it after any template or script change.

## Annotation server

`scripts/serve.py` is a single shared HTTP server on `127.0.0.1` (never exposed to the network). State file: `/tmp/render-doc-serve.json` (`{"pid": N, "port": N}`).

- `render.sh --open` starts it if not running, reuses it if alive (health-checked via `/health`).
- Documents are registered via POST `/register` with `{html, md}` paths; each gets a deterministic ID (sha256 prefix of the HTML path).
- POST `/annotate` with `{md, section, excerpt, tag, note}` writes the annotation into the markdown. Only registered `md` paths are accepted (403 otherwise).
- Auto-shuts down after 30 minutes of no requests. Cleans up the state file on exit.

One server handles all concurrent sessions. No user action needed to start or stop it.

## Boundaries

- Write only the sibling `.html` of the input file. The annotation server writes `@TAG:` lines into the source markdown; this is the only intentional modification of source files.
- Do not add network fetches to the template or server; no CDNs, no web fonts.
- Generated HTML under `.local/` is disposable; never commit it.
