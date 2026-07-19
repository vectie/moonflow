///|
/// A canonical request to schedule one retry attempt.
pub struct RetryScheduleRequestV2 {
  request_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  receipt_ref : @contracts.RecordRef
  receipt_digest : @contracts.ContentDigest
  receipt_bytes : Bytes
  policy_ref : @contracts.RecordRef
  policy_digest : @contracts.ContentDigest
  policy_bytes : Bytes
  timing_digest : @contracts.ContentDigest
  timing_bytes : Bytes
  due_at : Int64
  attempt_count : Int64
  retry_count : Int64
  retry_ordinal : Int64
  cause_key : String
  requested_work_ref : @contracts.RecordRef
  requested_work_digest : @contracts.ContentDigest
  logical_attempt_id : String
  logical_attempt_version : String
  logical_effect_id : String
  logical_effect_version : String
  artifact_digest : @contracts.ContentDigest
  child_attempt_request_ref : @contracts.RecordRef
  child_attempt_id : String
  child_attempt_ordinal : Int64
  child_attempt_idempotency_key : String
  child_schedule_request_ref : @contracts.RecordRef
  schedule_id : String
  schedule_idempotency_key : String
  source_schedule_deadline : Int64?
  admission_governance_deadline : Int64
  admission_controls_deadline : Int64
  requested_schedule_deadline : Int64
  governance_deadline : Int64?
  effective_deadline : Int64
  prefix_head_ref : @contracts.RecordRef
  prefix_head_digest : @contracts.ContentDigest
  prefix_sequence : Int64
  prefix_revision : Int64
  prefix_replay_digest : @contracts.ContentDigest
  command_idempotency_key : String
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn retry_schedule_min(left : Int64, right : Int64) -> Int64 {
  if left < right {
    left
  } else {
    right
  }
}

///|
/// Immutable replay accessors.
pub fn RetryScheduleRequestV2::request_ref(
  self : RetryScheduleRequestV2,
) -> @contracts.RecordRef {
  self.request_ref
}

///|
pub fn RetryScheduleRequestV2::workflow(
  self : RetryScheduleRequestV2,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn RetryScheduleRequestV2::receipt_ref(
  self : RetryScheduleRequestV2,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn RetryScheduleRequestV2::receipt_digest(
  self : RetryScheduleRequestV2,
) -> @contracts.ContentDigest {
  self.receipt_digest
}

///|
pub fn RetryScheduleRequestV2::receipt_bytes(
  self : RetryScheduleRequestV2,
) -> Bytes {
  self.receipt_bytes
}

///|
pub fn RetryScheduleRequestV2::policy_ref(
  self : RetryScheduleRequestV2,
) -> @contracts.RecordRef {
  self.policy_ref
}

///|
pub fn RetryScheduleRequestV2::policy_digest(
  self : RetryScheduleRequestV2,
) -> @contracts.ContentDigest {
  self.policy_digest
}

///|
pub fn RetryScheduleRequestV2::policy_bytes(
  self : RetryScheduleRequestV2,
) -> Bytes {
  self.policy_bytes
}

///|
pub fn RetryScheduleRequestV2::timing_digest(
  self : RetryScheduleRequestV2,
) -> @contracts.ContentDigest {
  self.timing_digest
}

///|
pub fn RetryScheduleRequestV2::timing_bytes(
  self : RetryScheduleRequestV2,
) -> Bytes {
  self.timing_bytes
}

///|
pub fn RetryScheduleRequestV2::due_at(self : RetryScheduleRequestV2) -> Int64 {
  self.due_at
}

///|
pub fn RetryScheduleRequestV2::attempt_count(
  self : RetryScheduleRequestV2,
) -> Int64 {
  self.attempt_count
}

///|
pub fn RetryScheduleRequestV2::retry_count(
  self : RetryScheduleRequestV2,
) -> Int64 {
  self.retry_count
}

///|
pub fn RetryScheduleRequestV2::retry_ordinal(
  self : RetryScheduleRequestV2,
) -> Int64 {
  self.retry_ordinal
}

///|
pub fn RetryScheduleRequestV2::cause_key(
  self : RetryScheduleRequestV2,
) -> String {
  self.cause_key
}

///|
pub fn RetryScheduleRequestV2::requested_work_ref(
  self : RetryScheduleRequestV2,
) -> @contracts.RecordRef {
  self.requested_work_ref
}

///|
pub fn RetryScheduleRequestV2::requested_work_digest(
  self : RetryScheduleRequestV2,
) -> @contracts.ContentDigest {
  self.requested_work_digest
}

///|
pub fn RetryScheduleRequestV2::logical_attempt_id(
  self : RetryScheduleRequestV2,
) -> String {
  self.logical_attempt_id
}

///|
pub fn RetryScheduleRequestV2::logical_attempt_version(
  self : RetryScheduleRequestV2,
) -> String {
  self.logical_attempt_version
}

///|
pub fn RetryScheduleRequestV2::logical_effect_id(
  self : RetryScheduleRequestV2,
) -> String {
  self.logical_effect_id
}

///|
pub fn RetryScheduleRequestV2::logical_effect_version(
  self : RetryScheduleRequestV2,
) -> String {
  self.logical_effect_version
}

///|
pub fn RetryScheduleRequestV2::artifact_digest(
  self : RetryScheduleRequestV2,
) -> @contracts.ContentDigest {
  self.artifact_digest
}

///|
pub fn RetryScheduleRequestV2::child_attempt_request_ref(
  self : RetryScheduleRequestV2,
) -> @contracts.RecordRef {
  self.child_attempt_request_ref
}

///|
pub fn RetryScheduleRequestV2::child_attempt_id(
  self : RetryScheduleRequestV2,
) -> String {
  self.child_attempt_id
}

///|
pub fn RetryScheduleRequestV2::child_attempt_ordinal(
  self : RetryScheduleRequestV2,
) -> Int64 {
  self.child_attempt_ordinal
}

///|
pub fn RetryScheduleRequestV2::child_attempt_idempotency_key(
  self : RetryScheduleRequestV2,
) -> String {
  self.child_attempt_idempotency_key
}

///|
pub fn RetryScheduleRequestV2::child_schedule_request_ref(
  self : RetryScheduleRequestV2,
) -> @contracts.RecordRef {
  self.child_schedule_request_ref
}

///|
pub fn RetryScheduleRequestV2::schedule_id(
  self : RetryScheduleRequestV2,
) -> String {
  self.schedule_id
}

///|
pub fn RetryScheduleRequestV2::schedule_idempotency_key(
  self : RetryScheduleRequestV2,
) -> String {
  self.schedule_idempotency_key
}

///|
pub fn RetryScheduleRequestV2::source_schedule_deadline(
  self : RetryScheduleRequestV2,
) -> Int64? {
  self.source_schedule_deadline
}

///|
pub fn RetryScheduleRequestV2::admission_governance_deadline(
  self : RetryScheduleRequestV2,
) -> Int64 {
  self.admission_governance_deadline
}

///|
pub fn RetryScheduleRequestV2::admission_controls_deadline(
  self : RetryScheduleRequestV2,
) -> Int64 {
  self.admission_controls_deadline
}

///|
pub fn RetryScheduleRequestV2::requested_schedule_deadline(
  self : RetryScheduleRequestV2,
) -> Int64 {
  self.requested_schedule_deadline
}

///|
pub fn RetryScheduleRequestV2::governance_deadline(
  self : RetryScheduleRequestV2,
) -> Int64? {
  self.governance_deadline
}

///|
pub fn RetryScheduleRequestV2::effective_deadline(
  self : RetryScheduleRequestV2,
) -> Int64 {
  self.effective_deadline
}

///|
pub fn RetryScheduleRequestV2::prefix_head_ref(
  self : RetryScheduleRequestV2,
) -> @contracts.RecordRef {
  self.prefix_head_ref
}

///|
pub fn RetryScheduleRequestV2::prefix_head_digest(
  self : RetryScheduleRequestV2,
) -> @contracts.ContentDigest {
  self.prefix_head_digest
}

///|
pub fn RetryScheduleRequestV2::prefix_sequence(
  self : RetryScheduleRequestV2,
) -> Int64 {
  self.prefix_sequence
}

///|
pub fn RetryScheduleRequestV2::prefix_revision(
  self : RetryScheduleRequestV2,
) -> Int64 {
  self.prefix_revision
}

///|
pub fn RetryScheduleRequestV2::prefix_replay_digest(
  self : RetryScheduleRequestV2,
) -> @contracts.ContentDigest {
  self.prefix_replay_digest
}

///|
pub fn RetryScheduleRequestV2::command_idempotency_key(
  self : RetryScheduleRequestV2,
) -> String {
  self.command_idempotency_key
}

///|
pub fn RetryScheduleRequestV2::canonical_bytes(
  self : RetryScheduleRequestV2,
) -> Bytes {
  self.canonical
}

///|
pub fn RetryScheduleRequestV2::digest(
  self : RetryScheduleRequestV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn RetryScheduleRequestV2::new(
  request_id : String,
  workflow : @contracts.RecordRef,
  receipt_ref : @contracts.RecordRef,
  receipt_digest : @contracts.ContentDigest,
  receipt_bytes : Bytes,
  policy_ref : @contracts.RecordRef,
  policy_digest : @contracts.ContentDigest,
  policy_bytes : Bytes,
  timing_digest : @contracts.ContentDigest,
  timing_bytes : Bytes,
  due_at : Int64,
  attempt_count : Int64,
  retry_count : Int64,
  retry_ordinal : Int64,
  cause_key : String,
  requested_work_ref : @contracts.RecordRef,
  requested_work_digest : @contracts.ContentDigest,
  logical_attempt_id : String,
  logical_attempt_version : String,
  logical_effect_id : String,
  logical_effect_version : String,
  artifact_digest : @contracts.ContentDigest,
  child_attempt_id : String,
  child_attempt_ordinal : Int64,
  child_attempt_idempotency_key : String,
  schedule_id : String,
  schedule_idempotency_key : String,
  source_schedule_deadline : Int64?,
  admission_governance_deadline : Int64,
  admission_controls_deadline : Int64,
  requested_schedule_deadline : Int64,
  governance_deadline : Int64?,
  prefix_head_ref : @contracts.RecordRef,
  prefix_head_digest : @contracts.ContentDigest,
  prefix_sequence : Int64,
  prefix_revision : Int64,
  prefix_replay_digest : @contracts.ContentDigest,
  command_idempotency_key : String,
) -> RetryScheduleRequestV2 raise RetryAuthorityError {
  require_text(request_id, "request_id")
  require_text(cause_key, "cause_key")
  require_text(logical_attempt_id, "logical_attempt_id")
  require_text(logical_attempt_version, "logical_attempt_version")
  require_text(logical_effect_id, "logical_effect_id")
  require_text(logical_effect_version, "logical_effect_version")
  require_text(child_attempt_id, "child_attempt_id")
  require_text(child_attempt_idempotency_key, "child_attempt_idempotency_key")
  require_text(schedule_id, "schedule_id")
  require_text(schedule_idempotency_key, "schedule_idempotency_key")
  require_text(command_idempotency_key, "command_idempotency_key")
  if receipt_ref.digest() != receipt_digest {
    raise IdentityMismatch(field="receipt_ref")
  }
  if receipt_digest != @contracts.sha256_digest(receipt_bytes) {
    raise DigestMismatch(field="receipt_bytes")
  }
  if policy_ref.digest() != policy_digest {
    raise IdentityMismatch(field="policy_ref")
  }
  if policy_digest != @contracts.sha256_digest(policy_bytes) {
    raise DigestMismatch(field="policy_bytes")
  }
  if timing_digest != @contracts.sha256_digest(timing_bytes) {
    raise DigestMismatch(field="timing_bytes")
  }
  if requested_work_ref.digest() != requested_work_digest {
    raise IdentityMismatch(field="requested_work_ref")
  }
  if prefix_head_ref.digest() != prefix_head_digest {
    raise IdentityMismatch(field="prefix_head_ref")
  }
  if attempt_count <= 0 {
    raise BoundViolation(field="attempt_count")
  }
  if retry_count < 0 {
    raise BoundViolation(field="retry_count")
  }
  if retry_ordinal != retry_count {
    raise BoundViolation(field="retry_ordinal")
  }
  if child_attempt_ordinal != attempt_count + 1 {
    raise BoundViolation(field="child_attempt_ordinal")
  }
  if due_at < 0 {
    raise BoundViolation(field="due_at")
  }
  if prefix_sequence < 0 {
    raise BoundViolation(field="prefix_sequence")
  }
  if prefix_revision < 0 {
    raise BoundViolation(field="prefix_revision")
  }
  if admission_governance_deadline < due_at {
    raise BoundViolation(field="admission_governance_deadline")
  }
  if admission_controls_deadline < due_at {
    raise BoundViolation(field="admission_controls_deadline")
  }
  if requested_schedule_deadline < due_at {
    raise BoundViolation(field="requested_schedule_deadline")
  }
  match source_schedule_deadline {
    Some(value) if value < due_at =>
      raise BoundViolation(field="source_schedule_deadline")
    _ => ()
  }
  match governance_deadline {
    Some(value) if value <= due_at =>
      raise BoundViolation(field="governance_deadline")
    _ => ()
  }
  let mut effective_deadline = retry_schedule_min(
    requested_schedule_deadline,
    retry_schedule_min(
      admission_governance_deadline, admission_controls_deadline,
    ),
  )
  match source_schedule_deadline {
    Some(value) =>
      effective_deadline = retry_schedule_min(effective_deadline, value)
    None => ()
  }
  match governance_deadline {
    Some(value) =>
      effective_deadline = retry_schedule_min(effective_deadline, value - 1)
    None => ()
  }
  let child_attempt_request_ref = retry_child_attempt_request_ref_v2(
    child_attempt_id, workflow, child_attempt_ordinal, child_attempt_idempotency_key,
    requested_work_digest,
  )
  let child_schedule_request_ref = retry_child_schedule_request_ref_v2(
    schedule_id, workflow, due_at, schedule_idempotency_key, requested_work_digest,
  )
  let writer = RetryWriter::new()
  writer.string("FLOW7/RETRY-SCHEDULE-REQUEST-V2/2.0.0")
  writer.string("2.0.0")
  writer.string(request_id)
  write_ref(writer, workflow)
  write_ref(writer, receipt_ref)
  writer.string(receipt_digest.text())
  writer.bytes(receipt_bytes)
  write_ref(writer, policy_ref)
  writer.string(policy_digest.text())
  writer.bytes(policy_bytes)
  writer.string(timing_digest.text())
  writer.bytes(timing_bytes)
  writer.int64(due_at)
  writer.int64(attempt_count)
  writer.int64(retry_count)
  writer.int64(retry_ordinal)
  writer.string(cause_key)
  write_ref(writer, requested_work_ref)
  writer.string(requested_work_digest.text())
  writer.string(logical_attempt_id)
  writer.string(logical_attempt_version)
  writer.string(logical_effect_id)
  writer.string(logical_effect_version)
  writer.string(artifact_digest.text())
  write_ref(writer, child_attempt_request_ref)
  writer.string(child_attempt_id)
  writer.int64(child_attempt_ordinal)
  writer.string(child_attempt_idempotency_key)
  write_ref(writer, child_schedule_request_ref)
  writer.string(schedule_id)
  writer.string(schedule_idempotency_key)
  writer.optional_int64(source_schedule_deadline)
  writer.int64(admission_governance_deadline)
  writer.int64(admission_controls_deadline)
  writer.int64(requested_schedule_deadline)
  writer.optional_int64(governance_deadline)
  writer.int64(effective_deadline)
  write_ref(writer, prefix_head_ref)
  writer.string(prefix_head_digest.text())
  writer.int64(prefix_sequence)
  writer.int64(prefix_revision)
  writer.string(prefix_replay_digest.text())
  writer.string(command_idempotency_key)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  let request_ref = proposal_ref(
    "retry-schedule-request-v2", request_id, digest,
  )
  {
    request_ref,
    workflow,
    receipt_ref,
    receipt_digest,
    receipt_bytes,
    policy_ref,
    policy_digest,
    policy_bytes,
    timing_digest,
    timing_bytes,
    due_at,
    attempt_count,
    retry_count,
    retry_ordinal,
    cause_key,
    requested_work_ref,
    requested_work_digest,
    logical_attempt_id,
    logical_attempt_version,
    logical_effect_id,
    logical_effect_version,
    artifact_digest,
    child_attempt_request_ref,
    child_attempt_id,
    child_attempt_ordinal,
    child_attempt_idempotency_key,
    child_schedule_request_ref,
    schedule_id,
    schedule_idempotency_key,
    source_schedule_deadline,
    admission_governance_deadline,
    admission_controls_deadline,
    requested_schedule_deadline,
    governance_deadline,
    effective_deadline,
    prefix_head_ref,
    prefix_head_digest,
    prefix_sequence,
    prefix_revision,
    prefix_replay_digest,
    command_idempotency_key,
    canonical,
    digest,
  }
}

///|
pub fn RetryScheduleRequestV2::decode(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
) -> RetryScheduleRequestV2 raise RetryAuthorityError {
  let reader = RetryReader::new(bytes)
  if reader.string() != "FLOW7/RETRY-SCHEDULE-REQUEST-V2/2.0.0" {
    raise Malformed(field="tag")
  }
  if reader.string() != "2.0.0" {
    raise Malformed(field="version")
  }
  let request_id = reader.string()
  let workflow = read_ref(reader)
  let receipt_ref = read_ref(reader)
  let receipt_digest = read_digest(reader)
  let receipt_bytes = reader.bytes()
  let policy_ref = read_ref(reader)
  let policy_digest = read_digest(reader)
  let policy_bytes = reader.bytes()
  let timing_digest = read_digest(reader)
  let timing_bytes = reader.bytes()
  let due_at = reader.int64()
  let attempt_count = reader.int64()
  let retry_count = reader.int64()
  let retry_ordinal = reader.int64()
  let cause_key = reader.string()
  let requested_work_ref = read_ref(reader)
  let requested_work_digest = read_digest(reader)
  let logical_attempt_id = reader.string()
  let logical_attempt_version = reader.string()
  let logical_effect_id = reader.string()
  let logical_effect_version = reader.string()
  let artifact_digest = read_digest(reader)
  let stored_child_attempt_ref = read_ref(reader)
  let child_attempt_id = reader.string()
  let child_attempt_ordinal = reader.int64()
  let child_attempt_idempotency_key = reader.string()
  let stored_child_schedule_ref = read_ref(reader)
  let schedule_id = reader.string()
  let schedule_idempotency_key = reader.string()
  let source_schedule_deadline = reader.optional_int64()
  let admission_governance_deadline = reader.int64()
  let admission_controls_deadline = reader.int64()
  let requested_schedule_deadline = reader.int64()
  let governance_deadline = reader.optional_int64()
  let stored_effective_deadline = reader.int64()
  let prefix_head_ref = read_ref(reader)
  let prefix_head_digest = read_digest(reader)
  let prefix_sequence = reader.int64()
  let prefix_revision = reader.int64()
  let prefix_replay_digest = read_digest(reader)
  let command_idempotency_key = reader.string()
  reader.finish()
  let value = RetryScheduleRequestV2::new(
    request_id,
    workflow,
    receipt_ref,
    receipt_digest,
    receipt_bytes,
    policy_ref,
    policy_digest,
    policy_bytes,
    timing_digest,
    timing_bytes,
    due_at,
    attempt_count,
    retry_count,
    retry_ordinal,
    cause_key,
    requested_work_ref,
    requested_work_digest,
    logical_attempt_id,
    logical_attempt_version,
    logical_effect_id,
    logical_effect_version,
    artifact_digest,
    stored_child_attempt_ref.id(),
    child_attempt_ordinal,
    child_attempt_idempotency_key,
    stored_child_schedule_ref.id(),
    schedule_idempotency_key,
    source_schedule_deadline,
    admission_governance_deadline,
    admission_controls_deadline,
    requested_schedule_deadline,
    governance_deadline,
    prefix_head_ref,
    prefix_head_digest,
    prefix_sequence,
    prefix_revision,
    prefix_replay_digest,
    command_idempotency_key,
  )
  if child_attempt_id != stored_child_attempt_ref.id() {
    raise IdentityMismatch(field="child_attempt_id")
  }
  if schedule_id != stored_child_schedule_ref.id() {
    raise IdentityMismatch(field="schedule_id")
  }
  if value.child_attempt_request_ref != stored_child_attempt_ref {
    raise IdentityMismatch(field="child_attempt_request_ref")
  }
  if value.child_schedule_request_ref != stored_child_schedule_ref {
    raise IdentityMismatch(field="child_schedule_request_ref")
  }
  if value.effective_deadline != stored_effective_deadline {
    raise BoundViolation(field="effective_deadline")
  }
  if value.request_ref != expected_ref {
    raise IdentityMismatch(field="request_ref")
  }
  if value.canonical != bytes {
    raise IdentityMismatch(field="canonical")
  }
  value
}
