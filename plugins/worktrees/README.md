<!--
Contract: B15 worktrees-readme
Behavior:
  Update the existing worktrees README to meet all 4 issue #61 sections.
Inputs:
  The existing README content, PLUGIN_README_TEMPLATE, plugin directory scan.
Outputs:
  Two updates to the existing README:
    1. Add the install command to the existing "Prerequisite: git-helpers"
       section or create a proper "## Getting started" section that includes
       both the install command (/plugin marketplace add cjdubb/clam,
       /plugin install worktrees@clam) and the git-helpers prerequisite.
    2. Add ## Uninstalling — uninstall command
       (/plugin uninstall worktrees@clam), note that git-helpers itself
       is not affected (it's managed separately via setup.sh).
Errors: n/a (documentation).
Invariants:
  - Preserve ALL existing content including both HTML-comment contract
    blocks (B01 and B05) and all existing sections verbatim.
  - The existing "Skills" section already serves as the "Commands" section;
    do not duplicate.
  - The existing "Dependencies" section already serves as the
    "Relationships" section; do not duplicate.
  - Follow PLUGIN_README_TEMPLATE section order for new/modified sections.
Edge cases:
  - The prerequisite section is important context that must not be lost
    when adding a Getting started section.
-->
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

Claude Code skills for the git worktree workflow: recognizing a bare-clone
worktree root and driving it through the `newtree` / `rmtree` / `copyenv` /
`cloneBareRepo` shell functions, plus the worktree-per-worker pattern for
handing isolated working directories to parallel agents or subagents.
Installing this plugin changes nothing globally — it teaches Claude Code
how to use tooling that already lives in your shell; it does not install,
configure, or modify that tooling itself.

## Prerequisite: git-helpers

```
/plugin marketplace add cjdubb/clam
/plugin install worktrees@clam
```

This plugin is documentation and skills, not tooling. It has a hard
prerequisite on [cjdubb/git-helpers](https://github.com/cjdubb/git-helpers),
the repo that actually provides `newtree`, `rmtree`, `copyenv`, and
`cloneBareRepo` as sourceable shell functions. This plugin never installs
git-helpers on your behalf — that stays a deliberate, explicit step you run
yourself:

```bash
~/github/git-helpers/setup.sh
```

`setup.sh` writes a managed block into your shell config that sources
`worktree-helpers.sh`, so pulling updates to git-helpers takes effect in new
shells without re-running it. If git-helpers is not installed on a given
machine, the skills in this plugin degrade to instructions for installing
it — they explain what `setup.sh` does and point at the upstream repo,
rather than failing outright or pretending the helpers exist.

## Skills

- **usage** — how to recognize a worktree root and correctly invoke
  `newtree`, `rmtree`, `copyenv`, and `cloneBareRepo` from the Bash tool.
- **per-worker** — the worktree-per-worker pattern: giving each parallel
  worker its own isolated worktree so concurrent git writes never race.

## Dependencies

- **Requires:** [cjdubb/git-helpers](https://github.com/cjdubb/git-helpers)
  installed and sourced in the shell (see Prerequisite above); Claude Code
  itself to load the skills.
- **Provides:** the `usage` and `per-worker` skills — model-invocable
  guidance for the worktree workflow. No shell functions, scripts, or
  global configuration; installing the plugin changes nothing globally.
- **Consumes:** nothing beyond git-helpers' shell functions when a skill's
  guidance leads Claude Code to run them via the Bash tool.

## Uninstalling

```
/plugin uninstall worktrees@clam
```

git-helpers itself is not affected — it's managed separately via
`setup.sh` and is never installed or removed by this plugin.
