---
profile-version: 1
landing-strategy: github-pr
landing-target: master
landing-merged-by: user
landing-verify: for t in plugins/*/scripts/*.test.sh plugins/*/lib/*.test.sh; do [ -f "$t" ] || continue; bash "$t" || exit 1; done; jq -e . .claude-plugin/marketplace.json >/dev/null
---

# Workflow notes

- Landing flow: the orchestrator pushes the branch and opens a GitHub PR;
  the engineer reviews and merges. The orchestrator never merges to master.
- Worktree layout: worktrees live at `~/github/clam/<branch>` off a bare
  repo; master's checkout is `~/github/clam/master`.
- A plugin is added to `.claude-plugin/marketplace.json` only once it is
  ported and working — the marketplace never lists empty shells (see the
  root README "Repo conventions").
- PR bodies: say what changed per plugin and how it was verified (which
  test suites ran, what was rehearsed).
