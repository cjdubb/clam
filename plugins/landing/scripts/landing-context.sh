#!/bin/bash
# SessionStart hook for the landing plugin. One job: tell the session how
# finished work lands in THIS repo, so the orchestrator follows the declared
# policy without being asked.
#
# - Repo has .claude/clam-profile.md: inject the parsed landing-* policy
#   (strategy / target / merged-by) plus the instruction to land via
#   /landing:land and to read the profile body first.
# - No profile: inject a nudge that /landing:init records the policy, and
#   to ask the user rather than assume a strategy until then.
#
# Fail-open: any error exits 0 with no output rather than breaking session
# start.

set -u

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || exit 0

PROFILE="$cwd/.claude/clam-profile.md"

# Read one flat key from the profile's YAML frontmatter (the block between
# the leading '---' line and the next '---' line; a file not starting with
# '---' has no frontmatter and yields nothing). Inline ' # …' comments and
# surrounding whitespace are stripped, non-printable bytes are dropped, and
# the value is capped at 40 characters. The body is never consulted.
profile_field() { # key
    awk -F':' -v key="$1" '
        NR == 1 { if ($0 != "---") exit; next }
        $0 == "---" { exit }
        $1 == key {
            v = substr($0, length(key) + 2)
            sub(/[[:space:]]#.*$/, "", v)
            gsub(/[^[:print:]]/, "", v)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            print substr(v, 1, 40)
            exit
        }
    ' "$PROFILE" 2>/dev/null
}

if [ -f "$PROFILE" ]; then
    strategy=$(profile_field landing-strategy)
    target=$(profile_field landing-target)
    merged_by=$(profile_field landing-merged-by)
    context=$(cat <<EOF
# Landing policy (clam landing plugin)

This repo declares how finished work lands in \`.claude/clam-profile.md\`:
strategy=${strategy:-unset}, target=${target:-unset}, merged-by=${merged_by:-unset}.
When implementation is complete and verified, land it with the /landing:land
skill, which follows the declared strategy — read the profile's body for
repo-specific workflow notes first. Do not merge into '${target:-the main branch}'
or open a PR by hand outside that flow.
EOF
)
else
    context=$(cat <<'EOF'
# Landing policy (clam landing plugin)

This repo has no `.claude/clam-profile.md`, so its landing policy (how
finished work reaches the main branch) is undeclared. Run /landing:init once
to detect, confirm, and record it. Until then, ask the user how work should
land rather than assuming a strategy.
EOF
)
fi

printf '%s' "$context" | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
