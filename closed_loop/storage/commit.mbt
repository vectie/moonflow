///|
let commit_magic : Bytes = b"MF4ACMT1"

///|
let batch_magic : Bytes = b"MF4ABAT1"

///|
let guarded_batch_magic : Bytes = b"MF4AGBT1"

///|
/// One validated atomic append request. Its canonical bytes cover the expected
/// revision, command key, complete ordered event sequence, and complete intent
/// set at the single visibility boundary.
pub struct CommitRequest {
  record_version : @contracts.Version
  schema_version : @contracts.Version
  workflow : @contracts.RecordRef
  expected_revision : Int64
  command_idempotency_key : String
  events : ReadOnlyArray[WorkflowEvent]
  intents : ReadOnlyArray[OutboxIntent]
}

///|
fn validate_request_records(
  workflow : @contracts.RecordRef,
  events : Array[WorkflowEvent],
  intents : Array[OutboxIntent],
) -> Unit raise StorageError {
  if events.is_empty() {
    raise ValidationFailure(field="commit_events")
  }
  for index, event in events {
    if !exact_record_equal(workflow, event.workflow) {
      raise ValidationFailure(field="event_workflow")
    }
    if index > 0 {
      let previous = events[index - 1]
      if event.sequence != previous.sequence + 1L {
        raise SequenceGap(
          workflow_id=workflow.id(),
          expected=previous.sequence + 1L,
          actual=event.sequence,
        )
      }
      if event.revision != previous.revision + 1L {
        raise RevisionGap(
          workflow_id=workflow.id(),
          expected=previous.revision + 1L,
          actual=event.revision,
        )
      }
      if event.previous_event_digest != Some(previous.event_ref.digest()) {
        raise DigestMismatch(
          record_kind="workflow_event_chain",
          record_id=event.event_ref.id(),
          expected=previous.event_ref.digest().text(),
          actual=event.previous_event_digest
            .map(value => value.text())
            .unwrap_or("missing"),
        )
      }
    }
    for earlier in 0..<index {
      let prior = events[earlier]
      if record_identity_equal(prior.event_ref, event.event_ref) {
        if prior != event {
          raise IdentityConflict(
            kind=event.event_ref.kind(),
            id=event.event_ref.id(),
            version=event.event_ref.version().text(),
          )
        }
        raise ValidationFailure(field="duplicate_event")
      }
      if prior.idempotency_key == event.idempotency_key {
        raise IdempotencyConflict(key=event.idempotency_key)
      }
    }
  }
  for index, intent in intents {
    if !exact_record_equal(workflow, intent.workflow) {
      raise ValidationFailure(field="intent_workflow")
    }
    for earlier in 0..<index {
      let prior = intents[earlier]
      if record_identity_equal(prior.intent_ref, intent.intent_ref) {
        if prior != intent {
          raise IdentityConflict(
            kind=intent.intent_ref.kind(),
            id=intent.intent_ref.id(),
            version=intent.intent_ref.version().text(),
          )
        }
        raise ValidationFailure(field="duplicate_intent")
      }
      if prior.idempotency_key == intent.idempotency_key {
        raise IdempotencyConflict(key=intent.idempotency_key)
      }
    }
  }
}

///|
pub fn CommitRequest::new(
  record_version : String,
  schema_version : String,
  workflow : @contracts.RecordRef,
  expected_revision : Int64,
  command_idempotency_key : String,
  events : Array[WorkflowEvent],
  intents : Array[OutboxIntent],
) -> CommitRequest raise StorageError {
  let record_version = storage_version(record_version, "commit_request")
  let schema_version = storage_version(schema_version, "commit_request_schema")
  if expected_revision < 0L {
    raise ValidationFailure(field="expected_revision")
  }
  require_storage_text(command_idempotency_key, "command_idempotency_key")
  validate_request_records(workflow, events, intents)
  {
    record_version,
    schema_version,
    workflow,
    expected_revision,
    command_idempotency_key,
    events: ReadOnlyArray::from_array(events.copy()),
    intents: ReadOnlyArray::from_array(intents.copy()),
  }
}

///|
pub fn CommitRequest::record_version(
  self : CommitRequest,
) -> @contracts.Version {
  self.record_version
}

///|
pub fn CommitRequest::schema_version(
  self : CommitRequest,
) -> @contracts.Version {
  self.schema_version
}

///|
pub fn CommitRequest::workflow(self : CommitRequest) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn CommitRequest::expected_revision(self : CommitRequest) -> Int64 {
  self.expected_revision
}

///|
pub fn CommitRequest::command_idempotency_key(self : CommitRequest) -> String {
  self.command_idempotency_key
}

///|
pub fn CommitRequest::events(
  self : CommitRequest,
) -> ReadOnlyArray[WorkflowEvent] {
  self.events
}

///|
pub fn CommitRequest::intents(
  self : CommitRequest,
) -> ReadOnlyArray[OutboxIntent] {
  self.intents
}

///|
pub fn CommitRequest::canonical_bytes(self : CommitRequest) -> Bytes {
  let writer = StorageWriter::new()
  try! writer.write_bytes(commit_magic)
  try! writer.write_string(self.record_version.text())
  try! writer.write_string(self.schema_version.text())
  try! writer.write_bytes(encode_record_ref(self.workflow, false))
  writer.write_int64(self.expected_revision)
  try! writer.write_string(self.command_idempotency_key)
  try! writer.write_count(self.events.length())
  for event in self.events {
    try! writer.write_bytes(event.canonical_bytes())
  }
  try! writer.write_count(self.intents.length())
  for intent in self.intents {
    try! writer.write_bytes(intent.canonical_bytes())
  }
  writer.finish()
}

///|
pub impl Eq for CommitRequest with fn equal(left, right) {
  left.canonical_bytes() == right.canonical_bytes()
}

///|
fn decode_commit_request(bytes : Bytes) -> CommitRequest raise StorageError {
  let reader = StorageReader::new(bytes)
  if reader.read_bytes() != commit_magic {
    raise ValidationFailure(field="commit_magic")
  }
  let record_version = reader.read_string()
  let schema_version = reader.read_string()
  let workflow = decode_record_ref(reader.read_bytes())
  let expected_revision = reader.read_int64()
  let key = reader.read_string()
  let events : Array[WorkflowEvent] = []
  let event_count = reader.read_count()
  for _ in 0..<event_count {
    events.push(decode_event(reader.read_bytes()))
  }
  let intents : Array[OutboxIntent] = []
  let intent_count = reader.read_count()
  for _ in 0..<intent_count {
    intents.push(decode_intent(reader.read_bytes()))
  }
  reader.require_end()
  CommitRequest::new(
    record_version, schema_version, workflow, expected_revision, key, events, intents,
  )
}

///|
/// Stable acknowledgement of one committed batch. It contains no opaque data.
pub struct CommitResult {
  record_version : @contracts.Version
  schema_version : @contracts.Version
  workflow : @contracts.RecordRef
  command_idempotency_key : String
  first_sequence : Int64
  last_sequence : Int64
  workflow_revision : Int64
  event_count : Int64
  intent_count : Int64
  last_event_digest : @contracts.ContentDigest
  batch_digest : @contracts.ContentDigest
} derive(Eq, Debug)

///|
fn result_signing_bytes(value : CommitResult) -> Bytes {
  let writer = StorageWriter::new()
  try! writer.write_string(value.record_version.text())
  try! writer.write_string(value.schema_version.text())
  try! writer.write_bytes(encode_record_ref(value.workflow, false))
  try! writer.write_string(value.command_idempotency_key)
  writer.write_int64(value.first_sequence)
  writer.write_int64(value.last_sequence)
  writer.write_int64(value.workflow_revision)
  writer.write_int64(value.event_count)
  writer.write_int64(value.intent_count)
  try! writer.write_string(value.last_event_digest.text())
  writer.finish()
}

///|
fn build_commit_result(
  request : CommitRequest,
  total_event_count : Int64,
  total_intent_count : Int64,
  batch_digest : @contracts.ContentDigest,
) -> CommitResult {
  let first = request.events[0]
  let last = request.events[request.events.length() - 1]
  {
    record_version: try! storage_version("1.0.0", "commit_result"),
    schema_version: try! storage_version("1.0.0", "commit_result_schema"),
    workflow: request.workflow,
    command_idempotency_key: request.command_idempotency_key,
    first_sequence: first.sequence,
    last_sequence: last.sequence,
    workflow_revision: last.revision,
    event_count: total_event_count,
    intent_count: total_intent_count,
    last_event_digest: last.event_ref.digest(),
    batch_digest,
  }
}

///|
pub fn CommitResult::record_version(self : CommitResult) -> @contracts.Version {
  self.record_version
}

///|
pub fn CommitResult::schema_version(self : CommitResult) -> @contracts.Version {
  self.schema_version
}

///|
pub fn CommitResult::workflow(self : CommitResult) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn CommitResult::command_idempotency_key(self : CommitResult) -> String {
  self.command_idempotency_key
}

///|
pub fn CommitResult::first_sequence(self : CommitResult) -> Int64 {
  self.first_sequence
}

///|
pub fn CommitResult::last_sequence(self : CommitResult) -> Int64 {
  self.last_sequence
}

///|
pub fn CommitResult::workflow_revision(self : CommitResult) -> Int64 {
  self.workflow_revision
}

///|
pub fn CommitResult::event_count(self : CommitResult) -> Int64 {
  self.event_count
}

///|
pub fn CommitResult::intent_count(self : CommitResult) -> Int64 {
  self.intent_count
}

///|
pub fn CommitResult::last_event_digest(
  self : CommitResult,
) -> @contracts.ContentDigest {
  self.last_event_digest
}

///|
pub fn CommitResult::batch_digest(
  self : CommitResult,
) -> @contracts.ContentDigest {
  self.batch_digest
}

///|
priv struct StoredBatch {
  request : CommitRequest
  result : CommitResult
  guards : ReadOnlyArray[WorkflowHeadGuard]
}

///|
/// Replay-visible, domain-neutral proof of one verified stored commit boundary.
/// Construction remains private to storage and is derived only after the
/// stored batch checksum and canonical request/result binding are validated.
pub struct CommittedBatchBoundary {
  command_idempotency_key : String
  expected_revision : Int64
  event_refs : ReadOnlyArray[@contracts.RecordRef]
  intent_refs : ReadOnlyArray[@contracts.RecordRef]
  guards : ReadOnlyArray[WorkflowHeadGuard]
  batch_digest : @contracts.ContentDigest
}

///|
fn committed_batch_boundary(batch : StoredBatch) -> CommittedBatchBoundary {
  {
    command_idempotency_key: batch.request.command_idempotency_key(),
    expected_revision: batch.request.expected_revision(),
    event_refs: ReadOnlyArray::from_array(
      [
        for event in batch.request.events() => event.event_ref()
      ],
    ),
    intent_refs: ReadOnlyArray::from_array(
      [
        for intent in batch.request.intents() => intent.intent_ref()
      ],
    ),
    guards: batch.guards,
    batch_digest: batch.result.batch_digest(),
  }
}

///|
pub fn CommittedBatchBoundary::command_idempotency_key(
  self : CommittedBatchBoundary,
) -> String {
  self.command_idempotency_key
}

///|
pub fn CommittedBatchBoundary::expected_revision(
  self : CommittedBatchBoundary,
) -> Int64 {
  self.expected_revision
}

///|
pub fn CommittedBatchBoundary::event_refs(
  self : CommittedBatchBoundary,
) -> ReadOnlyArray[@contracts.RecordRef] {
  self.event_refs
}

///|
pub fn CommittedBatchBoundary::intent_refs(
  self : CommittedBatchBoundary,
) -> ReadOnlyArray[@contracts.RecordRef] {
  self.intent_refs
}

///|
/// Exact immutable guards stored with this commit boundary. These are replay
/// provenance only and confer no mutation or external-effect authority.
pub fn CommittedBatchBoundary::guards(
  self : CommittedBatchBoundary,
) -> ReadOnlyArray[WorkflowHeadGuard] {
  self.guards
}

///|
pub fn CommittedBatchBoundary::batch_digest(
  self : CommittedBatchBoundary,
) -> @contracts.ContentDigest {
  self.batch_digest
}

///|
fn batch_body(
  request : CommitRequest,
  result : CommitResult,
  guards : ReadOnlyArray[WorkflowHeadGuard],
) -> Bytes {
  let writer = StorageWriter::new()
  try! writer.write_bytes(
    if guards.is_empty() {
      batch_magic
    } else {
      guarded_batch_magic
    },
  )
  try! writer.write_string("1.0.0")
  if !guards.is_empty() {
    try! writer.write_count(guards.length())
    for head_guard in guards {
      try! writer.write_bytes(head_guard.canonical_bytes())
    }
  }
  try! writer.write_bytes(request.canonical_bytes())
  try! writer.write_bytes(result_signing_bytes(result))
  writer.finish()
}

///|
fn make_stored_batch(
  request : CommitRequest,
  total_event_count : Int64,
  total_intent_count : Int64,
) -> StoredBatch {
  make_guarded_stored_batch(
    request,
    ReadOnlyArray::from_array([]),
    total_event_count,
    total_intent_count,
  )
}

///|
fn make_guarded_stored_batch(
  request : CommitRequest,
  guards : ReadOnlyArray[WorkflowHeadGuard],
  total_event_count : Int64,
  total_intent_count : Int64,
) -> StoredBatch {
  let placeholder = @contracts.sha256_digest(b"")
  let provisional = build_commit_result(
    request, total_event_count, total_intent_count, placeholder,
  )
  let digest = @contracts.sha256_digest(
    batch_body(request, provisional, guards),
  )
  {
    request,
    result: build_commit_result(
      request, total_event_count, total_intent_count, digest,
    ),
    guards,
  }
}

///|
fn encode_batch(batch : StoredBatch) -> Bytes {
  let body = batch_body(batch.request, batch.result, batch.guards)
  let writer = StorageWriter::new()
  try! writer.write_bytes(body)
  try! writer.write_string(batch.result.batch_digest.text())
  writer.finish()
}

///|
fn decode_result_signing(
  bytes : Bytes,
  request : CommitRequest,
  batch_digest : @contracts.ContentDigest,
) -> CommitResult raise StorageError {
  let reader = StorageReader::new(bytes)
  let record_version = reader.read_string()
  let schema_version = reader.read_string()
  ignore(storage_version(record_version, "commit_result"))
  ignore(storage_version(schema_version, "commit_result_schema"))
  let workflow = decode_record_ref(reader.read_bytes())
  let command_key = reader.read_string()
  let first_sequence = reader.read_int64()
  let last_sequence = reader.read_int64()
  let workflow_revision = reader.read_int64()
  let event_count = reader.read_int64()
  let intent_count = reader.read_int64()
  let last_event_digest = parse_content_digest(
    reader.read_string(),
    "commit_result",
  )
  reader.require_end()
  let expected = build_commit_result(
    request, event_count, intent_count, batch_digest,
  )
  if !exact_record_equal(workflow, expected.workflow) ||
    command_key != expected.command_idempotency_key ||
    first_sequence != expected.first_sequence ||
    last_sequence != expected.last_sequence ||
    workflow_revision != expected.workflow_revision ||
    last_event_digest != expected.last_event_digest {
    raise ValidationFailure(field="commit_result_binding")
  }
  expected
}

///|
fn decode_batch(bytes : Bytes) -> StoredBatch raise StorageError {
  let outer = StorageReader::new(bytes)
  let body = outer.read_bytes()
  let supplied = parse_content_digest(outer.read_string(), "commit_batch")
  outer.require_end()
  let actual = @contracts.sha256_digest(body)
  if supplied != actual {
    raise DigestMismatch(
      record_kind="commit_batch",
      record_id=supplied.hex(),
      expected=supplied.text(),
      actual=actual.text(),
    )
  }
  let reader = StorageReader::new(body)
  let magic = reader.read_bytes()
  if magic != batch_magic && magic != guarded_batch_magic {
    raise ValidationFailure(field="batch_magic")
  }
  ignore(storage_version(reader.read_string(), "commit_batch"))
  let guards : Array[WorkflowHeadGuard] = []
  if magic == guarded_batch_magic {
    let guard_count = reader.read_count()
    if guard_count == 0 {
      raise ValidationFailure(field="guarded_batch_guards")
    }
    for _ in 0..<guard_count {
      guards.push(decode_workflow_head_guard(reader.read_bytes()))
    }
  }
  let request = decode_commit_request(reader.read_bytes())
  let result_bytes = reader.read_bytes()
  reader.require_end()
  let result = decode_result_signing(result_bytes, request, supplied)
  let batch = { request, result, guards: ReadOnlyArray::from_array(guards) }
  if encode_batch(batch) != bytes {
    raise ValidationFailure(field="noncanonical_batch")
  }
  batch
}
