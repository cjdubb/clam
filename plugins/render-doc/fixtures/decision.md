# Decision: Which fixture proves the decision schema renders correctly?

Status: Open
Refs: clam-code#253

## Context

This fixture mirrors the decision-file template from the decision-rundown
skill: metadata lines, options with pros and cons, a recommendation, and a
deferred path. Evidence table:

| Claim | Source |
|-------|--------|
| Decision files live in `.local/decisions/` | decision-rundown SKILL.md |
| Tags must not highlight inside fences | render-doc boundary conditions |

The adversarial fence, again, because every document type must survive it:

```html
</script><script>console.log("escaped, or the page just broke")</script>
```

And a fenced tag that must stay plain: `@CONCERN: inside inline code`.

## Options

### 1. Comparison-card fixture

Three options rendered side by side as cards, with pros and cons parsed from
the strong-label convention.

**Pros:** exercises the exact markup the schema layer parses; small.
**Cons:** synthetic content proves less than a real decision file.

### 2. Copy of a historical decision

Reuse a past `.local/decisions/` file verbatim.

**Pros:** battle-tested prose and structure.
**Cons:** session-local files are gitignored and may carry project context that does not belong in a committed fixture.

### 3. No decision fixture

Smoke-test only the plan fixture.

**Pros:** one less file.
**Cons:** the decision schema path (cards, recommendation banner, status pill) would ship untested.

## Recommendation

Comparison-card fixture, because it exercises every branch of the decision
schema layer while staying small and self-explanatory.

## If Deferred

The smoke script keeps using this very file; nothing else depends on the
choice. @COMMENT: a tag in prose, which should render as a chip.
