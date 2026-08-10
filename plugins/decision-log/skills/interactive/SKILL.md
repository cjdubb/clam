---
name: interactive
description: "Iterative section-by-section authoring of a Decision Log via dialogue. Invoke with `/decision-log:interactive` when the problem framing or option space needs to be discovered collaboratively rather than drafted in one shot."
disable-model-invocation: true
---

# Decision Log (Interactive)

## Purpose

Interactive companion to the [decision-log:create](../create/SKILL.md) skill. Builds the DL one section at a time in dialogue with the user, confirming each section before writing to `.local/DL-DRAFT.md`.

Use this skill when the one-shot draft produced by `decision-log:create` would likely require heavy rework — for example, when the problem framing is contested, the option space is unclear, or prior DLs in this area produced generic Pros/Cons that didn't survive review.

The non-interactive [decision-log:create](../create/SKILL.md) skill remains the default and is faster for well-scoped decisions. This skill is only invoked explicitly via `/decision-log:interactive`.

## When to Use

Same triggering criteria as [decision-log:create](../create/SKILL.md) (Team Lead / EM / Principal sign-off categories). Prefer this skill when:

- The problem statement itself is unsettled and needs collaborative framing
- You expect ≥3 plausible options and want them discovered, not assumed
- Prior DLs covering similar decisions produced formulaic or ungrounded output

## Output Location

Same as [decision-log:create](../create/SKILL.md):

- **Draft:** `.local/DL-DRAFT.md`
- **Final:** `dev-docs/decision-logs/{YYYY-MM-DD}-DL-{short-description}.md`

Uses the same template, [template.md](../create/template.md). The structure of the output is identical to the non-interactive skill — only the authoring process differs.

<workflow name="decision_log_interactive" trigger="/decision-log:interactive invocation">

## Workflow

### Phase 1: Gather Context

Same as [decision-log:create](../create/SKILL.md) Phase 1: ask what decision needs to be documented, identify the ticket (via the issue-tracker skill) and related DLs.

### Phase 2: Explore the Codebase

Same as [decision-log:create](../create/SKILL.md) Phase 2. Exploration MUST complete before Phase 3 begins — the dialogue depends on grounded evidence to challenge claims with.

### Phase 3: Iterative Section-by-Section Drafting

<mandatory enforcement="strict">
Build the DL one section at a time. Do NOT write the full draft up front. At each gate, propose the section's content in chat, wait for the user's reaction, then append the confirmed content to `.local/DL-DRAFT.md` before moving to the next gate.
</mandatory>

Each gate follows the same pattern:

1. Propose the section's content **in the chat**, not the draft file
2. Wait for user reaction (approve, modify, reject)
3. On approval, append the confirmed content to `.local/DL-DRAFT.md`
4. Move to the next gate

Do not batch gates. Each section must be discussed independently.

#### Gate 1: Problem Framing (Background + The Problem)

Restate the problem in your own words, grounded in Phase 2 exploration:

- The systems / code / patterns involved
- What's broken or insufficient about the current state
- Why a decision is required now

Ask: "Is this the problem we're solving, or have I framed it wrong?"

Do not proceed until the framing is explicitly confirmed.

#### Gate 2: Impact

Quantify the cost of the problem along the relevant dimensions:

- User impact (latency, errors, blocked workflows)
- Developer impact (time spent, complexity, maintenance burden)
- Business impact (cost, risk, opportunity cost)

If a dimension cannot be quantified from available evidence, say so explicitly. Do not invent numbers. Ask the user to supply what you cannot derive.

#### Gate 3: Option Set (Names Only)

Propose **option names only** — no Pros / Cons yet. Include:

- "Do Nothing" as Option 1 (mandatory; frames the cost of inaction)
- At least 2 other genuine options
- Options you suspect are weak, for completeness and transparency

Ask: "Is this the option set we should evaluate? Anything missing? Anything to drop?"

The option set must be locked here. Drafting Pros / Cons for an option that should have been dropped wastes the user's review attention.

#### Gate 4: Per-Option Pros / Cons (Iterative)

For each option in the locked set, in order:

1. Propose Pros and Cons in chat, **each grounded in concrete codebase evidence** (file:line, measurement, or existing pattern)
2. Stop and ask: "Anything to add, remove, or push back on?"
3. On confirmation, append the option's section to `.local/DL-DRAFT.md`
4. Move to the next option

<rule enforcement="must">
Every Pro and Con must reference a specific file, pattern, or measurement, OR be flagged explicitly as a generic claim the user needs to confirm. Do not write "Better performance" unless you can name what is currently slow and by how much. If Phase 2 exploration did not surface evidence for a claim, that is a signal to re-explore — not to write the claim anyway.
</rule>

#### Gate 5: Decision + Rationale + Trade-offs Accepted

Propose:

- Which option to pick
- Why this option, addressing the key trade-offs explicitly
- What downsides we are knowingly accepting and why they're acceptable in this context

Ask: "Does this rationale match your thinking, or would you frame the trade-offs differently?"

#### Gate 6: Consequences

Propose Positive outcomes, Negative outcomes, and Risks (with mitigations for each risk).

Ask: "Anything missing? Any risks I haven't surfaced?"

### Phase 4: Late-Stage Tag Review (Optional)

Once all gates have passed and `.local/DL-DRAFT.md` is complete, the user may still annotate the draft with `@COMMENT:`, `@QUESTION:`, `@CONCERN:`, `@APPROVE:`, `@EVIDENCE:` tags for final polish. Handle them per the [decision-log:create](../create/SKILL.md) Phase 4 process.

This phase is usually unnecessary in the interactive flow — most sections have already been shaped live — but the tag mechanism remains available for last-pass adjustments.

### Phase 5: Finalize

Same as [decision-log:create](../create/SKILL.md) Phase 5: confirm explicit approval, write the final file to `dev-docs/decision-logs/`, delete the draft, report the path.

</workflow>

## Anti-Patterns

<anti_pattern name="batching_gates">

<example type="bad">
Claude proposes Background, Problem, Impact, and the option set in a single chat message and asks "look good?" The user can only react in aggregate, which collapses the value of the iterative flow.
</example>
<example type="good">
One gate per message. The user reacts to the framing before Claude proposes Impact. The user locks the option set before Claude drafts any Pros / Cons.
</example>

</anti_pattern>

<anti_pattern name="writing_before_confirming">

<example type="bad">
Claude writes the full Context section to `.local/DL-DRAFT.md` and *then* asks the user whether the framing is correct.
</example>
<example type="good">
Claude proposes the framing in chat first. Only after explicit confirmation does the section land in the draft file.
</example>

</anti_pattern>

<anti_pattern name="locking_options_implicitly">

<example type="bad">
Claude proposes Options A, B, C with full Pros / Cons in one go. The user says "I don't think C is a real option" — the work building C's section is wasted.
</example>
<example type="good">
Claude proposes option names only at Gate 3. The user vetoes C. Pros / Cons drafting begins only on the locked set.
</example>

</anti_pattern>

<anti_pattern name="ungrounded_pros_cons">

<example type="bad">
Claude proposes "Pros: better performance, easier to maintain" and waits for the user to fill in specifics.
</example>
<example type="good">
Claude proposes "Pros: eliminates the N+1 in `OrderService.getWithLineItems()` (`libs/order/src/order.service.ts:142`), ~200ms latency improvement per request" — or, if exploration didn't surface evidence, explicitly says "I don't have grounding for this claim — should I re-explore, or is this something you can confirm directly?"
</example>

</anti_pattern>
