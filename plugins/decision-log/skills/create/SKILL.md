---
name: create
description: Create lightweight Decision Logs (DLs) to record technical decisions. Use when asked to "write up a decision log" or "record this decision", and when a choice between approaches, an architectural call, or an unexpected problem forcing a change of direction needs recording during planning or implementation.
---

# Decision Log

## Purpose

Record technical decisions with enough context for future readers to understand *what* was decided, *why*, and *what alternatives were considered*.

Decision Logs (DLs) capture EVERY decision that impacts implementation, whether made at the start of a project or mid-flight when an unexpected problem forces a change in approach. The goal is to eliminate the gap where decisions are made verbally or in Slack and never recorded.

## When to Use

Per your team's engineering process, a DL is required for:

**Team Lead sign-off:**
- API endpoint changes
- Service interface changes
- Database schema changes

**Engineering Manager / Principal Engineer sign-off:**
- Architectural changes
- AWS infrastructure changes that could substantially increase cost
- Introduction of a new technology, library, package, or pattern

**Rule of thumb:** It is better to write a lightweight DL that turns out to be unnecessary than to skip one that was needed.

## Output Location

**Draft:** `.local/DL-DRAFT.md`
**Final:** `dev-docs/decision-logs/{YYYY-MM-DD}-DL-{short-description}.md`

Where `{short-description}` is a lowercase, hyphenated summary (e.g., `switch-to-zod-validation`).

## Invocation Context

This skill can be invoked:
- **Standalone:** at the start of a project to record an upfront design decision
- **Mid-workflow:** during a Build session when an unexpected problem requires a decision

When invoked mid-workflow, the skill uses the current session's context (ticket, worktree, prior exploration) to pre-populate relevant sections.

<workflow name="decision_log" trigger="/decision-log:create invocation">

## Workflow

### Phase 1: Gather Context

Understand what decision needs to be recorded.

1. **Ask the user** what decision they need to document. Get:
   - The problem or question that requires a decision
   - What options they're considering (if they have some in mind)
   - Any constraints or context that narrows the options

2. **Identify session context** (if available):
   - Current ticket (from worktree name, `.local/` files, or session history; fetch via the issue-tracker skill (`get`) if more context is needed; that skill ships with the pr-workflow plugin — without it, skip the fetch)
   - Related Decision Logs (search `dev-docs/decision-logs/` for relevant keywords)

### Phase 2: Explore the Codebase

<mandatory enforcement="strict">
Before drafting, verify the current state of the codebase to ground the DL in reality. Do NOT write a DL based purely on the user's description. Confirm it.
</mandatory>

**Spawn Explore subagents** to understand:
- Current state of the systems/code affected by the decision
- Existing patterns that any option would need to integrate with
- Potential impacts of the proposed options

The depth of exploration should be proportional to the decision's scope:
- **Small** (e.g., choosing between two libraries): Quick search for current usage patterns
- **Medium** (e.g., service interface change): Explore affected services, consumers, tests
- **Large** (e.g., architectural change): Thorough multi-file exploration of affected systems

### Phase 3: Draft the Decision Log

Write the draft to `.local/DL-DRAFT.md` using the template in [template.md](template.md).

<mandatory enforcement="strict">
The draft MUST include:
- At least **2 real options** beyond "Do Nothing" (if there's only one viable approach, that's not a decision, just do it)
- **"Do Nothing" as Option 1:** always first to frame the problem by making the cost of inaction explicit before the reader encounters options that require effort
- **Concrete, specific descriptions:** no vague statements like "improve performance"
- **Pros/Cons grounded in the codebase:** reference actual files, patterns, and constraints discovered during exploration
</mandatory>

<decision_tree name="draft_quality">

| Check | Fail Action |
|-------|-------------|
| Fewer than 2 real options | Ask user for more alternatives, or explore further to discover them |
| "Do Nothing" is not Option 1 | Move it to Option 1. This is mandatory |
| Pros/Cons are generic (not grounded in codebase) | Re-explore to find concrete evidence |
| Impact section is vague | Quantify where possible: latency numbers, error rates, dev hours |
| Options lack estimated effort | Add relative effort estimates |

</decision_tree>

After writing the draft, inform the user it's ready for review at `.local/DL-DRAFT.md`.

### Phase 4: Iterate

The user may provide feedback via chat or inline annotation tags in `.local/DL-DRAFT.md`.

**Supported tags:**

| Tag | Meaning | Expected Response |
|-----|---------|-------------------|
| `@COMMENT:` | General feedback or revision request | Revise the draft to address |
| `@QUESTION:` | Needs an answer | Provide answer in the draft or chat |
| `@CONCERN:` | Risk or issue that must be addressed | Add mitigation or reconsider approach |
| `@APPROVE:` | This section is good, don't change | Preserve as-is |
| `@EVIDENCE:` | Claim needs supporting evidence | Provide specific proof (see below) |

**For `@EVIDENCE:`, the required proof depends on the claim type:**

| Claim Type | Required Evidence |
|------------|-------------------|
| Library/framework functionality | Link to official documentation |
| "Benefit of this approach" | Proof it applies to THIS codebase, not generic benefits |
| Performance claim | Benchmark, measurement, or profiling data |
| "This pattern is used elsewhere" | Specific file:line references in the codebase |
| Compatibility/support claim | Version documentation or test results |

**When asked to re-review:**
1. Read `.local/DL-DRAFT.md`
2. Find all annotation tags
3. Address each based on its type
4. Remove resolved annotations (keep `@APPROVE:` sections unchanged)
5. Repeat until approved

### Phase 5: Finalize

Once the user explicitly approves the draft:

1. Create `dev-docs/decision-logs/` directory if it doesn't exist
2. Determine the filename: `{YYYY-MM-DD}-DL-{short-description}.md`
3. Write the final version from the draft, including:
   - Any referenced ticket rendered via the issue-tracker skill's `ref` operation (which yields the provider's canonical link form), never a bare key. This applies wherever a ticket is mentioned: the `## Related` section and anywhere in the body. Under provider `none` — or when the issue-tracker skill is not installed — omit the ticket reference.
   - Auto-linked related DLs (if discovered during exploration)
4. Delete `.local/DL-DRAFT.md`
5. Report the final file path to the user

<rule enforcement="must">
A DL MUST be merged (via PR) before implementation begins. Remind the user of this when finalizing.
</rule>

</workflow>

## Anti-Patterns

<anti_pattern name="skipping_exploration">

<example type="bad">
User asks for DL -> Claude immediately drafts based on user's description alone
</example>
<example type="good">
User asks for DL -> Claude explores codebase to verify current state -> Drafts with grounded knowledge
</example>

</anti_pattern>

<anti_pattern name="single_option">

<example type="bad">
"We should use Zod" -> DL with only Option 1: Do Nothing and Option 2: Zod
</example>
<example type="good">
"We should use Zod" -> DL with Option 1: Do Nothing, Option 2: Zod, Option 3: Joi (current pattern), Option 4: class-validator
</example>

</anti_pattern>

<anti_pattern name="generic_pros_cons">

<example type="bad">
**Pros:** Better performance, easier to maintain, more scalable
</example>
<example type="good">
**Pros:**
- Eliminates the N+1 query in `OrderService.getWithLineItems()` (`libs/order/src/order.service.ts:142`) which currently causes ~200ms latency per request
- Aligns with the batch-fetch pattern already used in `ScheduleService` (`libs/schedule/src/schedule.service.ts:87`)
</example>

</anti_pattern>

<anti_pattern name="premature_finalization">

<example type="bad">
Writes directly to `dev-docs/decision-logs/` without user review
</example>
<example type="good">
Writes to `.local/DL-DRAFT.md` -> User reviews -> Iterates -> User approves -> Writes to `dev-docs/decision-logs/`
</example>

</anti_pattern>

<anti_pattern name="formulaic_language">

Using the same phrases and sentence structures across DLs makes them read as machine-generated boilerplate rather than considered analysis.

<example type="bad">
Every DL uses "No implementation effort / No risk of introducing bugs" as Do Nothing pros, "This is acceptable because..." for trade-offs, and "Option X was ruled out because..." for every eliminated option.
</example>
<example type="good">
Do Nothing pros describe the actual cost of inaction for this specific problem. Trade-offs are stated directly ("Write amplification is minor given current throughput"). Elimination reasoning varies in phrasing and structure.
</example>

</anti_pattern>
