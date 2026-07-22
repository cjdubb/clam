<!--
Contract: B02 landing-skills-jsonc-update

Behavior:
  README documents the landing plugin with all references updated for the
  JSONC profile format (profile-version 2, merge/deploy structure).

Inputs: n/a (documentation surface).

Outputs (required document structure):
  - H1 `# landing` with purpose statement.
  - Profile section documenting .claude/clam-profile.jsonc with the
    merge/deploy JSONC schema, field table, and examples for both
    github-pr and local-merge repos.
  - Supported policy matrix (v0.1).
  - Skills section (/landing:land, /landing:init).
  - Hook section (landing-context.sh reading .jsonc).
  - Failure modes.
  - Roadmap (deliver plugin delegation replaces pr-workflow reference).
  - Tests section.

Invariants:
  - No references to the legacy .claude/clam-profile.md path.
  - No references to YAML frontmatter or awk parsing.
  - Profile examples use JSONC format with // comments.

Edge cases:
  - Legacy migration path documented (init detects .md, offers migration).
-->

NotImplemented: B02 — README to be updated for JSONC profile format.
