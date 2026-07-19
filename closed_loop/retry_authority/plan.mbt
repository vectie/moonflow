///|
/// Stable child identity computed before the retry plan is sealed. The
/// identity does not depend on the plan digest, avoiding a self-reference.
pub fn retry_child_attempt_request_ref_v2(
  attempt_id : String,
  workflow : @contracts.RecordRef,
  attempt_ordinal : Int64,
  idempotency_key : String,
  requested_work_digest : @contracts.ContentDigest,
) -> @contracts.RecordRef raise RetryAuthorityError {
  require_text(attempt_id, "child_attempt_id")
  require_text(idempotency_key, "child_attempt_idempotency_key")
  if attempt_ordinal <= 0L {
    raise BoundViolation(field="child_attempt_ordinal")
  }
  let writer = RetryWriter::new()
  writer.bytes(b"FLOW7/RETRY-CHILD-ATTEMPT-IDENTITY-V2/2.0.0")
  writer.string(attempt_id)
  write_ref(writer, workflow)
  writer.int64(attempt_ordinal)
  writer.string(idempotency_key)
  writer.string(requested_work_digest.text())
  proposal_ref(
    "retry-child-attempt-request-v2",
    attempt_id,
    @contracts.sha256_digest(writer.finish()),
  )
}

///|
/// Stable schedule identity computed before the retry plan is sealed.
pub fn retry_child_schedule_request_ref_v2(
  schedule_id : String,
  workflow : @contracts.RecordRef,
  due_at : Int64,
  idempotency_key : String,
  requested_work_digest : @contracts.ContentDigest,
) -> @contracts.RecordRef raise RetryAuthorityError {
  require_text(schedule_id, "schedule_id")
  require_text(idempotency_key, "schedule_idempotency_key")
  if due_at < 0L {
    raise BoundViolation(field="due_at")
  }
  let writer = RetryWriter::new()
  writer.bytes(b"FLOW7/RETRY-SCHEDULE-IDENTITY-V2/2.0.0")
  writer.string(schedule_id)
  write_ref(writer, workflow)
  writer.int64(due_at)
  writer.string(idempotency_key)
  writer.string(requested_work_digest.text())
  proposal_ref(
    "retry-child-schedule-request-v2",
    schedule_id,
    @contracts.sha256_digest(writer.finish()),
  )
}

///|
/// Immutable pre-commit proposal shared byte-for-byte by the effects attempt
/// and orchestration schedule. It is deliberately named Proposal: it is not a
/// claim that either child record has committed.
pub struct RetryPlanProposalV2 {
  plan_ref : @contracts.RecordRef
  request_ref : @contracts.RecordRef
  request_digest : @contracts.ContentDigest
  request_bytes : Bytes
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
  root_intent_ref : @contracts.RecordRef
  root_attempt_ref : @contracts.RecordRef
  source_intent_ref : @contracts.RecordRef
  source_attempt_ref : @contracts.RecordRef
  lineage_digest : @contracts.ContentDigest
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
  child_attempt_ordinal : Int64
  child_attempt_idempotency_key : String
  admission_ref : @contracts.RecordRef
  admission_digest : @contracts.ContentDigest
  admission_bytes : Bytes
  admission_deadline : Int64
  source_schedule_deadline : Int64?
  admission_governance_deadline : Int64
  admission_controls_deadline : Int64
  requested_schedule_deadline : Int64
  governance_digest : @contracts.ContentDigest?
  governance_bytes : Bytes?
  governance_deadline : Int64?
  schedule_request_ref : @contracts.RecordRef
  schedule_idempotency_key : String
  command_idempotency_key : String
  prefix_head_ref : @contracts.RecordRef
  prefix_head_digest : @contracts.ContentDigest
  prefix_sequence : Int64
  prefix_revision : Int64
  prefix_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn RetryPlanProposalV2::new(
  plan_id : String,
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
  root_intent_ref : @contracts.RecordRef,
  root_attempt_ref : @contracts.RecordRef,
  source_intent_ref : @contracts.RecordRef,
  source_attempt_ref : @contracts.RecordRef,
  lineage_digest : @contracts.ContentDigest,
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
  request_ref : @contracts.RecordRef,
  request_digest : @contracts.ContentDigest,
  request_bytes : Bytes,
  admission_ref : @contracts.RecordRef,
  admission_digest : @contracts.ContentDigest,
  admission_bytes : Bytes,
  admission_deadline : Int64,
  source_schedule_deadline : Int64?,
  admission_governance_deadline : Int64,
  admission_controls_deadline : Int64,
  requested_schedule_deadline : Int64,
  governance_digest : @contracts.ContentDigest?,
  governance_bytes : Bytes?,
  governance_deadline : Int64?,
  schedule_id : String,
  schedule_idempotency_key : String,
  command_idempotency_key : String,
  prefix_head_ref : @contracts.RecordRef,
  prefix_head_digest : @contracts.ContentDigest,
  prefix_sequence : Int64,
  prefix_revision : Int64,
  prefix_replay_digest : @contracts.ContentDigest,
) -> RetryPlanProposalV2 raise RetryAuthorityError {
  if request_ref.digest() != request_digest {
    raise IdentityMismatch(field="request_ref")
  }
  if request_digest != @contracts.sha256_digest(request_bytes) {
    raise DigestMismatch(field="request_bytes")
  }
  let request = RetryScheduleRequestV2::decode(request_ref, request_bytes)
  if request.digest() != request_digest ||
    request.workflow() != workflow ||
    request.receipt_ref() != receipt_ref ||
    request.receipt_digest() != receipt_digest ||
    request.receipt_bytes() != receipt_bytes ||
    request.policy_ref() != policy_ref ||
    request.policy_digest() != policy_digest ||
    request.policy_bytes() != policy_bytes ||
    request.timing_digest() != timing_digest ||
    request.timing_bytes() != timing_bytes ||
    request.due_at() != due_at ||
    request.attempt_count() != attempt_count ||
    request.retry_count() != retry_count ||
    request.retry_ordinal() != retry_ordinal ||
    request.cause_key() != cause_key ||
    request.requested_work_ref() != requested_work_ref ||
    request.requested_work_digest() != requested_work_digest ||
    request.logical_attempt_id() != logical_attempt_id ||
    request.logical_attempt_version() != logical_attempt_version ||
    request.logical_effect_id() != logical_effect_id ||
    request.logical_effect_version() != logical_effect_version ||
    request.artifact_digest() != artifact_digest ||
    request.child_attempt_request_ref() !=
    retry_child_attempt_request_ref_v2(
      child_attempt_id, workflow, child_attempt_ordinal, child_attempt_idempotency_key,
      requested_work_digest,
    ) ||
    request.child_attempt_id() != child_attempt_id ||
    request.child_attempt_ordinal() != child_attempt_ordinal ||
    request.child_attempt_idempotency_key() != child_attempt_idempotency_key ||
    request.child_schedule_request_ref() !=
    retry_child_schedule_request_ref_v2(
      schedule_id, workflow, due_at, schedule_idempotency_key, requested_work_digest,
    ) ||
    request.schedule_id() != schedule_id ||
    request.schedule_idempotency_key() != schedule_idempotency_key ||
    request.source_schedule_deadline() != source_schedule_deadline ||
    request.admission_governance_deadline() != admission_governance_deadline ||
    request.admission_controls_deadline() != admission_controls_deadline ||
    request.requested_schedule_deadline() != requested_schedule_deadline ||
    request.governance_deadline() != governance_deadline ||
    request.effective_deadline() != admission_deadline ||
    request.prefix_head_ref() != prefix_head_ref ||
    request.prefix_head_digest() != prefix_head_digest ||
    request.prefix_sequence() != prefix_sequence ||
    request.prefix_revision() != prefix_revision ||
    request.prefix_replay_digest() != prefix_replay_digest ||
    request.command_idempotency_key() != command_idempotency_key {
    raise IdentityMismatch(field="request")
  }
  require_text(plan_id, "plan_id")
  require_text(cause_key, "cause_key")
  require_text(logical_attempt_id, "logical_attempt_id")
  require_text(logical_attempt_version, "logical_attempt_version")
  require_text(logical_effect_id, "logical_effect_id")
  require_text(logical_effect_version, "logical_effect_version")
  require_text(child_attempt_idempotency_key, "child_attempt_idempotency_key")
  require_text(schedule_idempotency_key, "schedule_idempotency_key")
  require_text(command_idempotency_key, "command_idempotency_key")
  if receipt_ref.digest() != receipt_digest ||
    @contracts.sha256_digest(receipt_bytes) != receipt_digest {
    raise DigestMismatch(field="receipt")
  }
  if policy_ref.digest() != policy_digest ||
    @contracts.sha256_digest(policy_bytes) != policy_digest {
    raise DigestMismatch(field="policy")
  }
  if @contracts.sha256_digest(timing_bytes) != timing_digest {
    raise DigestMismatch(field="timing")
  }
  if requested_work_ref.digest() != requested_work_digest {
    raise DigestMismatch(field="requested_work")
  }
  if admission_ref.digest() != admission_digest ||
    @contracts.sha256_digest(admission_bytes) != admission_digest {
    raise DigestMismatch(field="admission")
  }
  if prefix_head_ref.digest() != prefix_head_digest {
    raise DigestMismatch(field="prefix_head")
  }
  if attempt_count <= 0L ||
    retry_count < 0L ||
    retry_ordinal != retry_count ||
    child_attempt_ordinal != attempt_count + 1L {
    raise BoundViolation(field="retry_counters")
  }
  if due_at < 0L ||
    admission_deadline < due_at ||
    admission_governance_deadline < due_at ||
    admission_controls_deadline < due_at ||
    requested_schedule_deadline < due_at ||
    prefix_sequence < 0L ||
    prefix_revision < 0L {
    raise BoundViolation(field="retry_deadlines_or_prefix")
  }
  match (governance_digest, governance_bytes, governance_deadline) {
    (None, None, None) => ()
    (Some(digest), Some(bytes), deadline) => {
      if @contracts.sha256_digest(bytes) != digest {
        raise DigestMismatch(field="governance")
      }
      match deadline {
        Some(value) if value <= due_at =>
          raise BoundViolation(field="governance_deadline")
        _ => ()
      }
    }
    _ => raise Malformed(field="governance_binding")
  }
  match source_schedule_deadline {
    Some(value) if value < due_at =>
      raise BoundViolation(field="source_schedule_deadline")
    _ => ()
  }
  let mut expected_deadline = requested_schedule_deadline
  if admission_governance_deadline < expected_deadline {
    expected_deadline = admission_governance_deadline
  }
  if admission_controls_deadline < expected_deadline {
    expected_deadline = admission_controls_deadline
  }
  match source_schedule_deadline {
    Some(value) if value < expected_deadline => expected_deadline = value
    _ => ()
  }
  match governance_deadline {
    Some(value) if value - 1L < expected_deadline =>
      expected_deadline = value - 1L
    _ => ()
  }
  if admission_deadline != expected_deadline {
    raise BoundViolation(field="effective_schedule_deadline")
  }
  let child_attempt_request_ref = retry_child_attempt_request_ref_v2(
    child_attempt_id, workflow, child_attempt_ordinal, child_attempt_idempotency_key,
    requested_work_digest,
  )
  let schedule_request_ref = retry_child_schedule_request_ref_v2(
    schedule_id, workflow, due_at, schedule_idempotency_key, requested_work_digest,
  )
  let writer = RetryWriter::new()
  writer.bytes(b"FLOW7/RETRY-PLAN-PROPOSAL-V2/2.0.0")
  writer.string(plan_id)
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
  write_ref(writer, root_intent_ref)
  write_ref(writer, root_attempt_ref)
  write_ref(writer, source_intent_ref)
  write_ref(writer, source_attempt_ref)
  writer.string(lineage_digest.text())
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
  writer.int64(child_attempt_ordinal)
  writer.string(child_attempt_idempotency_key)
  write_ref(writer, request_ref)
  writer.string(request_digest.text())
  writer.bytes(request_bytes)
  write_ref(writer, admission_ref)
  writer.string(admission_digest.text())
  writer.bytes(admission_bytes)
  writer.int64(admission_deadline)
  writer.optional_int64(source_schedule_deadline)
  writer.int64(admission_governance_deadline)
  writer.int64(admission_controls_deadline)
  writer.int64(requested_schedule_deadline)
  match (governance_digest, governance_bytes, governance_deadline) {
    (None, None, None) => writer.byte(0)
    (Some(digest), Some(bytes), deadline) => {
      writer.byte(1)
      writer.string(digest.text())
      writer.bytes(bytes)
      writer.optional_int64(deadline)
    }
    _ => raise Malformed(field="governance_binding")
  }
  write_ref(writer, schedule_request_ref)
  writer.string(schedule_idempotency_key)
  writer.string(command_idempotency_key)
  write_ref(writer, prefix_head_ref)
  writer.string(prefix_head_digest.text())
  writer.int64(prefix_sequence)
  writer.int64(prefix_revision)
  writer.string(prefix_replay_digest.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    plan_ref: proposal_ref("retry-plan-proposal-v2", plan_id, digest),
    request_ref,
    request_digest,
    request_bytes,
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
    root_intent_ref,
    root_attempt_ref,
    source_intent_ref,
    source_attempt_ref,
    lineage_digest,
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
    child_attempt_ordinal,
    child_attempt_idempotency_key,
    admission_ref,
    admission_digest,
    admission_bytes,
    admission_deadline,
    source_schedule_deadline,
    admission_governance_deadline,
    admission_controls_deadline,
    requested_schedule_deadline,
    governance_digest,
    governance_bytes,
    governance_deadline,
    schedule_request_ref,
    schedule_idempotency_key,
    command_idempotency_key,
    prefix_head_ref,
    prefix_head_digest,
    prefix_sequence,
    prefix_revision,
    prefix_replay_digest,
    canonical,
    digest,
  }
}

///|
/// Strictly reconstruct a proposal from committed nested bytes. Callers must
/// still validate the decoded proposal against their current replay state.
pub fn RetryPlanProposalV2::decode(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
) -> RetryPlanProposalV2 raise RetryAuthorityError {
  let reader = RetryReader::new(bytes)
  if reader.bytes() != b"FLOW7/RETRY-PLAN-PROPOSAL-V2/2.0.0" {
    raise Malformed(field="retry_plan_tag")
  }
  let plan_id = reader.string()
  if plan_id != expected_ref.id() {
    raise IdentityMismatch(field="plan_id")
  }
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
  let root_intent_ref = read_ref(reader)
  let root_attempt_ref = read_ref(reader)
  let source_intent_ref = read_ref(reader)
  let source_attempt_ref = read_ref(reader)
  let lineage_digest = read_digest(reader)
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
  let child_attempt_request_ref = read_ref(reader)
  let child_attempt_ordinal = reader.int64()
  let child_attempt_idempotency_key = reader.string()
  let request_ref = read_ref(reader)
  let request_digest = read_digest(reader)
  let request_bytes = reader.bytes()
  let admission_ref = read_ref(reader)
  let admission_digest = read_digest(reader)
  let admission_bytes = reader.bytes()
  let admission_deadline = reader.int64()
  let source_schedule_deadline = reader.optional_int64()
  let admission_governance_deadline = reader.int64()
  let admission_controls_deadline = reader.int64()
  let requested_schedule_deadline = reader.int64()
  let (governance_digest, governance_bytes, governance_deadline) = match
    reader.byte() {
    0 => (None, None, None)
    1 =>
      (Some(read_digest(reader)), Some(reader.bytes()), reader.optional_int64())
    _ => raise Malformed(field="governance_binding_marker")
  }
  let schedule_request_ref = read_ref(reader)
  let schedule_idempotency_key = reader.string()
  let command_idempotency_key = reader.string()
  let prefix_head_ref = read_ref(reader)
  let prefix_head_digest = read_digest(reader)
  let prefix_sequence = reader.int64()
  let prefix_revision = reader.int64()
  let prefix_replay_digest = read_digest(reader)
  reader.finish()
  let value = RetryPlanProposalV2::new(
    plan_id,
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
    root_intent_ref,
    root_attempt_ref,
    source_intent_ref,
    source_attempt_ref,
    lineage_digest,
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
    child_attempt_request_ref.id(),
    child_attempt_ordinal,
    child_attempt_idempotency_key,
    request_ref,
    request_digest,
    request_bytes,
    admission_ref,
    admission_digest,
    admission_bytes,
    admission_deadline,
    source_schedule_deadline,
    admission_governance_deadline,
    admission_controls_deadline,
    requested_schedule_deadline,
    governance_digest,
    governance_bytes,
    governance_deadline,
    schedule_request_ref.id(),
    schedule_idempotency_key,
    command_idempotency_key,
    prefix_head_ref,
    prefix_head_digest,
    prefix_sequence,
    prefix_revision,
    prefix_replay_digest,
  )
  if value.child_attempt_request_ref != child_attempt_request_ref ||
    value.schedule_request_ref != schedule_request_ref ||
    value.plan_ref != expected_ref ||
    value.canonical != bytes {
    raise DigestMismatch(field="retry_plan_canonical")
  }
  value
}

///|
pub fn RetryPlanProposalV2::plan_ref(
  self : RetryPlanProposalV2,
) -> @contracts.RecordRef {
  self.plan_ref
}

///|
pub fn RetryPlanProposalV2::request_ref(
  self : RetryPlanProposalV2,
) -> @contracts.RecordRef {
  self.request_ref
}

///|
pub fn RetryPlanProposalV2::request_digest(
  self : RetryPlanProposalV2,
) -> @contracts.ContentDigest {
  self.request_digest
}

///|
pub fn RetryPlanProposalV2::request_bytes(self : RetryPlanProposalV2) -> Bytes {
  self.request_bytes
}

///|
pub fn RetryPlanProposalV2::workflow(
  self : RetryPlanProposalV2,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn RetryPlanProposalV2::receipt_ref(
  self : RetryPlanProposalV2,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn RetryPlanProposalV2::receipt_digest(
  self : RetryPlanProposalV2,
) -> @contracts.ContentDigest {
  self.receipt_digest
}

///|
pub fn RetryPlanProposalV2::receipt_bytes(self : RetryPlanProposalV2) -> Bytes {
  self.receipt_bytes
}

///|
pub fn RetryPlanProposalV2::policy_ref(
  self : RetryPlanProposalV2,
) -> @contracts.RecordRef {
  self.policy_ref
}

///|
pub fn RetryPlanProposalV2::policy_digest(
  self : RetryPlanProposalV2,
) -> @contracts.ContentDigest {
  self.policy_digest
}

///|
pub fn RetryPlanProposalV2::policy_bytes(self : RetryPlanProposalV2) -> Bytes {
  self.policy_bytes
}

///|
pub fn RetryPlanProposalV2::timing_digest(
  self : RetryPlanProposalV2,
) -> @contracts.ContentDigest {
  self.timing_digest
}

///|
pub fn RetryPlanProposalV2::timing_bytes(self : RetryPlanProposalV2) -> Bytes {
  self.timing_bytes
}

///|
pub fn RetryPlanProposalV2::due_at(self : RetryPlanProposalV2) -> Int64 {
  self.due_at
}

///|
pub fn RetryPlanProposalV2::root_intent_ref(
  self : RetryPlanProposalV2,
) -> @contracts.RecordRef {
  self.root_intent_ref
}

///|
pub fn RetryPlanProposalV2::root_attempt_ref(
  self : RetryPlanProposalV2,
) -> @contracts.RecordRef {
  self.root_attempt_ref
}

///|
pub fn RetryPlanProposalV2::source_intent_ref(
  self : RetryPlanProposalV2,
) -> @contracts.RecordRef {
  self.source_intent_ref
}

///|
pub fn RetryPlanProposalV2::source_attempt_ref(
  self : RetryPlanProposalV2,
) -> @contracts.RecordRef {
  self.source_attempt_ref
}

///|
pub fn RetryPlanProposalV2::lineage_digest(
  self : RetryPlanProposalV2,
) -> @contracts.ContentDigest {
  self.lineage_digest
}

///|
pub fn RetryPlanProposalV2::attempt_count(self : RetryPlanProposalV2) -> Int64 {
  self.attempt_count
}

///|
pub fn RetryPlanProposalV2::retry_count(self : RetryPlanProposalV2) -> Int64 {
  self.retry_count
}

///|
pub fn RetryPlanProposalV2::retry_ordinal(self : RetryPlanProposalV2) -> Int64 {
  self.retry_ordinal
}

///|
pub fn RetryPlanProposalV2::cause_key(self : RetryPlanProposalV2) -> String {
  self.cause_key
}

///|
pub fn RetryPlanProposalV2::requested_work_ref(
  self : RetryPlanProposalV2,
) -> @contracts.RecordRef {
  self.requested_work_ref
}

///|
pub fn RetryPlanProposalV2::requested_work_digest(
  self : RetryPlanProposalV2,
) -> @contracts.ContentDigest {
  self.requested_work_digest
}

///|
pub fn RetryPlanProposalV2::logical_attempt_id(
  self : RetryPlanProposalV2,
) -> String {
  self.logical_attempt_id
}

///|
pub fn RetryPlanProposalV2::logical_attempt_version(
  self : RetryPlanProposalV2,
) -> String {
  self.logical_attempt_version
}

///|
pub fn RetryPlanProposalV2::logical_effect_id(
  self : RetryPlanProposalV2,
) -> String {
  self.logical_effect_id
}

///|
pub fn RetryPlanProposalV2::logical_effect_version(
  self : RetryPlanProposalV2,
) -> String {
  self.logical_effect_version
}

///|
pub fn RetryPlanProposalV2::artifact_digest(
  self : RetryPlanProposalV2,
) -> @contracts.ContentDigest {
  self.artifact_digest
}

///|
pub fn RetryPlanProposalV2::child_attempt_request_ref(
  self : RetryPlanProposalV2,
) -> @contracts.RecordRef {
  self.child_attempt_request_ref
}

///|
pub fn RetryPlanProposalV2::child_attempt_ordinal(
  self : RetryPlanProposalV2,
) -> Int64 {
  self.child_attempt_ordinal
}

///|
pub fn RetryPlanProposalV2::child_attempt_idempotency_key(
  self : RetryPlanProposalV2,
) -> String {
  self.child_attempt_idempotency_key
}

///|
pub fn RetryPlanProposalV2::admission_ref(
  self : RetryPlanProposalV2,
) -> @contracts.RecordRef {
  self.admission_ref
}

///|
pub fn RetryPlanProposalV2::admission_digest(
  self : RetryPlanProposalV2,
) -> @contracts.ContentDigest {
  self.admission_digest
}

///|
pub fn RetryPlanProposalV2::admission_bytes(
  self : RetryPlanProposalV2,
) -> Bytes {
  self.admission_bytes
}

///|
pub fn RetryPlanProposalV2::admission_deadline(
  self : RetryPlanProposalV2,
) -> Int64 {
  self.admission_deadline
}

///|
pub fn RetryPlanProposalV2::source_schedule_deadline(
  self : RetryPlanProposalV2,
) -> Int64? {
  self.source_schedule_deadline
}

///|
pub fn RetryPlanProposalV2::admission_governance_deadline(
  self : RetryPlanProposalV2,
) -> Int64 {
  self.admission_governance_deadline
}

///|
pub fn RetryPlanProposalV2::admission_controls_deadline(
  self : RetryPlanProposalV2,
) -> Int64 {
  self.admission_controls_deadline
}

///|
pub fn RetryPlanProposalV2::requested_schedule_deadline(
  self : RetryPlanProposalV2,
) -> Int64 {
  self.requested_schedule_deadline
}

///|
pub fn RetryPlanProposalV2::governance_digest(
  self : RetryPlanProposalV2,
) -> @contracts.ContentDigest? {
  self.governance_digest
}

///|
pub fn RetryPlanProposalV2::governance_bytes(
  self : RetryPlanProposalV2,
) -> Bytes? {
  self.governance_bytes
}

///|
pub fn RetryPlanProposalV2::governance_deadline(
  self : RetryPlanProposalV2,
) -> Int64? {
  self.governance_deadline
}

///|
pub fn RetryPlanProposalV2::schedule_request_ref(
  self : RetryPlanProposalV2,
) -> @contracts.RecordRef {
  self.schedule_request_ref
}

///|
pub fn RetryPlanProposalV2::schedule_idempotency_key(
  self : RetryPlanProposalV2,
) -> String {
  self.schedule_idempotency_key
}

///|
pub fn RetryPlanProposalV2::command_idempotency_key(
  self : RetryPlanProposalV2,
) -> String {
  self.command_idempotency_key
}

///|
pub fn RetryPlanProposalV2::prefix_head_ref(
  self : RetryPlanProposalV2,
) -> @contracts.RecordRef {
  self.prefix_head_ref
}

///|
pub fn RetryPlanProposalV2::prefix_head_digest(
  self : RetryPlanProposalV2,
) -> @contracts.ContentDigest {
  self.prefix_head_digest
}

///|
pub fn RetryPlanProposalV2::prefix_sequence(
  self : RetryPlanProposalV2,
) -> Int64 {
  self.prefix_sequence
}

///|
pub fn RetryPlanProposalV2::prefix_revision(
  self : RetryPlanProposalV2,
) -> Int64 {
  self.prefix_revision
}

///|
pub fn RetryPlanProposalV2::prefix_replay_digest(
  self : RetryPlanProposalV2,
) -> @contracts.ContentDigest {
  self.prefix_replay_digest
}

///|
pub fn RetryPlanProposalV2::canonical_bytes(
  self : RetryPlanProposalV2,
) -> Bytes {
  self.canonical
}

///|
pub fn RetryPlanProposalV2::digest(
  self : RetryPlanProposalV2,
) -> @contracts.ContentDigest {
  self.digest
}

///| Exact retry schedule request binding.
