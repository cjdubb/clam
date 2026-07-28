
# worktrees

Claude Code skills for the git worktree workflow: recognizing a bare-clone
worktree root and driving it through the `newtree` / `rmtree` / `copyenv` /
`cloneBareRepo` shell functions, plus the worktree-per-worker pattern for
handing isolated working directories to parallel agents or subagents.
Installing this plugin changes nothing globally — it teaches Claude Code
how to use tooling that already lives in your shell; it does not install,
configure, or modify that tooling itself.

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install worktrees@clam
```

### Prerequisite: git-helpers

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

## What to expect

Installing this plugin changes nothing globally: it does not install,
configure, or modify git-helpers or any other tooling, and it writes no
settings, hooks, or files of its own anywhere. There are no hooks here, so
nothing fires automatically in the background. The plugin is inert until
you — or the model — invoke one of its skills, `usage` or `per-worker`,
either directly or because Claude Code judges the current task matches one
of their trigger descriptions (creating/removing a worktree, or dispatching
parallel writers). Once a skill is active, it only guides you through
calling the `newtree`, `rmtree`, `copyenv`, and `cloneBareRepo` shell
functions already provided by git-helpers (see Getting started); this
plugin itself never runs raw `git worktree` commands on your behalf.

## Common workflows

### Create a worktree for a branch

From the worktree root (or from inside any of its existing worktrees):

```bash
cd <root> && newtree feat/my-feature && pwd
```

`newtree` keeps the branch name's slashes (`feat/my-feature`) but creates
the worktree directory with dashes instead (`feat-my-feature/`). If
`origin/feat/my-feature` already exists remotely it's checked out with
upstream set; otherwise a new branch is created off the resolved default
branch. Because `newtree` changes your cwd, always capture the printed
`pwd` output and use it as the working directory for later commands rather
than assuming a path. See the `usage` skill (Commands) for the full
branch-resolution and existing-directory rules.

### Remove a worktree when you're done with it

From the root, using the worktree's dashed directory name:

```bash
rmtree feat-my-feature
```

Or, from inside the worktree itself, with no argument at all — `rmtree`
removes the worktree you're standing in and leaves your shell at the root
afterward. `rmtree` refuses to remove a worktree with uncommitted changes;
pass `--force` only when you mean to discard that work.

### Give each parallel worker its own worktree

Before dispatching more than one worker — subagent, session, or human —
that will commit, branch, or open a pull request, create a worktree per
writer: run `newtree <branch>` for each one, record the absolute path from
`pwd`, and hand that path and branch name to the worker with instructions
to work only under it. Once a worker's branch is merged or abandoned,
`rmtree` its directory. See the `per-worker` skill (Commands) for the full
lifecycle and hand-off examples — it applies the same whether the worker is
a dispatched subagent or a human you're handing a branch to.

### Provision env files into a new worktree

Configure the mapping once per repo, from any of its worktrees:

```bash
copyenv --configure ~/env-files/myproject .env apps/api/.env
```

From then on, every `newtree` automatically runs `copyenv` for you; files
that already exist at the destination are skipped unless you pass
`--force`. Run `copyenv --list` to preview the configured mappings without
copying anything, or `copyenv <dir-name>` to provision a specific sibling
worktree by hand. Env files are secrets — make sure the destination paths
are gitignored in the target project.

## Commands

- **`usage`** — teaches how to recognize a worktree root (a directory with
  a bare clone at `.bare/`) and correctly invoke `newtree`, `rmtree`,
  `copyenv`, and `cloneBareRepo` from the Bash tool: branch/directory
  slash-to-dash mapping, default-branch resolution, dirty-worktree
  refusal, env-file provisioning, and the fallback procedure for when the
  helpers aren't yet sourced in the current shell. Model-invocable — Claude
  Code triggers it automatically when creating or removing worktrees, or
  when `newtree`/`rmtree`/`copyenv`/`cloneBareRepo`/"worktree(s)" comes up
  — and can also be invoked directly as `/worktrees:usage`.
- **`per-worker`** — documents the worktree-per-worker pattern: giving each
  parallel writing worker its own isolated worktree so concurrent git
  writes never race. Model-invocable — triggers when dispatching parallel
  workers that will commit, branch, or open pull requests, or when handing
  a branch off to another session or human — and can also be invoked
  directly as `/worktrees:per-worker`.

## Relationships to other plugins

- **Requires:** [cjdubb/git-helpers](https://github.com/cjdubb/git-helpers)
  installed and sourced in the shell (see Prerequisite in Getting started);
  Claude Code itself, to load the skills.
- **Provides:** the `usage` and `per-worker` skills — model-invocable
  guidance for the worktree workflow. No shell functions, scripts, or
  global configuration; installing the plugin changes nothing globally.
- **Consumes:** nothing beyond git-helpers' shell functions, when a
  skill's guidance leads Claude Code to run them via the Bash tool.

## Uninstalling

```
/plugin uninstall worktrees@clam
```

No further cleanup is needed: this plugin never wrote any files, settings,
or shell configuration of its own. Only git-helpers' `setup.sh` — run by
you, not this plugin — manages the `# BEGIN GIT-HELPERS` block in your
shell config, and uninstalling this plugin does not touch it.
