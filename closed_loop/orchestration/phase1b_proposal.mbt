///|
let cancellation_proposal_record_kind_v22 = "orchestration-cancellation-proposal-v2"

///|
let phase1b_max_evidence_count_v22 = 128

///|
fn phase1b_require_short_text_v22(
  value : String,
  field : String,
) -> Unit raise OrchestrationError {
  require_text(value, field)
  if value.length() > 512 {
    raise MalformedInput(field~)
  }
}

///|
fn phase1b_require_evidence_bound_v22(
  evidence : ArrayView[@contracts.EvidenceRef],
  field : String,
) -> Unit raise OrchestrationError {
  if evidence.length() > phase1b_max_evidence_count_v22 {
    raise MalformedInput(field~)
  }
  for index, value in evidence {
    if evidence[:index].any(prior => prior == value) {
      raise EvidenceMismatch(field~)
    }
  }
}

///|
fn phase1b_schema_v22(kind : String) -> @contracts.SchemaRef {
  orchestration_schema(kind)
}

///|
fn cancellation_proposal_subject_payload_v22(
  proposal_ref : @contracts.RecordRef,
  proposal_bytes : Bytes,
  workflow : @contracts.RecordRef,
  governed_subject : @contracts.RecordRef,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/CANCELLATION-PROPOSAL-SUBJECT-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  write_ref(writer, workflow)
  write_ref(writer, governed_subject)
  write_ref(writer, proposal_ref)
  writer.bytes(proposal_bytes)
  writer.finish()
}

///|
fn cancellation_proposal_subject_v22(
  proposal_ref : @contracts.RecordRef,
  proposal_bytes : Bytes,
  workflow : @contracts.RecordRef,
  governed_subject : @contracts.RecordRef,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  event_idempotency_key : String,
  prefix_head_digest : @contracts.ContentDigest,
) -> @contracts.WireEnvelope raise OrchestrationError {
  @contracts.WireEnvelope::new(
    orchestration_contract_id,
    orchestration_record_version,
    "cancellation-proposal-subject-\{proposal_ref.id()}",
    "cancellation.proposal.v2",
    governed_subject,
    phase1b_schema_v22("cancellation.proposal.v2"),
    cancellation_proposal_subject_payload_v22(
      proposal_ref, proposal_bytes, workflow, governed_subject,
    ),
    orchestration_producer_id,
    orchestration_record_version,
    [],
    evidence,
    run_ref=workflow,
    correlation_ref=workflow.id(),
    causation_ref=causation.id(),
    idempotency_ref=event_idempotency_key,
    previous_digest=prefix_head_digest,
  ) catch {
    _ => raise MalformedInput(field="cancellation_proposal_subject")
  }
}

///|
fn require_root_binding_matches_aggregate_v22(
  root : CommittedCancellationGovernanceBindingReceiptV2,
  aggregate : ClosedLoopProjectionV2,
) -> Unit raise OrchestrationError {
  let effects = aggregate.effects
  let orchestration = aggregate.orchestration
  require_root_binding_verified_v22(orchestration)
  guard aggregate.prefix_event is Some(prefix) else {
    raise ReplayBindingViolation(field="cancellation_head_binding")
  }
  if root.workflow != effects.workflow() ||
    root.workflow != orchestration.workflow() ||
    root.workflow != prefix.workflow() ||
    root.current_sequence != effects.sequence() ||
    root.current_sequence != orchestration.sequence() ||
    root.current_sequence != prefix.sequence() ||
    root.current_revision != effects.revision() ||
    root.current_revision != orchestration.revision() ||
    root.current_revision != prefix.revision() ||
    root.current_head_digest != prefix.event_ref().digest() ||
    effects.last_event_digest() != Some(root.current_head_digest) ||
    orchestration.last_event_digest() != Some(root.current_head_digest) ||
    root.effects_state_digest != effects.state_digest() ||
    root.orchestration_state_digest != orchestration.state_digest() ||
    root.replay_digest != aggregate.replay_digest {
    raise ReplayBindingViolation(field="cancellation_head_binding")
  }
  for registration in orchestration.schedules {
    match registration.schedule().retry_plan() {
      None => ()
      Some(plan) => {
        let bound = root.retry_policy
        if plan.policy_ref() != bound.retry_policy_ref ||
          plan.policy_digest() != bound.retry_policy_digest ||
          plan.policy_bytes() != bound.retry_policy_bytes {
          raise PolicyMismatch(field="root_retry_policy_binding")
        }
      }
    }
  }
}

///|
/// Immutable, inert cancellation proposal frozen at one replay-derived work
/// head. It performs no mutation and confers no cancellation authority.
pub struct CancellationProposalV2 {
  proposal_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  root_registration_ref : @contracts.RecordRef
  root_registration_bytes : Bytes
  root_schedule_ref : @contracts.RecordRef
  root_requested_work_ref : @contracts.RecordRef
  root_requested_work_digest : @contracts.ContentDigest
  root_attempt_ref : @contracts.RecordRef
  root_attempt_digest : @contracts.ContentDigest
  root_intent_ref : @contracts.RecordRef
  root_intent_digest : @contracts.ContentDigest
  source_attempt_ref : @contracts.RecordRef?
  source_attempt_digest : @contracts.ContentDigest?
  source_intent_ref : @contracts.RecordRef?
  source_intent_digest : @contracts.ContentDigest?
  governed_subject : @contracts.RecordRef
  reason_ref : @contracts.RecordRef
  observed_at : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation : @contracts.RecordRef
  prefix_event_ref : @contracts.RecordRef
  prefix_sequence : Int64
  prefix_revision : Int64
  prefix_replay_digest : @contracts.ContentDigest
  event_idempotency_key : String
  command_idempotency_key : String
  governance_subject : @contracts.WireEnvelope
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
// Derive one coherent source pair. Intents are historical evidence, so an old
// intent remains visible after a retry attempt, but it must never be paired
// with that newer attempt.
fn cancellation_source_lineage_v22(
  effects : @effects.EffectsProjection,
) -> (@contracts.RecordRef?, @contracts.RecordRef?) raise OrchestrationError {
  effects.latest_attempt_intent_refs() catch {
    _ => raise ReplayBindingViolation(field="cancellation_proposal_lineage")
  }
}

///|
fn cancellation_proposal_signing_bytes_v22(
  proposal_id : String,
  workflow : @contracts.RecordRef,
  root_registration_ref : @contracts.RecordRef,
  root_registration_bytes : Bytes,
  root_schedule_ref : @contracts.RecordRef,
  root_requested_work_ref : @contracts.RecordRef,
  root_requested_work_digest : @contracts.ContentDigest,
  root_attempt_ref : @contracts.RecordRef,
  root_attempt_digest : @contracts.ContentDigest,
  root_intent_ref : @contracts.RecordRef,
  root_intent_digest : @contracts.ContentDigest,
  source_attempt_ref : @contracts.RecordRef?,
  source_attempt_digest : @contracts.ContentDigest?,
  source_intent_ref : @contracts.RecordRef?,
  source_intent_digest : @contracts.ContentDigest?,
  governed_subject : @contracts.RecordRef,
  reason_ref : @contracts.RecordRef,
  observed_at : Int64,
  evidence : ArrayView[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  prefix_event_ref : @contracts.RecordRef,
  prefix_sequence : Int64,
  prefix_revision : Int64,
  prefix_replay_digest : @contracts.ContentDigest,
  event_idempotency_key : String,
  command_idempotency_key : String,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/CANCELLATION-PROPOSAL-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(proposal_id)
  write_ref(writer, workflow)
  write_ref(writer, root_registration_ref)
  writer.bytes(root_registration_bytes)
  write_ref(writer, root_schedule_ref)
  write_ref(writer, root_requested_work_ref)
  writer.string(root_requested_work_digest.text())
  write_ref(writer, root_attempt_ref)
  writer.string(root_attempt_digest.text())
  write_ref(writer, root_intent_ref)
  writer.string(root_intent_digest.text())
  write_optional_ref(writer, source_attempt_ref)
  writer.optional_digest(source_attempt_digest)
  write_optional_ref(writer, source_intent_ref)
  writer.optional_digest(source_intent_digest)
  write_ref(writer, governed_subject)
  write_ref(writer, reason_ref)
  writer.int64(observed_at)
  write_evidence(writer, evidence)
  write_ref(writer, causation)
  write_ref(writer, prefix_event_ref)
  writer.int64(prefix_sequence)
  writer.int64(prefix_revision)
  writer.string(prefix_replay_digest.text())
  writer.string(event_idempotency_key)
  writer.string(command_idempotency_key)
  writer.finish()
}

///|
fn build_cancellation_proposal_v22(
  proposal_id : String,
  workflow : @contracts.RecordRef,
  root_registration_ref : @contracts.RecordRef,
  root_registration_bytes : Bytes,
  root_schedule_ref : @contracts.RecordRef,
  root_requested_work_ref : @contracts.RecordRef,
  root_requested_work_digest : @contracts.ContentDigest,
  root_attempt_ref : @contracts.RecordRef,
  root_attempt_digest : @contracts.ContentDigest,
  root_intent_ref : @contracts.RecordRef,
  root_intent_digest : @contracts.ContentDigest,
  source_attempt_ref : @contracts.RecordRef?,
  source_attempt_digest : @contracts.ContentDigest?,
  source_intent_ref : @contracts.RecordRef?,
  source_intent_digest : @contracts.ContentDigest?,
  governed_subject : @contracts.RecordRef,
  reason_ref : @contracts.RecordRef,
  observed_at : Int64,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  prefix_event_ref : @contracts.RecordRef,
  prefix_sequence : Int64,
  prefix_revision : Int64,
  prefix_replay_digest : @contracts.ContentDigest,
  event_idempotency_key : String,
  command_idempotency_key : String,
) -> CancellationProposalV2 raise OrchestrationError {
  phase1b_require_short_text_v22(proposal_id, "cancellation_proposal_id")
  phase1b_require_short_text_v22(
    event_idempotency_key, "cancellation_proposal_event_idempotency",
  )
  phase1b_require_short_text_v22(
    command_idempotency_key, "cancellation_proposal_command_idempotency",
  )
  require_utc_millis_v22(observed_at, "cancellation_proposal_observed_at")
  if prefix_sequence <= 0L || prefix_revision <= 0L {
    raise ReplayBindingViolation(field="cancellation_head_binding")
  }
  if (source_attempt_ref is Some(_)) != (source_attempt_digest is Some(_)) ||
    (source_intent_ref is Some(_)) != (source_intent_digest is Some(_)) {
    raise ReplayBindingViolation(field="cancellation_proposal_lineage")
  }
  if source_intent_ref is Some(_) && source_attempt_ref is None {
    raise ReplayBindingViolation(field="cancellation_proposal_lineage")
  }
  phase1b_require_evidence_bound_v22(evidence, "cancellation_proposal_evidence")
  let canonical = cancellation_proposal_signing_bytes_v22(
    proposal_id, workflow, root_registration_ref, root_registration_bytes, root_schedule_ref,
    root_requested_work_ref, root_requested_work_digest, root_attempt_ref, root_attempt_digest,
    root_intent_ref, root_intent_digest, source_attempt_ref, source_attempt_digest,
    source_intent_ref, source_intent_digest, governed_subject, reason_ref, observed_at,
    evidence, causation, prefix_event_ref, prefix_sequence, prefix_revision, prefix_replay_digest,
    event_idempotency_key, command_idempotency_key,
  )
  let digest = @contracts.sha256_digest(canonical)
  let proposal_ref = self_ref_v22(
    cancellation_proposal_record_kind_v22, proposal_id, digest,
  )
  let governance_subject = cancellation_proposal_subject_v22(
    proposal_ref,
    canonical,
    workflow,
    governed_subject,
    evidence,
    causation,
    event_idempotency_key,
    prefix_event_ref.digest(),
  )
  {
    proposal_ref,
    workflow,
    root_registration_ref,
    root_registration_bytes,
    root_schedule_ref,
    root_requested_work_ref,
    root_requested_work_digest,
    root_attempt_ref,
    root_attempt_digest,
    root_intent_ref,
    root_intent_digest,
    source_attempt_ref,
    source_attempt_digest,
    source_intent_ref,
    source_intent_digest,
    governed_subject,
    reason_ref,
    observed_at,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    causation,
    prefix_event_ref,
    prefix_sequence,
    prefix_revision,
    prefix_replay_digest,
    event_idempotency_key,
    command_idempotency_key,
    governance_subject,
    canonical,
    digest,
  }
}

///|
pub fn CancellationProposalV2::new(
  proposal_id : String,
  root_binding : CommittedCancellationGovernanceBindingReceiptV2,
  aggregate : ClosedLoopProjectionV2,
  governed_subject : @contracts.RecordRef,
  reason_ref : @contracts.RecordRef,
  observed_at : Int64,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  event_idempotency_key : String,
  command_idempotency_key : String,
) -> CancellationProposalV2 raise OrchestrationError {
  require_root_binding_matches_aggregate_v22(root_binding, aggregate)
  let registration = root_binding.registration
  let schedule = registration.schedule()
  let admission = schedule.admission()
  let planned = admission.planned()
  let root_governed_subject = admission.governance().governed_subject()
  if governed_subject != root_governed_subject ||
    governed_subject != planned.subject() ||
    planned.workflow() != root_binding.workflow {
    raise ReplayBindingViolation(field="cancellation_proposal_subject_binding")
  }
  let genesis_time = admission.eligibility().clock()
  if observed_at < genesis_time {
    raise ClockRegression(previous=genesis_time, incoming=observed_at)
  }
  let (source_attempt_ref, source_intent_ref) = cancellation_source_lineage_v22(
    aggregate.effects,
  )
  let source_attempt_digest = source_attempt_ref.map(value => value.digest())
  let source_intent_digest = source_intent_ref.map(value => value.digest())
  guard aggregate.prefix_event is Some(prefix) else {
    raise ReplayBindingViolation(field="cancellation_head_binding")
  }
  let root_attempt = admission.attempt()
  build_cancellation_proposal_v22(
    proposal_id,
    root_binding.workflow,
    registration.record_ref(),
    registration.canonical_bytes(),
    registration.schedule_ref(),
    planned.requested_work_ref(),
    planned.requested_work_digest(),
    root_attempt.attempt_ref(),
    root_attempt.attempt_digest(),
    admission.intent_ref(),
    admission.intent_digest(),
    source_attempt_ref,
    source_attempt_digest,
    source_intent_ref,
    source_intent_digest,
    governed_subject,
    reason_ref,
    observed_at,
    evidence,
    causation,
    prefix.event_ref(),
    prefix.sequence(),
    prefix.revision(),
    aggregate.replay_digest,
    event_idempotency_key,
    command_idempotency_key,
  )
}

///|
fn decode_cancellation_proposal_v22_strict(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
) -> CancellationProposalV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/CANCELLATION-PROPOSAL-V2/2.2.0" {
    raise MalformedInput(field="cancellation_proposal_tag")
  }
  let version = reader.read_string()
  if version != orchestration_record_version_v22 {
    raise UnsupportedVersion(field="cancellation_proposal", version~)
  }
  let proposal_id = reader.read_string()
  let workflow = reader.read_ref()
  let root_registration_ref = reader.read_ref()
  let root_registration_bytes = reader.read_bytes()
  let root_schedule_ref = reader.read_ref()
  let root_requested_work_ref = reader.read_ref()
  let root_requested_work_digest = reader.read_digest()
  let root_attempt_ref = reader.read_ref()
  let root_attempt_digest = reader.read_digest()
  let root_intent_ref = reader.read_ref()
  let root_intent_digest = reader.read_digest()
  let source_attempt_ref = reader.read_optional_ref()
  let source_attempt_digest = reader.read_optional_digest()
  let source_intent_ref = reader.read_optional_ref()
  let source_intent_digest = reader.read_optional_digest()
  let governed_subject = reader.read_ref()
  let reason_ref = reader.read_ref()
  let observed_at = reader.read_int64()
  let evidence = reader.read_evidence()
  let causation = reader.read_ref()
  let prefix_event_ref = reader.read_ref()
  let prefix_sequence = reader.read_int64()
  let prefix_revision = reader.read_int64()
  let prefix_replay_digest = reader.read_digest()
  let event_idempotency_key = reader.read_string()
  let command_idempotency_key = reader.read_string()
  reader.require_end()
  let root_registration = ScheduleRegisteredV2::decode(
    root_registration_ref.id(),
    root_registration_bytes,
  ) catch {
    _ => raise MalformedInput(field="cancellation_proposal_root_registration")
  }
  let root_admission = root_registration.schedule().admission()
  if root_registration.record_ref() != root_registration_ref ||
    root_registration.workflow() != workflow ||
    root_registration.schedule_ref() != root_schedule_ref ||
    root_admission.planned().requested_work_ref() != root_requested_work_ref ||
    root_admission.planned().requested_work_digest() !=
    root_requested_work_digest ||
    root_admission.attempt().attempt_ref() != root_attempt_ref ||
    root_admission.attempt().attempt_digest() != root_attempt_digest ||
    root_admission.intent_ref() != root_intent_ref ||
    root_admission.intent_digest() != root_intent_digest ||
    root_admission.governance().governed_subject() != governed_subject {
    raise ReplayBindingViolation(field="cancellation_proposal_root_binding")
  }
  let decoded = build_cancellation_proposal_v22(
    proposal_id, workflow, root_registration_ref, root_registration_bytes, root_schedule_ref,
    root_requested_work_ref, root_requested_work_digest, root_attempt_ref, root_attempt_digest,
    root_intent_ref, root_intent_digest, source_attempt_ref, source_attempt_digest,
    source_intent_ref, source_intent_digest, governed_subject, reason_ref, observed_at,
    evidence, causation, prefix_event_ref, prefix_sequence, prefix_revision, prefix_replay_digest,
    event_idempotency_key, command_idempotency_key,
  )
  if decoded.proposal_ref != expected_ref ||
    decoded.canonical != bytes ||
    expected_ref.kind() != cancellation_proposal_record_kind_v22 ||
    expected_ref.version().text() != orchestration_record_version_v22 {
    raise ReplayBindingViolation(field="cancellation_proposal_self_address")
  }
  decoded
}

///|
pub fn CancellationProposalV2::record_ref(
  self : CancellationProposalV2,
) -> @contracts.RecordRef {
  self.proposal_ref
}

///|
pub fn CancellationProposalV2::digest(
  self : CancellationProposalV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn CancellationProposalV2::canonical_bytes(
  self : CancellationProposalV2,
) -> Bytes {
  self.canonical
}

///|
pub fn CancellationProposalV2::source_attempt_ref(
  self : CancellationProposalV2,
) -> @contracts.RecordRef? {
  self.source_attempt_ref
}

///|
pub fn CancellationProposalV2::source_intent_ref(
  self : CancellationProposalV2,
) -> @contracts.RecordRef? {
  self.source_intent_ref
}

///|
pub fn CancellationProposalV2::workflow(
  self : CancellationProposalV2,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn CancellationProposalV2::governed_subject(
  self : CancellationProposalV2,
) -> @contracts.RecordRef {
  self.governed_subject
}

///|
pub fn CancellationProposalV2::governance_subject(
  self : CancellationProposalV2,
) -> @contracts.WireEnvelope {
  self.governance_subject
}

///|
pub fn CancellationProposalV2::reason_ref(
  self : CancellationProposalV2,
) -> @contracts.RecordRef {
  self.reason_ref
}

///|
pub fn CancellationProposalV2::observed_at(
  self : CancellationProposalV2,
) -> Int64 {
  self.observed_at
}

///|
pub fn CancellationProposalV2::evidence(
  self : CancellationProposalV2,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn CancellationProposalV2::prefix_event_ref(
  self : CancellationProposalV2,
) -> @contracts.RecordRef {
  self.prefix_event_ref
}

///|
pub fn CancellationProposalV2::prefix_sequence(
  self : CancellationProposalV2,
) -> Int64 {
  self.prefix_sequence
}

///|
pub fn CancellationProposalV2::prefix_revision(
  self : CancellationProposalV2,
) -> Int64 {
  self.prefix_revision
}

///|
pub fn CancellationProposalV2::prefix_replay_digest(
  self : CancellationProposalV2,
) -> @contracts.ContentDigest {
  self.prefix_replay_digest
}

///|
pub fn CancellationProposalV2::event_idempotency_key(
  self : CancellationProposalV2,
) -> String {
  self.event_idempotency_key
}

///|
pub fn CancellationProposalV2::command_idempotency_key(
  self : CancellationProposalV2,
) -> String {
  self.command_idempotency_key
}

///|
/// Revalidate this inert proposal against the exact current governed replay.
pub fn CancellationProposalV2::validate_current(
  self : CancellationProposalV2,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> Unit raise OrchestrationError {
  require_proposal_current_v22(self, current)
}
