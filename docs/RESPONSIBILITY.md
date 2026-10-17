# Explicit responsibility for a work item

`moonflow responsibility WORKSPACE RUN_ID CHANGE_JSON` appends one coordination
event. First stop all other runtime writers for this run. The command serializes
other responsibility commands, but older execution/transition/import commands do
not participate in that lock. Mixed-command concurrent writing is unsupported.

Read `moonflow owner-summary WORKSPACE RUN_ID` immediately before preparing:

```json
{
  "contract_id": "moonflow.responsibility-change.v1",
  "event_id": "assign-research-1",
  "run_id": "assignment-run",
  "book_id": "book",
  "declaration_revision": "r1",
  "source_digest": "sha256:r1",
  "work_item_id": "research",
  "action": "assign",
  "actor_id": "bob",
  "assigner_id": "alice",
  "expected_sequence": 1,
  "expected_event_id": "COPY_THE_CURRENT_LAST_EVENT_ID",
  "recorded_at": "2026-10-15T00:00:00Z"
}
```

Use actual identity and head fields from the readback. A later assignment with a
new event ID reassigns responsibility. To clear it, use `action: "clear"` and
`actor_id: ""`, with the current head and another new event ID. The assigner is
always required, including clear. IDs are recorded operator-supplied names;
this command does not authenticate a person or resolve them in a directory.

An exact retry of the same event ID and payload is idempotent, even after newer
events. Changed content reusing an ID fails. New stale-head requests fail and
must be reconsidered against a fresh summary. Do not automatically replace the
head and resubmit an old decision. Wrong run, item, revision, book and source
identities fail. An assign action requires a nonblank actor; clear requires an
empty actor. Terminal work items reject new assignment and clear requests.

## Scope and history

An assignment belongs to one work item in one run and source revision. It
survives ordinary nonterminal status changes until explicitly reassigned or
cleared. Accepted, failed, cancelled and superseded work retains the historical
record but never advertises that actor as its next actor. Parent assignments
are never copied into child revisions or reused checkpoints. A new revision
needs its own explicit assignment.

Events use the existing runtime envelope with the additive kind
`responsibility-changed`; its `detail` contains the typed v1 change JSON.
Existing event wire fields and old event arrays remain unchanged. Older
consumers that do not know this new kind reject it rather than ignoring it.
The reducer validates the change's identity, named assigner, action and exact
previous sequence/event ID before appending it. Existing duplicate-event logic
continues to reject conflicting event content.

`status` and saved `projection.json` include the last responsibility record per
item, including clears and terminal history. `owner-summary` reads only the
authoritative events; it exposes the current nonterminal actor at both action
and summary level. Its text form shows the same actor. The assigner's name and
the assignment event/time are available in the status responsibility record.
The existing optional-field JSON encoding omits `next_actor_id` when no actor
exists; consumers must treat an absent optional actor as unassigned. The typed
API represents this as `None`; status item's `responsibility` is explicitly null
until a responsibility event exists. This retains the old wire behavior.

The event array is atomically replaced only after successful replay and a final
head check; previous events remain unchanged. Projection replacement follows.
If interrupted between those writes, a read still replays the authoritative
events and an exact command retry repairs the projection without duplicating
events. This is not a general multi-file transaction or mixed-writer guarantee.

## Boundaries

Responsibility is coordination, not authorization, approval, dispatch,
qualification as reviewer, customer acceptance, delivery acceptance or payment.
It changes no item status, execution binding, runnable set, attempt, result,
review, authority or approval. Actual execution and internal acceptance still
require all existing governed controls and evidence. MF-W07 and MOONFLOW-R02
are the motivating owner-status requirements; this bounded development slice
does not close their complete authored acceptance or any broader release gate.

Regression tests: `responsibility_test.mbt`, existing `owner_summary_test.mbt`,
and `scripts/verify_responsibility.mbtx CLI NEW_WORKSPACE`. The verifier invokes
separate CLI processes for import, assign, read, retry, reject, reassign, clear,
projection repair and child-revision readback. No provider or adapter executes.
