///|
let invocation_started_event_kind_v3 = "effect.dispatch.invocation-started.v3"

///|
let invocation_started_record_magic_v3 = b"FLOW7/DISPATCH-INVOCATION-STARTED-V3/3.0.0"

///|
/// Inert proof that invocation entry was durably declared in the same atomic
/// batch as its claim. It never grants or recreates provider-call permission.
pub struct DispatchInvocationStartedV3 {
  start_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  attempt_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  claim_ref : @contracts.RecordRef
  claim_digest : @contracts.ContentDigest
  activation_ref : @contracts.RecordRef
  activation_digest : @contracts.ContentDigest
  provider_profile_digest : @contracts.ContentDigest
  event_id : String
  claim_event_id : String
  command_idempotency_key : String
  owner : @contracts.RecordRef
  lease_epoch : Int64
  fencing_token : Int64
  started_at : Int64
  expected_work_revision : Int64
  expected_work_head_digest : @contracts.ContentDigest
  expected_work_replay_digest : @contracts.ContentDigest
  governance_workflow : @contracts.RecordRef
  expected_governance_revision : Int64
  expected_governance_head_digest : @contracts.ContentDigest?
  expected_governance_replay_digest : @contracts.ContentDigest
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn dispatch_invocation_start_signing_bytes_v3(
  start_id : String,
  claim : DispatchClaimRecordV3,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(invocation_started_record_magic_v3)
  writer.string("3.0.0")
  writer.string(start_id)
  write_ref(writer, claim.workflow)
  write_ref(writer, claim.intent_ref)
  write_ref(writer, claim.attempt_ref)
  write_ref(writer, claim.governed_subject)
  write_ref(writer, claim.claim_ref)
  writer.string(claim.digest.text())
  write_ref(writer, claim.activation_ref)
  writer.string(claim.activation_digest.text())
  writer.string(claim.provider_profile_digest.text())
  writer.string(claim.invocation_event_id)
  writer.string(claim.dispatch_event_id)
  writer.string(claim.command_idempotency_key)
  write_ref(writer, claim.owner)
  writer.int64(claim.lease_epoch)
  writer.int64(claim.fencing_token)
  writer.int64(claim.claimed_at)
  writer.int64(claim.expected_work_revision)
  writer.string(claim.expected_work_head_digest.text())
  writer.string(claim.expected_work_replay_digest.text())
  write_ref(writer, claim.governance_workflow)
  writer.int64(claim.expected_governance_revision)
  writer.optional_digest(claim.expected_governance_head_digest)
  writer.string(claim.expected_governance_replay_digest.text())
  write_evidence(writer, claim.evidence)
  writer.finish()
}

///|
fn make_dispatch_invocation_started_v3(
  claim : DispatchClaimRecordV3,
) -> DispatchInvocationStartedV3 raise OrchestrationError {
  require_text(claim.invocation_event_id, "dispatch_invocation_v3_event_id")
  let start_id = "\{claim.claim_ref.id()}:invocation-start"
  let canonical = dispatch_invocation_start_signing_bytes_v3(start_id, claim)
  let digest = @contracts.sha256_digest(canonical)
  {
    start_ref: self_ref_v3(
      "orchestration-dispatch-invocation-start-v3", start_id, digest,
    ),
    workflow: claim.workflow,
    intent_ref: claim.intent_ref,
    attempt_ref: claim.attempt_ref,
    governed_subject: claim.governed_subject,
    claim_ref: claim.claim_ref,
    claim_digest: claim.digest,
    activation_ref: claim.activation_ref,
    activation_digest: claim.activation_digest,
    provider_profile_digest: claim.provider_profile_digest,
    event_id: claim.invocation_event_id,
    claim_event_id: claim.dispatch_event_id,
    command_idempotency_key: claim.command_idempotency_key,
    owner: claim.owner,
    lease_epoch: claim.lease_epoch,
    fencing_token: claim.fencing_token,
    started_at: claim.claimed_at,
    expected_work_revision: claim.expected_work_revision,
    expected_work_head_digest: claim.expected_work_head_digest,
    expected_work_replay_digest: claim.expected_work_replay_digest,
    governance_workflow: claim.governance_workflow,
    expected_governance_revision: claim.expected_governance_revision,
    expected_governance_head_digest: claim.expected_governance_head_digest,
    expected_governance_replay_digest: claim.expected_governance_replay_digest,
    evidence: claim.evidence,
    canonical,
    digest,
  }
}

///|
fn decode_dispatch_invocation_started_v3(
  bytes : Bytes,
) -> DispatchInvocationStartedV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != invocation_started_record_magic_v3 {
    raise MalformedInput(field="dispatch_invocation_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="dispatch_invocation_v3", version~)
  }
  let start_id = reader.read_string()
  let workflow = reader.read_ref()
  let intent_ref = reader.read_ref()
  let attempt_ref = reader.read_ref()
  let governed_subject = reader.read_ref()
  let claim_ref = reader.read_ref()
  let claim_digest = reader.read_digest()
  let activation_ref = reader.read_ref()
  let activation_digest = reader.read_digest()
  let provider_profile_digest = reader.read_digest()
  let event_id = reader.read_string()
  let claim_event_id = reader.read_string()
  let command_idempotency_key = reader.read_string()
  let owner = reader.read_ref()
  let lease_epoch = reader.read_int64()
  let fencing_token = reader.read_int64()
  let started_at = reader.read_int64()
  let expected_work_revision = reader.read_int64()
  let expected_work_head_digest = reader.read_digest()
  let expected_work_replay_digest = reader.read_digest()
  let governance_workflow = reader.read_ref()
  let expected_governance_revision = reader.read_int64()
  let expected_governance_head_digest = reader.read_optional_digest()
  let expected_governance_replay_digest = reader.read_digest()
  let evidence = reader.read_evidence()
  reader.require_end()
  // Reconstruct a minimal claim-shaped binding only through exact fields. The
  // canonical comparison below prevents this inert record from accepting any
  // alternate representation.
  let writer = OrchestrationWriter::new()
  writer.bytes(invocation_started_record_magic_v3)
  writer.string("3.0.0")
  writer.string(start_id)
  write_ref(writer, workflow)
  write_ref(writer, intent_ref)
  write_ref(writer, attempt_ref)
  write_ref(writer, governed_subject)
  write_ref(writer, claim_ref)
  writer.string(claim_digest.text())
  write_ref(writer, activation_ref)
  writer.string(activation_digest.text())
  writer.string(provider_profile_digest.text())
  writer.string(event_id)
  writer.string(claim_event_id)
  writer.string(command_idempotency_key)
  write_ref(writer, owner)
  writer.int64(lease_epoch)
  writer.int64(fencing_token)
  writer.int64(started_at)
  writer.int64(expected_work_revision)
  writer.string(expected_work_head_digest.text())
  writer.string(expected_work_replay_digest.text())
  write_ref(writer, governance_workflow)
  writer.int64(expected_governance_revision)
  writer.optional_digest(expected_governance_head_digest)
  writer.string(expected_governance_replay_digest.text())
  write_evidence(writer, evidence)
  let canonical = writer.finish()
  if canonical != bytes || start_id != "\{claim_ref.id()}:invocation-start" {
    raise DigestMismatch(field="dispatch_invocation_v3_noncanonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    start_ref: self_ref_v3(
      "orchestration-dispatch-invocation-start-v3", start_id, digest,
    ),
    workflow,
    intent_ref,
    attempt_ref,
    governed_subject,
    claim_ref,
    claim_digest,
    activation_ref,
    activation_digest,
    provider_profile_digest,
    event_id,
    claim_event_id,
    command_idempotency_key,
    owner,
    lease_epoch,
    fencing_token,
    started_at,
    expected_work_revision,
    expected_work_head_digest,
    expected_work_replay_digest,
    governance_workflow,
    expected_governance_revision,
    expected_governance_head_digest,
    expected_governance_replay_digest,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical,
    digest,
  }
}

///|
fn dispatch_invocation_started_event_v3(
  claim : DispatchClaimRecordV3,
  claim_event : @storage.WorkflowEvent,
) -> @storage.WorkflowEvent raise OrchestrationError {
  let started = make_dispatch_invocation_started_v3(claim)
  let evidence = [ for value in claim.evidence => value ]
  let envelope = @contracts.WireEnvelope::new(
    dispatch_claim_transport_contract_id_v3,
    orchestration_record_version,
    started.event_id,
    invocation_started_event_kind_v3,
    started.governed_subject,
    phase1b_effect_schema_v22(invocation_started_event_kind_v3),
    started.canonical,
    dispatch_claim_transport_producer_id_v3,
    orchestration_record_version,
    [],
    evidence,
    run_ref=started.workflow,
    attempt_ref=started.attempt_ref,
    correlation_ref=started.workflow.id(),
    causation_ref=started.claim_ref.id(),
    idempotency_ref=started.start_ref.id(),
    previous_digest=claim_event.event_ref().digest(),
  ) catch {
    _ => raise MalformedInput(field="dispatch_invocation_v3_envelope")
  }
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    started.workflow,
    started.event_id,
    claim_event.sequence() + 1L,
    claim_event.revision() + 1L,
    started.start_ref.id(),
    envelope,
    evidence,
    previous_event_digest=claim_event.event_ref().digest(),
  ) catch {
    _ => raise MalformedInput(field="dispatch_invocation_v3_event")
  }
}

///|
fn require_dispatch_invocation_event_binding_v3(
  started : DispatchInvocationStartedV3,
  event : @storage.WorkflowEvent,
  claim : DispatchClaimRecordV3,
) -> Unit raise OrchestrationError {
  let envelope = event.payload()
  if started.claim_ref != claim.claim_ref ||
    started.claim_digest != claim.digest ||
    started.activation_ref != claim.activation_ref ||
    started.activation_digest != claim.activation_digest ||
    started.provider_profile_digest != claim.provider_profile_digest ||
    started.workflow != claim.workflow ||
    started.intent_ref != claim.intent_ref ||
    started.attempt_ref != claim.attempt_ref ||
    started.governed_subject != claim.governed_subject ||
    started.owner != claim.owner ||
    started.lease_epoch != claim.lease_epoch ||
    started.fencing_token != claim.fencing_token ||
    started.event_id != claim.invocation_event_id ||
    started.claim_event_id != claim.dispatch_event_id ||
    started.command_idempotency_key != claim.command_idempotency_key ||
    started.started_at != claim.claimed_at ||
    started.expected_work_revision != claim.expected_work_revision ||
    started.expected_work_head_digest != claim.expected_work_head_digest ||
    started.expected_work_replay_digest != claim.expected_work_replay_digest ||
    started.governance_workflow != claim.governance_workflow ||
    started.expected_governance_revision != claim.expected_governance_revision ||
    started.expected_governance_head_digest !=
    claim.expected_governance_head_digest ||
    started.expected_governance_replay_digest !=
    claim.expected_governance_replay_digest ||
    !same_evidence(started.evidence, claim.evidence) ||
    event.record_version().text() != orchestration_record_version ||
    event.schema_version().text() != orchestration_schema_version ||
    event.workflow() != claim.workflow ||
    event.event_ref().id() != started.event_id ||
    event.revision() != claim.expected_work_revision + 2L ||
    event.sequence() != event.revision() ||
    event.idempotency_key() != started.start_ref.id() ||
    event.previous_event_digest() is None ||
    envelope.envelope_id() != event.event_ref().id() ||
    envelope.contract_id() != dispatch_claim_transport_contract_id_v3 ||
    envelope.contract_version().text() != orchestration_record_version ||
    envelope.producer_id() != dispatch_claim_transport_producer_id_v3 ||
    envelope.producer_version().text() != orchestration_record_version ||
    envelope.envelope_kind() != invocation_started_event_kind_v3 ||
    envelope.subject() != claim.governed_subject ||
    envelope.run_ref() != Some(claim.workflow) ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() != Some(claim.attempt_ref) ||
    envelope.correlation_ref() != Some(claim.workflow.id()) ||
    envelope.causation_ref() != Some(claim.claim_ref.id()) ||
    envelope.idempotency_ref() != Some(started.start_ref.id()) ||
    envelope.previous_digest() != event.previous_event_digest() ||
    envelope.schema() !=
    phase1b_effect_schema_v22(invocation_started_event_kind_v3) ||
    envelope.payload() != started.canonical ||
    !same_evidence(event.evidence(), claim.evidence) ||
    !same_evidence(envelope.evidence(), claim.evidence) ||
    !envelope.artifacts().is_empty() ||
    !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(field="dispatch_invocation_v3_event_binding")
  }
}

///|
pub fn DispatchInvocationStartedV3::record_ref(
  self : DispatchInvocationStartedV3,
) -> @contracts.RecordRef {
  self.start_ref
}

///|
pub fn DispatchInvocationStartedV3::canonical_bytes(
  self : DispatchInvocationStartedV3,
) -> Bytes {
  self.canonical
}

///|
pub fn DispatchInvocationStartedV3::digest(
  self : DispatchInvocationStartedV3,
) -> @contracts.ContentDigest {
  self.digest
}
