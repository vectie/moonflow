///|
let scheduler_claimed_event_kind_v3 = "orchestration.scheduler.claimed.v3"

///|
let scheduler_receipt_event_kind_v3 = "orchestration.scheduler.receipt.v3"

///|
pub struct ScheduledActionV3 {
  action_ref : @contracts.RecordRef
  action_id : String
  action_kind : String
  target_workflow : @contracts.RecordRef
  subject_ref : @contracts.RecordRef
  source_ref : @contracts.RecordRef
  source_digest : @contracts.ContentDigest
  time_workflow : @contracts.RecordRef
  due_at : UtcInstantV3
  effective_deadline : EffectiveDeadlineV3
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
/// Register an inert host-facing action description. This value grants no
/// mutation or external-effect authority.
pub fn ScheduledActionV3::new(
  action_id : String,
  action_kind : String,
  target_workflow : @contracts.RecordRef,
  subject_ref : @contracts.RecordRef,
  source_ref : @contracts.RecordRef,
  source_digest : @contracts.ContentDigest,
  time_workflow : @contracts.RecordRef,
  due_at : UtcInstantV3,
  effective_deadline : EffectiveDeadlineV3,
  evidence : Array[@contracts.EvidenceRef],
) -> ScheduledActionV3 raise OrchestrationError {
  require_text(action_id, "scheduled_action_v3_id")
  require_text(action_kind, "scheduled_action_v3_kind")
  if source_ref.digest() != source_digest ||
    due_at.epoch_millis >= effective_deadline.exclusive_cutoff.epoch_millis {
    raise ScheduleStateViolation(field="scheduled_action_v3_bounds")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/SCHEDULED-ACTION-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(action_id)
  writer.string(action_kind)
  write_ref(writer, target_workflow)
  write_ref(writer, subject_ref)
  write_ref(writer, source_ref)
  writer.string(source_digest.text())
  write_ref(writer, time_workflow)
  writer.bytes(due_at.canonical)
  writer.bytes(effective_deadline.canonical)
  write_evidence(writer, evidence)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    action_ref: self_ref_v3(
      "orchestration-scheduled-action-v3", action_id, digest,
    ),
    action_id,
    action_kind,
    target_workflow,
    subject_ref,
    source_ref,
    source_digest,
    time_workflow,
    due_at,
    effective_deadline,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    canonical,
    digest,
  }
}

///|
pub fn ScheduledActionV3::record_ref(
  self : ScheduledActionV3,
) -> @contracts.RecordRef {
  self.action_ref
}

///|
pub fn ScheduledActionV3::action_kind(self : ScheduledActionV3) -> String {
  self.action_kind
}

///|
pub fn ScheduledActionV3::target_workflow(
  self : ScheduledActionV3,
) -> @contracts.RecordRef {
  self.target_workflow
}

///|
pub fn ScheduledActionV3::subject_ref(
  self : ScheduledActionV3,
) -> @contracts.RecordRef {
  self.subject_ref
}

///|
pub fn ScheduledActionV3::due_at(self : ScheduledActionV3) -> UtcInstantV3 {
  self.due_at
}

///|
pub fn ScheduledActionV3::effective_deadline(
  self : ScheduledActionV3,
) -> EffectiveDeadlineV3 {
  self.effective_deadline
}

///|
pub fn ScheduledActionV3::canonical_bytes(self : ScheduledActionV3) -> Bytes {
  self.canonical
}

///|
pub fn ScheduledActionV3::digest(
  self : ScheduledActionV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub(all) enum SchedulerActionStateV3 {
  SchedulerWaitingV3
  SchedulerDueV3
  SchedulerClaimedV3
  SchedulerExpiredV3
  SchedulerCompletedV3
  SchedulerFailedV3
} derive(Eq, Debug)

///|
pub struct SchedulerActionViewV3 {
  action : ScheduledActionV3
  state : SchedulerActionStateV3
  time_observation_ref : @contracts.RecordRef
  time_observation_digest : @contracts.ContentDigest
  evaluated_at : UtcInstantV3
  claim_ref : @contracts.RecordRef?
  receipt_ref : @contracts.RecordRef?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn make_scheduler_action_view_v3(
  action : ScheduledActionV3,
  state : SchedulerActionStateV3,
  observation : TimeObservationV3,
  claim_ref : @contracts.RecordRef?,
  receipt_ref : @contracts.RecordRef?,
) -> SchedulerActionViewV3 raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/SCHEDULER-ACTION-VIEW-V3/3.0.0")
  writer.string("3.0.0")
  writer.bytes(action.canonical)
  writer.string(
    match state {
      SchedulerWaitingV3 => "waiting"
      SchedulerDueV3 => "due"
      SchedulerClaimedV3 => "claimed"
      SchedulerExpiredV3 => "expired"
      SchedulerCompletedV3 => "completed"
      SchedulerFailedV3 => "failed"
    },
  )
  write_ref(writer, observation.observation_ref)
  writer.string(observation.digest.text())
  writer.bytes(observation.effective_instant.canonical)
  match claim_ref {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value)
    }
  }
  match receipt_ref {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value)
    }
  }
  let canonical = writer.finish()
  {
    action,
    state,
    time_observation_ref: observation.observation_ref,
    time_observation_digest: observation.digest,
    evaluated_at: observation.effective_instant,
    claim_ref,
    receipt_ref,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn SchedulerActionViewV3::action(
  self : SchedulerActionViewV3,
) -> ScheduledActionV3 {
  self.action
}

///|
pub fn SchedulerActionViewV3::state(
  self : SchedulerActionViewV3,
) -> SchedulerActionStateV3 {
  self.state
}

///|
pub fn SchedulerActionViewV3::evaluated_at(
  self : SchedulerActionViewV3,
) -> UtcInstantV3 {
  self.evaluated_at
}

///|
pub fn SchedulerActionViewV3::canonical_bytes(
  self : SchedulerActionViewV3,
) -> Bytes {
  self.canonical
}

///|
pub fn SchedulerActionViewV3::digest(
  self : SchedulerActionViewV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub struct SchedulerClaimV3 {
  claim_ref : @contracts.RecordRef
  scheduler_workflow : @contracts.RecordRef
  action_ref : @contracts.RecordRef
  action_digest : @contracts.ContentDigest
  target_workflow : @contracts.RecordRef
  subject_ref : @contracts.RecordRef
  owner_ref : @contracts.RecordRef
  claim_epoch : Int64
  fencing_token : Int64
  claimed_at : UtcInstantV3
  expires_at_exclusive : UtcInstantV3
  time_workflow : @contracts.RecordRef
  time_observation_ref : @contracts.RecordRef
  time_observation_digest : @contracts.ContentDigest
  expected_time_revision : Int64
  expected_time_head_digest : @contracts.ContentDigest?
  expected_time_replay_digest : @contracts.ContentDigest
  event_id : String
  command_idempotency_key : String
  expected_scheduler_revision : Int64
  expected_scheduler_head_digest : @contracts.ContentDigest?
  expected_scheduler_replay_digest : @contracts.ContentDigest
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn scheduler_claim_signing_bytes_v3(
  claim_id : String,
  scheduler_workflow : @contracts.RecordRef,
  action_ref : @contracts.RecordRef,
  action_digest : @contracts.ContentDigest,
  target_workflow : @contracts.RecordRef,
  subject_ref : @contracts.RecordRef,
  owner_ref : @contracts.RecordRef,
  claim_epoch : Int64,
  fencing_token : Int64,
  claimed_at : UtcInstantV3,
  expires_at_exclusive : UtcInstantV3,
  time_workflow : @contracts.RecordRef,
  time_observation_ref : @contracts.RecordRef,
  time_observation_digest : @contracts.ContentDigest,
  expected_time_revision : Int64,
  expected_time_head_digest : @contracts.ContentDigest?,
  expected_time_replay_digest : @contracts.ContentDigest,
  event_id : String,
  command_idempotency_key : String,
  expected_scheduler_revision : Int64,
  expected_scheduler_head_digest : @contracts.ContentDigest?,
  expected_scheduler_replay_digest : @contracts.ContentDigest,
  evidence : ArrayView[@contracts.EvidenceRef],
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/SCHEDULER-CLAIM-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(claim_id)
  write_ref(writer, scheduler_workflow)
  write_ref(writer, action_ref)
  writer.string(action_digest.text())
  write_ref(writer, target_workflow)
  write_ref(writer, subject_ref)
  write_ref(writer, owner_ref)
  writer.int64(claim_epoch)
  writer.int64(fencing_token)
  writer.bytes(claimed_at.canonical)
  writer.bytes(expires_at_exclusive.canonical)
  write_ref(writer, time_workflow)
  write_ref(writer, time_observation_ref)
  writer.string(time_observation_digest.text())
  writer.int64(expected_time_revision)
  writer.optional_digest(expected_time_head_digest)
  writer.string(expected_time_replay_digest.text())
  writer.string(event_id)
  writer.string(command_idempotency_key)
  writer.int64(expected_scheduler_revision)
  writer.optional_digest(expected_scheduler_head_digest)
  writer.string(expected_scheduler_replay_digest.text())
  write_evidence(writer, evidence)
  writer.finish()
}

///|
pub(all) enum SchedulerReceiptOutcomeV3 {
  SchedulerActionCompletedReceiptV3
  SchedulerActionFailedReceiptV3
  SchedulerClaimReleasedReceiptV3
  SchedulerClaimExpiredReceiptV3
} derive(Eq, Debug)

///|
fn SchedulerReceiptOutcomeV3::wire(self : SchedulerReceiptOutcomeV3) -> String {
  match self {
    SchedulerActionCompletedReceiptV3 => "completed"
    SchedulerActionFailedReceiptV3 => "failed"
    SchedulerClaimReleasedReceiptV3 => "released"
    SchedulerClaimExpiredReceiptV3 => "expired"
  }
}

///|
fn decode_scheduler_receipt_outcome_v3(
  value : String,
) -> SchedulerReceiptOutcomeV3 raise OrchestrationError {
  match value {
    "completed" => SchedulerActionCompletedReceiptV3
    "failed" => SchedulerActionFailedReceiptV3
    "released" => SchedulerClaimReleasedReceiptV3
    "expired" => SchedulerClaimExpiredReceiptV3
    _ => raise MalformedInput(field="scheduler_receipt_v3_outcome")
  }
}

///|
pub struct SchedulerReceiptV3 {
  receipt_ref : @contracts.RecordRef
  scheduler_workflow : @contracts.RecordRef
  action_ref : @contracts.RecordRef
  action_digest : @contracts.ContentDigest
  claim_ref : @contracts.RecordRef
  claim_digest : @contracts.ContentDigest
  owner_ref : @contracts.RecordRef
  claim_epoch : Int64
  fencing_token : Int64
  outcome : SchedulerReceiptOutcomeV3
  recorded_at : UtcInstantV3
  result_ref : @contracts.RecordRef?
  result_digest : @contracts.ContentDigest?
  time_workflow : @contracts.RecordRef
  time_observation_ref : @contracts.RecordRef
  time_observation_digest : @contracts.ContentDigest
  expected_time_revision : Int64
  expected_time_head_digest : @contracts.ContentDigest?
  expected_time_replay_digest : @contracts.ContentDigest
  event_id : String
  command_idempotency_key : String
  expected_scheduler_revision : Int64
  expected_scheduler_head_digest : @contracts.ContentDigest?
  expected_scheduler_replay_digest : @contracts.ContentDigest
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn scheduler_receipt_signing_bytes_v3(
  receipt_id : String,
  scheduler_workflow : @contracts.RecordRef,
  action_ref : @contracts.RecordRef,
  action_digest : @contracts.ContentDigest,
  claim_ref : @contracts.RecordRef,
  claim_digest : @contracts.ContentDigest,
  owner_ref : @contracts.RecordRef,
  claim_epoch : Int64,
  fencing_token : Int64,
  outcome : SchedulerReceiptOutcomeV3,
  recorded_at : UtcInstantV3,
  result_ref : @contracts.RecordRef?,
  result_digest : @contracts.ContentDigest?,
  time_workflow : @contracts.RecordRef,
  time_observation_ref : @contracts.RecordRef,
  time_observation_digest : @contracts.ContentDigest,
  expected_time_revision : Int64,
  expected_time_head_digest : @contracts.ContentDigest?,
  expected_time_replay_digest : @contracts.ContentDigest,
  event_id : String,
  command_idempotency_key : String,
  expected_scheduler_revision : Int64,
  expected_scheduler_head_digest : @contracts.ContentDigest?,
  expected_scheduler_replay_digest : @contracts.ContentDigest,
  evidence : ArrayView[@contracts.EvidenceRef],
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/SCHEDULER-RECEIPT-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(receipt_id)
  write_ref(writer, scheduler_workflow)
  write_ref(writer, action_ref)
  writer.string(action_digest.text())
  write_ref(writer, claim_ref)
  writer.string(claim_digest.text())
  write_ref(writer, owner_ref)
  writer.int64(claim_epoch)
  writer.int64(fencing_token)
  writer.string(outcome.wire())
  writer.bytes(recorded_at.canonical)
  match result_ref {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value)
      guard result_digest is Some(digest) else {
        raise ReplayBindingViolation(field="scheduler_receipt_v3_result_digest")
      }
      writer.string(digest.text())
    }
  }
  if result_ref is None && result_digest is Some(_) {
    raise ReplayBindingViolation(field="scheduler_receipt_v3_result_ref")
  }
  write_ref(writer, time_workflow)
  write_ref(writer, time_observation_ref)
  writer.string(time_observation_digest.text())
  writer.int64(expected_time_revision)
  writer.optional_digest(expected_time_head_digest)
  writer.string(expected_time_replay_digest.text())
  writer.string(event_id)
  writer.string(command_idempotency_key)
  writer.int64(expected_scheduler_revision)
  writer.optional_digest(expected_scheduler_head_digest)
  writer.string(expected_scheduler_replay_digest.text())
  write_evidence(writer, evidence)
  writer.finish()
}

///|
pub struct SchedulerProjectionV3 {
  replay : @storage.ReplayResult
  claims : ReadOnlyArray[SchedulerClaimV3]
  receipts : ReadOnlyArray[SchedulerReceiptV3]
  digest : @contracts.ContentDigest
}

///|
fn SchedulerProjectionV3::latest_claim_for(
  self : SchedulerProjectionV3,
  action_ref : @contracts.RecordRef,
) -> SchedulerClaimV3? {
  self.claims.filter(value => value.action_ref == action_ref).last()
}

///|
fn SchedulerProjectionV3::latest_receipt_for(
  self : SchedulerProjectionV3,
  action_ref : @contracts.RecordRef,
) -> SchedulerReceiptV3? {
  self.receipts.filter(value => value.action_ref == action_ref).last()
}

///|
fn decode_scheduler_claim_v3(
  bytes : Bytes,
) -> SchedulerClaimV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/SCHEDULER-CLAIM-V3/3.0.0" {
    raise MalformedInput(field="scheduler_claim_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="scheduler_claim_v3", version~)
  }
  let claim_id = reader.read_string()
  let scheduler_workflow = reader.read_ref()
  let action_ref = reader.read_ref()
  let action_digest = reader.read_digest()
  let target_workflow = reader.read_ref()
  let subject_ref = reader.read_ref()
  let owner_ref = reader.read_ref()
  let claim_epoch = reader.read_int64()
  let fencing_token = reader.read_int64()
  let claimed_at = decode_utc_instant_v3(reader.read_bytes())
  let expires_at_exclusive = decode_utc_instant_v3(reader.read_bytes())
  let time_workflow = reader.read_ref()
  let time_observation_ref = reader.read_ref()
  let time_observation_digest = reader.read_digest()
  let expected_time_revision = reader.read_int64()
  let expected_time_head_digest = reader.read_optional_digest()
  let expected_time_replay_digest = reader.read_digest()
  let event_id = reader.read_string()
  let command_idempotency_key = reader.read_string()
  let expected_scheduler_revision = reader.read_int64()
  let expected_scheduler_head_digest = reader.read_optional_digest()
  let expected_scheduler_replay_digest = reader.read_digest()
  let evidence = reader.read_evidence()
  reader.require_end()
  require_text(claim_id, "scheduler_claim_v3_id")
  require_text(event_id, "scheduler_claim_v3_event")
  require_text(command_idempotency_key, "scheduler_claim_v3_command")
  if action_ref.digest() != action_digest ||
    claim_epoch <= 0L ||
    fencing_token <= 0L ||
    expected_time_revision < 0L ||
    expected_scheduler_revision < 0L ||
    expires_at_exclusive.epoch_millis <= claimed_at.epoch_millis ||
    time_observation_ref.digest() != time_observation_digest ||
    evidence.is_empty() {
    raise ReplayBindingViolation(field="scheduler_claim_v3_bounds")
  }
  let canonical = scheduler_claim_signing_bytes_v3(
    claim_id, scheduler_workflow, action_ref, action_digest, target_workflow, subject_ref,
    owner_ref, claim_epoch, fencing_token, claimed_at, expires_at_exclusive, time_workflow,
    time_observation_ref, time_observation_digest, expected_time_revision, expected_time_head_digest,
    expected_time_replay_digest, event_id, command_idempotency_key, expected_scheduler_revision,
    expected_scheduler_head_digest, expected_scheduler_replay_digest, evidence,
  )
  if canonical != bytes {
    raise DigestMismatch(field="scheduler_claim_v3_noncanonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    claim_ref: self_ref_v3("orchestration-scheduler-claim-v3", claim_id, digest),
    scheduler_workflow,
    action_ref,
    action_digest,
    target_workflow,
    subject_ref,
    owner_ref,
    claim_epoch,
    fencing_token,
    claimed_at,
    expires_at_exclusive,
    time_workflow,
    time_observation_ref,
    time_observation_digest,
    expected_time_revision,
    expected_time_head_digest,
    expected_time_replay_digest,
    event_id,
    command_idempotency_key,
    expected_scheduler_revision,
    expected_scheduler_head_digest,
    expected_scheduler_replay_digest,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical,
    digest,
  }
}

///|
fn decode_scheduler_receipt_v3(
  bytes : Bytes,
) -> SchedulerReceiptV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/SCHEDULER-RECEIPT-V3/3.0.0" {
    raise MalformedInput(field="scheduler_receipt_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="scheduler_receipt_v3", version~)
  }
  let receipt_id = reader.read_string()
  let scheduler_workflow = reader.read_ref()
  let action_ref = reader.read_ref()
  let action_digest = reader.read_digest()
  let claim_ref = reader.read_ref()
  let claim_digest = reader.read_digest()
  let owner_ref = reader.read_ref()
  let claim_epoch = reader.read_int64()
  let fencing_token = reader.read_int64()
  let outcome = decode_scheduler_receipt_outcome_v3(reader.read_string())
  let recorded_at = decode_utc_instant_v3(reader.read_bytes())
  let (result_ref, result_digest) = match reader.read_byte() {
    0 => (None, None)
    1 => (Some(reader.read_ref()), Some(reader.read_digest()))
    _ => raise MalformedInput(field="scheduler_receipt_v3_result_marker")
  }
  let time_workflow = reader.read_ref()
  let time_observation_ref = reader.read_ref()
  let time_observation_digest = reader.read_digest()
  let expected_time_revision = reader.read_int64()
  let expected_time_head_digest = reader.read_optional_digest()
  let expected_time_replay_digest = reader.read_digest()
  let event_id = reader.read_string()
  let command_idempotency_key = reader.read_string()
  let expected_scheduler_revision = reader.read_int64()
  let expected_scheduler_head_digest = reader.read_optional_digest()
  let expected_scheduler_replay_digest = reader.read_digest()
  let evidence = reader.read_evidence()
  reader.require_end()
  require_text(receipt_id, "scheduler_receipt_v3_id")
  require_text(event_id, "scheduler_receipt_v3_event")
  require_text(command_idempotency_key, "scheduler_receipt_v3_command")
  if action_ref.digest() != action_digest ||
    claim_ref.digest() != claim_digest ||
    time_observation_ref.digest() != time_observation_digest ||
    claim_epoch <= 0L ||
    fencing_token <= 0L ||
    expected_time_revision < 0L ||
    expected_scheduler_revision < 0L ||
    evidence.is_empty() {
    raise ReplayBindingViolation(field="scheduler_receipt_v3_bounds")
  }
  let canonical = scheduler_receipt_signing_bytes_v3(
    receipt_id, scheduler_workflow, action_ref, action_digest, claim_ref, claim_digest,
    owner_ref, claim_epoch, fencing_token, outcome, recorded_at, result_ref, result_digest,
    time_workflow, time_observation_ref, time_observation_digest, expected_time_revision,
    expected_time_head_digest, expected_time_replay_digest, event_id, command_idempotency_key,
    expected_scheduler_revision, expected_scheduler_head_digest, expected_scheduler_replay_digest,
    evidence,
  )
  if canonical != bytes {
    raise DigestMismatch(field="scheduler_receipt_v3_noncanonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    receipt_ref: self_ref_v3(
      "orchestration-scheduler-receipt-v3", receipt_id, digest,
    ),
    scheduler_workflow,
    action_ref,
    action_digest,
    claim_ref,
    claim_digest,
    owner_ref,
    claim_epoch,
    fencing_token,
    outcome,
    recorded_at,
    result_ref,
    result_digest,
    time_workflow,
    time_observation_ref,
    time_observation_digest,
    expected_time_revision,
    expected_time_head_digest,
    expected_time_replay_digest,
    event_id,
    command_idempotency_key,
    expected_scheduler_revision,
    expected_scheduler_head_digest,
    expected_scheduler_replay_digest,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical,
    digest,
  }
}

///|
fn scheduler_event_v3(
  event_kind : String,
  scheduler_workflow : @contracts.RecordRef,
  subject_ref : @contracts.RecordRef,
  record_ref : @contracts.RecordRef,
  event_id : String,
  command_idempotency_key : String,
  expected_revision : Int64,
  expected_head_digest : @contracts.ContentDigest?,
  canonical : Bytes,
  evidence : Array[@contracts.EvidenceRef],
) -> @storage.WorkflowEvent raise OrchestrationError {
  let envelope = @contracts.WireEnvelope::new(
    "closed-loop.orchestration",
    orchestration_record_version,
    event_id,
    event_kind,
    subject_ref,
    phase3_time_schema_v3(event_kind),
    canonical,
    "orchestration-protocol",
    orchestration_record_version,
    [],
    evidence,
    run_ref=scheduler_workflow,
    correlation_ref=scheduler_workflow.id(),
    causation_ref=subject_ref.id(),
    idempotency_ref=record_ref.id(),
    previous_digest?=expected_head_digest,
  ) catch {
    _ => raise MalformedInput(field="scheduler_event_v3_envelope")
  }
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    scheduler_workflow,
    event_id,
    expected_revision + 1L,
    expected_revision + 1L,
    record_ref.id(),
    envelope,
    evidence,
    previous_event_digest?=expected_head_digest,
  ) catch {
    _ => raise MalformedInput(field="scheduler_event_v3")
  }
}

///|
fn require_scheduler_transport_v3(
  event : @storage.WorkflowEvent,
  event_kind : String,
  scheduler_workflow : @contracts.RecordRef,
  subject_ref : @contracts.RecordRef,
  record_ref : @contracts.RecordRef,
  event_id : String,
  expected_revision : Int64,
  expected_head_digest : @contracts.ContentDigest?,
  canonical : Bytes,
  evidence : ReadOnlyArray[@contracts.EvidenceRef],
) -> Unit raise OrchestrationError {
  let envelope = event.payload()
  if event.workflow() != scheduler_workflow ||
    event.event_ref().id() != event_id ||
    event.sequence() != expected_revision + 1L ||
    event.revision() != expected_revision + 1L ||
    event.previous_event_digest() != expected_head_digest ||
    event.idempotency_key() != record_ref.id() ||
    envelope.envelope_kind() != event_kind ||
    envelope.subject() != subject_ref ||
    envelope.run_ref() != Some(scheduler_workflow) ||
    envelope.payload() != canonical ||
    envelope.previous_digest() != expected_head_digest ||
    !same_evidence(event.evidence(), evidence) ||
    !same_evidence(envelope.evidence(), evidence) {
    raise ReplayBindingViolation(field="scheduler_v3_transport")
  }
}

///|
fn require_scheduler_time_guard_v3(
  replay : @storage.ReplayResult,
  event : @storage.WorkflowEvent,
  command_idempotency_key : String,
  expected_scheduler_revision : Int64,
  time_workflow : @contracts.RecordRef,
  expected_time_revision : Int64,
  expected_time_head_digest : @contracts.ContentDigest?,
  expected_time_replay_digest : @contracts.ContentDigest,
) -> Unit raise OrchestrationError {
  let batches = replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().length() == 1 &&
      batch.event_refs()[0] == event.event_ref()
    })
  if batches.length() != 1 ||
    batches[0].command_idempotency_key() != command_idempotency_key ||
    batches[0].expected_revision() != expected_scheduler_revision ||
    !batches[0].intent_refs().is_empty() ||
    batches[0].guards().length() != 1 {
    raise ReplayBindingViolation(field="scheduler_v3_commit_boundary")
  }
  let head_guard = batches[0].guards()[0]
  if head_guard.workflow() != time_workflow ||
    head_guard.expected_revision() != expected_time_revision ||
    head_guard.expected_head_digest() != expected_time_head_digest ||
    head_guard.expected_replay_digest() != expected_time_replay_digest {
    raise ReplayBindingViolation(field="scheduler_v3_time_guard")
  }
}

///|
pub fn fold_scheduler_v3(
  replay : @storage.ReplayResult,
) -> SchedulerProjectionV3 raise OrchestrationError {
  let claims : Array[SchedulerClaimV3] = []
  let receipts : Array[SchedulerReceiptV3] = []
  for event in replay.events() {
    let kind = event.payload().envelope_kind()
    if kind == scheduled_action_registered_event_kind_v1 {
      if scheduled_action_registration_event_consumption_v1(event, replay) != 1 {
        raise ReplayBindingViolation(
          field="scheduler_registration_accounting_v1",
        )
      }
    } else if kind == scheduler_claimed_event_kind_v3 {
      let claim = decode_scheduler_claim_v3(event.payload().payload())
      require_scheduler_transport_v3(
        event,
        kind,
        claim.scheduler_workflow,
        claim.subject_ref,
        claim.claim_ref,
        claim.event_id,
        claim.expected_scheduler_revision,
        claim.expected_scheduler_head_digest,
        claim.canonical,
        claim.evidence,
      )
      require_scheduler_time_guard_v3(
        replay,
        event,
        claim.command_idempotency_key,
        claim.expected_scheduler_revision,
        claim.time_workflow,
        claim.expected_time_revision,
        claim.expected_time_head_digest,
        claim.expected_time_replay_digest,
      )
      let prefix = replay.verified_prefix(claim.expected_scheduler_revision) catch {
        _ => raise ReplayBindingViolation(field="scheduler_claim_v3_prefix")
      }
      if prefix.replay_digest() != claim.expected_scheduler_replay_digest ||
        prefix.head().last_event_digest() !=
        claim.expected_scheduler_head_digest ||
        claim.scheduler_workflow != replay.workflow() {
        raise ReplayBindingViolation(field="scheduler_claim_v3_replay")
      }
      match
        claims.filter(value => value.action_ref == claim.action_ref).last() {
        None =>
          if claim.claim_epoch != 1L || claim.fencing_token != 1L {
            raise ReplayBindingViolation(
              field="scheduler_claim_v3_initial_fence",
            )
          }
        Some(previous) => {
          let prior_receipt = receipts
            .filter(value => value.claim_ref == previous.claim_ref)
            .last()
          let reclaimable = match prior_receipt {
            Some(value) =>
              value.outcome == SchedulerClaimReleasedReceiptV3 ||
              value.outcome == SchedulerClaimExpiredReceiptV3
            None =>
              claim.claimed_at.epoch_millis >=
              previous.expires_at_exclusive.epoch_millis
          }
          if !reclaimable ||
            claim.claim_epoch != previous.claim_epoch + 1L ||
            claim.fencing_token != previous.fencing_token + 1L {
            raise ReplayBindingViolation(field="scheduler_claim_v3_successor")
          }
        }
      }
      claims.push(claim)
    } else if kind == scheduler_receipt_event_kind_v3 {
      let receipt = decode_scheduler_receipt_v3(event.payload().payload())
      require_scheduler_transport_v3(
        event,
        kind,
        receipt.scheduler_workflow,
        receipt.action_ref,
        receipt.receipt_ref,
        receipt.event_id,
        receipt.expected_scheduler_revision,
        receipt.expected_scheduler_head_digest,
        receipt.canonical,
        receipt.evidence,
      )
      require_scheduler_time_guard_v3(
        replay,
        event,
        receipt.command_idempotency_key,
        receipt.expected_scheduler_revision,
        receipt.time_workflow,
        receipt.expected_time_revision,
        receipt.expected_time_head_digest,
        receipt.expected_time_replay_digest,
      )
      let prefix = replay.verified_prefix(receipt.expected_scheduler_revision) catch {
        _ => raise ReplayBindingViolation(field="scheduler_receipt_v3_prefix")
      }
      guard claims.filter(value => value.claim_ref == receipt.claim_ref).last()
        is Some(claim) else {
        raise ReplayBindingViolation(field="scheduler_receipt_v3_claim")
      }
      if prefix.replay_digest() != receipt.expected_scheduler_replay_digest ||
        prefix.head().last_event_digest() !=
        receipt.expected_scheduler_head_digest ||
        receipt.scheduler_workflow != replay.workflow() ||
        receipts.any(value => value.claim_ref == receipt.claim_ref) ||
        receipt.claim_digest != claim.digest ||
        receipt.action_ref != claim.action_ref ||
        receipt.action_digest != claim.action_digest ||
        receipt.owner_ref != claim.owner_ref ||
        receipt.claim_epoch != claim.claim_epoch ||
        receipt.fencing_token != claim.fencing_token {
        raise ReplayBindingViolation(field="scheduler_receipt_v3_replay")
      }
      let expired = receipt.recorded_at.epoch_millis >=
        claim.expires_at_exclusive.epoch_millis
      if (receipt.outcome == SchedulerClaimExpiredReceiptV3 && !expired) ||
        (receipt.outcome != SchedulerClaimExpiredReceiptV3 && expired) {
        raise ReplayBindingViolation(field="scheduler_receipt_v3_expiry")
      }
      receipts.push(receipt)
    } else {
      raise ReplayBindingViolation(field="scheduler_v3_foreign_event")
    }
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/SCHEDULER-PROJECTION-V3/3.0.0")
  write_ref(writer, replay.workflow())
  writer.string(replay.replay_digest().text())
  writer.count(claims.length())
  for claim in claims {
    writer.string(claim.digest.text())
  }
  writer.count(receipts.length())
  for receipt in receipts {
    writer.string(receipt.digest.text())
  }
  let digest = @contracts.sha256_digest(writer.finish())
  {
    replay,
    claims: ReadOnlyArray::from_array(claims),
    receipts: ReadOnlyArray::from_array(receipts),
    digest,
  }
}

///|
pub fn[S : @storage.StoragePort] replay_scheduler_v3(
  store : S,
  scheduler_workflow : @contracts.RecordRef,
) -> SchedulerProjectionV3 raise {
  fold_scheduler_v3(store.replay(scheduler_workflow))
}

///|
pub fn SchedulerProjectionV3::workflow(
  self : SchedulerProjectionV3,
) -> @contracts.RecordRef {
  self.replay.workflow()
}

///|
pub fn SchedulerProjectionV3::claims(
  self : SchedulerProjectionV3,
) -> ReadOnlyArray[SchedulerClaimV3] {
  self.claims
}

///|
pub fn SchedulerProjectionV3::receipts(
  self : SchedulerProjectionV3,
) -> ReadOnlyArray[SchedulerReceiptV3] {
  self.receipts
}

///|
pub fn SchedulerProjectionV3::digest(
  self : SchedulerProjectionV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Evaluate all inert scheduled actions from the latest committed time fact.
/// The host cannot supply `now`; replay of the same streams returns the same
/// states and bytes regardless of host timezone.
pub fn scheduler_action_views_v3(
  actions : Array[ScheduledActionV3],
  scheduler : SchedulerProjectionV3,
  time : TimeEvidenceProjectionV3,
) -> Array[SchedulerActionViewV3] raise OrchestrationError {
  guard time.latest is Some(observation) else {
    raise ScheduleStateViolation(field="scheduler_v3_time_observation_required")
  }
  let ordered = actions.copy()
  ordered.sort_by((left, right) => {
    let due_order = left.due_at.epoch_millis.compare(right.due_at.epoch_millis)
    if due_order != 0 {
      due_order
    } else {
      left.action_id.compare(right.action_id)
    }
  })
  let views : Array[SchedulerActionViewV3] = []
  for index, action in ordered {
    if action.time_workflow != time.replay.workflow() ||
      ordered.filter(value => value.action_ref == action.action_ref).length() !=
      1 {
      raise ReplayBindingViolation(field="scheduler_v3_action_identity")
    }
    let receipt = scheduler.latest_receipt_for(action.action_ref)
    let claim = scheduler.latest_claim_for(action.action_ref)
    let now = observation.effective_instant.epoch_millis
    let state = match receipt {
      Some(value) if value.outcome == SchedulerActionCompletedReceiptV3 =>
        SchedulerCompletedV3
      Some(value) if value.outcome == SchedulerActionFailedReceiptV3 =>
        SchedulerFailedV3
      _ =>
        match claim {
          Some(value) if scheduler.receipts
            .filter(receipt => receipt.claim_ref == value.claim_ref)
            .is_empty() &&
            now < value.expires_at_exclusive.epoch_millis => SchedulerClaimedV3
          _ =>
            if now >= action.effective_deadline.exclusive_cutoff.epoch_millis {
              SchedulerExpiredV3
            } else if now >= action.due_at.epoch_millis {
              SchedulerDueV3
            } else {
              SchedulerWaitingV3
            }
        }
    }
    views.push(
      make_scheduler_action_view_v3(
        action,
        state,
        observation,
        claim.map(value => value.claim_ref),
        receipt.map(value => value.receipt_ref),
      ),
    )
  }
  views
}

///|
pub fn due_scheduler_actions_v3(
  actions : Array[ScheduledActionV3],
  scheduler : SchedulerProjectionV3,
  time : TimeEvidenceProjectionV3,
) -> Array[SchedulerActionViewV3] raise OrchestrationError {
  scheduler_action_views_v3(actions, scheduler, time).filter(value => {
    value.state == SchedulerDueV3
  })
}

///|
fn make_scheduler_claim_v3(
  scheduler : SchedulerProjectionV3,
  time : TimeEvidenceProjectionV3,
  action : ScheduledActionV3,
  claim_id : String,
  event_id : String,
  command_idempotency_key : String,
  owner_ref : @contracts.RecordRef,
  ttl_millis : Int64,
  evidence : Array[@contracts.EvidenceRef],
) -> SchedulerClaimV3 raise OrchestrationError {
  require_text(claim_id, "scheduler_claim_v3_id")
  require_text(event_id, "scheduler_claim_v3_event")
  require_text(command_idempotency_key, "scheduler_claim_v3_command")
  if ttl_millis <= 0L || evidence.is_empty() {
    raise TtlViolation(field="scheduler_claim_v3_ttl")
  }
  guard time.latest is Some(observation) else {
    raise ScheduleStateViolation(field="scheduler_claim_v3_time")
  }
  let views = scheduler_action_views_v3([action], scheduler, time)
  if views.length() != 1 || views[0].state != SchedulerDueV3 {
    raise ScheduleStateViolation(field="scheduler_claim_v3_not_due")
  }
  let now = observation.effective_instant.epoch_millis
  if ttl_millis > int64_max - now {
    raise ArithmeticOverflow(field="scheduler_claim_v3_ttl")
  }
  let requested_expiry = now + ttl_millis
  let expiry = if requested_expiry <
    action.effective_deadline.exclusive_cutoff.epoch_millis {
    requested_expiry
  } else {
    action.effective_deadline.exclusive_cutoff.epoch_millis
  }
  if expiry <= now {
    raise ScheduleStateViolation(field="scheduler_claim_v3_expired")
  }
  let (claim_epoch, fencing_token) = match
    scheduler.latest_claim_for(action.action_ref) {
    None => (1L, 1L)
    Some(previous) => {
      if previous.claim_epoch == int64_max ||
        previous.fencing_token == int64_max {
        raise ArithmeticOverflow(field="scheduler_claim_v3_fence")
      }
      (previous.claim_epoch + 1L, previous.fencing_token + 1L)
    }
  }
  let claimed_at = observation.effective_instant
  let expires_at_exclusive = UtcInstantV3::new(expiry)
  let scheduler_head = scheduler.replay.head()
  let time_head = time.replay.head()
  let canonical = scheduler_claim_signing_bytes_v3(
    claim_id,
    scheduler.replay.workflow(),
    action.action_ref,
    action.digest,
    action.target_workflow,
    action.subject_ref,
    owner_ref,
    claim_epoch,
    fencing_token,
    claimed_at,
    expires_at_exclusive,
    time.replay.workflow(),
    observation.observation_ref,
    observation.digest,
    time_head.revision(),
    time_head.last_event_digest(),
    time.replay.replay_digest(),
    event_id,
    command_idempotency_key,
    scheduler_head.revision(),
    scheduler_head.last_event_digest(),
    scheduler.replay.replay_digest(),
    evidence,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    claim_ref: self_ref_v3("orchestration-scheduler-claim-v3", claim_id, digest),
    scheduler_workflow: scheduler.replay.workflow(),
    action_ref: action.action_ref,
    action_digest: action.digest,
    target_workflow: action.target_workflow,
    subject_ref: action.subject_ref,
    owner_ref,
    claim_epoch,
    fencing_token,
    claimed_at,
    expires_at_exclusive,
    time_workflow: time.replay.workflow(),
    time_observation_ref: observation.observation_ref,
    time_observation_digest: observation.digest,
    expected_time_revision: time_head.revision(),
    expected_time_head_digest: time_head.last_event_digest(),
    expected_time_replay_digest: time.replay.replay_digest(),
    event_id,
    command_idempotency_key,
    expected_scheduler_revision: scheduler_head.revision(),
    expected_scheduler_head_digest: scheduler_head.last_event_digest(),
    expected_scheduler_replay_digest: scheduler.replay.replay_digest(),
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    canonical,
    digest,
  }
}

///|
pub struct SchedulerClaimCommitPlanV3 {
  claim : SchedulerClaimV3
  request : @storage.GuardedCommitRequest
}

///|
pub fn prepare_scheduler_claim_v3(
  scheduler : SchedulerProjectionV3,
  time : TimeEvidenceProjectionV3,
  action : ScheduledActionV3,
  claim_id : String,
  event_id : String,
  command_idempotency_key : String,
  owner_ref : @contracts.RecordRef,
  ttl_millis : Int64,
  evidence : Array[@contracts.EvidenceRef],
) -> SchedulerClaimCommitPlanV3 raise OrchestrationError {
  let claim = make_scheduler_claim_v3(
    scheduler, time, action, claim_id, event_id, command_idempotency_key, owner_ref,
    ttl_millis, evidence,
  )
  let event = scheduler_event_v3(
    scheduler_claimed_event_kind_v3,
    claim.scheduler_workflow,
    claim.subject_ref,
    claim.claim_ref,
    claim.event_id,
    claim.command_idempotency_key,
    claim.expected_scheduler_revision,
    claim.expected_scheduler_head_digest,
    claim.canonical,
    [
      for value in claim.evidence => value
    ],
  )
  let mutation = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    claim.scheduler_workflow,
    claim.expected_scheduler_revision,
    claim.command_idempotency_key,
    [event],
    [],
  ) catch {
    _ => raise ReplayBindingViolation(field="scheduler_claim_v3_commit")
  }
  let request = @storage.GuardedCommitRequest::new(mutation, [
    @storage.WorkflowHeadGuard::new(
      claim.time_workflow,
      claim.expected_time_revision,
      claim.expected_time_head_digest,
      claim.expected_time_replay_digest,
    ),
  ]) catch {
    _ => raise ReplayBindingViolation(field="scheduler_claim_v3_guard")
  }
  { claim, request }
}

///|
pub fn SchedulerClaimCommitPlanV3::claim(
  self : SchedulerClaimCommitPlanV3,
) -> SchedulerClaimV3 {
  self.claim
}

///|
pub fn SchedulerClaimCommitPlanV3::request(
  self : SchedulerClaimCommitPlanV3,
) -> @storage.GuardedCommitRequest {
  self.request
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] commit_scheduler_claim_v3(
  store : S,
  plan : SchedulerClaimCommitPlanV3,
) -> @storage.ClassifiedGuardedCommitOutcome raise {
  store.classified_guarded_commit(plan.request)
}

///|
fn make_scheduler_receipt_v3(
  scheduler : SchedulerProjectionV3,
  time : TimeEvidenceProjectionV3,
  claim_ref : @contracts.RecordRef,
  receipt_id : String,
  event_id : String,
  command_idempotency_key : String,
  outcome : SchedulerReceiptOutcomeV3,
  result_ref : @contracts.RecordRef?,
  result_digest : @contracts.ContentDigest?,
  evidence : Array[@contracts.EvidenceRef],
) -> SchedulerReceiptV3 raise OrchestrationError {
  require_text(receipt_id, "scheduler_receipt_v3_id")
  require_text(event_id, "scheduler_receipt_v3_event")
  require_text(command_idempotency_key, "scheduler_receipt_v3_command")
  if evidence.is_empty() {
    raise EvidenceMismatch(field="scheduler_receipt_v3_evidence")
  }
  guard scheduler.claims.filter(value => value.claim_ref == claim_ref).last()
    is Some(claim) else {
    raise IdentityMismatch(field="scheduler_receipt_v3_claim")
  }
  if scheduler.receipts.any(value => value.claim_ref == claim_ref) {
    raise ScheduleStateViolation(field="scheduler_receipt_v3_existing")
  }
  guard time.latest is Some(observation) else {
    raise ScheduleStateViolation(field="scheduler_receipt_v3_time")
  }
  if time.replay.workflow() != claim.time_workflow {
    raise WorkflowMismatch(field="scheduler_receipt_v3_time_workflow")
  }
  let expired = observation.effective_instant.epoch_millis >=
    claim.expires_at_exclusive.epoch_millis
  if (outcome == SchedulerClaimExpiredReceiptV3 && !expired) ||
    (outcome != SchedulerClaimExpiredReceiptV3 && expired) {
    raise ScheduleStateViolation(field="scheduler_receipt_v3_expiry")
  }
  match outcome {
    SchedulerActionCompletedReceiptV3 => {
      guard result_ref is Some(value) && result_digest == Some(value.digest()) else {
        raise ReplayBindingViolation(
          field="scheduler_receipt_v3_completed_result",
        )
      }
    }
    SchedulerClaimReleasedReceiptV3 | SchedulerClaimExpiredReceiptV3 =>
      if result_ref is Some(_) || result_digest is Some(_) {
        raise ReplayBindingViolation(
          field="scheduler_receipt_v3_release_result",
        )
      }
    SchedulerActionFailedReceiptV3 =>
      match result_ref {
        Some(value) if result_digest != Some(value.digest()) =>
          raise ReplayBindingViolation(
            field="scheduler_receipt_v3_failed_result",
          )
        None if result_digest is Some(_) =>
          raise ReplayBindingViolation(
            field="scheduler_receipt_v3_failed_result",
          )
        _ => ()
      }
  }
  let scheduler_head = scheduler.replay.head()
  let time_head = time.replay.head()
  let canonical = scheduler_receipt_signing_bytes_v3(
    receipt_id,
    scheduler.replay.workflow(),
    claim.action_ref,
    claim.action_digest,
    claim.claim_ref,
    claim.digest,
    claim.owner_ref,
    claim.claim_epoch,
    claim.fencing_token,
    outcome,
    observation.effective_instant,
    result_ref,
    result_digest,
    time.replay.workflow(),
    observation.observation_ref,
    observation.digest,
    time_head.revision(),
    time_head.last_event_digest(),
    time.replay.replay_digest(),
    event_id,
    command_idempotency_key,
    scheduler_head.revision(),
    scheduler_head.last_event_digest(),
    scheduler.replay.replay_digest(),
    evidence,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    receipt_ref: self_ref_v3(
      "orchestration-scheduler-receipt-v3", receipt_id, digest,
    ),
    scheduler_workflow: scheduler.replay.workflow(),
    action_ref: claim.action_ref,
    action_digest: claim.action_digest,
    claim_ref: claim.claim_ref,
    claim_digest: claim.digest,
    owner_ref: claim.owner_ref,
    claim_epoch: claim.claim_epoch,
    fencing_token: claim.fencing_token,
    outcome,
    recorded_at: observation.effective_instant,
    result_ref,
    result_digest,
    time_workflow: time.replay.workflow(),
    time_observation_ref: observation.observation_ref,
    time_observation_digest: observation.digest,
    expected_time_revision: time_head.revision(),
    expected_time_head_digest: time_head.last_event_digest(),
    expected_time_replay_digest: time.replay.replay_digest(),
    event_id,
    command_idempotency_key,
    expected_scheduler_revision: scheduler_head.revision(),
    expected_scheduler_head_digest: scheduler_head.last_event_digest(),
    expected_scheduler_replay_digest: scheduler.replay.replay_digest(),
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    canonical,
    digest,
  }
}

///|
pub struct SchedulerReceiptCommitPlanV3 {
  receipt : SchedulerReceiptV3
  request : @storage.GuardedCommitRequest
}

///|
pub fn prepare_scheduler_receipt_v3(
  scheduler : SchedulerProjectionV3,
  time : TimeEvidenceProjectionV3,
  claim_ref : @contracts.RecordRef,
  receipt_id : String,
  event_id : String,
  command_idempotency_key : String,
  outcome : SchedulerReceiptOutcomeV3,
  evidence : Array[@contracts.EvidenceRef],
  result_ref? : @contracts.RecordRef,
  result_digest? : @contracts.ContentDigest,
) -> SchedulerReceiptCommitPlanV3 raise OrchestrationError {
  let receipt = make_scheduler_receipt_v3(
    scheduler, time, claim_ref, receipt_id, event_id, command_idempotency_key, outcome,
    result_ref, result_digest, evidence,
  )
  let event = scheduler_event_v3(
    scheduler_receipt_event_kind_v3,
    receipt.scheduler_workflow,
    receipt.action_ref,
    receipt.receipt_ref,
    receipt.event_id,
    receipt.command_idempotency_key,
    receipt.expected_scheduler_revision,
    receipt.expected_scheduler_head_digest,
    receipt.canonical,
    [
      for value in receipt.evidence => value
    ],
  )
  let mutation = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    receipt.scheduler_workflow,
    receipt.expected_scheduler_revision,
    receipt.command_idempotency_key,
    [event],
    [],
  ) catch {
    _ => raise ReplayBindingViolation(field="scheduler_receipt_v3_commit")
  }
  let request = @storage.GuardedCommitRequest::new(mutation, [
    @storage.WorkflowHeadGuard::new(
      receipt.time_workflow,
      receipt.expected_time_revision,
      receipt.expected_time_head_digest,
      receipt.expected_time_replay_digest,
    ),
  ]) catch {
    _ => raise ReplayBindingViolation(field="scheduler_receipt_v3_guard")
  }
  { receipt, request }
}

///|
pub fn SchedulerReceiptCommitPlanV3::receipt(
  self : SchedulerReceiptCommitPlanV3,
) -> SchedulerReceiptV3 {
  self.receipt
}

///|
pub fn SchedulerReceiptCommitPlanV3::request(
  self : SchedulerReceiptCommitPlanV3,
) -> @storage.GuardedCommitRequest {
  self.request
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] commit_scheduler_receipt_v3(
  store : S,
  plan : SchedulerReceiptCommitPlanV3,
) -> @storage.ClassifiedGuardedCommitOutcome raise {
  store.classified_guarded_commit(plan.request)
}

///|
pub fn SchedulerClaimV3::record_ref(
  self : SchedulerClaimV3,
) -> @contracts.RecordRef {
  self.claim_ref
}

///|
pub fn SchedulerClaimV3::action_ref(
  self : SchedulerClaimV3,
) -> @contracts.RecordRef {
  self.action_ref
}

///|
pub fn SchedulerClaimV3::owner_ref(
  self : SchedulerClaimV3,
) -> @contracts.RecordRef {
  self.owner_ref
}

///|
pub fn SchedulerClaimV3::claim_epoch(self : SchedulerClaimV3) -> Int64 {
  self.claim_epoch
}

///|
pub fn SchedulerClaimV3::fencing_token(self : SchedulerClaimV3) -> Int64 {
  self.fencing_token
}

///|
pub fn SchedulerClaimV3::claimed_at(self : SchedulerClaimV3) -> UtcInstantV3 {
  self.claimed_at
}

///|
pub fn SchedulerClaimV3::expires_at_exclusive(
  self : SchedulerClaimV3,
) -> UtcInstantV3 {
  self.expires_at_exclusive
}

///|
pub fn SchedulerClaimV3::canonical_bytes(self : SchedulerClaimV3) -> Bytes {
  self.canonical
}

///|
pub fn SchedulerClaimV3::digest(
  self : SchedulerClaimV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn SchedulerReceiptV3::record_ref(
  self : SchedulerReceiptV3,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn SchedulerReceiptV3::outcome(
  self : SchedulerReceiptV3,
) -> SchedulerReceiptOutcomeV3 {
  self.outcome
}

///|
pub fn SchedulerReceiptV3::recorded_at(
  self : SchedulerReceiptV3,
) -> UtcInstantV3 {
  self.recorded_at
}

///|
pub fn SchedulerReceiptV3::canonical_bytes(self : SchedulerReceiptV3) -> Bytes {
  self.canonical
}

///|
pub fn SchedulerReceiptV3::digest(
  self : SchedulerReceiptV3,
) -> @contracts.ContentDigest {
  self.digest
}
