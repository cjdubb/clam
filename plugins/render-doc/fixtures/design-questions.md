# Design Questions: Configurable default effort via setup.sh

Issue: clam-code#260
Date: 2026-07-14
Status: Awaiting answers (planning Phase 2 Part 2)

Constraints confirmed in Part 1: `clam` sessions only; interactive prompt only (no flags); unset → `max` (backwards compatible). @QUESTION: does this prose tag render as a chip?

## DQ1: Where does the default get resolved?

**Context:** `_clam_launch <model> <effort>` takes effort as positional arg 2 (`general/claude-alias.sh:24-26`); all three aliases hardcode `max` (`clam` :51, `clam47` :53, `clam46` :55).

**Tension:** a single point of truth competes with an explicit, self-documenting function contract.

### Option 1: Per-alias resolution

Each alias becomes `_clam_launch claude-opus-4-8 "${CLAM_DEFAULT_EFFORT:-max}" "$@"`, so the launcher signature stays explicit.

**Pros:** `_clam_launch`'s signature stays self-documenting; a future alias can still pass a literal effort.
**Cons:** the `:-max` fallback is repeated in all three aliases, so a policy change touches three lines.

### Option 2: Resolve inside `_clam_launch`

Drop the effort parameter and have the function read `"${CLAM_DEFAULT_EFFORT:-max}"` itself.

**Pros:** one point of truth for the default; aliases shrink to a model name.
**Cons:** the function's contract becomes implicit; a per-alias override needs a new mechanism.

**Tradeoff assessment:** the core tradeoff is contract explicitness vs. duplication. Is keeping `_clam_launch`'s signature self-documenting worth the fallback appearing three times, and should the legacy `clam47`/`clam46` aliases honour the configured default too?

**Recommendation:** Option 1 (per-alias resolution), because the three-line duplication is trivial next to the cost of an implicit launcher contract, and it keeps a future literal-effort alias possible. You still decide whether the legacy aliases opt in.

## DQ2: Env var name — `CLAM_DEFAULT_EFFORT` or reuse `CLAUDE_EFFORT`?

**Context:** existing setup toggles all use the `CLAM_` prefix (`CLAM_PRE_PR_VERIFY_MODE`, `CLAM_PR_CRONS`, exported at `setup.sh:568-576`). Separately the statusline already reads `CLAUDE_EFFORT` as a display fallback when session JSON lacks `.effort.level` (`general/statusline/context.sh:42-47`).

**Tension:** reusing `CLAUDE_EFFORT` gets statusline fallback display "for free", but a globally-exported value would also bleed into plain `claude` sessions, where the statusline could then show the shell value instead of the session's real effort.

### Option 1: New `CLAM_DEFAULT_EFFORT`

A `CLAM_`-prefixed variable read only by the aliases.

**Pros:** follows the established `CLAM_` convention; leaves the statusline untouched; no cross-session bleed.
**Cons:** the statusline gains no free display fallback; one more variable name to document.

### Option 2: Reuse `CLAUDE_EFFORT`

Export the variable the statusline already reads.

**Pros:** statusline display works with no extra code.
**Cons:** the exported value leaks into non-`clam` sessions and can misreport their effort.

**Tradeoff assessment:** the key question is whether display convenience is worth cross-session display inaccuracy. Is there any scenario where the shell-config value should be shown in non-`clam` sessions, or should the two mechanisms stay decoupled?

**Recommendation:** Option 1 (new `CLAM_DEFAULT_EFFORT`), because correctness of the statusline in plain `claude` sessions outweighs saving a few lines, and convention consistency lowers the documentation burden.

## DQ3: Validation strictness at prompt and launch

**Context:** the effort value is interpolated into the managed shell block as an `export` line (`setup.sh:568-576`) and into `claude --effort <value>` at every launch (`claude-alias.sh:35,46`). The only free-text prompt today, the ntfy topic, validates with a regex before accepting (`setup.sh:337`). Effort is a 5-value enum: `low|medium|high|xhigh|max`.

**Tension:** a typo'd value breaks every `clam` launch until setup is re-run; but a hard allowlist means a future CLI level needs a clam-code update before users can select it. (The version lock keeps the enum known for the locked range, softening the future-proofing concern.)

### Option 1: Hard allowlist at prompt, no runtime guard

Re-prompt until valid; let `claude` fail loudly if someone hand-edits the shell config later.

**Pros:** simplest; the invalid value can never be persisted through the prompt.
**Cons:** a later hand-edit to the shell config is unguarded and fails at launch.

### Option 2: Hard allowlist at prompt + runtime fallback

The alias falls back to `max` with a stderr warning when the env var is invalid.

**Pros:** protects hand-editors; a bad value self-heals at launch instead of breaking it.
**Cons:** adds branching logic to the alias file that must itself be maintained.

**Tradeoff assessment:** the consequential tradeoff is failure locality — should an invalid value be impossible to persist (Option 1) or self-healing at launch (Option 2)? How much should setup.sh trust future hand-edits of the shell config?

**Recommendation:** Option 2 (allowlist + runtime fallback), because a broken launcher is high-friction to diagnose and the fallback is a few lines; the stderr warning keeps the misconfiguration visible. You may prefer Option 1 if you'd rather keep the alias file logic-free.

## DQ4: How should the setup prompt sequence this question? (non-conforming on purpose)

**Context:** this section deliberately omits `### Option` headings and a Recommendation so the renderer must fall back to generic rendering for this DQ while DQ1–DQ3 still render as cards. It exercises the per-section try/catch path (`applySchema` in `template.html`).

**Tension:** the options below are written as prose bullets rather than the option-card markup:

- Ask for effort right after the model prompt, keeping related questions together.
- Ask at the end of setup, after the higher-stakes permission prompts.

There is no pros/cons markup and no recommendation here, so this whole section should render generically — heading, prose, and bullets — with no option cards and no banner.

The adversarial fence below must render verbatim and must not break the page or highlight its tags:

```html
</script><script>console.log("if you can read this outside a code block, escaping failed")</script>
<!-- @CONCERN: this tag is inside a fence and must NOT become a chip -->
```

## Dimension Assessment

| Dimension | Relevant? | Coverage |
|-----------|-----------|----------|
| Security | Yes | DQ3 — value is interpolated into shell config; validation prevents injection (precedent: ntfy regex, setup.sh:337) |
| Performance | N/A | one string expansion at alias invocation |
| Testing | Yes | no harness for setup.sh/claude-alias.sh; plan will specify manual verification + shellcheck |
| Deployment | Yes | pull + re-run setup.sh; symlinked alias goes live on merge-down; unset var → `max` |
| Observability | N/A | statusline already shows live effort (context.sh:42-47) |
| Backwards compatibility | Yes | unset → `max`; both DQ1 options preserve the fallback |
| Error handling | Yes | DQ3 (invalid value at prompt and at launch) |
| Concurrency | N/A | no shared state |
