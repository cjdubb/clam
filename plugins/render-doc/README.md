<!--
Contract: B01 render-doc plugin core
Behavior:
- `scripts/render.sh <doc.md> [--open]` converts a markdown document into ONE
  self-contained HTML file written as a sibling of the input
  (`.local/PLAN.md` -> `.local/PLAN.html`), exit 0 on success.
- The HTML is produced by splicing three slot lines in `assets/template.html`:
  `__MARKED_SPLICE__` -> contents of `assets/marked.min.js` (vendored parser);
  `__DOC_B64_SPLICE__` -> the document base64-encoded into a data block;
  `__SOURCE_PATH_SPLICE__` -> absolute path of the source `.md`, placed in a
  `<script type="text/plain">` block (inert text). The page decodes and
  parses client-side, entirely offline.
- Output self-check: any leftover slot marker fails the render before
  anything is written.
- `--open`: when python3 is available, ensure the shared annotation server
  (`scripts/serve.py`) is running (first call starts it, subsequent calls
  reuse it; it auto-shuts down after 30 minutes of inactivity) and open
  `http://127.0.0.1:<port>/d/<id>`. Without python3, fall back to a plain
  `file://` open.
- Annotation write-back: when served, each composer "Add" POSTs to the
  server, which writes the `@TAG: note` line into the source markdown
  (section-level annotations insert after the `## heading` line; block-level
  after the line containing the verbatim excerpt). On `file://`, annotations
  are in-memory only and "Copy all feedback" is the export path.
Inputs: path (relative or absolute) to a readable markdown file; optional
  `--open` flag.
Outputs: the sibling `.html`, self-contained — vendored `marked v18.0.6`
  present; no external URLs/CDNs; system fonts; document content confined to
  the base64 data block (the rendered file closes exactly as many `</script>`
  elements as the template, so document content can never terminate a
  script).
Errors: missing input, missing template or parser, splice failure -> exit
  non-zero with a message on stderr and NO output written. Callers MUST
  treat a non-zero exit as "fall back to the markdown flow", never as a
  reason to block review.
Invariants:
- The plugin is fully self-contained and works with ONLY this plugin
  installed: no reference anywhere in the plugin to `~/.claude/skills/`,
  clam-code paths, or another plugin's files; scripts resolve their own
  location (SCRIPT_DIR pattern) so any install path works; SKILL.md refers
  to scripts via `${CLAUDE_PLUGIN_ROOT}/scripts/render.sh`.
- No dependency on decision-log in any direction from this plugin's side
  (decision-log consumes this plugin by skill name, one-directionally).
- `CLAM_RENDER_DOC` gates only automatic checkpoint rendering by CALLERS;
  explicit `/render-doc:render` invocation always works regardless of the
  flag. Nothing in this repo writes the flag; this README documents
  exporting it.
- `assets/template.html`, `assets/marked.min.js`, and `fixtures/*.md` are
  byte-identical copies of the clam-code source (orchestrator verifies with
  `cmp` at acceptance; provenance invariant, not a committed-test clause).
Edge cases:
- A document containing `</script>` (or any markup) must not escape the data
  block.
- Schema-aware layouts key on the H1: `Plan:`, `Decision:`, and
  `Design Questions:` get their special layouts; any other H1 gets baseline
  rendering; a non-conforming `## DQ<n>:` section falls back to baseline for
  that section only.
- `scripts/render.test.sh` renders fixtures in a temp directory so the repo
  tree stays clean; macOS/GNU `base64` decode-flag divergence (`-d`/`-D`) is
  handled.
Docs contract (skills/render/SKILL.md): frontmatter `name: render`
  (invocation `/render-doc:render <file>`) with a description that triggers
  at feedback checkpoints and on requests for an HTML view of a document;
  usage command `bash ${CLAUDE_PLUGIN_ROOT}/scripts/render.sh <doc.md>
  [--open]`; documents the annotation vocabulary verbatim (`@COMMENT:`,
  `@QUESTION:`, `@CONCERN:`, `@APPROVE:`, `@EVIDENCE:`); documents checkpoint
  integration (callers check `CLAM_RENDER_DOC`, unset = disabled; known
  caller `/decision-log:rundown`; references to not-yet-ported skills phrased
  to degrade gracefully); contains no clam-code-era paths.
Docs contract (this README's visible body): what the plugin does, usage,
  exporting `CLAM_RENDER_DOC` (no setup script writes it anymore), python3
  soft requirement and the `file://` degradation, ported-from-clam-code
  attribution.
Reference material (read-only source of the port):
  /home/cwilliamson/github/clam-code/general/skills/render-doc/
  (SKILL.md, scripts/render.sh, scripts/serve.py, scripts/smoke.sh — adapt
  into scripts/render.test.sh — assets/, fixtures/).
-->

<!--
Contract: B05 issue-8 composition
Behavior: repo-level integrity of the render-doc port once B01-B04 are
implemented, verified by plugins/render-doc/scripts/structure.test.sh.
Clauses (each independently checked, non-zero exit listing failures):
- Every `${CLAUDE_PLUGIN_ROOT}/...` path named in
  plugins/render-doc/skills/render/SKILL.md resolves to a real file inside
  this plugin.
- No tracked file in the repo references the clam-code-era skill path
  (`~/.claude/skills/render-doc`) except MIGRATION.md (history) and test
  files' own exclusion logic.
- Version agreement: plugins/render-doc/.claude-plugin/plugin.json version ==
  the render-doc entry in .claude-plugin/marketplace.json == the root README
  render-doc row (v0.1.0).
- plugins/decision-log/skills/rundown/SKILL.md references the skill name
  `render-doc:render` (the consumer seam holds).
- End-to-end: rendering one fixture through scripts/render.sh in a temp
  directory succeeds and passes self-containment checks (vendored parser
  present, no leftover slot markers, template/output `</script>` counts
  equal).
Invariants: test-only block — no non-test file changes belong to B05.
Edge cases: run before implementation it fails for the right reason
(NotImplemented markers present / marketplace entry missing).
-->

# render-doc

NotImplemented: B01 render-doc plugin core.

This README body, the skill, scripts, assets, and fixtures are stubs; the
authoritative behavioral contracts are the docblocks above. Implementation
ports /home/cwilliamson/github/clam-code/general/skills/render-doc/ per plan
`.local/plans/001-render-doc-port.md`.
