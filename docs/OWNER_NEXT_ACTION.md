# Owner next-action projection v1

Implements the bounded MOONFLOW-R02 owner-status slice on the event/replay
foundation of MOONFLOW-B10. Responsibility events add explicit coordination
records; execution transitions, authorities, attempts, reconciliation, reviews
and revision migration remain unchanged. See `RESPONSIBILITY.md` for assignment.

## Use

`moonflow owner-summary <workspace> <run-id>` returns only the
`moonflow.owner-summary.v1` JSON object. Append `--text` for its compact text
form. Both commands replay `events.json` and perform no writes. Existing
`status` output and persisted `projection.json` include the exact same object
under `owner_summary`.

The existing MoonDesk Flow run card leads with the next action. Expand an item
to see why it is next, its exact retained artifacts, attempt/result/output
identity, and existing detailed item diagnostics. Expand “Continue with
existing actions and controls” to use the existing governed controls. No new
execution or retry button is added.

## Contract and ordering

The root public API is `owner_summary_v1(RunProjection)`. Its arrays are copies,
so a later event cannot mutate a previous summary. `owner_summary_is_current_v1`
compares the complete pure projection with a current run. `owner_summary_text_v1`
uses the same labels, reason ordering and evidence as JSON.

- Identity: run, book, declaration revision, source digest, sequence, last
  event ID and its recorded time. Time is the event's recorded time, not a
  freshness TTL or the wall clock when the command was called
- Outcome is the recorded engine outcome, with a plain-language label
- Actions order: unknown outcome, failed, blocked, review, waiting, ready,
  active, proposed, cancelled, superseded. This is presentation priority, not an
  execution plan. Registration order is preserved within each group
- Reasons preserve recorded blocker/error first, then unmet dependencies in
  declared order. No multiple blockers are collapsed into a single label
- `next_actor_id` is the most recent explicit responsible operator for this
  nonterminal work item, or null after clear or when unassigned. Product IDs,
  authorities and prior reviewers never become owners implicitly. `next_role`
  still describes the state-required role, not a person's qualification.
  Terminal history retains assignments but advertises no next actor
- Evidence includes exact retained artifact references, current attempt/result
  and output digest, and any internal review receipt/reviewer. Retained artifact
  lists can include prior attempt or review evidence; they are not asserted to
  all be outputs of the current attempt

Internal acceptance is explicitly distinct from customer approval, delivery
acceptance and payment. Unknown adapter outcomes require reconciliation before
any retry. Failure copy asks for a governed recovery decision and never grants
retry eligibility. A child revision obtains its own summary; a parent's accepted
summary fails the child's identity check even when some checkpoints were reused.

## Observation boundaries

MoonDesk checks the embedded summary against outer run identity and item evidence,
then requires the host's `event-head-matched` observation. The host compares the
retained summary to the current event array identity, order and head on each read.
Missing/corrupt/newer/mismatched events leave the owner summary unavailable.
Older producers without a summary still expose detailed diagnostics.

UI refreshes are generation/workspace-bound. Late responses cannot replace a
newer requested observation or a different workspace; lower event heads cannot
replace an already observed higher head. Loading or failed refreshes suppress
the current completion claim while retaining older details.

This remains an observation, not a live guarantee or a second event-replay engine
in Desk. It cannot know about an unimported graph revision, an unobserved later
event, or a domain/customer/financial fact absent from the event store. Artifact
references are displayed exactly; no new artifact-serving route is introduced.
