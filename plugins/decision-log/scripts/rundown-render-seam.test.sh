#!/usr/bin/env bash
# Test for Block B04 decision-log re-point. Source of truth: the HTML-
# comment docblock titled "Contract: B04 decision-log re-point" in
# plugins/decision-log/skills/rundown/SKILL.md (just above the rendered-doc
# gate paragraph).
#
# Behavior under contract: the rendered-doc gate in
# plugins/decision-log/skills/rundown/SKILL.md must stop invoking a
# clam-code-era script path (`~/.claude/skills/render-doc/scripts/render.sh`)
# and instead consume the render-doc plugin BY SKILL NAME
# (`render-doc:render`) — no filesystem path into another plugin anywhere in
# decision-log. Gate semantics (skill-availability check, skip-silently
# wording for the absent case, the "HTML render failed — presenting as
# markdown" failure line, and the NEVER-block rule) are retained verbatim
# in spirit. The
# plugins/decision-log/README.md soft-dependency entry for render-doc is
# updated to match: names the plugin/skill, keeps the graceful-degradation
# wording, and drops the clam-code location.
#
# Every content check below runs against a comment-stripped copy of the
# target file (sed '/<!--/,/-->/d'), so the docblock's own prose (which
# necessarily quotes strings like `render-doc:render`) can never satisfy a
# check meant for real content. This is why these checks are expected to
# FAIL against the current NotImplemented: B04 state (the old path-based
# gate paragraph is still in place) and PASS once the seam is re-pointed.
#
# Run: bash plugins/decision-log/scripts/rundown-render-seam.test.sh (exits
# non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SKILL="$PLUGIN_ROOT/skills/rundown/SKILL.md"
README="$PLUGIN_ROOT/README.md"

FAILED=0

check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

check "skills/rundown/SKILL.md exists" "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"
check "README.md exists" "$([ -f "$README" ] && echo yes || echo no)" "yes"

# Comment-stripped copies: docblock prose can never satisfy a content check.
SKILL_BODY="$(sed '/<!--/,/-->/d' "$SKILL" 2>/dev/null)"
README_BODY="$(sed '/<!--/,/-->/d' "$README" 2>/dev/null)"

# ===========================================================================
# PART 1: skills/rundown/SKILL.md (stripped)
# ===========================================================================

# --- New seam is named by skill, not by path --------------------------------

check "SKILL.md references the skill name render-doc:render" \
  "$(grep -qF 'render-doc:render' <<<"$SKILL_BODY" && echo yes || echo no)" "yes"

check "SKILL.md contains NO clam-code-era path ~/.claude/skills/render-doc" \
  "$(grep -qF '~/.claude/skills/render-doc' <<<"$SKILL_BODY" && echo yes || echo no)" "no"

check "SKILL.md contains NO filesystem path plugins/render-doc/ into the render-doc plugin" \
  "$(grep -qF 'plugins/render-doc/' <<<"$SKILL_BODY" && echo yes || echo no)" "no"

check "SKILL.md contains NO filesystem path render-doc/scripts into the render-doc plugin" \
  "$(grep -qF 'render-doc/scripts' <<<"$SKILL_BODY" && echo yes || echo no)" "no"

# --- Gate semantics retained verbatim in spirit -----------------------------

check "SKILL.md gates on skill availability (render-doc plugin not installed)" \
  "$(grep -qF 'render-doc plugin is not installed' <<<"$SKILL_BODY" && echo yes || echo no)" "yes"

check "SKILL.md retains skip-silently wording for the absent case" \
  "$(grep -qF 'skip the render silently' <<<"$SKILL_BODY" && echo yes || echo no)" "yes"

check "SKILL.md retains the failure line 'HTML render failed — presenting as markdown'" \
  "$(grep -qF 'HTML render failed — presenting as markdown' <<<"$SKILL_BODY" && echo yes || echo no)" "yes"

check "SKILL.md retains the NEVER-block rule (a render failure must NEVER block the decision)" \
  "$(grep -qF 'must NEVER block the decision' <<<"$SKILL_BODY" && echo yes || echo no)" "yes"

# ===========================================================================
# PART 2: README.md (stripped)
# ===========================================================================

check "README.md render-doc entry names the skill render-doc:render, or names the render-doc plugin alongside its skill" \
  "$( (grep -qF 'render-doc:render' <<<"$README_BODY" || (grep -qF 'render-doc' <<<"$README_BODY" && grep -qiE 'render-doc.*\bskill\b|\bskill\b.*render-doc' <<<"$README_BODY")) && echo yes || echo no)" "yes"

check "README.md render-doc entry keeps graceful-degradation wording" \
  "$(grep -qiE 'skip|graceful|degrad' <<<"$README_BODY" && echo yes || echo no)" "yes"

check "README.md no longer contains the clam-code-era path ~/.claude/skills/render-doc/" \
  "$(grep -qF '~/.claude/skills/render-doc/' <<<"$README_BODY" && echo yes || echo no)" "no"

check "README.md no longer contains 'still clam-code' location wording" \
  "$(grep -qF 'still clam-code' <<<"$README_BODY" && echo yes || echo no)" "no"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
