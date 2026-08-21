# clam

The ubiquitous language of this marketplace: terms that cross plugin
boundaries and therefore belong to the repository rather than to any one
plugin. Definitions only — the rules governing plugin structure live in
[ARCHITECTURE.md](ARCHITECTURE.md), and artifact formats live in
`docs/protocols/`.

## Language

### Agent roles

**Orchestrator**:
The agent the engineer interacts with directly — the top of the agent tree,
responsible for high-level planning and for delegating the work it plans.
_Avoid_: coordinator, main agent, lead agent, driver

**Worker**:
An agent an Orchestrator delegates a single specific task to, implementing
against a contract it did not design.
_Avoid_: builder, implementer, helper agent, sub-orchestrator
