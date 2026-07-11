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

## Event stream v2

`moonflow.event-stream.v2` deliberately starts a fresh execution contract. A
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

## CLI

```text
moonflow import-graph <workspace> <graph.json>
moonflow status <workspace> <run-id>
moonflow transition <workspace> <run-id> <work-item-id> <action> <recorded-at> [detail]
moonflow advance <workspace> <run-id> <recorded-at>
```

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
