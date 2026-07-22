# Plan: Fixture plan for render-doc smoke tests

Ticket: FIX-001
Date: 2026-07-13

## Problem Statement

This fixture exercises the render-doc pipeline: GFM tables, nested lists,
code fences (including adversarial content), long sections, and annotation
tags. It mirrors the section shape of a real `.local/PLAN.md`.

@QUESTION: does this tag render as a highlighted chip in prose?

## Exploration Findings

### Current State

Nested lists with mixed markers:

- Top-level finding one
  - Nested detail with `inline code`
    - Third level, because plans go deep
  - Second nested detail
- Top-level finding two
  1. Ordered child one
  2. Ordered child two
     - Unordered grandchild

### Patterns and Conventions

A GFM table with alignment:

| Pattern | Location | Notes |
|---------|----------|-------|
| Either types | `libs/user/src/service.ts:45` | Standard error channel |
| DAO base | `libs/data/src/dao-base.ts:142` | Optimistic locking lives here |
| Guards | `libs/auth/src/guards.ts:78` | 403 on missing permission |

### Impact Surface

Task list rendering:

- [x] Fixture covers tables
- [x] Fixture covers fences
- [ ] Reviewer has admired the dark theme

## Proposed Approach

The adversarial fence: the next code block contains a closing script tag and
literal annotation tags. Neither may break the page or be highlighted.

```html
<script>
  console.log("if you can read this outside a code block, escaping failed");
</script>
<!-- @CONCERN: this tag is inside a fence and must NOT become a chip -->
<!-- @APPROVE: neither may this one -->
```

A bash fence with tag-like text:

```bash
echo "@QUESTION: still inside a fence"
grep -r "@EVIDENCE:" .local/
```

Inline code containing a tag: `@COMMENT: inline code, no chip`.

## Approaches Also Considered

### Hand-rolled parser

- **Description:** Write a subset markdown parser by hand.
- **Why not:** GFM tables and nested fences make a subset parser a correctness liability.

### Server-side rendering

- **Description:** Run a local HTTP server that renders on request.
- **Why not:** The plan bans servers; a static file needs no process supervision.

### Agent-authored HTML

- **Description:** Have the agent hand-write the HTML every revision.
- **Why not:** Hundreds of regenerated lines per review round is recurring token cost.

## Edge Cases and Failure Modes

- Markdown containing a closing script tag -> page renders, fence shown verbatim
- Empty section body -> section renders with heading only
- Very deep list nesting -> indentation stays readable
- CRITICAL: template slot markers left unreplaced -> render.sh exits non-zero before writing output

## Constraints

- Do NOT fetch anything from the network at render or view time
- Do NOT modify the source markdown

## Verification Strategy

A long section to exercise scrolling and the sticky TOC. Paragraph one of
filler prose that describes verification in enough words to take vertical
space. The smoke script asserts the parser is present, the document survives
a base64 round-trip, no splice markers remain, and no external resources are
referenced.

Paragraph two continues the filler. The rendered page must show this section
in the table of contents and highlight it when scrolled into view. Blockquote
check:

> The markdown stays canonical; the HTML is a disposable derived view.

Paragraph three: horizontal rule below.

---

Paragraph four: after the rule, still inside the same section.

## Rollback Strategy

Code-only change: revert the PR. Generated HTML files are disposable.

---

## Changelog

| Date | Change | Reason |
|------|--------|--------|
| 2026-07-13 | Initial fixture | - |
| 2026-07-13 | Added adversarial fences | Prove the escaping strategy |
