---
name: usage
description: "Use when creating or removing git worktrees, or when the user mentions newtree, rmtree, copyenv, cloneBareRepo, or worktree(s). Teaches the git-helpers worktree functions: how to find the worktree root, create and remove worktrees, provision env files, and fall back gracefully when the helpers are not sourced in this shell."
---

# Using git-helpers worktrees

This skill governs how you, operating the Bash tool, create and remove git
worktrees in a repo that uses the git-helpers bare-clone layout. Use the
`newtree`, `rmtree`, `copyenv`, and `cloneBareRepo` shell functions — never
hand-roll `git worktree` commands, and never invent paths. These functions
are usually already available as ordinary shell functions because the Bash
tool's shells initialize from the user's profile; treat them as commands you
can just call, the same as `git` or `ls`.

## The worktree root

A "worktree root" is a directory containing a bare clone at `<root>/.bare`,
created by `cloneBareRepo` (or the equivalent script). The root itself has no
working tree of its own — it only holds `.bare/` plus the sibling worktree
directories that `newtree` creates.

Do not assume `newtree` and `rmtree` only work when your cwd is exactly the
root. They work from the root itself **or from inside any of its
worktrees** — each call resolves the root by walking up to the repo's common
git dir (which is always `<root>/.bare`) and taking its parent, so it finds
the right root no matter which worktree you happen to be standing in. Only
error out if the current directory is neither the root nor inside one of its
worktrees.

## newtree

`newtree <branch-name>` creates (or reuses) a worktree for `<branch-name>`
and `cd`s you into it.

- The **branch name keeps its slashes** exactly as given (e.g.
  `feat/my-feature`), but the **worktree directory name replaces every slash
  with a dash** (`feat/my-feature` -> `feat-my-feature/`), created directly
  under the root as a sibling of the other worktrees.
- It runs `git fetch origin` first, so the repo must have an `origin` remote
  configured — there is no offline path that skips this fetch.
- If `origin/<branch-name>` already exists remotely, it is checked out with
  upstream set to that branch (`git branch --set-upstream-to`).
- If not, it tries a dash-for-slash match: a dashed local name like
  `user-feature` matches an existing slashed remote branch `user/feature`,
  and that remote branch is checked out (with upstream set) instead of
  creating a new one.
- Otherwise it creates a brand-new branch from the resolved default branch,
  resolved in this order: (1) the cached `origin/HEAD` if one is already set
  locally — no network call; (2) if unset, one `git remote set-head origin
  --auto` call to populate it, then re-read; (3) if that still fails (for
  example you are **offline** with nothing cached), it falls back to
  `origin/master` and prints a warning that the fallback was used. Do not be
  surprised by this warning — it means the real default branch could not be
  determined, not that something is broken.
- If the worktree directory **already exists** locally, `newtree` does not
  fail — it warns and simply navigates into the existing directory.
- After creating a worktree, `newtree` **automatically runs `copyenv`** if
  the repo has copyenv configured (see below). If the repo has no copyenv
  configuration at all, this step is a no-op and `newtree` behaves exactly
  like **plain** `newtree` with no env-file provisioning. If copyenv *is*
  configured but the copy fails (missing source dir, missing source file,
  bad config), `newtree` returns non-zero — but the **worktree is still
  KEPT** and your shell is left inside it, so fix the copyenv config or
  source files and re-run `copyenv` rather than recreating the worktree.

Because `newtree` changes your cwd as a side effect, compose it as a single
Bash call so you know exactly where you ended up, and capture the resulting
absolute path with `pwd` for any calls you make later in the session:

```bash
cd <root> && newtree feat/my-feature && pwd
```

Use the printed `pwd` output as the working directory for subsequent
commands in that worktree, rather than assuming a path.

## rmtree

`rmtree` removes a worktree. It identifies worktrees **by directory name,
not branch name** — the two can differ because slashes in the branch name
become dashes in the directory name, so always pass the dashed directory
name (e.g. `rmtree feat-my-feature`), never the slashed branch name.

Run it two ways:

- From the root or a sibling worktree, with the target's directory name:
  `rmtree feat-my-feature`.
- From **inside** the worktree itself, with no argument at all — bare
  `rmtree` removes the worktree you are currently standing in and leaves
  your shell at the **root** afterward, so you don't end up in a deleted
  directory.

`rmtree` refuses to remove a **dirty** worktree (uncommitted changes) unless
told otherwise. Any extra arguments are passed straight through to `git
worktree remove`, so `rmtree feat-my-feature --force` (or just `rmtree
--force` from inside the worktree) overrides the dirty-worktree refusal.

## copyenv

`copyenv` provisions a worktree's **untracked** files from a per-repo
configured source directory. A fresh worktree contains only what git tracks,
so anything gitignored — `.env` and friends, but equally local tool or editor
config like `.claude/settings.local.json` — is absent until something puts it
there. Configure it once per repo, from any of its worktrees; the config is
stored in the shared `.bare` repo config, so every worktree sees the same
setting:

```bash
copyenv --configure ~/env-files/myproject .env apps/api/.env
copyenv --configure ~/env-files/myproject   # every file under the dir
```

Each named file is a path taken as **relative to both** the source directory
and the destination worktree — `<source-dir>/<rel>` is copied to
`<worktree>/<rel>`. Re-running `--configure` replaces the previous config
outright; to amend one in place instead, use the granular forms — they
require an existing config and never create a partial one:

```bash
copyenv --add-file .claude/settings.local.json  # add to the configured list
copyenv --remove-file apps/api/.env             # drop one entry
copyenv --set-source ~/env-files/renamed        # repoint, keeping the list
```

Day to day:

```bash
copyenv                    # provision the worktree you are standing in
copyenv feat-my-feature    # provision a named sibling worktree
copyenv --list             # preview the configured mappings, copies nothing
copyenv --force            # overwrite files that already exist in the worktree
```

Files that already exist at the destination are **skipped** with a warning
unless you pass `--force` — this makes re-running `copyenv` idempotent and
keeps it from clobbering local edits. The corollary: changing what the source
directory holds does **not** reach worktrees that already have the file. Run
`copyenv --force` on each one that needs refreshing.

Only `newtree` runs `copyenv` automatically. A worktree created any other way
— a raw `git worktree add`, or a tool that makes its own — starts without
these files, and nothing warns you. When you find such a worktree, or create
one, run `copyenv <dir-name>` against it rather than assuming it was
provisioned.

Treat anything seeded this way as a **secret** unless you know it isn't: the
destination paths must be **gitignored** by the target project (or by the
user's global ignore file). `copyenv` only places the files in the worktree —
it does nothing to stop git from tracking them if the ignore rules don't
already cover that path, so verify the destination is ignored before relying
on this.

## cloneBareRepo

`cloneBareRepo <directory-path> <repo-url>` **converts** a plain repo URL
into a worktree root, one time, per repo: it clones the repo as a bare
clone at `<directory-path>/.bare`, wires up the layout, and `cd`s you into
the new root. Use it once per repo, not per worktree — `newtree` handles
every worktree after that.

The non-shell-function equivalent is the standalone script
`setup-git-repo-with-trees.sh <directory-path> <repo-url>`, which converts
the repo the same way but (being a plain script, not a sourced shell
function) cannot `cd` your shell into the result afterward.

## If the helpers are not available

Try invoking `newtree` (or `rmtree`, `copyenv`, `cloneBareRepo`) **directly**
first, with no setup step. Bash tool shells initialize from the user's
profile, so these functions are almost always already sourced and available
exactly like any other command.

Only if that call fails with something like "command not found" should you
go looking for the helpers: locate the managed block delimited by
`# BEGIN GIT-HELPERS` (and a matching `# END GIT-HELPERS`) inside the user's
`.bashrc` or `.zshrc`. That block points at the real location of
`worktree-helpers.sh` on this machine — read it to find the path, then
source that file and retry the call in the same Bash invocation, e.g.
`source <path-from-managed-block> && newtree feat/my-feature`.

Never hardcode a path to `worktree-helpers.sh` — always read it out of the
managed block on the machine you're actually running on, since it varies
per install. And never fall back to raw `git worktree` plumbing commands as
a substitute for these functions; if you truly cannot locate or source the
helpers, stop and surface that to the user instead of improvising with bare
git.

For patterns around running many worktrees as parallel workers (dispatch,
naming conventions across a fleet, cleanup ordering), see the sibling
per-worker skill — this skill only covers the four functions themselves and
stays unopinionated about orchestration.
