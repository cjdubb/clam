---
name: scaffold
description: Scaffold an approved lego plan into runtime-present, deliberately unimplemented stubs carrying full behavioral contracts, then run the scaffold gate (strongest available check). Orchestrator-authored; never delegated. Use after /lego:plan approval and before /lego:dispatch.
---

# Lego Scaffolding

The scaffold turns the approved block design into code-level interfaces the
whole flow hangs off: test-writers test against it, implementers fill it in,
and the compiler (where one exists) proves the design composes. Scaffolding is
orchestrator work; do not delegate it.

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

Composition blocks are scaffolded too: their stub is the wiring surface (the
function/module that composes children), and their contract describes the
composed behavior.

## Step 2: Run the scaffold gate

Prove the design composes using the **strongest available check**, from
`.local/config.json` commands, in this order:

1. `typecheck` — best: interfaces are proven to compose.
2. `build` / compile — good: everything at least resolves and compiles.
3. `lint` or an import/syntax check — weak: files parse and resolve.
4. None available — the gate defers to the test wave's red run (tests importing
   and calling every stub is the first mechanical composition proof).

Record which rung ran in the plan document. Fix scaffold errors here; a scaffold
that fails its gate must not be dispatched.

## Step 3: Update state and checkpoint

- Set every scaffolded block to `Status: Scaffolded` and fill in its `Code:`
  path(s) in `.local/blocks.md`.
- Commit the scaffold (with the engineer's consent) as a phase boundary. Clean
  phase-boundary commits are what make realm verification precise in dispatch:
  each wave's diff can then be checked in isolation.

Then proceed to `/lego:dispatch`.
