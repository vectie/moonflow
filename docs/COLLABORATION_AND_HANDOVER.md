# Collaboration and handover operator contract

MoonFlow owns multi-person workspace policy and handover lifecycle state. It
does not introduce another agent runtime. MoonDesk and other products consume
MoonFlow's validated CLI projection instead of decoding or rewriting state.

## Durable state and commands

Collaboration snapshots live at:

```text
<workspace>/.moonsuite/products/moonflow/collaboration/<workspace-id>.json
```

Handover snapshots live at:

```text
<workspace>/.moonsuite/products/moonflow/handovers/<handover-id>.json
```

The owner CLI is the supported operator seam:

```text
moonflow collaboration apply <workspace> <workspace-id> <typed-mutation.json>
moonflow collaboration inspect <workspace> <workspace-id>
moonflow handover apply <workspace> <handover-id> <typed-mutation.json>
moonflow handover inspect <workspace> <handover-id>
moonflow handover list <workspace>
```

`apply` takes a process-scoped writer lock, decodes the current snapshot,
verifies its digest and replay log, applies one typed policy mutation, and
atomically replaces the snapshot. The OS releases the lock after a crash, and
the expected-head check occurs while the writer lock is held.
`inspect` performs the same validation and prints the canonical projection.
Missing state and invalid/tampered state are errors, not empty success results.
`handover list` is the discoverable owner-validated catalog; invalid snapshot
files appear as `quarantined` entries and are never rendered as valid state.

## Collaboration mutation envelope

Every request uses `moonflow.collaboration-operator-mutation.v1` and includes
`workspace_id`, `action`, `mutation_id`, encoded `actor`, `recorded_at`, and an
action-specific `payload`. Every non-`start` action also includes the current
`expected_head`. `start` instead includes `workspace_ref` and omits the head.

Supported actions are:

- `start`: `{ "owner_membership_id": ... }`
- `add-member`: membership id, encoded principal, and typed roles
- `assign`: assignee, operation ref, subject digest, and optional due time
- `claim`: assignment id, lease id, and bounded expiry
- `assignment-transition`: state plus optional submitted artifact/review id
- `comment`: immutable subject/anchor/body evidence and typed mentions
- `review`: independent human reviewer and exact subject digest
- `review-begin`: review id
- `decision`: `approved` or `changes-requested` plus immutable evidence

Exact retries return `idempotent`. Reused mutation ids with different content
or stale heads return a typed conflict. Backdating, non-member mentions, stale
leases, comment-as-approval, and mismatched review/output completion fail
closed. Snapshot replay retains the event log, so these guarantees survive a
restart.

## Handover lifecycle

Handover requests use `moonflow.handover-operator-mutation.v1`.

- `start` carries the MoonLib bundle and control envelope.
- `transition` carries `expected_head`, `target_state`, and any required fresh
  receiver authority or quarantine evidence.

The lifecycle is `draft → sealed → offered → accepted/rejected/expired →
imported → resumed → completed`. No later state compensates for an invalid
earlier gate. The immutable transition log is replayed on every restore.

## UI availability

A missing collaboration snapshot means “not configured” and should show a
setup action. A valid snapshot can be rendered. A decode failure means
quarantine/recovery; a UI must not fabricate members, assignments, reviews, or
handover state.
