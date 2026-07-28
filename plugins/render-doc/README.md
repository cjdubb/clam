
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
  (`scripts/serve.py`) starts (or is reused if already running) and writes
  its state to `/tmp/render-doc-serve.json`. From then on, "Add" clicks in
  the browser composer write `@TAG: note` lines back into the source
  markdown — the only other file this plugin modifies, and only in response
  to an explicit annotation.
- Other plugins never see this plugin unless they choose to: automatic
  rendering at their checkpoints is gated by checking whether the
  `render-doc:render` skill is available, and skipping silently when it is
  not.

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
only). Any other H1 gets baseline rendering: TOC with scroll tracking,
collapsible h2 sections, styled GFM tables. A topbar toggle switches to
generic rendering at any time.

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

**`scripts/serve.py [<state-file>]`** — the shared local annotation server
started by `render.sh --open`. One instance serves all rendered documents on
`127.0.0.1` (never exposed to the network); the first `--open` call starts
it, later calls reuse it (health-checked via `/health`). State — `{"pid":
N, "port": N}` — is written to `/tmp/render-doc-serve.json` by default (or
the path given as the first argument) so `render.sh` can discover a running
instance. Documents register via POST `/register` with `{html, md}` paths
and get a deterministic ID (a sha256 prefix of the HTML path); annotations
arrive via POST `/annotate` with `{md, section, excerpt, tag, note}` and are
only accepted for a registered `md` path (403 otherwise). Auto-shuts down
after 30 minutes without a request and cleans up its state file on exit. No
user action is needed to start or stop it — it comes and goes with usage.

### Failure modes

| Scenario | Behavior |
|----------|----------|
| Missing input / template / parser | Exit 1, message on stderr, no output written |
| Markdown parser throws in-browser | Error card with the raw markdown shown as text |
| Schema section missing or reshaped | That transform silently falls back to baseline rendering |
| `open` fails or is absent | Render still succeeds; path printed for manual viewing |
| python3 unavailable | `--open` falls back to `file://` open; annotations are in-memory only |
| Annotation server unreachable | "Add" still works in-memory; no save confirmation shown |

### Maintenance

The parser is `marked` v18.0.6 (MIT), vendored byte-identical from the npm
tarball as `assets/marked.min.js`; the file header records provenance and
the upgrade procedure. `scripts/render.test.sh` renders all three fixtures
(`plan`, `decision`, `design-questions`) in a temp directory and asserts:
parser spliced, doc round-trips byte-for-byte through base64, no slot
markers remain, script-element count unchanged (the `</script>` proof), no
external resource references, and `render.sh` fails loudly on bad input.
Run it after any template or script change.

## Tests

```bash
bash plugins/render-doc/scripts/render.test.sh
bash plugins/render-doc/scripts/structure.test.sh
bash plugins/render-doc/scripts/registration.test.sh
bash plugins/render-doc/scripts/migration.test.sh
```

## Provenance

Ported from clam-code, adapted to run as a standalone plugin: paths resolve
relative to the plugin's own install location instead of a fixed skills
directory, and cross-skill references degrade gracefully for skills not yet
ported.

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

No other cleanup needed for a normal install. If the annotation server is
running, it shuts itself down automatically after 30 minutes of inactivity
and removes its state file (`/tmp/render-doc-serve.json`); to stop it
immediately, kill the PID recorded in that file. Rendered `.html` files
under `.local/` are disposable derived views, not tracked by the plugin —
remove them yourself if you don't want to keep them around.
