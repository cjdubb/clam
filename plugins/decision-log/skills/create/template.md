# Decision Log Template

```markdown
# {YYYY-MM-DD} - DL - {What it's about}

**Date:** {YYYY-MM-DD}

## Context / Problem Statement

### Background

{What's the current situation? What systems, services, or patterns are involved?
Provide enough context for someone unfamiliar to understand.}

### The Problem

{What specific problem are we solving? Be precise and concrete.
Avoid vague statements like "improve performance" - specify what's slow and by how much.}

### Impact

{Why does this matter? Quantify where possible:
- User impact (latency, errors, blocked workflows)
- Developer impact (time spent, complexity, maintenance burden)
- Business impact (cost, risk, opportunity cost)}

## Options Considered

### Option 1: Do Nothing

{Always the first option. Frames the problem by making the cost of inaction explicit before presenting alternatives.}

**Pros:**
- {describe what is preserved by not changing anything}

**Cons:**
- {ongoing cost of the problem}
- {risk if problem worsens}

### Option 2: {Name}

{Detailed description of this approach}

**Pros:**
- {benefit 1}
- {benefit 2}

**Cons:**
- {drawback 1}
- {drawback 2}

**Estimated effort:** {Small / Medium / Large - relative to other options}

### Option 3: {Name}

{Detailed description of this approach}

**Pros:**
- {benefit 1}
- {benefit 2}

**Cons:**
- {drawback 1}
- {drawback 2}

**Estimated effort:** {Small / Medium / Large}

## Decision

**Chosen option:** {Option N - Name}

**Rationale:**
{Why this option over others. Address the key trade-offs explicitly, ensuring that they're relevant to our context.}

**Trade-offs accepted:**
{What downsides we're knowingly accepting and why they're acceptable.}

## Consequences

**Positive:**
- {expected benefit 1}
- {expected benefit 2}

**Negative:**
- {accepted drawback 1}
- {accepted drawback 2}

**Risks:**
- {risk 1} - Mitigation: {how we'll address it}
- {risk 2} - Mitigation: {how we'll address it}

## Related

- {Each related decision log as a relative markdown link, resolvable from this file's directory: [2025-11-02 - DL - retire the legacy scheduler](2025-11-02-DL-retire-legacy-scheduler.md)}
- {The artifact under decision, and any plan or protocol this decision rests on, carried the same way: [the ingestion rewrite plan](../plans/002-ingestion-rewrite.md)}
- Ticket: {ticket reference via the issue-tracker skill (`ref`); omit under provider `none`}
```
