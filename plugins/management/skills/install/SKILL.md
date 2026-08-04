---
name: install
description: "Install clam plugins in bulk: refresh the marketplace catalog, page everything not yet installed into themed multi-select picks, install the chosen set at one confirmed scope, then surface which setup skills to run and how to reload. Explicit user action: never runs implicitly."
disable-model-invocation: true
---

# Clam Installs

This is the guided, engineer-confirmed flow for installing clam plugins in
bulk. It never runs on its own — only an explicit `/management:install`
starts it.

Everything on offer comes from the marketplace catalog, read at runtime.
This skill carries no list of its own: whatever the catalog holds today is
the menu, so a plugin published tomorrow appears here without this file
changing, and one that is withdrawn stops being offered on its own.

## `/management:install`

1. **Preflight.** Confirm the `claude` CLI is on PATH, and that the clam
   marketplace clone exists at
   `${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/marketplaces/clam/`. If the
   clone is missing, say so, instruct `/plugin marketplace add
   cjdubb/clam`, and stop — without the catalog there is nothing to offer.
   Otherwise run `claude plugin marketplace update clam` to refresh it.
   That refresh is read-only against the clone: it does not touch a single
   installed plugin.
2. **Read the catalog and what's already installed.** Take the catalog
   from the clone's `.claude-plugin/marketplace.json` — each entry's
   `name`, `description`, and `category` — and what is already installed
   from `~/.claude/plugins/installed_plugins.json`, whose `plugins` object
   is keyed `<name>@<marketplace>` (only the `@clam` keys are this flow's
   business; keys from other marketplaces are unrelated software that
   happens to share the file). Drop every already-installed entry: the
   menu is only what the user could still add. If nothing is left, say
   every catalogued plugin is already installed and stop.
3. **Build themed pages.** Group the remaining entries by their `category`
   value, one page per category, treating the value as an opaque label
   rather than a known set. Then re-chunk at runtime so that every page
   carries 2-4 options: split a category holding more than four into
   consecutive pages, and merge the remainder of every category holding
   fewer than two into a single final mixed page. An entry with no
   `category` at all — an older clone predating the field — is grouped by
   what its description says it does, onto the themed page it reads
   closest to.
4. **Present each page as a multi-select pick.** Ask with AskUserQuestion
   and `multiSelect` true, at most 4 questions per call and 2-4 options per
   question — a catalog wider than that takes several sequential calls,
   until every page has been offered. Each option's label is the plugin
   name and its description is the catalog description. Nothing is
   pre-selected, and no answer on a page means nothing from that page.
   **If the picker is unavailable or the call is denied, present the same
   pages as numbered plain-text lists** — one block per page, one number
   per plugin — and ask the user to reply with the numbers they want. Say
   nothing about why the picker was unavailable and attribute it to
   nothing: the plain-text path is a complete way to run this flow, not a
   degraded one.
5. **Ask for the scope once.** One question covering the whole run, never
   one per plugin:
   - `local` — this repo only, private to this machine. Recommended: it
     suits a per-repo working style and is the easiest to undo.
   - `user` — every project for this user.
   - `project` — this repo, written to the shareable
     `.claude/settings.json` that gets committed and applies to everyone
     working in the repo.
   There is no silent default. Ask, then pass the answer through to every
   install command exactly as chosen — the CLI's own default is `user`, so
   an omitted flag silently means something other than the recommendation.
6. **Install the selection.** For each selected plugin run `claude plugin
   install <name>@clam --scope <scope>` with the scope from step 5, and
   report each result as it completes. A failure on one plugin does not
   abort the batch — keep going through the rest of the selection and
   collect every failure to report together at the end. If the user
   selected nothing at all, confirm the no-op and exit without running a
   single install.
7. **Offer setup skills — never run them.** For each plugin that installed
   successfully, read its skills from the clone
   (`plugins/<name>/skills/*/SKILL.md`) and offer any whose own frontmatter
   describes it as one-time setup or initialization — a skill that
   self-describes as configuring the plugin, rather than as the everyday
   work the plugin exists to do. Offer the matching `/<plugin>:<skill>`
   command and stop there. Never run one: a setup skill writes the user's
   settings, and whether and where that happens is the engineer's call,
   not this flow's.
8. **Close with reload guidance.** Tell the user to run `/reload-plugins`
   to pick the new plugins up in the current session — unless something
   just installed ships hooks or agents (a `hooks/` or `agents/` directory,
   or a `hooks` key in its `plugin.json`), in which case the session has to
   be restarted before those arm, because hook registration is fixed when
   the session starts. State explicitly which of the two applies, based on
   what was actually installed.

## Errors

- **`claude` CLI not found on PATH.** Report that the `claude` CLI is not
  available and fall back to walking the user through the interactive
  `/plugin` flow instead — `/plugin marketplace update clam` for the
  refresh, and the `/plugin` menu's install action in place of the CLI
  commands above. Never silently stop without saying so.
- **No marketplace clone** (step 1): say the clam marketplace has not been
  added, instruct `/plugin marketplace add cjdubb/clam`, and stop — every
  step from 2 on has no catalog to read.
- **`installed_plugins.json` missing or malformed.** Missing is normal and
  means nothing is installed yet: offer the whole catalog. Malformed is
  not — surface what failed to parse and stop, rather than guessing at
  what is installed and reinstalling over it.
- **A `claude plugin install` command fails for one plugin.** Record the
  failure, keep going with the rest of the selection, and report the full
  failure list at the end, per step 6.

## Notes

- Nothing is installed before the picks in step 4 and the scope answer in
  step 5; every step ahead of them only reads.
- Already-installed plugins are dropped in step 2 rather than shown as
  unavailable options: this flow only adds, and never updates or reinstalls
  something already present.
- One scope covers the whole batch. Installing at two different scopes is
  two runs of this flow, not one run with a scope question per plugin.
- The failure list in step 6 is reported even when every install succeeded
  — as an explicit "no failures", so a silent tail is never mistaken for a
  clean one.
- `management` itself is dropped in step 2 like anything else already
  installed — this flow is running from it.
