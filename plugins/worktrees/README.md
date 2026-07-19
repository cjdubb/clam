<!--
Contract: B01 plugin-manifest
Behavior:   plugins/worktrees/ presents a valid, installable Claude Code plugin:
            .claude-plugin/plugin.json manifest plus this README documenting it.
Inputs:     none (static artifacts read by Claude Code's plugin loader and by
            humans browsing the marketplace).
Outputs:    plugin.json with name "worktrees", version "0.1.0", author matching
            the marketplace owner, and a real one-line description (no TODO
            markers). README with sections: what the plugin is; the hard
            prerequisite on git-helpers (github.com/cjdubb/git-helpers) with
            install pointer (setup.sh managed shell block) — documented, never
            installed by this plugin; a skill inventory covering `usage` and
            `per-worker` with one line each; a Dependencies section in the
            requires/provides/consumes style of the git-helpers README.
Errors:     n/a (invalid JSON or missing files = failed structural tests).
Invariants: installing the plugin changes nothing globally (repo design
            constraint, stated in README); version string here is the single
            source the marketplace entry must match; no machine-specific
            absolute paths anywhere.
Edge cases: git-helpers absent on the machine — README must say the plugin's
            skills degrade to instructions for installing it, not hard failure.
-->
<!--
Contract: B05 worktrees-plugin (composition)
Behavior:   the assembled plugin loads cleanly in Claude Code: every directory
            under skills/ contains a SKILL.md whose frontmatter parses, has a
            unique `name`, and a non-placeholder `description`; plugin.json
            version and the marketplace.json worktrees entry version agree;
            the repo test suite (find plugins -name '*.test.sh' … ) is green.
Inputs:     the artifacts of B01–B04.
Outputs:    /reload-plugins loads the plugin; /worktrees:usage and
            /worktrees:per-worker resolve (engineer live-checks at acceptance —
            not machine-verifiable from bash).
Errors:     duplicate or invalid skill names, version drift between manifest
            and marketplace, TODO markers surviving to acceptance.
Invariants: skill names never repeat the plugin name (repo convention);
            marketplace lists the plugin only once it works.
Edge cases: a skills/<dir>/ without SKILL.md is a defect, not ignorable.
-->

# worktrees

TODO(B01): NotImplemented — plugin purpose paragraph.

## Prerequisite: git-helpers

TODO(B01): NotImplemented.

## Skills

TODO(B01): NotImplemented.

## Dependencies

TODO(B01): NotImplemented.
