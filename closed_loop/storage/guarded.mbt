///|
let workflow_head_guard_magic : Bytes = b"MF4AGRD1"

///|
let guarded_commit_request_magic : Bytes = b"MF4AGCR1"

///|
let guard_conflict_receipt_magic : Bytes = b"MF4AGCF1"

///|
/// Exact storage evidence that must still identify a workflow head when a
/// guarded mutation is linearized. Construction is validated, but the value
/// itself grants no domain authority.
pub struct WorkflowHeadGuard {
  workflow : @contracts.RecordRef
  expected_revision : Int64
  expected_head_digest : @contracts.ContentDigest?
  expected_replay_digest : @contracts.ContentDigest
  canonical : Bytes
}

///|
pub fn WorkflowHeadGuard::new(
  workflow : @contracts.RecordRef,
  expected_revision : Int64,
  expected_head_digest : @contracts.ContentDigest?,
  expected_replay_digest : @contracts.ContentDigest,
) -> WorkflowHeadGuard raise StorageError {
  if expected_revision < 0L ||
    (expected_revision == 0L) != (expected_head_digest is None) {
    raise ValidationFailure(field="workflow_head_guard_position")
  }
  let writer = StorageWriter::new()
  try! writer.write_bytes(workflow_head_guard_magic)
  try! writer.write_string("1.0.0")
  try! writer.write_bytes(encode_record_ref(workflow, false))
  writer.write_int64(expected_revision)
  match expected_head_digest {
    None => writer.write_byte(0)
    Some(digest) => {
      writer.write_byte(1)
      try! writer.write_string(digest.text())
    }
  }
  try! writer.write_string(expected_replay_digest.text())
  {
    workflow,
    expected_revision,
    expected_head_digest,
    expected_replay_digest,
    canonical: writer.finish(),
  }
}

///|
fn decode_workflow_head_guard(
  bytes : Bytes,
) -> WorkflowHeadGuard raise StorageError {
  let reader = StorageReader::new(bytes)
  if reader.read_bytes() != workflow_head_guard_magic {
    raise ValidationFailure(field="workflow_head_guard_magic")
  }
  ignore(storage_version(reader.read_string(), "workflow_head_guard"))
  let workflow = decode_record_ref(reader.read_bytes())
  let expected_revision = reader.read_int64()
  let expected_head_digest = match reader.read_byte() {
    0 => None
    1 => Some(parse_content_digest(reader.read_string(), "workflow_head_guard"))
    _ => raise ValidationFailure(field="workflow_head_guard_digest_tag")
  }
  let expected_replay_digest = parse_content_digest(
    reader.read_string(),
    "workflow_head_guard_replay_digest",
  )
  reader.require_end()
  let value = WorkflowHeadGuard::new(
    workflow, expected_revision, expected_head_digest, expected_replay_digest,
  )
  if value.canonical != bytes {
    raise ValidationFailure(field="noncanonical_workflow_head_guard")
  }
  value
}

///|
pub fn WorkflowHeadGuard::workflow(
  self : WorkflowHeadGuard,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn WorkflowHeadGuard::expected_revision(self : WorkflowHeadGuard) -> Int64 {
  self.expected_revision
}

///|
pub fn WorkflowHeadGuard::expected_head_digest(
  self : WorkflowHeadGuard,
) -> @contracts.ContentDigest? {
  self.expected_head_digest
}

///|
pub fn WorkflowHeadGuard::expected_replay_digest(
  self : WorkflowHeadGuard,
) -> @contracts.ContentDigest {
  self.expected_replay_digest
}

///|
pub fn WorkflowHeadGuard::canonical_bytes(self : WorkflowHeadGuard) -> Bytes {
  self.canonical
}

///|
pub impl Eq for WorkflowHeadGuard with fn equal(left, right) {
  left.canonical == right.canonical
}

///|
/// One ordinary mutation plus the exact independent workflow heads that must
/// remain unchanged at its storage linearization point.
pub struct GuardedCommitRequest {
  mutation : CommitRequest
  guards : ReadOnlyArray[WorkflowHeadGuard]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn GuardedCommitRequest::new(
  mutation : CommitRequest,
  guards : Array[WorkflowHeadGuard],
) -> GuardedCommitRequest raise StorageError {
  if guards.is_empty() {
    raise ValidationFailure(field="guarded_commit_guards")
  }
  for index, head_guard in guards {
    if exact_record_equal(mutation.workflow, head_guard.workflow) {
      raise ValidationFailure(field="guarded_commit_independent_workflow")
    }
    for prior in 0..<index {
      if exact_record_equal(guards[prior].workflow, head_guard.workflow) {
        raise ValidationFailure(field="guarded_commit_duplicate_workflow")
      }
    }
  }
  let writer = StorageWriter::new()
  try! writer.write_bytes(guarded_commit_request_magic)
  try! writer.write_string("1.0.0")
  try! writer.write_bytes(mutation.canonical_bytes())
  try! writer.write_count(guards.length())
  for head_guard in guards {
    try! writer.write_bytes(head_guard.canonical_bytes())
  }
  let canonical = writer.finish()
  {
    mutation,
    guards: ReadOnlyArray::from_array(guards.copy()),
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn GuardedCommitRequest::mutation(
  self : GuardedCommitRequest,
) -> CommitRequest {
  self.mutation
}

///|
pub fn GuardedCommitRequest::guards(
  self : GuardedCommitRequest,
) -> ReadOnlyArray[WorkflowHeadGuard] {
  self.guards
}

///|
pub fn GuardedCommitRequest::canonical_bytes(
  self : GuardedCommitRequest,
) -> Bytes {
  self.canonical
}

///|
pub fn GuardedCommitRequest::digest(
  self : GuardedCommitRequest,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub impl Eq for GuardedCommitRequest with fn equal(left, right) {
  left.canonical == right.canonical
}

///|
/// Non-durable observation proving why one guarded mutation was rejected. It
/// grants no workflow, lease, retry, reconciliation, or effect authority.
pub struct GuardConflictReceipt {
  request_digest : @contracts.ContentDigest
  mutation_workflow : @contracts.RecordRef
  command_idempotency_key : String
  guard_workflow : @contracts.RecordRef
  expected_revision : Int64
  expected_head_digest : @contracts.ContentDigest?
  expected_replay_digest : @contracts.ContentDigest
  actual_revision : Int64
  actual_head_digest : @contracts.ContentDigest?
  actual_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn make_guard_conflict_receipt(
  request : GuardedCommitRequest,
  head_guard : WorkflowHeadGuard,
  actual : ReplayResult,
) -> GuardConflictReceipt raise StorageError {
  if !exact_record_equal(actual.workflow(), head_guard.workflow) ||
    !exact_record_equal(actual.head().workflow(), head_guard.workflow) {
    raise ValidationFailure(field="guarded_commit_actual_workflow")
  }
  let head = actual.head()
  let writer = StorageWriter::new()
  writer.write_bytes(guard_conflict_receipt_magic)
  writer.write_string("1.0.0")
  writer.write_string(request.digest.text())
  writer.write_bytes(encode_record_ref(request.mutation.workflow, false))
  writer.write_string(request.mutation.command_idempotency_key)
  writer.write_bytes(encode_record_ref(head_guard.workflow, false))
  writer.write_int64(head_guard.expected_revision)
  write_optional_digest(writer, head_guard.expected_head_digest)
  writer.write_string(head_guard.expected_replay_digest.text())
  writer.write_int64(head.revision())
  write_optional_digest(writer, head.last_event_digest())
  writer.write_string(actual.replay_digest().text())
  let canonical = writer.finish()
  {
    request_digest: request.digest,
    mutation_workflow: request.mutation.workflow,
    command_idempotency_key: request.mutation.command_idempotency_key,
    guard_workflow: head_guard.workflow,
    expected_revision: head_guard.expected_revision,
    expected_head_digest: head_guard.expected_head_digest,
    expected_replay_digest: head_guard.expected_replay_digest,
    actual_revision: head.revision(),
    actual_head_digest: head.last_event_digest(),
    actual_replay_digest: actual.replay_digest(),
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn GuardConflictReceipt::request_digest(
  self : GuardConflictReceipt,
) -> @contracts.ContentDigest {
  self.request_digest
}

///|
pub fn GuardConflictReceipt::mutation_workflow(
  self : GuardConflictReceipt,
) -> @contracts.RecordRef {
  self.mutation_workflow
}

///|
pub fn GuardConflictReceipt::command_idempotency_key(
  self : GuardConflictReceipt,
) -> String {
  self.command_idempotency_key
}

///|
pub fn GuardConflictReceipt::guard_workflow(
  self : GuardConflictReceipt,
) -> @contracts.RecordRef {
  self.guard_workflow
}

///|
pub fn GuardConflictReceipt::expected_revision(
  self : GuardConflictReceipt,
) -> Int64 {
  self.expected_revision
}

///|
pub fn GuardConflictReceipt::expected_head_digest(
  self : GuardConflictReceipt,
) -> @contracts.ContentDigest? {
  self.expected_head_digest
}

///|
pub fn GuardConflictReceipt::expected_replay_digest(
  self : GuardConflictReceipt,
) -> @contracts.ContentDigest {
  self.expected_replay_digest
}

///|
pub fn GuardConflictReceipt::actual_revision(
  self : GuardConflictReceipt,
) -> Int64 {
  self.actual_revision
}

///|
pub fn GuardConflictReceipt::actual_head_digest(
  self : GuardConflictReceipt,
) -> @contracts.ContentDigest? {
  self.actual_head_digest
}

///|
pub fn GuardConflictReceipt::actual_replay_digest(
  self : GuardConflictReceipt,
) -> @contracts.ContentDigest {
  self.actual_replay_digest
}

///|
pub fn GuardConflictReceipt::canonical_bytes(
  self : GuardConflictReceipt,
) -> Bytes {
  self.canonical
}

///|
pub fn GuardConflictReceipt::digest(
  self : GuardConflictReceipt,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// A rejection observation is current only while the same exact actual guard
/// replay remains authoritative.
pub fn GuardConflictReceipt::validate_current(
  self : GuardConflictReceipt,
  replay : ReplayResult,
) -> Unit raise StorageError {
  if !exact_record_equal(replay.workflow(), self.guard_workflow) ||
    !exact_record_equal(replay.head().workflow(), self.guard_workflow) {
    raise ValidationFailure(field="guard_conflict_receipt_workflow")
  }
  let head = replay.head()
  if head.revision() != self.actual_revision ||
    head.last_event_digest() != self.actual_head_digest ||
    replay.replay_digest() != self.actual_replay_digest {
    raise ValidationFailure(field="guard_conflict_receipt_not_current")
  }
}

///|
pub(all) enum GuardedCommitOutcome {
  GuardedCommitSucceeded(CommitResult)
  GuardedCommitRejected(GuardConflictReceipt)
}

///|
/// Additive publication classification for recovery protocols that must
/// distinguish the one storage call that made a batch visible from an exact
/// idempotent replay. Neither success variant is external-effect authority.
pub(all) enum ClassifiedGuardedCommitOutcome {
  FreshlyApplied(CommitResult)
  AlreadyCommitted(CommitResult)
  GuardRejected(GuardConflictReceipt)
}

///|
fn guard_matches_replay(
  head_guard : WorkflowHeadGuard,
  replay : ReplayResult,
) -> Bool {
  exact_record_equal(replay.workflow(), head_guard.workflow) &&
  exact_record_equal(replay.head().workflow(), head_guard.workflow) &&
  replay.head().revision() == head_guard.expected_revision &&
  replay.head().last_event_digest() == head_guard.expected_head_digest &&
  replay.replay_digest() == head_guard.expected_replay_digest
}

///|
fn prepare_guarded_commit(
  mutation_batches : Array[StoredBatch],
  guard_replays : Array[ReplayResult],
  request : GuardedCommitRequest,
) -> (StoredBatch?, StoredBatch?, GuardConflictReceipt?) raise StorageError {
  validate_batches(mutation_batches)
  match
    find_command_batch(
      mutation_batches,
      request.mutation.command_idempotency_key,
    ) {
    Some(existing) => {
      if existing.request == request.mutation &&
        existing.guards == request.guards {
        return (Some(existing), None, None)
      }
      raise IdempotencyConflict(key=request.mutation.command_idempotency_key)
    }
    None => ()
  }
  if guard_replays.length() != request.guards.length() {
    raise ValidationFailure(field="guarded_commit_guard_store_count")
  }
  for index, head_guard in request.guards {
    let actual = guard_replays[index]
    if !guard_matches_replay(head_guard, actual) {
      return (
        None,
        None,
        Some(make_guard_conflict_receipt(request, head_guard, actual)),
      )
    }
  }
  match prepare_commit(mutation_batches, request.mutation) {
    (Some(_), None) =>
      raise ValidationFailure(field="guarded_commit_idempotency_classification")
    (None, Some(prepared)) => {
      let batch = make_guarded_stored_batch(
        prepared.request,
        request.guards,
        prepared.result.event_count,
        prepared.result.intent_count,
      )
      (None, Some(batch), None)
    }
    _ => raise ValidationFailure(field="guarded_commit_classification")
  }
}
