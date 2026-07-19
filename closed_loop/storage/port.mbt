///|
/// Verified head and cardinality for one exact workflow identity.
pub struct WorkflowHead {
  workflow : @contracts.RecordRef
  sequence : Int64
  revision : Int64
  last_event_digest : @contracts.ContentDigest?
  event_count : Int64
  intent_count : Int64
} derive(Eq, Debug)

///|
pub fn WorkflowHead::workflow(self : WorkflowHead) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn WorkflowHead::sequence(self : WorkflowHead) -> Int64 {
  self.sequence
}

///|
pub fn WorkflowHead::revision(self : WorkflowHead) -> Int64 {
  self.revision
}

///|
pub fn WorkflowHead::last_event_digest(
  self : WorkflowHead,
) -> @contracts.ContentDigest? {
  self.last_event_digest
}

///|
pub fn WorkflowHead::event_count(self : WorkflowHead) -> Int64 {
  self.event_count
}

///|
pub fn WorkflowHead::intent_count(self : WorkflowHead) -> Int64 {
  self.intent_count
}

///|
/// Pure verified replay data. `events` is the full authoritative order;
/// `tail_events` begins after the selected optional checkpoint. The replay
/// digest never depends on a checkpoint.
pub struct ReplayResult {
  record_version : @contracts.Version
  schema_version : @contracts.Version
  workflow : @contracts.RecordRef
  events : ReadOnlyArray[WorkflowEvent]
  intents : ReadOnlyArray[OutboxIntent]
  committed_batches : ReadOnlyArray[CommittedBatchBoundary]
  checkpoint : CheckpointRecord?
  tail_events : ReadOnlyArray[WorkflowEvent]
  head : WorkflowHead
  replay_digest : @contracts.ContentDigest
}

///|
pub fn ReplayResult::record_version(self : ReplayResult) -> @contracts.Version {
  self.record_version
}

///|
pub fn ReplayResult::schema_version(self : ReplayResult) -> @contracts.Version {
  self.schema_version
}

///|
pub fn ReplayResult::workflow(self : ReplayResult) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn ReplayResult::events(
  self : ReplayResult,
) -> ReadOnlyArray[WorkflowEvent] {
  self.events
}

///|
pub fn ReplayResult::intents(
  self : ReplayResult,
) -> ReadOnlyArray[OutboxIntent] {
  self.intents
}

///|
/// Exact verified commit boundaries retained by replay. These boundaries are
/// storage metadata only and assign no domain meaning to their event kinds.
pub fn ReplayResult::committed_batches(
  self : ReplayResult,
) -> ReadOnlyArray[CommittedBatchBoundary] {
  self.committed_batches
}

///|
pub fn ReplayResult::checkpoint(self : ReplayResult) -> CheckpointRecord? {
  self.checkpoint
}

///|
pub fn ReplayResult::tail_events(
  self : ReplayResult,
) -> ReadOnlyArray[WorkflowEvent] {
  self.tail_events
}

///|
pub fn ReplayResult::head(self : ReplayResult) -> WorkflowHead {
  self.head
}

///|
pub fn ReplayResult::replay_digest(
  self : ReplayResult,
) -> @contracts.ContentDigest {
  self.replay_digest
}

///|
/// Derive a storage-verified prefix only at an exact committed batch boundary.
/// This is a read-only replay operation and confers no workflow authority.
pub fn ReplayResult::verified_prefix(
  self : ReplayResult,
  revision : Int64,
) -> ReplayResult raise StorageError {
  if revision < 0L || revision > self.head.revision {
    raise ValidationFailure(field="replay_prefix_revision")
  }
  if revision > 0L &&
    !self.committed_batches.any(batch => {
      batch.expected_revision() + batch.event_refs().length().to_int64() ==
      revision
    }) {
    raise ValidationFailure(field="replay_prefix_batch_boundary")
  }
  let events = [
    for event in self.events if event.revision() <= revision => event
  ]
  let event_refs = [ for event in events => event.event_ref() ]
  let intents = [
    for intent in self.intents if event_refs.any(value => {
      value == intent.causative_event()
    }) => intent
  ]
  let batches = [
    for batch in self.committed_batches if batch.expected_revision() +
    batch.event_refs().length().to_int64() <=
    revision => batch
  ]
  let last_digest = events.last().map(event => event.event_ref().digest())
  {
    record_version: self.record_version,
    schema_version: self.schema_version,
    workflow: self.workflow,
    events: ReadOnlyArray::from_array(events),
    intents: ReadOnlyArray::from_array(intents),
    committed_batches: ReadOnlyArray::from_array(batches),
    checkpoint: None,
    tail_events: ReadOnlyArray::from_array(events.copy()),
    head: {
      workflow: self.workflow,
      sequence: events.length().to_int64(),
      revision,
      last_event_digest: last_digest,
      event_count: events.length().to_int64(),
      intent_count: intents.length().to_int64(),
    },
    replay_digest: replay_digest_for(self.workflow, events),
  }
}

///|
/// Domain-neutral durable storage port. It exposes atomic commit, verified
/// replay/checkpoints, and read-only head/query operations only.
pub(open) trait StoragePort {
  fn commit(Self, CommitRequest) -> CommitResult raise StorageError
  fn replay(Self, @contracts.RecordRef) -> ReplayResult raise StorageError
  fn write_checkpoint(Self, CheckpointRecord) -> Unit raise StorageError
  fn read_checkpoint(Self, @contracts.RecordRef) -> CheckpointRecord? raise StorageError
  fn head(Self, @contracts.RecordRef) -> WorkflowHead raise StorageError
  fn events(Self, @contracts.RecordRef) -> ReadOnlyArray[WorkflowEvent] raise StorageError
  fn intents(Self, @contracts.RecordRef) -> ReadOnlyArray[OutboxIntent] raise StorageError
}

///|
/// Additive capability for a mutation whose independent workflow heads are
/// checked in the same storage transaction and linearization point.
pub(open) trait GuardedStoragePort: StoragePort {
  fn guarded_commit(Self, GuardedCommitRequest) -> GuardedCommitOutcome raise StorageError
}

///|
/// Sealed capability implemented only by storage-owned wrappers constructed
/// from a current trusted registry activation receipt. External
/// `GuardedStoragePort` implementations cannot satisfy the official lifecycle
/// mutation boundary.
pub trait RegistryBoundGuardedStoragePort: GuardedStoragePort {
  /// Exact operation profile selected by this bound capability.
  fn selected_guard_profile(Self) -> GuardProfile raise StorageError

  /// Latest append-only profile registry visible to this capability.
  fn registered_guard_profiles(Self) -> ReadOnlyArray[GuardProfile] raise StorageError

  /// Replay one guard workflow from the root fixed by the sealed registry
  /// profile selected for this operation. This is read-only provenance; the
  /// subsequent guarded commit still performs the authoritative exact profile
  /// and atomic head comparison.
  fn replay_registered_guard(Self, @contracts.RecordRef) -> ReplayResult raise StorageError
}

///|
/// Sealed additive capability for recovery-aware callers. Existing guarded
/// commit contracts remain unchanged; only registry-bound storage wrappers can
/// reveal whether the exact command was newly published or already durable.
pub trait ClassifiedRegistryBoundGuardedStoragePort: RegistryBoundGuardedStoragePort {
  fn classified_guarded_commit(Self, GuardedCommitRequest) -> ClassifiedGuardedCommitOutcome raise StorageError
}
