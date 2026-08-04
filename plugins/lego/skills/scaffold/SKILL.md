---
name: scaffold
description: Scaffold an approved lego plan into runtime-present, deliberately unimplemented stubs carrying full behavioral contracts, then run the scaffold gate (strongest available check). Orchestrator-authored; never delegated. Use after /lego:plan approval and before /lego:dispatch.
---

# Lego Scaffolding

The scaffold turns the approved block design into code-level interfaces the
whole flow hangs off: test-writers test against it, implementers fill it in,
and the compiler (where one exists) proves the design composes. Scaffolding is
orchestrator work; do not delegate it.

Scaffolding happens on the **integration branch** — the branch lego was
started on. Every work unit's worktree forks from the integration tip, so all
stubs must land there first: each work unit then sees every sibling block's
*stub* but never a sibling's *tests* or *implementation*.

Precondition: an approved plan in `.local/plans/` with blocks at `Status: Planned`.

## Step 1: Write the stubs

For every block, create its public interface in the repo's language, obeying two
principles:

1. **Runtime-present, deliberately unimplemented.** Tests must be able to import
   and CALL the stub and fail for the right reason. Declaration-only stubs
   (`declare function`, header-only) cannot produce a right-reason red run, so
   bodies exist and fail loudly:

   | Language | Stub body |
   |---|---|
   | TypeScript/JS | `throw new Error("NotImplemented: B<NN>")` |
   | Python | `raise NotImplementedError("B<NN>")` |
   | Go | `panic("NotImplemented: B<NN>")` |
   | Rust | `unimplemented!("B<NN>")` |
   | Ruby/JVM/other | the idiomatic equivalent |

   Supporting types, interfaces, and signatures are written in full; only
   behavior is absent.

2. **Types are not contracts.** Every stub carries a contract docblock in the
   language's doc convention. This docblock is the authoritative contract that
   tests and implementations are verified against:

   ```
   Contract: B<NN> <name>
   Behavior:   what it does, stated operationally
   Inputs:     domains, units, preconditions
   Outputs:    exact semantics (ordering, stability, nullability, units)
   Errors:     every failure mode and how it manifests
   Invariants: what always holds (purity, no mutation, idempotency, ...)
   Edge cases: empty, boundary, duplicate, oversized, concurrent, ...
   ```

   Write contracts so a test-writer with NO other context can enumerate the
   clauses and test each one. Ambiguity here becomes escalation traffic later;
   spend the effort now.

   **Prose blocks are the exception to docblock permanence.** When a block's
   deliverable is a document — a `SKILL.md`, a `README.md`, a template — its
   "doc convention" is an HTML comment, and the prose written below it *is*
   the implementation. A contract left in place there ships as a duplicate of
   the text beneath it, and an HTML comment is invisible only to the markdown
   renderer: every reader that loads the file, Claude included, still pays for
   it. So mark these for removal when you write them:

   ```
   <!-- Contract: B<NN> <name> (remove at acceptance)
   Behavior: ...
   -->
   ```

   The implementation wave deletes the comment; acceptance confirms it is
   gone. Anything the contract asserts that must outlive the block — a
   standing editing rule, an invariant with no other home — is moved into the
   document's own prose or a short editing note *before* the contract goes.

Composition blocks are scaffolded too: their stub is the wiring surface (the
function/module that composes children), and their contract describes the
composed behavior.

## Step 2: Run the scaffold gate

**Rung 0: the sizing lint.** Before the composition rungs below run,
re-check the plan's own sizing discipline rather than trusting it from
planning time: run `scripts/blocks-lint.sh` against `.local/blocks.md`
(this presupposes an approved plan's block map already exists — a fresh
repo with no `.local/blocks.md` yet has nothing to scaffold, so the rung
never runs). Exit 0 proceeds to the rungs below. Exit 1 means findings — an
oversized entry with no `Justification:`, a malformed `Est:`, or similar —
and the plan goes back to `/lego:plan` as a sizing defect; it is never
patched silently here, at scaffold time. Exit 2 is an environment or usage
error (a missing block map, a bad `--budget`, e.g.): fix it and re-run, it
says nothing about the plan itself. If `scripts/blocks-lint.sh` is absent —
an older checkout mid an upgrade — rung 0 is skipped with an explicit
warning naming the script, visible in the transcript, never silent. A block
whose `Est:` already carries a `Justification:` for exceeding the
per-block ceiling passes the lint as written; nothing about it is
re-argued here.

Prove the design composes using the **strongest available check**, from the
effective config's commands (`.claude/lego.json` merged with any
`.local/config.json` override — see `docs/config-schema.md`), in this order:

1. `typecheck` — best: interfaces are proven to compose.
2. `build` / compile — good: everything at least resolves and compiles.
3. `lint` or an import/syntax check — weak: files parse and resolve.
4. None available — the gate defers to the test wave's red run (tests importing
   and calling every stub is the first mechanical composition proof).

Record which rung ran in the plan document. Fix scaffold errors here; a scaffold
that fails its gate must not be dispatched.

### Step 2a: Blocks with no red/green cycle

Some blocks carry no executable behavior to verify: prose whose quality is the
deliverable (a README section, guidance text), or configuration whose only
assertion is its own literal content. Planning always produces some of these,
so decide their gate now, at scaffold time, rather than leaving dispatch to
improvise one.

**Decide by clause, not by convenience.** Walk every clause in the block's
contract docblock and ask whether it can be expressed as an executable
assertion. Structural and anchor assertions count as executable — a token,
heading, or ordering check over a prose file is a real test — so a prose
file with anchors is not review-gated; it takes the normal test wave like
any other block.

Reserve review-gated status for blocks where no clause is executably assertable —
never merely because tests would be inconvenient, low-value, or awkward to
write. Content with no assertable structure — README body text carrying no
anchors a script could check, for instance — is review-gated. A block with a
mix of assertable and non-assertable clauses is not review-gated either:
partial testability means the normal wave runs and covers what it can, and
the reviewer covers the remainder at acceptance.

Review-gating is decided at scaffold time, by the orchestrator, and
recorded on the block; it is never a dispatch-time improvisation. The
moment you mark a block review-gated, note it — with the reason — on its
`.local/blocks.md` entry.

A review-gated block's test wave is skipped, and a skipped test wave is
always recorded with its reason; the skip is never silent. Its acceptance
gate replaces the normal one: orchestrator verification of the artifact
against every contract clause, plus explicit engineer acceptance —
orchestrator verification alone does not accept a review-gated block;
both are required. Everything else about the block — realm rules, the
contract docblock, the block-map lifecycle — is unchanged.

This applies identically to engineer-owned blocks. An engineer-owned
review-gated block takes the same gate as any other — the engineer
cannot accept their own block unilaterally, and the orchestrator still
verifies it against every clause before the block can move to `Accepted`.

## Step 3: Update state and checkpoint

- Set every scaffolded block to `Status: Scaffolded` and fill in its `Code:`
  field in `.local/blocks.md` with each block's **actual** path(s), verified
  pairwise disjoint across work units. A violation goes back to `/lego:plan`
  as a decomposition defect rather than being resolved silently here.
  Before committing, verify that any questions raised during scaffolding —
  contract ambiguities, path-disjointness concerns — have been resolved with
  the engineer.

- Commit the scaffold (with the engineer's consent) as a phase boundary. Clean
  phase-boundary commits are what make realm verification precise in dispatch:
  each wave's diff can then be checked in isolation. This commit is what every
  work unit's worktree forks from — dispatch runs `worktree.sh add` against
  this commit's branch tip.

Then proceed to `/lego:dispatch`.
