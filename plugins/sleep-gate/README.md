# sleep-gate

<!-- Contract: B04 plugin README (plan 001-sleep-gate) (remove at acceptance)

Behavior:
  A README conforming to plugins/PLUGIN_README_TEMPLATE.md that documents
  what the gate blocks, what it deliberately allows, and what to reach for
  instead. It states both detection rules in plain terms with a worked
  example of each, lists all four alternatives, and says explicitly that the
  hook fails open and has no configuration surface.

  Section by section:
    - Getting started: the marketplace add + install commands. No
      configuration required; the plugin is hooks-only and activates on
      install.
    - What to expect: the PreToolUse hook fires on every Bash tool call,
      top-level and subagent alike. Rule L and Rule B stated in plain terms,
      each with one worked example of a command that is denied. The 2-second
      floor is named as a number. The Rule B carve-out words (while, until,
      for, break, wait, trap) are listed, because an engineer hitting an
      unexpected denial needs to read why from here. No files are created or
      read; no settings are written.
    - Common workflows: what to do when the gate denies a command — the four
      alternatives, each with a one-line example: foreground execution
      bounded by the Bash tool's own timeout parameter; run_in_background
      with its completion notification; wait "$pid"; a condition poll.
      Also: how to get the sleep back (uninstall).
    - Commands: the one hook. sleep-gate.sh (PreToolUse, matcher Bash) —
      what it reads, what it writes, that it always exits 0, and that every
      failure path allows the call.
    - Tests: the bash invocations for this plugin's own suites.
    - Update: the marketplace update + plugin update commands, matching the
      section every other plugin README in this repo carries.
    - Relationships to other plugins: none. Fully standalone.
    - Uninstalling: the uninstall command; nothing is left behind.

Inputs:  none.
Outputs: plugins/sleep-gate/README.md.
Errors:  none at runtime.

Invariants:
  - Names NO other plugin anywhere, in any form — not a skill invocation,
    not a marketplace id, not English naming, not a filesystem path, not in
    a comment. This is a leaf plugin and the README is one of the places
    that rule is most often broken.
  - The six required H2 headings appear with exact names in exact order, and
    the extra sections (Tests, Update) appear ONLY between "## Commands" and
    "## Relationships to other plugins". Enforced by scripts/readme-lint.sh.
  - The fail-open posture is stated explicitly, not implied.

Edge cases:
  - The README quotes `sleep` examples that its own test must not match by
    accident: readme.test.sh strips fenced code blocks before asserting on
    prose, the technique scripts/readme-lint.sh already uses for HTML
    comments.
-->

## Getting started

## What to expect

## Common workflows

## Commands

## Tests

## Update

## Relationships to other plugins

## Uninstalling
