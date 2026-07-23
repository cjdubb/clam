<!--
Contract: B01 readme-template
Behavior:
  Cookiecutter README template for clam plugins. New plugins copy this file
  to their own README.md and fill in every placeholder. Existing plugins
  use it as a checklist to verify their README covers all required sections.
Inputs:
  None (static template).
Outputs:
  A markdown file with these required sections, in order:
    1. H1 heading with the plugin name and a one-paragraph purpose statement
    2. ## Getting started — install command and any configuration needed
    3. ## Commands — skills, hooks, scripts the plugin provides
    4. ## Relationships to other plugins — how this plugin interacts with
       others; if standalone, say so explicitly
    5. ## Uninstalling — uninstall command and any cleanup steps
  Optional additional sections (## Tests, ## Knobs, etc.) may appear between
  Commands and Relationships.
Errors:
  n/a (static template).
Invariants:
  - Every required section is present with a placeholder comment explaining
    what to write there.
  - Section order matches the issue #61 specification.
  - The template is self-documenting: a plugin author with no other context
    can copy it and produce a compliant README.
Edge cases:
  - Plugins with no skills (hooks-only): the Commands section documents
    hooks instead.
  - Plugins with no relationships: the section says so explicitly rather
    than being omitted.
-->

# {plugin-name}

<!-- One paragraph: what the plugin does, stated operationally. -->

## Getting started

```
/plugin marketplace add cjdubb/clam
/plugin install {plugin-name}@clam
```

<!-- Any post-install configuration or prerequisites. If installing is all
     that's needed, say so ("No configuration required" or similar). -->

## Commands

<!-- Document every user-facing component the plugin provides:

     - Skills: invocation syntax, what it does, whether it's model-invocable
     - Hooks: which event, what the hook does, any gating env vars
     - Scripts: CLI usage, what it does, requirements

     Use tables, subsections, or a flat list — match the depth to the
     plugin's complexity. A plugin with one skill needs one paragraph;
     a plugin with five hooks and three scripts needs subsections. -->

## Relationships to other plugins

<!-- How this plugin interacts with other plugins:
     - Hard dependencies (requires)
     - Soft integrations (optional, degrades gracefully)
     - What this plugin provides to others

     If the plugin is fully standalone, say so explicitly:
     "None required. This plugin is fully standalone." -->

## Uninstalling

```
/plugin uninstall {plugin-name}@clam
```

<!-- Any cleanup steps: files to remove, settings to revert, shell config
     to update. If uninstalling is all that's needed, say so. -->
