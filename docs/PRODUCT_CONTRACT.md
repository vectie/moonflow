# MoonFlow product contract

Class: platform
Maturity: local alpha orchestration engine
Last reviewed: 2026-07-30

## Outcome

MoonFlow advances declared work through dependencies, attempts, authority
decisions, evidence, review and recovery without becoming an agent.

## Users and jobs

- MoonClaw requests the next durable action for approved work.
- MoonDesk visualizes and controls runs.
- Product adapters execute typed domain operations and return receipts.
- Operators inspect, reconcile, revise and recover runs.

## Ownership

MoonFlow owns imported work graphs, event streams, attempt identity,
idempotency, adapter selection records, evidence bindings, review state and
restart recovery.

MoonFlow does not own model reasoning, personas, self-scheduling, domain policy,
source intent, result acceptance or external-effect authority. MoonClaw is the
only agent runtime; MoonBook owns source and accepted knowledge.

## Capability status

| Capability | Status |
| --- | --- |
| Versioned work graphs and event replay | available |
| Authority-aware attempts and review states | available |
| Artifact verification and result reconciliation | available |
| Revision and checkpoint reuse | available |
| Restart recovery and unknown-outcome handling | available |
| CLI/operator inspection | available |
| MoonDesk canvas projection | conditional on MoonDesk integration |
| Self-directed agent behavior | excluded |

## Adapter contract

An executable capability declares product identity, versioned operation ID,
health, input/output schemas, authority classes, claim ceiling and
reconciliation behavior. Selection fails closed if any dimension is missing or
incompatible.

The canvas must use these real operation identifiers. Product names or invented
verbs do not create executable adapters.

The executable source is now
`moonflow.capability-source-bundle.v1`: product-owned pack manifests,
host-owned adapter declarations and expiring health attestations compile to a
portable `moonflow.capability-catalog.v1`. Operation and schema identities are
derived as `product/tool@pack-version` and
`product/schema@schema-version`. A conformant catalog can be consumed by the
existing director; `import-conformant-graph` refuses to create a run when a
product, operation, schema, authority or claim binding drifts.

See [Executable capability truth](CAPABILITY_TRUTH.md) for the adoption
contract and portable fixtures.

## Persistence and recovery

Runs are append-only event histories. Revisions create child runs rather than
rewriting accepted history. Unknown external outcomes reconcile before retry,
and non-compensable effects cannot be repeated automatically.

## Verification

```sh
moon check --target native
moon test --target native
moon info
moon fmt
```

Run conformance and restart/replay cases when changing event or adapter
contracts.

## Release gates and next milestones

- Have MoonDesk discover and retain the implemented manifest-derived catalog
  and graph conformance report rather than maintaining a second product list.
- Complete one cross-product run with restart and outcome evidence.
- Adopt the published adapter declaration and health fixtures in each
  participating pack/host.
- Add operator documentation for backup, restore and failed reconciliation.
- Keep all agent and domain behavior outside MoonFlow.
