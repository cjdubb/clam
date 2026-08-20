#!/bin/bash
# SessionStart hook for the build plugin: inject the ROUTING POINTER only.
#
# Why this hook exists (F06, round-3 eval): with entry left wholly to model
# skill-triggering discretion, a fresh session given the most natural build
# prompt there is — "Build the feature described in FEATURE.md" — invoked no
# skill at all and implemented directly, bypassing the delivery lifecycle.
# Prose triggers demonstrably do not fire; the entry point needs an anchor
# injected at session start.
#
# Deliberately minimal, and NOT a return of the removed build-context.sh
# framing hook (B09): this emits a few fixed lines telling the session that
# build:build is the front door for new feature/build asks, and nothing
# else. All framing stays in the on-demand /build:context skill; all
# routing logic stays in /build:build. No files are read beyond stdin, no
# state is written, no companions are named.
#
# Fail-open: any error exits 0. Consumes stdin (hook JSON) so the harness
# never blocks on an unread pipe. Kill-switch: CLAM_BUILD_ROUTING=disabled
# silences it.

set -u

cat >/dev/null 2>&1 || true

[ "${CLAM_BUILD_ROUTING:-enabled}" = "disabled" ] && exit 0

cat <<'EOF'
# Delivery routing (build plugin)

This repo has the build plugin installed. When the engineer asks to build,
implement, add, or create a feature — including a bare prompt like "Build
X" — invoke the `build:build` skill FIRST and let it route the session
(resume in-flight work, or start new work through the installed delivery
workflow). Do not begin implementing directly from such a prompt; direct
implementation bypasses planning, tracking, and landing.

For a conceptual overview of the delivery framework itself, `/build:context`
is available on demand.
EOF

exit 0
