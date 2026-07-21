---
name: create
description: "Spin up a fresh orchestrator for a sub-effort. Writes a handover document, creates the recipient orchestration worktree via newtree, and populates its .local/ so the user just runs clam and picks Build. Use when an orchestrator session has identified a discrete sub-effort that warrants its own coordination context, or when the user explicitly asks for a handover. The orchestrator scaffolds the worktree but never starts the new session; the user does."
---

<!--
Contract: B01 handover-plugin — skill
Behavior:   provides /orchestrator-handover:create, a four-step procedural skill
            that an orchestrator invokes to spin off a sub-effort into its own
            orchestration context:
            (1) write a handover document to the current worktree's .local/
                using the companion template (template.md);
            (2) create a recipient orchestrator worktree via newtree and
                populate its .local/ (handover doc copy, MODE file set to
                "Build", empty .orchestrator marker);
            (3) write a placeholder TODO.md in the recipient's .local/ using
                the tracking plugin's template format;
            (4) report the created path and hand off to the user.
Inputs:     invoked by an active orchestrator session. Requires: an issue key
            or descriptive slug for the sub-effort, and enough session context
            to populate the handover template sections (what is done, what is
            open, decisions pending, proposed work breakdown).
Outputs:    (a) .local/handover-{ISSUE-KEY}.md in the current worktree
            (provenance copy); (b) a recipient worktree at
            orchestrate-{ISSUE-KEY}-{short-description} with .local/ populated:
            handover doc, MODE=Build, empty .orchestrator, TODO.md, and any
            local artifacts referenced in the handover's source-of-truth
            section.
Errors:     worktree creation failure (newtree fails or .git absent after
            creation) → abort immediately, surface to user, never leave a
            half-populated directory behind.
Invariants: - never starts a session in the recipient worktree (human-start
              gate: only the user runs clam + Build)
            - never writes content into .orchestrator (empty marker only;
              the recipient fills it at Gate 1)
            - never pre-populates PLAN.md or IMPLEMENTATION-PLAN.md in the
              recipient worktree
            - never delegates any scaffolding step to a subagent
            - issue-tracker-agnostic: works with GitHub Issues, Linear,
              Jira, or no tracker at all
            - always uses newtree (no newcliptree)
            - worktree creation runs in a subshell so the current session's
              cwd never drifts
            - all bash commands for step 2 run in a single shell invocation
              (Bash tool does not persist variables between calls)
Edge cases: - no issue tracker in use → slug-based naming
              (orchestrate/{short-description})
            - tracking plugin not installed → skill inlines the essential
              TODO.md fields rather than referencing the template
            - team-review plugin absent → orchestrator-guard.sh not
              available; Write to sibling worktree may prompt for
              confirmation
            - session-modes plugin absent → /start detection of handover
              docs not available; recipient's first move section documents
              manual pickup
            - recipient worktree directory already exists → newtree warns
              and navigates (not a failure)
            - cross-repo sub-effort → skill notes this is possible but the
              default assumes same repo
-->

<!-- NotImplemented: B01 — skill body to be written during implementation.
     The four-step procedure (write handover, create worktree, write TODO,
     hand off) will be written here following the contract above. -->

# Orchestrator Handover

Not yet implemented.
