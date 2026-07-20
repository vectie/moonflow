# MoonFlow responsibility and testability

MoonFlow is a durable orchestration engine, not an agent runtime and not a
domain pack. It owns the state transition between declared work, adapter
attempts, evidence, review, recovery, and acceptance. It does not create domain
intent, execute product effects itself, or approve its own results.

## Ownership matrix

| Concern | Responsible owner | MoonFlow responsibility |
|---|---|---|
| Source intent and acceptance criteria | MoonBook | Import the exact revision and digest; never rewrite it. |
| Model loop and agent execution | MoonClaw | Submit and reconcile typed work; never create another model loop. |
| Domain operation | Declared product adapter | Select against capability and record the immutable receipt. |
| Authority grant | MoonGate/operator | Check the declared authority; never widen it. |
| Acceptance | Independent reviewer/Bookkeeper | Preserve the review receipt; success is only review-ready. |
| Retry and restart recovery | MoonFlow | Reconcile unknown outcomes and replay durable events idempotently. |

## Refactored decision seams

- `canonical_authority_classes` is the one vocabulary used by graph import,
  event application, adapter capability validation, and adapter requests.
- `projection_outcome_for_statuses` is a pure precedence decision. Mutation is
  limited to a small projection method that assigns its result.
- Adapter selection, execution receipt reconciliation, and acceptance review
  remain separate functions and durable artifacts.

These seams let unit tests exercise policy without filesystem, network,
MoonClaw, MoonGate, or a product adapter. Integration tests then prove replay,
artifact containment, idempotency, restart behavior, and cross-product receipt
identity separately.

## Responsible completion

MoonFlow may report a run accepted only when every item has an independent
acceptance receipt bound to the exact result and source declaration. Adapter
success alone means `review`, never `accepted`. Unknown outcomes reconcile
before retry, external or physical authority is never inferred, and domain
claims remain owned by the producing product.
