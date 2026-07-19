///|
/// Event kinds consumed exactly once by the orchestration half of replay.
pub fn is_orchestration_event_kind_v2(kind : String) -> Bool {
  kind == "schedule.registered.v2" ||
  kind == "lease.claimed.v2" ||
  kind == "lease.renewed.v2" ||
  kind == "lease.released.v2" ||
  kind == "lease.expired.v2" ||
  kind == "lease.reclaimed.v2" ||
  kind == "work.cancellation.requested.v2" ||
  kind == "work.terminal.v2"
}

///|
/// Event kinds permitted ahead of mixed schedule admission.
pub fn is_verified_mixed_schedule_prefix_kind_v2(kind : String) -> Bool {
  kind == "EvidenceAttached" ||
  kind == "AuthorityRequested" ||
  kind == "AuthorityGranted" ||
  kind == "AuthorityDenied" ||
  kind == "ReviewRequested" ||
  kind == "ReviewDecisionRecorded" ||
  kind == "ReviewReceiptBound" ||
  kind == "attempt.registered.v1" ||
  kind == "effect.intent.requested.v1" ||
  kind == "effect.dispatch.observed.v1" ||
  kind == "effect.receipt.recorded.v1" ||
  kind == "effect.outcome.unknown.v1" ||
  kind == "effect.reconciliation.requested.v1" ||
  kind == "effect.reconciliation.resolved.v1"
}

///|
/// Genesis has no committed event, revision, or head digest.
pub fn is_genesis_position(
  sequence : Int64,
  revision : Int64,
  has_head_digest : Bool,
) -> Bool {
  sequence == 0L && revision == 0L && !has_head_digest
}

///|
/// The exact durable batch that owns a contested expected revision.
pub struct ContestedBatch {
  command_key : String
  expected_revision : Int64
  event_refs : ReadOnlyArray[@contracts.RecordRef]
  batch_digest : @contracts.ContentDigest
}

///|
pub fn contested_batch(
  replay : @storage.ReplayResult,
  expected_revision : Int64,
) -> ContestedBatch? {
  for boundary in replay.committed_batches() {
    if boundary.expected_revision() == expected_revision {
      return Some({
        command_key: boundary.command_idempotency_key(),
        expected_revision,
        event_refs: boundary.event_refs(),
        batch_digest: boundary.batch_digest(),
      })
    }
  }
  None
}

///|
pub fn ContestedBatch::command_key(self : ContestedBatch) -> String {
  self.command_key
}

///|
pub fn ContestedBatch::expected_revision(self : ContestedBatch) -> Int64 {
  self.expected_revision
}

///|
pub fn ContestedBatch::event_refs(
  self : ContestedBatch,
) -> ReadOnlyArray[@contracts.RecordRef] {
  self.event_refs
}

///|
pub fn ContestedBatch::batch_digest(
  self : ContestedBatch,
) -> @contracts.ContentDigest {
  self.batch_digest
}

///|
/// Recover the complete ordered event batch and reject a boundary/ref mismatch.
pub fn contested_events(
  replay : @storage.ReplayResult,
  batch : ContestedBatch,
) -> Array[@storage.WorkflowEvent]? {
  let events : Array[@storage.WorkflowEvent] = []
  for expected in batch.event_refs {
    let mut found : @storage.WorkflowEvent? = None
    for event in replay.events() {
      if event.event_ref() == expected {
        found = Some(event)
      }
    }
    guard found is Some(event) else { return None }
    events.push(event)
  }
  if events.is_empty() || events[0].revision() != batch.expected_revision + 1L {
    return None
  }
  for index in 1..<events.length() {
    if events[index].revision() != events[index - 1].revision() + 1L ||
      events[index].sequence() != events[index - 1].sequence() + 1L {
      return None
    }
  }
  Some(events)
}

///|
/// Closed replay evidence for the one durable batch that occupied a contested
/// expected revision.  The winner prefix, rather than the later live head, is
/// the immutable source of historical race receipts.
pub struct LifecycleContest {
  batch : ContestedBatch
  events : ReadOnlyArray[@storage.WorkflowEvent]
  winner_prefix_replay_digest : @contracts.ContentDigest
  winner_head_revision : Int64
  winner_head_digest : @contracts.ContentDigest?
}

///|
/// Recover and validate the exact historical winner at one expected head.
/// `None` deliberately collapses malformed/missing replay evidence; the facade
/// translates that closed implementation failure into its public typed error.
pub fn lifecycle_contest(
  replay : @storage.ReplayResult,
  expected_revision : Int64,
  expected_head_digest : @contracts.ContentDigest?,
) -> LifecycleContest? {
  guard contested_batch(replay, expected_revision) is Some(batch) else {
    return None
  }
  guard contested_events(replay, batch) is Some(events) else { return None }
  if events[0].previous_event_digest() != expected_head_digest {
    return None
  }
  let winner_head_revision = events[events.length() - 1].revision()
  let prefix_option = try replay.verified_prefix(winner_head_revision) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
  guard prefix_option is Some(prefix) else { return None }
  let head = prefix.head()
  if head.revision() != winner_head_revision ||
    head.last_event_digest() !=
    Some(events[events.length() - 1].event_ref().digest()) {
    return None
  }
  Some({
    batch,
    events: ReadOnlyArray::from_array(events),
    winner_prefix_replay_digest: prefix.replay_digest(),
    winner_head_revision,
    winner_head_digest: head.last_event_digest(),
  })
}

///|
pub fn LifecycleContest::batch(self : LifecycleContest) -> ContestedBatch {
  self.batch
}

///|
pub fn LifecycleContest::events(
  self : LifecycleContest,
) -> ReadOnlyArray[@storage.WorkflowEvent] {
  self.events
}

///|
pub fn LifecycleContest::winner_prefix_replay_digest(
  self : LifecycleContest,
) -> @contracts.ContentDigest {
  self.winner_prefix_replay_digest
}

///|
pub fn LifecycleContest::winner_head_revision(self : LifecycleContest) -> Int64 {
  self.winner_head_revision
}

///|
pub fn LifecycleContest::winner_head_digest(
  self : LifecycleContest,
) -> @contracts.ContentDigest? {
  self.winner_head_digest
}
