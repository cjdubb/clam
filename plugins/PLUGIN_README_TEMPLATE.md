# {plugin-name}

<!-- One paragraph: what the plugin does, stated operationally. What problem
     does it solve? What does the user get by installing it? Complex plugins
     may use 2-3 sentences; simple ones need just one. -->

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install {plugin-name}@clam
```

<!-- Post-install steps: any required configuration, prerequisites, or
     setup commands. If installing is all that's needed, say so:
     "No configuration required." If there's a hard prerequisite
     (external tooling, another plugin), document it here. -->

## What to expect

<!-- What changes after installing this plugin? Answer concretely:
     - Hooks that start firing (and on which events)
     - Context injected into sessions
     - Files created or read
     - Settings written (if any — most plugins are inert until a skill runs)
     - What happens in sessions where the plugin is active vs. inactive

     For simple plugins that are inert until a skill is run, say so:
     "Installing changes nothing — the plugin is inert until you run
     `/plugin-name:setup`." -->

## Common workflows

<!-- 2-4 recipes for the things an engineer actually does with this plugin.
     Each recipe is an H3 with a task-oriented title ("Suppress attribution",
     "Check which skills fire", "Land a PR") and a short walkthrough — enough
     to follow without reading the Commands reference.

     Simple plugins: 1-2 recipes is fine.
     Complex plugins: cover the main scenarios, link to Commands for detail. -->

## Commands

<!-- Document every user-facing component the plugin provides. Use
     subsections to separate component types:

     ### Skills
     For each: invocation syntax, what it does, whether model-invocable.

     ### Hooks
     For each: which event it fires on, what it does, gating env vars.

     ### Scripts
     For each: CLI usage, what it does, requirements.

     Match depth to complexity: a plugin with one skill needs one paragraph;
     a plugin with five hooks and three scripts needs the full breakdown.
     A simple plugin with only skills can skip the ### subsection headers
     and just document each skill directly.

     Configuration lives here, not in its own section. The sanctioned config
     interface is a setup command; env vars are the wire protocol between a
     command and a hook, not a user interface. So:
     - Config written by a setup command: document it under that command.
     - Env vars read by a hook: document them inline with that hook.
     - Env-var-heavy plugins: add a summary table at the end of this section:

       | Env var | Default | Effect |
       |---------|---------|--------|
       | `VAR_NAME` | `value` | What it controls |

     - Any var a user must set by hand (no setup command writes it yet) gets
       an exact instruction beside it: set it in the `env` block of the
       settings file for the scope where the plugin is installed. -->

<!-- Optional section — include between Commands and Relationships when
     relevant to the plugin:

     ## Tests

     For plugins with test suites. List the commands:

     ```bash
     bash plugins/{plugin-name}/scripts/foo.test.sh
     ```
-->

## Relationships to other plugins

<!-- How this plugin interacts with other clam plugins:
     - Hard dependencies (requires — the plugin breaks without these)
     - Soft integrations (optional — degrades gracefully when absent)
     - What this plugin provides to others (stable interfaces, files,
       skills other plugins consume)

     If standalone: "None required. This plugin is fully standalone."

     For plugins with hard dependencies, the Requires / Provides / Consumes
     taxonomy (as used by worktrees and orchestrator-handover) is a good
     pattern. -->

## Uninstalling

```
/plugin uninstall {plugin-name}@clam
```

<!-- Cleanup steps beyond uninstalling:
     - Settings to revert (run a `setup remove` command first?)
     - Files that are not removed (logs, artifacts, state in .local/)
     - Shell config to update (sourced libs?)
     If uninstalling is all that's needed, say so. -->
