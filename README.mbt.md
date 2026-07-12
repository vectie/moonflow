# MoonFlow

MoonFlow is Moon Suite's durable declared-goal execution runtime. MoonBook owns
source intent; MoonFlow imports a versioned Work graph, preserves its source
linkage, evaluates dependencies, records attempts and evidence, and projects a
recoverable run state.

## Constitutional boundary

- MoonFlow executes declared intent; it does not author MoonBook goals.
- MoonFlow owns run events, attempts, policy decisions, and recovery state.
- Product adapters own their domain effects and return typed receipts.
- MoonTown may propose work but cannot mark MoonFlow items complete.
- Physical effects always require separately granted physical authority.

## Event stream v3

`moonflow.event-stream.v3` adds governed checkpoint reuse without weakening the
fresh execution contract. A
Work graph must provide:

- `book_id`, `declaration_revision`, and `source_digest`;
- a unique `declaration_id` for every Work item;
- canonical `requested_authority` values;
- non-empty `acceptance_criteria`;
- known, acyclic dependencies.

The importer fails closed instead of creating permanently waiting work when a
dependency is unknown or cyclic. Every event carries the immutable source
context, so replay rejects events from a different book revision or digest.

Canonical authority classes are `observe`, `cognitive-maintenance`,
`sandbox-execution`, `workspace-mutation`, `external-effect`, and
`physical-effect`.

## Adapter contract

The adapter boundary records capability, request, attempt, idempotency key,
input digest, requested authority, external job identity, terminal status,
output digest, artifacts, error classification, and compensability. Production
adapters must support reconciliation. Result import fails closed when request,
attempt, idempotency, or product identity differs.

Capability records also declare health, operations, authority classes,
input/output contracts, and a claim ceiling. The director selects an adapter
only when all dimensions match. Unknown outcomes reconcile before any retry;
quality rejection revises the input or procedure instead of repeating it.

`prepare-next` removes hand-authored dispatch requests. It derives each ready
item's requirement from its MoonBook execution binding, selects a healthy
compatible adapter, verifies and hashes the declared input artifacts, writes a
durable decision/request pair, and submits the attempt event. A rejected
selection is retained as a decision receipt and does not start work.
`complete-artifacts` performs the symmetric return path for local adapters: it
verifies workspace-relative output artifacts, derives their aggregate digest,
materializes the typed result receipt, and reconciles it into review state.

## Native revision and evidence lineage

`revise-run` creates a child run and never rewrites its parent. It reuses an
accepted checkpoint only when declaration identity, owner, authority,
acceptance criteria, evidence identity, and every dependency revalidate.
Changed checkpoints are explicitly marked invalidated in a
`moonflow.run-migration.v1` receipt. Reuse is represented by a durable
`checkpoint-reused` event and remains distinct from new execution.

`bundle-evidence` reads a workspace-relative descriptor, verifies every source
before mutation, hashes and stores immutable content-addressed objects, writes a
manifest, and verifies workspace containment again after mutation. The command
removes manual copying and hash transcription while retaining producer,
contract, claim, and result provenance.

## CLI

```text
moonflow import-graph <workspace> <graph.json>
moonflow status <workspace> <run-id>
moonflow transition <workspace> <run-id> <work-item-id> <action> <recorded-at> [detail]
moonflow advance <workspace> <run-id> <recorded-at>
moonflow submit-attempt <workspace> <run-id> <request.json>
moonflow reconcile-attempt <workspace> <run-id> <result.json>
moonflow review-outcome <workspace> <run-id> <workspace-relative-review-receipt>
moonflow revise-run <workspace> <parent-run-id> <child-graph-artifact> <proposal-artifact> <migration-id> <recorded-at>
moonflow select-adapter <workspace> <capabilities-artifact> <requirement-artifact>
moonflow prepare-next <workspace> <run-id> <capabilities-artifact> <recorded-at>
moonflow complete-artifacts <workspace> <run-id> <work-item-id> <recorded-at> <artifact>...
moonflow bundle-evidence <workspace> <bundle-spec-artifact> <recorded-at>
moonflow validate-capability <capability.json>
```

Adapter success moves Work to review; it never implies acceptance. The only
CLI acceptance path is `review-outcome`, whose typed receipt must match the
persisted run, declaration, result, attempt, and output digest, review every
original criterion in order, and cite evidence already attached to the Work
item.

If execution reveals that a criterion belongs to the wrong product, MoonBook
compiles a new declaration revision and `revise-run` performs checkpoint
migration. The old event history remains unchanged; invalid evidence is never
reinterpreted in place.

All runtime state is stored under
`<workspace>/.moonsuite/products/moonflow/runs/<run-id>`. Artifact transitions
accept only existing workspace-relative paths and reject canonical path escape.

## Verification

```text
moon check --target native --deny-warn
moon test --target native --deny-warn
moon info
moon fmt
```
