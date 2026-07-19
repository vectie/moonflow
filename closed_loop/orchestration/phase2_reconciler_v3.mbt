///|
let reconciliation_result_event_kind_v3 = "effect.reconciliation.result-recorded.v3"

///|
let recovery_backoff_event_kind_v3 = "effect.recovery.backoff-scheduled.v3"

///|
let recovery_automation_stopped_event_kind_v3 = "effect.recovery.automation-stopped.v3"

///|
let reconciliation_result_magic_v3 = b"FLOW7/RECONCILIATION-RESULT-V3/3.0.0"

///|
let recovery_backoff_magic_v3 = b"FLOW7/RECOVERY-BACKOFF-V3/3.0.0"

///|
let recovery_automation_stopped_magic_v3 = b"FLOW7/RECOVERY-AUTOMATION-STOPPED-V3/3.0.0"

///|
pub(all) enum ProviderQueryEvidenceKindV3 {
  ProviderQueryAppliedEvidenceV3
  ProviderQueryTerminalFailedEvidenceV3
  ProviderQueryTombstoneBarrierEvidenceV3
  ProviderQueryTimeoutEvidenceV3
  ProviderQueryNotFoundEvidenceV3
  ProviderQueryAmbiguousEvidenceV3
} derive(Eq, Debug)

///|
fn ProviderQueryEvidenceKindV3::wire(
  self : ProviderQueryEvidenceKindV3,
) -> String {
  match self {
    ProviderQueryAppliedEvidenceV3 => "applied"
    ProviderQueryTerminalFailedEvidenceV3 => "terminal_failed"
    ProviderQueryTombstoneBarrierEvidenceV3 => "tombstone_barrier"
    ProviderQueryTimeoutEvidenceV3 => "timeout"
    ProviderQueryNotFoundEvidenceV3 => "not_found"
    ProviderQueryAmbiguousEvidenceV3 => "ambiguous"
  }
}

///|
fn provider_query_evidence_kind_from_wire_v3(
  value : String,
) -> ProviderQueryEvidenceKindV3 raise OrchestrationError {
  match value {
    "applied" => ProviderQueryAppliedEvidenceV3
    "terminal_failed" => ProviderQueryTerminalFailedEvidenceV3
    "tombstone_barrier" => ProviderQueryTombstoneBarrierEvidenceV3
    "timeout" => ProviderQueryTimeoutEvidenceV3
    "not_found" => ProviderQueryNotFoundEvidenceV3
    "ambiguous" => ProviderQueryAmbiguousEvidenceV3
    _ => raise MalformedInput(field="provider_query_evidence_v3_kind")
  }
}

///|
/// Exact key-specific proof that the original create cannot apply after the
/// barrier. A not-found response without this proof is never retry authority.
pub struct AuthoritativeNotAppliedProofV3 {
  proof_ref : @contracts.RecordRef
  external_idempotency_key : String
  dispatch_claim_ref : @contracts.RecordRef
  dispatch_fencing_token : Int64
  reconciliation_claim_ref : @contracts.RecordRef
  reconciliation_fencing_token : Int64
  barrier_id : String
  barrier_digest : @contracts.ContentDigest
  query_identity : String
  query_body_digest : @contracts.ContentDigest
  provider_fence_floor : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn AuthoritativeNotAppliedProofV3::new(
  proof_id : String,
  external_idempotency_key : String,
  dispatch_claim_ref : @contracts.RecordRef,
  dispatch_fencing_token : Int64,
  reconciliation_claim_ref : @contracts.RecordRef,
  reconciliation_fencing_token : Int64,
  barrier_id : String,
  barrier_digest : @contracts.ContentDigest,
  query_identity : String,
  query_body_digest : @contracts.ContentDigest,
  provider_fence_floor : Int64,
) -> AuthoritativeNotAppliedProofV3 raise OrchestrationError {
  require_text(proof_id, "not_applied_proof_v3_id")
  require_text(external_idempotency_key, "not_applied_proof_v3_key")
  require_text(barrier_id, "not_applied_proof_v3_barrier")
  require_text(query_identity, "not_applied_proof_v3_query")
  if dispatch_fencing_token < 0L ||
    reconciliation_fencing_token < 0L ||
    provider_fence_floor <= dispatch_fencing_token ||
    provider_fence_floor < reconciliation_fencing_token {
    raise FencingViolation(
      expected_greater_than=dispatch_fencing_token,
      actual=provider_fence_floor,
    )
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/AUTHORITATIVE-NOT-APPLIED-PROOF-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(proof_id)
  writer.string(external_idempotency_key)
  write_ref(writer, dispatch_claim_ref)
  writer.int64(dispatch_fencing_token)
  write_ref(writer, reconciliation_claim_ref)
  writer.int64(reconciliation_fencing_token)
  writer.string(barrier_id)
  writer.string(barrier_digest.text())
  writer.string(query_identity)
  writer.string(query_body_digest.text())
  writer.int64(provider_fence_floor)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    proof_ref: self_ref_v3(
      "orchestration-authoritative-not-applied-proof-v3", proof_id, digest,
    ),
    external_idempotency_key,
    dispatch_claim_ref,
    dispatch_fencing_token,
    reconciliation_claim_ref,
    reconciliation_fencing_token,
    barrier_id,
    barrier_digest,
    query_identity,
    query_body_digest,
    provider_fence_floor,
    canonical,
    digest,
  }
}

///|
fn decode_authoritative_not_applied_proof_v3(
  bytes : Bytes,
) -> AuthoritativeNotAppliedProofV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/AUTHORITATIVE-NOT-APPLIED-PROOF-V3/3.0.0" {
    raise MalformedInput(field="not_applied_proof_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="not_applied_proof_v3", version~)
  }
  let value = AuthoritativeNotAppliedProofV3::new(
    reader.read_string(),
    reader.read_string(),
    reader.read_ref(),
    reader.read_int64(),
    reader.read_ref(),
    reader.read_int64(),
    reader.read_string(),
    reader.read_digest(),
    reader.read_string(),
    reader.read_digest(),
    reader.read_int64(),
  )
  reader.require_end()
  if value.canonical != bytes {
    raise DigestMismatch(field="not_applied_proof_v3_noncanonical")
  }
  value
}

///|
pub struct ProviderQueryEvidenceV3 {
  provider_id : String
  provider_event_id : String
  evidence_kind : ProviderQueryEvidenceKindV3
  body_digest : @contracts.ContentDigest
  external_idempotency_key : String
  dispatch_claim_ref : @contracts.RecordRef
  dispatch_fencing_token : Int64
  reconciliation_claim_ref : @contracts.RecordRef
  reconciliation_fencing_token : Int64
  source_at : Int64
  retrieved_at : Int64
  not_applied_proof : AuthoritativeNotAppliedProofV3?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn ProviderQueryEvidenceV3::new(
  provider_id : String,
  provider_event_id : String,
  evidence_kind : ProviderQueryEvidenceKindV3,
  body_digest : @contracts.ContentDigest,
  external_idempotency_key : String,
  dispatch_claim_ref : @contracts.RecordRef,
  dispatch_fencing_token : Int64,
  reconciliation_claim_ref : @contracts.RecordRef,
  reconciliation_fencing_token : Int64,
  source_at : Int64,
  retrieved_at : Int64,
  not_applied_proof? : AuthoritativeNotAppliedProofV3,
) -> ProviderQueryEvidenceV3 raise OrchestrationError {
  require_text(provider_id, "provider_query_evidence_v3_provider")
  require_text(provider_event_id, "provider_query_evidence_v3_event")
  require_text(external_idempotency_key, "provider_query_evidence_v3_key")
  if dispatch_fencing_token < 0L ||
    reconciliation_fencing_token < 0L ||
    source_at < 0L ||
    retrieved_at < source_at ||
    (evidence_kind == ProviderQueryTombstoneBarrierEvidenceV3) !=
    (not_applied_proof is Some(_)) {
    raise MalformedInput(field="provider_query_evidence_v3_bounds")
  }
  match not_applied_proof {
    None => ()
    Some(proof) =>
      if proof.external_idempotency_key != external_idempotency_key ||
        proof.dispatch_claim_ref != dispatch_claim_ref ||
        proof.dispatch_fencing_token != dispatch_fencing_token ||
        proof.reconciliation_claim_ref != reconciliation_claim_ref ||
        proof.reconciliation_fencing_token != reconciliation_fencing_token ||
        proof.query_identity != "\{provider_id}:\{provider_event_id}" ||
        proof.query_body_digest != body_digest {
        raise ReplayBindingViolation(field="not_applied_proof_v3_query_binding")
      }
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/PROVIDER-QUERY-EVIDENCE-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(provider_id)
  writer.string(provider_event_id)
  writer.string(evidence_kind.wire())
  writer.string(body_digest.text())
  writer.string(external_idempotency_key)
  write_ref(writer, dispatch_claim_ref)
  writer.int64(dispatch_fencing_token)
  write_ref(writer, reconciliation_claim_ref)
  writer.int64(reconciliation_fencing_token)
  writer.int64(source_at)
  writer.int64(retrieved_at)
  match not_applied_proof {
    None => writer.byte(0)
    Some(proof) => {
      writer.byte(1)
      writer.bytes(proof.canonical)
    }
  }
  let canonical = writer.finish()
  {
    provider_id,
    provider_event_id,
    evidence_kind,
    body_digest,
    external_idempotency_key,
    dispatch_claim_ref,
    dispatch_fencing_token,
    reconciliation_claim_ref,
    reconciliation_fencing_token,
    source_at,
    retrieved_at,
    not_applied_proof,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
fn decode_provider_query_evidence_v3(
  bytes : Bytes,
) -> ProviderQueryEvidenceV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/PROVIDER-QUERY-EVIDENCE-V3/3.0.0" {
    raise MalformedInput(field="provider_query_evidence_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="provider_query_evidence_v3", version~)
  }
  let provider_id = reader.read_string()
  let provider_event_id = reader.read_string()
  let evidence_kind = provider_query_evidence_kind_from_wire_v3(
    reader.read_string(),
  )
  let body_digest = reader.read_digest()
  let external_idempotency_key = reader.read_string()
  let dispatch_claim_ref = reader.read_ref()
  let dispatch_fencing_token = reader.read_int64()
  let reconciliation_claim_ref = reader.read_ref()
  let reconciliation_fencing_token = reader.read_int64()
  let source_at = reader.read_int64()
  let retrieved_at = reader.read_int64()
  let proof = match reader.read_byte() {
    0 => None
    1 => Some(decode_authoritative_not_applied_proof_v3(reader.read_bytes()))
    _ => raise MalformedInput(field="provider_query_evidence_v3_proof")
  }
  reader.require_end()
  let value = ProviderQueryEvidenceV3::new(
    provider_id,
    provider_event_id,
    evidence_kind,
    body_digest,
    external_idempotency_key,
    dispatch_claim_ref,
    dispatch_fencing_token,
    reconciliation_claim_ref,
    reconciliation_fencing_token,
    source_at,
    retrieved_at,
    not_applied_proof?=proof,
  )
  if value.canonical != bytes {
    raise DigestMismatch(field="provider_query_evidence_v3_noncanonical")
  }
  value
}

///|
pub(all) enum ProviderQueryResultV3 {
  ProviderQueryAppliedV3(ProviderQueryEvidenceV3)
  ProviderQueryTerminalFailedV3(ProviderQueryEvidenceV3)
  ProviderQueryConfirmedNotAppliedV3(ProviderQueryEvidenceV3)
  ProviderQueryStillUnknownV3(ProviderQueryEvidenceV3?)
}

///|
pub struct GuardedRecoveryQueryCallV3 {
  query_start_ref : @contracts.RecordRef
  reconciliation_claim_ref : @contracts.RecordRef
  dispatch_claim_ref : @contracts.RecordRef
  provider_operation : @contracts.WireEnvelope
  external_idempotency_key : String
  owner : @contracts.RecordRef
  lease_epoch : Int64
  dispatch_fencing_token : Int64
  reconciliation_fencing_token : Int64
  reconciliation_ordinal : Int64
  capability_ref : @contracts.RecordRef
  capability_kind : String
  provider_profile_digest : @contracts.ContentDigest
  permitted_evidence : ReadOnlyArray[@contracts.EvidenceRef]
  durable_work_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub(open) trait GuardedRecoveryQueryPortV3 {
  fn recovery_profile(Self) -> ProviderRecoveryProfileV3
  fn query_guarded_effect(Self, GuardedRecoveryQueryCallV3) -> ProviderQueryResultV3 raise
}

///|
fn guarded_recovery_query_call_v3(
  dispatch : DispatchClaimRecordV3,
  claim : ReconciliationClaimRecordV3,
  started : ReconciliationQueryStartedV3,
  replay_digest : @contracts.ContentDigest,
) -> GuardedRecoveryQueryCallV3 raise OrchestrationError {
  if started.reconciliation_claim_ref != claim.reconciliation_claim_ref ||
    started.reconciliation_claim_digest != claim.digest ||
    claim.dispatch_claim_ref != dispatch.claim_ref ||
    claim.dispatch_claim_digest != dispatch.digest {
    raise ReplayBindingViolation(field="guarded_recovery_query_v3_binding")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/GUARDED-RECOVERY-QUERY-CALL-V3/3.0.0")
  write_ref(writer, started.query_start_ref)
  write_ref(writer, claim.reconciliation_claim_ref)
  write_ref(writer, dispatch.claim_ref)
  writer.bytes(@contracts.encode_wire_envelope(dispatch.provider_operation))
  writer.string(dispatch.external_idempotency_key)
  write_ref(writer, claim.owner)
  writer.int64(claim.lease_epoch)
  writer.int64(dispatch.fencing_token)
  writer.int64(claim.fencing_token)
  writer.int64(claim.reconciliation_ordinal)
  write_ref(writer, dispatch.capability_ref)
  writer.string(dispatch.capability_kind)
  writer.string(dispatch.provider_profile_digest.text())
  write_evidence(writer, dispatch.evidence)
  writer.string(replay_digest.text())
  let canonical = writer.finish()
  {
    query_start_ref: started.query_start_ref,
    reconciliation_claim_ref: claim.reconciliation_claim_ref,
    dispatch_claim_ref: dispatch.claim_ref,
    provider_operation: dispatch.provider_operation,
    external_idempotency_key: dispatch.external_idempotency_key,
    owner: claim.owner,
    lease_epoch: claim.lease_epoch,
    dispatch_fencing_token: dispatch.fencing_token,
    reconciliation_fencing_token: claim.fencing_token,
    reconciliation_ordinal: claim.reconciliation_ordinal,
    capability_ref: dispatch.capability_ref,
    capability_kind: dispatch.capability_kind,
    provider_profile_digest: dispatch.provider_profile_digest,
    permitted_evidence: dispatch.evidence,
    durable_work_replay_digest: replay_digest,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub(all) enum ReconciliationOutcomeV3 {
  ReconciliationAppliedV3
  ReconciliationTerminalFailedV3
  ReconciliationConfirmedNotAppliedV3
  ReconciliationUnknownV3
} derive(Eq, Debug)

///|
fn ReconciliationOutcomeV3::wire(self : ReconciliationOutcomeV3) -> String {
  match self {
    ReconciliationAppliedV3 => "applied"
    ReconciliationTerminalFailedV3 => "terminal_failed"
    ReconciliationConfirmedNotAppliedV3 => "confirmed_not_applied"
    ReconciliationUnknownV3 => "unknown"
  }
}

///|
fn reconciliation_outcome_from_wire_v3(
  value : String,
) -> ReconciliationOutcomeV3 raise OrchestrationError {
  match value {
    "applied" => ReconciliationAppliedV3
    "terminal_failed" => ReconciliationTerminalFailedV3
    "confirmed_not_applied" => ReconciliationConfirmedNotAppliedV3
    "unknown" => ReconciliationUnknownV3
    _ => raise MalformedInput(field="reconciliation_result_v3_outcome")
  }
}

///|
pub struct ReconciliationResultRecordV3 {
  result_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  dispatch_claim_ref : @contracts.RecordRef
  dispatch_claim_digest : @contracts.ContentDigest
  reconciliation_claim_ref : @contracts.RecordRef
  reconciliation_claim_digest : @contracts.ContentDigest
  query_start_ref : @contracts.RecordRef
  query_start_digest : @contracts.ContentDigest
  policy_binding_ref : @contracts.RecordRef
  policy_binding_digest : @contracts.ContentDigest
  outcome : ReconciliationOutcomeV3
  provider_evidence : ProviderQueryEvidenceV3?
  event_id : String
  command_idempotency_key : String
  observed_at : Int64
  expected_work_revision : Int64
  expected_work_head_digest : @contracts.ContentDigest
  expected_work_replay_digest : @contracts.ContentDigest
  governance_workflow : @contracts.RecordRef
  expected_governance_revision : Int64
  expected_governance_head_digest : @contracts.ContentDigest?
  expected_governance_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn reconciliation_result_signing_bytes_v3(
  result_id : String,
  workflow : @contracts.RecordRef,
  intent_ref : @contracts.RecordRef,
  governed_subject : @contracts.RecordRef,
  dispatch_claim_ref : @contracts.RecordRef,
  dispatch_claim_digest : @contracts.ContentDigest,
  reconciliation_claim_ref : @contracts.RecordRef,
  reconciliation_claim_digest : @contracts.ContentDigest,
  query_start_ref : @contracts.RecordRef,
  query_start_digest : @contracts.ContentDigest,
  policy_binding_ref : @contracts.RecordRef,
  policy_binding_digest : @contracts.ContentDigest,
  outcome : ReconciliationOutcomeV3,
  evidence : ProviderQueryEvidenceV3?,
  event_id : String,
  command_idempotency_key : String,
  observed_at : Int64,
  expected_work_revision : Int64,
  expected_work_head_digest : @contracts.ContentDigest,
  expected_work_replay_digest : @contracts.ContentDigest,
  governance_workflow : @contracts.RecordRef,
  expected_governance_revision : Int64,
  expected_governance_head_digest : @contracts.ContentDigest?,
  expected_governance_replay_digest : @contracts.ContentDigest,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(reconciliation_result_magic_v3)
  writer.string("3.0.0")
  writer.string(result_id)
  write_ref(writer, workflow)
  write_ref(writer, intent_ref)
  write_ref(writer, governed_subject)
  write_ref(writer, dispatch_claim_ref)
  writer.string(dispatch_claim_digest.text())
  write_ref(writer, reconciliation_claim_ref)
  writer.string(reconciliation_claim_digest.text())
  write_ref(writer, query_start_ref)
  writer.string(query_start_digest.text())
  write_ref(writer, policy_binding_ref)
  writer.string(policy_binding_digest.text())
  writer.string(outcome.wire())
  match evidence {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      writer.bytes(value.canonical)
    }
  }
  writer.string(event_id)
  writer.string(command_idempotency_key)
  writer.int64(observed_at)
  writer.int64(expected_work_revision)
  writer.string(expected_work_head_digest.text())
  writer.string(expected_work_replay_digest.text())
  write_ref(writer, governance_workflow)
  writer.int64(expected_governance_revision)
  writer.optional_digest(expected_governance_head_digest)
  writer.string(expected_governance_replay_digest.text())
  writer.finish()
}

///|
fn decode_reconciliation_result_record_v3(
  bytes : Bytes,
) -> ReconciliationResultRecordV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != reconciliation_result_magic_v3 {
    raise MalformedInput(field="reconciliation_result_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="reconciliation_result_v3", version~)
  }
  let result_id = reader.read_string()
  let workflow = reader.read_ref()
  let intent_ref = reader.read_ref()
  let governed_subject = reader.read_ref()
  let dispatch_claim_ref = reader.read_ref()
  let dispatch_claim_digest = reader.read_digest()
  let reconciliation_claim_ref = reader.read_ref()
  let reconciliation_claim_digest = reader.read_digest()
  let query_start_ref = reader.read_ref()
  let query_start_digest = reader.read_digest()
  let policy_binding_ref = reader.read_ref()
  let policy_binding_digest = reader.read_digest()
  let outcome = reconciliation_outcome_from_wire_v3(reader.read_string())
  let evidence = match reader.read_byte() {
    0 => None
    1 => Some(decode_provider_query_evidence_v3(reader.read_bytes()))
    _ => raise MalformedInput(field="reconciliation_result_v3_evidence")
  }
  let event_id = reader.read_string()
  let command_idempotency_key = reader.read_string()
  let observed_at = reader.read_int64()
  let expected_work_revision = reader.read_int64()
  let expected_work_head_digest = reader.read_digest()
  let expected_work_replay_digest = reader.read_digest()
  let governance_workflow = reader.read_ref()
  let expected_governance_revision = reader.read_int64()
  let expected_governance_head_digest = reader.read_optional_digest()
  let expected_governance_replay_digest = reader.read_digest()
  reader.require_end()
  let canonical = reconciliation_result_signing_bytes_v3(
    result_id, workflow, intent_ref, governed_subject, dispatch_claim_ref, dispatch_claim_digest,
    reconciliation_claim_ref, reconciliation_claim_digest, query_start_ref, query_start_digest,
    policy_binding_ref, policy_binding_digest, outcome, evidence, event_id, command_idempotency_key,
    observed_at, expected_work_revision, expected_work_head_digest, expected_work_replay_digest,
    governance_workflow, expected_governance_revision, expected_governance_head_digest,
    expected_governance_replay_digest,
  )
  if canonical != bytes {
    raise DigestMismatch(field="reconciliation_result_v3_noncanonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    result_ref: self_ref_v3(
      "orchestration-reconciliation-result-v3", result_id, digest,
    ),
    workflow,
    intent_ref,
    governed_subject,
    dispatch_claim_ref,
    dispatch_claim_digest,
    reconciliation_claim_ref,
    reconciliation_claim_digest,
    query_start_ref,
    query_start_digest,
    policy_binding_ref,
    policy_binding_digest,
    outcome,
    provider_evidence: evidence,
    event_id,
    command_idempotency_key,
    observed_at,
    expected_work_revision,
    expected_work_head_digest,
    expected_work_replay_digest,
    governance_workflow,
    expected_governance_revision,
    expected_governance_head_digest,
    expected_governance_replay_digest,
    canonical,
    digest,
  }
}

///|
pub struct RecoveryBackoffScheduledV3 {
  backoff_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  result_ref : @contracts.RecordRef
  result_digest : @contracts.ContentDigest
  policy_binding_ref : @contracts.RecordRef
  policy_binding_digest : @contracts.ContentDigest
  reconciliation_ordinal : Int64
  next_due_at : Int64
  deadline : Int64
  event_id : String
  command_idempotency_key : String
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub(all) enum RecoveryAutomationStopReasonV3 {
  RecoveryAttemptsExhaustedV3
  RecoveryDeadlineExceededV3
  RecoveryContradictoryEvidenceV3
} derive(Eq, Debug)

///|
fn RecoveryAutomationStopReasonV3::wire(
  self : RecoveryAutomationStopReasonV3,
) -> String {
  match self {
    RecoveryAttemptsExhaustedV3 => "attempts_exhausted"
    RecoveryDeadlineExceededV3 => "deadline_exceeded"
    RecoveryContradictoryEvidenceV3 => "contradictory_evidence"
  }
}

///|
pub struct RecoveryAutomationStoppedV3 {
  stopped_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  source_ref : @contracts.RecordRef
  source_digest : @contracts.ContentDigest
  policy_binding_ref : @contracts.RecordRef
  policy_binding_digest : @contracts.ContentDigest
  reason : RecoveryAutomationStopReasonV3
  reconciliation_ordinal : Int64
  stopped_at : Int64
  event_id : String
  command_idempotency_key : String
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn recovery_backoff_record_v3(
  result : ReconciliationResultRecordV3,
  policy_binding : RecoveryPolicyBoundV3,
  claim : ReconciliationClaimRecordV3,
  next_due_at : Int64,
  deadline : Int64,
  event_id : String,
) -> RecoveryBackoffScheduledV3 raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_backoff_magic_v3)
  writer.string("3.0.0")
  writer.string(event_id)
  write_ref(writer, result.workflow)
  write_ref(writer, result.intent_ref)
  write_ref(writer, result.result_ref)
  writer.string(result.digest.text())
  write_ref(writer, policy_binding.binding_ref)
  writer.string(policy_binding.digest.text())
  writer.int64(claim.reconciliation_ordinal)
  writer.int64(next_due_at)
  writer.int64(deadline)
  writer.string(result.command_idempotency_key)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    backoff_ref: self_ref_v3(
      "orchestration-recovery-backoff-v3", event_id, digest,
    ),
    workflow: result.workflow,
    intent_ref: result.intent_ref,
    result_ref: result.result_ref,
    result_digest: result.digest,
    policy_binding_ref: policy_binding.binding_ref,
    policy_binding_digest: policy_binding.digest,
    reconciliation_ordinal: claim.reconciliation_ordinal,
    next_due_at,
    deadline,
    event_id,
    command_idempotency_key: result.command_idempotency_key,
    canonical,
    digest,
  }
}

///|
fn recovery_automation_stopped_record_v3(
  result : ReconciliationResultRecordV3,
  policy_binding : RecoveryPolicyBoundV3,
  claim : ReconciliationClaimRecordV3,
  reason : RecoveryAutomationStopReasonV3,
  stopped_at : Int64,
  event_id : String,
) -> RecoveryAutomationStoppedV3 raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_automation_stopped_magic_v3)
  writer.string("3.0.0")
  writer.string(event_id)
  write_ref(writer, result.workflow)
  write_ref(writer, result.intent_ref)
  write_ref(writer, result.result_ref)
  writer.string(result.digest.text())
  write_ref(writer, policy_binding.binding_ref)
  writer.string(policy_binding.digest.text())
  writer.string(reason.wire())
  writer.int64(claim.reconciliation_ordinal)
  writer.int64(stopped_at)
  writer.string(result.command_idempotency_key)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    stopped_ref: self_ref_v3(
      "orchestration-recovery-automation-stopped-v3", event_id, digest,
    ),
    workflow: result.workflow,
    intent_ref: result.intent_ref,
    source_ref: result.result_ref,
    source_digest: result.digest,
    policy_binding_ref: policy_binding.binding_ref,
    policy_binding_digest: policy_binding.digest,
    reason,
    reconciliation_ordinal: claim.reconciliation_ordinal,
    stopped_at,
    event_id,
    command_idempotency_key: result.command_idempotency_key,
    canonical,
    digest,
  }
}

///|
fn decode_recovery_backoff_scheduled_v3(
  bytes : Bytes,
) -> RecoveryBackoffScheduledV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != recovery_backoff_magic_v3 ||
    reader.read_string() != "3.0.0" {
    raise MalformedInput(field="recovery_backoff_v3_magic")
  }
  let event_id = reader.read_string()
  let workflow = reader.read_ref()
  let intent_ref = reader.read_ref()
  let result_ref = reader.read_ref()
  let result_digest = reader.read_digest()
  let policy_binding_ref = reader.read_ref()
  let policy_binding_digest = reader.read_digest()
  let reconciliation_ordinal = reader.read_int64()
  let next_due_at = reader.read_int64()
  let deadline = reader.read_int64()
  let command_idempotency_key = reader.read_string()
  reader.require_end()
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_backoff_magic_v3)
  writer.string("3.0.0")
  writer.string(event_id)
  write_ref(writer, workflow)
  write_ref(writer, intent_ref)
  write_ref(writer, result_ref)
  writer.string(result_digest.text())
  write_ref(writer, policy_binding_ref)
  writer.string(policy_binding_digest.text())
  writer.int64(reconciliation_ordinal)
  writer.int64(next_due_at)
  writer.int64(deadline)
  writer.string(command_idempotency_key)
  let canonical = writer.finish()
  if canonical != bytes ||
    reconciliation_ordinal <= 0L ||
    next_due_at < 0L ||
    deadline < 0L ||
    next_due_at > deadline {
    raise DigestMismatch(field="recovery_backoff_v3_noncanonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    backoff_ref: self_ref_v3(
      "orchestration-recovery-backoff-v3", event_id, digest,
    ),
    workflow,
    intent_ref,
    result_ref,
    result_digest,
    policy_binding_ref,
    policy_binding_digest,
    reconciliation_ordinal,
    next_due_at,
    deadline,
    event_id,
    command_idempotency_key,
    canonical,
    digest,
  }
}

///|
fn recovery_automation_stop_reason_from_wire_v3(
  value : String,
) -> RecoveryAutomationStopReasonV3 raise OrchestrationError {
  match value {
    "attempts_exhausted" => RecoveryAttemptsExhaustedV3
    "deadline_exceeded" => RecoveryDeadlineExceededV3
    "contradictory_evidence" => RecoveryContradictoryEvidenceV3
    _ => raise MalformedInput(field="recovery_automation_stopped_v3_reason")
  }
}

///|
fn decode_recovery_automation_stopped_v3(
  bytes : Bytes,
) -> RecoveryAutomationStoppedV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != recovery_automation_stopped_magic_v3 ||
    reader.read_string() != "3.0.0" {
    raise MalformedInput(field="recovery_automation_stopped_v3_magic")
  }
  let event_id = reader.read_string()
  let workflow = reader.read_ref()
  let intent_ref = reader.read_ref()
  let source_ref = reader.read_ref()
  let source_digest = reader.read_digest()
  let policy_binding_ref = reader.read_ref()
  let policy_binding_digest = reader.read_digest()
  let reason = recovery_automation_stop_reason_from_wire_v3(
    reader.read_string(),
  )
  let reconciliation_ordinal = reader.read_int64()
  let stopped_at = reader.read_int64()
  let command_idempotency_key = reader.read_string()
  reader.require_end()
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_automation_stopped_magic_v3)
  writer.string("3.0.0")
  writer.string(event_id)
  write_ref(writer, workflow)
  write_ref(writer, intent_ref)
  write_ref(writer, source_ref)
  writer.string(source_digest.text())
  write_ref(writer, policy_binding_ref)
  writer.string(policy_binding_digest.text())
  writer.string(reason.wire())
  writer.int64(reconciliation_ordinal)
  writer.int64(stopped_at)
  writer.string(command_idempotency_key)
  let canonical = writer.finish()
  if canonical != bytes || reconciliation_ordinal <= 0L || stopped_at < 0L {
    raise DigestMismatch(field="recovery_automation_stopped_v3_noncanonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    stopped_ref: self_ref_v3(
      "orchestration-recovery-automation-stopped-v3", event_id, digest,
    ),
    workflow,
    intent_ref,
    source_ref,
    source_digest,
    policy_binding_ref,
    policy_binding_digest,
    reason,
    reconciliation_ordinal,
    stopped_at,
    event_id,
    command_idempotency_key,
    canonical,
    digest,
  }
}

///|
fn recovery_auxiliary_event_v3(
  workflow : @contracts.RecordRef,
  subject : @contracts.RecordRef,
  source_ref : @contracts.RecordRef,
  record_ref : @contracts.RecordRef,
  kind : String,
  event_id : String,
  payload : Bytes,
  sequence : Int64,
  revision : Int64,
  previous_digest : @contracts.ContentDigest,
) -> @storage.WorkflowEvent raise OrchestrationError {
  let evidence : Array[@contracts.EvidenceRef] = []
  let envelope = @contracts.WireEnvelope::new(
    dispatch_claim_transport_contract_id_v3,
    orchestration_record_version,
    event_id,
    kind,
    subject,
    phase1b_effect_schema_v22(kind),
    payload,
    dispatch_claim_transport_producer_id_v3,
    orchestration_record_version,
    [],
    evidence,
    run_ref=workflow,
    correlation_ref=workflow.id(),
    causation_ref=source_ref.id(),
    idempotency_ref=record_ref.id(),
    previous_digest~,
  ) catch {
    _ => raise MalformedInput(field="recovery_auxiliary_envelope_v3")
  }
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    workflow,
    event_id,
    sequence,
    revision,
    record_ref.id(),
    envelope,
    evidence,
    previous_event_digest=previous_digest,
  ) catch {
    _ => raise MalformedInput(field="recovery_auxiliary_event_v3")
  }
}

///|
fn bytes_have_reconciliation_result_magic_v3(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    magic => magic == reconciliation_result_magic_v3
  }
}

///|
fn bytes_have_recovery_backoff_magic_v3(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    magic => magic == recovery_backoff_magic_v3
  }
}

///|
fn bytes_have_recovery_automation_stopped_magic_v3(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    magic => magic == recovery_automation_stopped_magic_v3
  }
}

///|
fn require_reconciliation_result_binding_v3(
  record : ReconciliationResultRecordV3,
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let envelope = event.payload()
  if record.observed_at < 0L ||
    event.record_version().text() != orchestration_record_version ||
    event.schema_version().text() != orchestration_schema_version ||
    event.workflow() != record.workflow ||
    event.event_ref().id() != record.event_id ||
    event.sequence() != event.revision() ||
    event.revision() != record.expected_work_revision + 1L ||
    event.previous_event_digest() != Some(record.expected_work_head_digest) ||
    event.idempotency_key() != record.result_ref.id() ||
    envelope.envelope_id() != event.event_ref().id() ||
    envelope.contract_id() != dispatch_claim_transport_contract_id_v3 ||
    envelope.contract_version().text() != orchestration_record_version ||
    envelope.producer_id() != dispatch_claim_transport_producer_id_v3 ||
    envelope.producer_version().text() != orchestration_record_version ||
    envelope.envelope_kind() != reconciliation_result_event_kind_v3 ||
    envelope.subject() != record.governed_subject ||
    envelope.run_ref() != Some(record.workflow) ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() is Some(_) ||
    envelope.correlation_ref() != Some(record.workflow.id()) ||
    envelope.causation_ref() != Some(record.reconciliation_claim_ref.id()) ||
    envelope.idempotency_ref() != Some(record.result_ref.id()) ||
    envelope.previous_digest() != Some(record.expected_work_head_digest) ||
    envelope.schema() !=
    phase1b_effect_schema_v22(reconciliation_result_event_kind_v3) ||
    envelope.payload() != record.canonical ||
    !event.evidence().is_empty() ||
    !envelope.evidence().is_empty() ||
    !envelope.artifacts().is_empty() ||
    !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(field="reconciliation_result_v3_transport")
  }
  let batches = replay
    .committed_batches()
    .filter(batch => batch.event_refs().any(value => value == event.event_ref()))
  let expected_events = if record.outcome == ReconciliationUnknownV3 {
    2
  } else {
    1
  }
  if !try_require_callback_reconciliation_result_transaction_v3(
      record, event, replay,
    ) {
    if batches.length() != 1 ||
      batches[0].expected_revision() != record.expected_work_revision ||
      batches[0].command_idempotency_key() != record.command_idempotency_key ||
      batches[0].event_refs().length() != expected_events ||
      batches[0].event_refs()[0] != event.event_ref() ||
      !batches[0].intent_refs().is_empty() ||
      batches[0].guards().length() != 1 {
      raise ReplayBindingViolation(field="reconciliation_result_v3_transaction")
    }
    let head_guard = batches[0].guards()[0]
    if head_guard.workflow() != record.governance_workflow ||
      head_guard.expected_revision() != record.expected_governance_revision ||
      head_guard.expected_head_digest() !=
      record.expected_governance_head_digest ||
      head_guard.expected_replay_digest() !=
      record.expected_governance_replay_digest {
      raise ReplayBindingViolation(field="reconciliation_result_v3_guard")
    }
  }
  let prefix = verified_prefix_v3(
    replay,
    record.expected_work_revision,
    "reconciliation_result_v3_prefix",
  )
  if prefix.head().last_event_digest() != Some(record.expected_work_head_digest) ||
    prefix.replay_digest() != record.expected_work_replay_digest {
    raise ReplayBindingViolation(field="reconciliation_result_v3_prefix")
  }
}

///|
fn recovery_auxiliary_source_v3(
  replay : @storage.ReplayResult,
  source_ref : @contracts.RecordRef,
  source_digest : @contracts.ContentDigest,
) -> (@storage.WorkflowEvent, ReconciliationResultRecordV3) raise OrchestrationError {
  guard first(replay.events(), event => {
      event.payload().envelope_kind() == reconciliation_result_event_kind_v3 &&
      event.payload().idempotency_ref() == Some(source_ref.id())
    })
    is Some(event) else {
    raise ReplayBindingViolation(field="recovery_auxiliary_v3_source")
  }
  let result = decode_reconciliation_result_record_v3(event.payload().payload())
  if result.result_ref != source_ref ||
    result.digest != source_digest ||
    result.outcome != ReconciliationUnknownV3 {
    raise ReplayBindingViolation(field="recovery_auxiliary_v3_source")
  }
  (event, result)
}

///|
fn require_recovery_backoff_binding_v3(
  record : RecoveryBackoffScheduledV3,
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let (source_event, source) = recovery_auxiliary_source_v3(
    replay,
    record.result_ref,
    record.result_digest,
  )
  let envelope = event.payload()
  if record.workflow != source.workflow ||
    record.intent_ref != source.intent_ref ||
    record.policy_binding_ref != source.policy_binding_ref ||
    record.policy_binding_digest != source.policy_binding_digest ||
    record.command_idempotency_key != source.command_idempotency_key ||
    event.workflow() != record.workflow ||
    event.event_ref().id() != record.event_id ||
    event.sequence() != source_event.sequence() + 1L ||
    event.revision() != source_event.revision() + 1L ||
    event.previous_event_digest() != Some(source_event.event_ref().digest()) ||
    event.idempotency_key() != record.backoff_ref.id() ||
    envelope.envelope_id() != event.event_ref().id() ||
    envelope.contract_id() != dispatch_claim_transport_contract_id_v3 ||
    envelope.contract_version().text() != orchestration_record_version ||
    envelope.producer_id() != dispatch_claim_transport_producer_id_v3 ||
    envelope.producer_version().text() != orchestration_record_version ||
    envelope.envelope_kind() != recovery_backoff_event_kind_v3 ||
    envelope.subject() != source.governed_subject ||
    envelope.run_ref() != Some(record.workflow) ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() is Some(_) ||
    envelope.correlation_ref() != Some(record.workflow.id()) ||
    envelope.causation_ref() != Some(record.result_ref.id()) ||
    envelope.idempotency_ref() != Some(record.backoff_ref.id()) ||
    envelope.previous_digest() != Some(source_event.event_ref().digest()) ||
    envelope.schema() !=
    phase1b_effect_schema_v22(recovery_backoff_event_kind_v3) ||
    envelope.payload() != record.canonical ||
    !event.evidence().is_empty() ||
    !envelope.evidence().is_empty() ||
    !envelope.artifacts().is_empty() ||
    !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(field="recovery_backoff_v3_transport")
  }
  let batches = replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().any(value => value == source_event.event_ref())
    })
  if batches.length() != 1 ||
    batches[0].event_refs().length() != 2 ||
    batches[0].event_refs()[0] != source_event.event_ref() ||
    batches[0].event_refs()[1] != event.event_ref() ||
    batches[0].command_idempotency_key() != record.command_idempotency_key ||
    !batches[0].intent_refs().is_empty() {
    raise ReplayBindingViolation(field="recovery_backoff_v3_transaction")
  }
}

///|
fn require_recovery_automation_stopped_binding_v3(
  record : RecoveryAutomationStoppedV3,
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let (source_event, source) = recovery_auxiliary_source_v3(
    replay,
    record.source_ref,
    record.source_digest,
  )
  let envelope = event.payload()
  if record.workflow != source.workflow ||
    record.intent_ref != source.intent_ref ||
    record.policy_binding_ref != source.policy_binding_ref ||
    record.policy_binding_digest != source.policy_binding_digest ||
    record.command_idempotency_key != source.command_idempotency_key ||
    event.workflow() != record.workflow ||
    event.event_ref().id() != record.event_id ||
    event.sequence() != source_event.sequence() + 1L ||
    event.revision() != source_event.revision() + 1L ||
    event.previous_event_digest() != Some(source_event.event_ref().digest()) ||
    event.idempotency_key() != record.stopped_ref.id() ||
    envelope.envelope_id() != event.event_ref().id() ||
    envelope.contract_id() != dispatch_claim_transport_contract_id_v3 ||
    envelope.contract_version().text() != orchestration_record_version ||
    envelope.producer_id() != dispatch_claim_transport_producer_id_v3 ||
    envelope.producer_version().text() != orchestration_record_version ||
    envelope.envelope_kind() != recovery_automation_stopped_event_kind_v3 ||
    envelope.subject() != source.governed_subject ||
    envelope.run_ref() != Some(record.workflow) ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() is Some(_) ||
    envelope.correlation_ref() != Some(record.workflow.id()) ||
    envelope.causation_ref() != Some(record.source_ref.id()) ||
    envelope.idempotency_ref() != Some(record.stopped_ref.id()) ||
    envelope.previous_digest() != Some(source_event.event_ref().digest()) ||
    envelope.schema() !=
    phase1b_effect_schema_v22(recovery_automation_stopped_event_kind_v3) ||
    envelope.payload() != record.canonical ||
    !event.evidence().is_empty() ||
    !envelope.evidence().is_empty() ||
    !envelope.artifacts().is_empty() ||
    !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(
      field="recovery_automation_stopped_v3_transport",
    )
  }
  let batches = replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().any(value => value == source_event.event_ref())
    })
  if batches.length() != 1 ||
    batches[0].event_refs().length() != 2 ||
    batches[0].event_refs()[0] != source_event.event_ref() ||
    batches[0].event_refs()[1] != event.event_ref() ||
    batches[0].command_idempotency_key() != record.command_idempotency_key ||
    !batches[0].intent_refs().is_empty() {
    raise ReplayBindingViolation(
      field="recovery_automation_stopped_v3_transaction",
    )
  }
}

///|
fn require_reconciliation_result_prefix_v3(
  empty : @effects.EffectsProjection,
  record : ReconciliationResultRecordV3,
  work_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let work_prefix = verified_prefix_v3(
    work_replay,
    record.expected_work_revision,
    "reconciliation_result_v3_work_prefix",
  )
  let governance_prefix = verified_prefix_v3(
    governance_replay,
    record.expected_governance_revision,
    "reconciliation_result_v3_governance_prefix",
  )
  if governance_prefix.workflow() != record.governance_workflow ||
    governance_prefix.head().last_event_digest() !=
    record.expected_governance_head_digest ||
    governance_prefix.replay_digest() !=
    record.expected_governance_replay_digest {
    raise ReplayBindingViolation(field="reconciliation_result_v3_governance")
  }
  let prefix = fold_governed_recovery_v3(empty, work_prefix, governance_prefix)
  guard prefix.current_claim(record.intent_ref) is Some(dispatch) else {
    raise ReplayBindingViolation(field="reconciliation_result_v3_dispatch")
  }
  guard prefix.current_reconciliation_claim_v3(record.intent_ref) is Some(claim) else {
    raise ReplayBindingViolation(field="reconciliation_result_v3_claim")
  }
  guard first(prefix.reconciliation_query_starts, started => {
      started.query_start_ref == record.query_start_ref
    })
    is Some(started) else {
    raise ReplayBindingViolation(field="reconciliation_result_v3_query_start")
  }
  guard prefix.recovery_policy_for_v3(record.intent_ref) is Some(policy) else {
    raise ReplayBindingViolation(field="reconciliation_result_v3_policy")
  }
  if dispatch.claim_ref != record.dispatch_claim_ref ||
    dispatch.digest != record.dispatch_claim_digest ||
    claim.reconciliation_claim_ref != record.reconciliation_claim_ref ||
    claim.digest != record.reconciliation_claim_digest ||
    started.digest != record.query_start_digest ||
    policy.binding_ref != record.policy_binding_ref ||
    policy.digest != record.policy_binding_digest ||
    record.observed_at < claim.claimed_at ||
    prefix.current_reconciliation_result_v3(record.intent_ref) is Some(_) {
    raise ReplayBindingViolation(field="reconciliation_result_v3_source")
  }
  let evidence_ok = match (record.outcome, record.provider_evidence) {
    (ReconciliationAppliedV3, Some(value)) =>
      value.evidence_kind == ProviderQueryAppliedEvidenceV3
    (ReconciliationTerminalFailedV3, Some(value)) =>
      value.evidence_kind == ProviderQueryTerminalFailedEvidenceV3
    (ReconciliationConfirmedNotAppliedV3, Some(value)) =>
      value.evidence_kind == ProviderQueryTombstoneBarrierEvidenceV3 &&
      value.not_applied_proof is Some(_)
    (ReconciliationUnknownV3, None) => true
    (ReconciliationUnknownV3, Some(value)) =>
      value.evidence_kind != ProviderQueryAppliedEvidenceV3 &&
      value.evidence_kind != ProviderQueryTerminalFailedEvidenceV3 &&
      value.evidence_kind != ProviderQueryTombstoneBarrierEvidenceV3
    _ => false
  }
  if !evidence_ok {
    raise ReplayBindingViolation(field="reconciliation_result_v3_evidence")
  }
  match record.provider_evidence {
    None => ()
    Some(value) =>
      if value.external_idempotency_key != dispatch.external_idempotency_key ||
        value.dispatch_claim_ref != dispatch.claim_ref ||
        value.dispatch_fencing_token != dispatch.fencing_token ||
        value.reconciliation_claim_ref != claim.reconciliation_claim_ref ||
        value.reconciliation_fencing_token != claim.fencing_token ||
        value.source_at < dispatch.claimed_at ||
        value.retrieved_at != record.observed_at {
        raise ReplayBindingViolation(field="reconciliation_result_v3_evidence")
      }
  }
}

///|
fn normalize_provider_query_result_v3(
  result : ProviderQueryResultV3,
  dispatch : DispatchClaimRecordV3,
  claim : ReconciliationClaimRecordV3,
  observed_at : Int64,
) -> (ReconciliationOutcomeV3, ProviderQueryEvidenceV3?) {
  let valid = fn(evidence : ProviderQueryEvidenceV3) {
    evidence.external_idempotency_key == dispatch.external_idempotency_key &&
    evidence.dispatch_claim_ref == dispatch.claim_ref &&
    evidence.dispatch_fencing_token == dispatch.fencing_token &&
    evidence.reconciliation_claim_ref == claim.reconciliation_claim_ref &&
    evidence.reconciliation_fencing_token == claim.fencing_token &&
    evidence.retrieved_at == observed_at
  }
  match result {
    ProviderQueryAppliedV3(evidence) if valid(evidence) &&
      evidence.evidence_kind == ProviderQueryAppliedEvidenceV3 =>
      (ReconciliationAppliedV3, Some(evidence))
    ProviderQueryTerminalFailedV3(evidence) if valid(evidence) &&
      evidence.evidence_kind == ProviderQueryTerminalFailedEvidenceV3 =>
      (ReconciliationTerminalFailedV3, Some(evidence))
    ProviderQueryConfirmedNotAppliedV3(evidence) if valid(evidence) &&
      evidence.evidence_kind == ProviderQueryTombstoneBarrierEvidenceV3 &&
      evidence.not_applied_proof is Some(_) =>
      (ReconciliationConfirmedNotAppliedV3, Some(evidence))
    ProviderQueryStillUnknownV3(Some(evidence)) if valid(evidence) &&
      evidence.evidence_kind != ProviderQueryAppliedEvidenceV3 &&
      evidence.evidence_kind != ProviderQueryTerminalFailedEvidenceV3 &&
      evidence.evidence_kind != ProviderQueryTombstoneBarrierEvidenceV3 =>
      (ReconciliationUnknownV3, Some(evidence))
    _ => (ReconciliationUnknownV3, None)
  }
}

///|
fn make_reconciliation_result_record_v3(
  current : CurrentGovernedRecoveryProjectionV3,
  dispatch : DispatchClaimRecordV3,
  claim : ReconciliationClaimRecordV3,
  started : ReconciliationQueryStartedV3,
  policy : RecoveryPolicyBoundV3,
  outcome : ReconciliationOutcomeV3,
  evidence : ProviderQueryEvidenceV3?,
  result_id : String,
  event_id : String,
  command_idempotency_key : String,
  observed_at : Int64,
) -> ReconciliationResultRecordV3 raise OrchestrationError {
  let canonical = reconciliation_result_signing_bytes_v3(
    result_id,
    dispatch.workflow,
    dispatch.intent_ref,
    dispatch.governed_subject,
    dispatch.claim_ref,
    dispatch.digest,
    claim.reconciliation_claim_ref,
    claim.digest,
    started.query_start_ref,
    started.digest,
    policy.binding_ref,
    policy.digest,
    outcome,
    evidence,
    event_id,
    command_idempotency_key,
    observed_at,
    current.current.work_revision,
    current.current.work_head_digest,
    current.current.work_replay_digest,
    current.governance_replay.workflow(),
    current.current.governance_revision,
    current.current.governance_head_digest,
    current.current.governance_replay_digest,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    result_ref: self_ref_v3(
      "orchestration-reconciliation-result-v3", result_id, digest,
    ),
    workflow: dispatch.workflow,
    intent_ref: dispatch.intent_ref,
    governed_subject: dispatch.governed_subject,
    dispatch_claim_ref: dispatch.claim_ref,
    dispatch_claim_digest: dispatch.digest,
    reconciliation_claim_ref: claim.reconciliation_claim_ref,
    reconciliation_claim_digest: claim.digest,
    query_start_ref: started.query_start_ref,
    query_start_digest: started.digest,
    policy_binding_ref: policy.binding_ref,
    policy_binding_digest: policy.digest,
    outcome,
    provider_evidence: evidence,
    event_id,
    command_idempotency_key,
    observed_at,
    expected_work_revision: current.current.work_revision,
    expected_work_head_digest: current.current.work_head_digest,
    expected_work_replay_digest: current.current.work_replay_digest,
    governance_workflow: current.governance_replay.workflow(),
    expected_governance_revision: current.current.governance_revision,
    expected_governance_head_digest: current.current.governance_head_digest,
    expected_governance_replay_digest: current.current.governance_replay_digest,
    canonical,
    digest,
  }
}

///|
fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] persist_reconciliation_result_v3(
  store : S,
  candidate : ReconciliationClaimCandidateV3,
  outcome : ReconciliationOutcomeV3,
  evidence : ProviderQueryEvidenceV3?,
  result_id : String,
  event_id : String,
  auxiliary_event_id : String,
  observed_at : Int64,
) -> Bool {
  try {
    let work = store.replay(candidate.claim.workflow)
    let governance = store.replay_registered_guard(
      candidate.claim.governance_workflow,
    )
    let current = fold_governed_recovery_v3(
      candidate.empty_effects,
      work,
      governance,
    )
    guard current.current_reconciliation_claim_v3(candidate.claim.intent_ref)
      is Some(claim) else {
      return false
    }
    if claim.reconciliation_claim_ref !=
      candidate.claim.reconciliation_claim_ref {
      return false
    }
    guard first(current.reconciliation_query_starts, started => {
        started.reconciliation_claim_ref == claim.reconciliation_claim_ref
      })
      is Some(started) else {
      return false
    }
    guard current.recovery_policy_for_v3(claim.intent_ref) is Some(policy) else {
      return false
    }
    guard current.current_claim(claim.intent_ref) is Some(dispatch) else {
      return false
    }
    let command = claim.command_idempotency_key + ":result"
    let result = make_reconciliation_result_record_v3(
      current, dispatch, claim, started, policy, outcome, evidence, result_id, event_id,
      command, observed_at,
    )
    let first_event = recovery_auxiliary_event_v3(
      result.workflow,
      result.governed_subject,
      result.reconciliation_claim_ref,
      result.result_ref,
      reconciliation_result_event_kind_v3,
      result.event_id,
      result.canonical,
      current.current.work_sequence + 1L,
      current.current.work_revision + 1L,
      current.current.work_head_digest,
    )
    let events : Array[@storage.WorkflowEvent] = [first_event]
    if outcome == ReconciliationUnknownV3 {
      let deadline = match
        @decision.recovery_deadline(
          dispatch.claimed_at,
          policy.policy.maximum_elapsed,
        ) {
        @decision.RecoveryDueAt(value) => value
        _ => return false
      }
      let exhausted = claim.reconciliation_ordinal >=
        policy.policy.maximum_reconciliation_attempts ||
        observed_at >= deadline
      if exhausted {
        let reason = if observed_at >= deadline {
          RecoveryDeadlineExceededV3
        } else {
          RecoveryAttemptsExhaustedV3
        }
        let stopped = recovery_automation_stopped_record_v3(
          result, policy, claim, reason, observed_at, auxiliary_event_id,
        )
        events.push(
          recovery_auxiliary_event_v3(
            stopped.workflow,
            result.governed_subject,
            result.result_ref,
            stopped.stopped_ref,
            recovery_automation_stopped_event_kind_v3,
            stopped.event_id,
            stopped.canonical,
            first_event.sequence() + 1L,
            first_event.revision() + 1L,
            first_event.event_ref().digest(),
          ),
        )
      } else {
        let material = @utf8.encode(
          "\{policy.policy.seed.text()}:\{claim.reconciliation_claim_ref.id()}:\{claim.reconciliation_ordinal}",
        )
        let due = match
          @decision.recovery_due_at(
            observed_at,
            policy.policy.base_delay,
            policy.policy.maximum_delay,
            policy.policy.backoff_numerator,
            policy.policy.backoff_denominator,
            claim.reconciliation_ordinal,
            policy.policy.jitter_range,
            material,
          ) {
          @decision.RecoveryDueAt(value) => value
          _ => return false
        }
        if due > deadline {
          let stopped = recovery_automation_stopped_record_v3(
            result,
            policy,
            claim,
            RecoveryDeadlineExceededV3,
            observed_at,
            auxiliary_event_id,
          )
          events.push(
            recovery_auxiliary_event_v3(
              stopped.workflow,
              result.governed_subject,
              result.result_ref,
              stopped.stopped_ref,
              recovery_automation_stopped_event_kind_v3,
              stopped.event_id,
              stopped.canonical,
              first_event.sequence() + 1L,
              first_event.revision() + 1L,
              first_event.event_ref().digest(),
            ),
          )
        } else {
          let backoff = recovery_backoff_record_v3(
            result, policy, claim, due, deadline, auxiliary_event_id,
          )
          events.push(
            recovery_auxiliary_event_v3(
              backoff.workflow,
              result.governed_subject,
              result.result_ref,
              backoff.backoff_ref,
              recovery_backoff_event_kind_v3,
              backoff.event_id,
              backoff.canonical,
              first_event.sequence() + 1L,
              first_event.revision() + 1L,
              first_event.event_ref().digest(),
            ),
          )
        }
      }
    }
    let request = @storage.CommitRequest::new(
      orchestration_record_version,
      orchestration_schema_version,
      result.workflow,
      result.expected_work_revision,
      result.command_idempotency_key,
      events,
      [],
    )
    let guarded = @storage.GuardedCommitRequest::new(request, [
      @storage.WorkflowHeadGuard::new(
        governance.workflow(),
        governance.head().revision(),
        governance.head().last_event_digest(),
        governance.replay_digest(),
      ),
    ])
    require_phase2_governance_guard_profile_v3(store, guarded)
    match store.classified_guarded_commit(guarded) {
      @storage.FreshlyApplied(_) | @storage.AlreadyCommitted(_) => true
      @storage.GuardRejected(_) => false
    }
  } catch {
    _ => false
  }
}

///|
pub(all) enum GuardedRecoveryQueryDispositionV3 {
  GuardedRecoveryQueryObservedV3(ReconciliationOutcomeV3)
  GuardedRecoveryQueryAlreadyCommittedV3
  GuardedRecoveryQueryRaceLostNoCallV3
  GuardedRecoveryQueryStaleGovernanceNoCallV3
} derive(Eq, Debug)

///|
pub struct GuardedRecoveryQueryResultV3 {
  disposition : GuardedRecoveryQueryDispositionV3
  reconciliation_claim_ref : @contracts.RecordRef?
  query_start_ref : @contracts.RecordRef?
  provider_evidence : ProviderQueryEvidenceV3?
  result_persisted : Bool
}

///|
pub fn[
  S : @storage.ClassifiedRegistryBoundGuardedStoragePort,
  P : GuardedRecoveryQueryPortV3,
] reconcile_guarded_effect_v3(
  store : S,
  current : CurrentGovernedRecoveryProjectionV3,
  port : P,
  intent_ref : @contracts.RecordRef,
  claim_id : String,
  claim_event_id : String,
  query_started_event_id : String,
  command_idempotency_key : String,
  result_id : String,
  result_event_id : String,
  auxiliary_event_id : String,
  claimed_at : Int64,
  observed_at : Int64,
) -> GuardedRecoveryQueryResultV3 raise {
  require_text(result_id, "reconciliation_result_v3_id")
  require_text(result_event_id, "reconciliation_result_v3_event")
  require_text(auxiliary_event_id, "reconciliation_auxiliary_v3_event")
  if observed_at < claimed_at {
    raise OrderingViolation(field="reconciliation_result_v3_time")
  }
  match current.current_reconciliation_claim_v3(intent_ref) {
    Some(existing) if existing.command_idempotency_key ==
      command_idempotency_key => {
      if existing.reconciliation_claim_ref.id() != claim_id ||
        existing.claim_event_id != claim_event_id ||
        existing.query_started_event_id != query_started_event_id ||
        existing.claimed_at != claimed_at {
        raise IdempotencyConflict(key=command_idempotency_key)
      }
      guard first(current.reconciliation_query_starts, started => {
          started.reconciliation_claim_ref == existing.reconciliation_claim_ref &&
          started.reconciliation_claim_digest == existing.digest
        })
        is Some(started) else {
        raise ReplayBindingViolation(
          field="reconciliation_query_started_v3_missing",
        )
      }
      let committed_result = current.current_reconciliation_result_v3(
        intent_ref,
      )
      return {
        disposition: GuardedRecoveryQueryAlreadyCommittedV3,
        reconciliation_claim_ref: Some(existing.reconciliation_claim_ref),
        query_start_ref: Some(started.query_start_ref),
        provider_evidence: match committed_result {
          Some(value) => value.provider_evidence
          None => None
        },
        result_persisted: committed_result is Some(_),
      }
    }
    _ => ()
  }
  let candidate = current.prepare_reconciliation_claim_v3(
    intent_ref, claim_id, claim_event_id, query_started_event_id, command_idempotency_key,
    claimed_at,
  )
  let profile = port.recovery_profile()
  if profile.digest != candidate.claim.provider_profile_digest ||
    !profile.supports_authoritative_query() {
    raise RecoveryViolation(field="guarded_recovery_query_v3_profile")
  }
  match commit_reconciliation_claim_v3(store, candidate) {
    ReconciliationClaimAlreadyCommittedV3 =>
      {
        disposition: GuardedRecoveryQueryAlreadyCommittedV3,
        reconciliation_claim_ref: Some(candidate.claim.reconciliation_claim_ref),
        query_start_ref: Some(candidate.started.query_start_ref),
        provider_evidence: None,
        result_persisted: false,
      }
    ReconciliationClaimRaceLostV3 =>
      {
        disposition: GuardedRecoveryQueryRaceLostNoCallV3,
        reconciliation_claim_ref: None,
        query_start_ref: None,
        provider_evidence: None,
        result_persisted: false,
      }
    ReconciliationClaimStaleGovernanceV3 =>
      {
        disposition: GuardedRecoveryQueryStaleGovernanceNoCallV3,
        reconciliation_claim_ref: None,
        query_start_ref: None,
        provider_evidence: None,
        result_persisted: false,
      }
    ReconciliationClaimFreshV3 => {
      let durable_work = store.replay(candidate.claim.workflow)
      let durable_governance = store.replay_registered_guard(
        candidate.claim.governance_workflow,
      )
      let durable = fold_governed_recovery_v3(
        candidate.empty_effects,
        durable_work,
        durable_governance,
      )
      guard durable.current_claim(intent_ref) is Some(dispatch) else {
        raise RecoveryViolation(field="guarded_recovery_query_v3_dispatch")
      }
      guard durable.current_reconciliation_claim_v3(intent_ref) is Some(claim) else {
        raise RecoveryViolation(field="guarded_recovery_query_v3_claim")
      }
      guard first(durable.reconciliation_query_starts, started => {
          started.reconciliation_claim_ref == claim.reconciliation_claim_ref
        })
        is Some(started) else {
        raise RecoveryViolation(field="guarded_recovery_query_v3_start")
      }
      let call = guarded_recovery_query_call_v3(
        dispatch,
        claim,
        started,
        durable_work.replay_digest(),
      )
      let (normalized_outcome, normalized_evidence) = normalize_provider_query_result_v3(
        port.query_guarded_effect(call),
        dispatch,
        claim,
        observed_at,
      ) catch {
        _ => (ReconciliationUnknownV3, None)
      }
      let (outcome, evidence) = if normalized_outcome ==
        ReconciliationConfirmedNotAppliedV3 &&
        !profile.supports_authoritative_tombstone() {
        (ReconciliationUnknownV3, None)
      } else {
        (normalized_outcome, normalized_evidence)
      }
      let persisted = persist_reconciliation_result_v3(
        store, candidate, outcome, evidence, result_id, result_event_id, auxiliary_event_id,
        observed_at,
      )
      {
        disposition: GuardedRecoveryQueryObservedV3(outcome),
        reconciliation_claim_ref: Some(claim.reconciliation_claim_ref),
        query_start_ref: Some(started.query_start_ref),
        provider_evidence: evidence,
        result_persisted: persisted,
      }
    }
  }
}

///|
pub fn GuardedRecoveryQueryCallV3::external_idempotency_key(
  self : GuardedRecoveryQueryCallV3,
) -> String {
  self.external_idempotency_key
}

///|
pub fn GuardedRecoveryQueryCallV3::provider_operation(
  self : GuardedRecoveryQueryCallV3,
) -> @contracts.WireEnvelope {
  self.provider_operation
}

///|
pub fn GuardedRecoveryQueryCallV3::owner(
  self : GuardedRecoveryQueryCallV3,
) -> @contracts.RecordRef {
  self.owner
}

///|
pub fn GuardedRecoveryQueryCallV3::reconciliation_ordinal(
  self : GuardedRecoveryQueryCallV3,
) -> Int64 {
  self.reconciliation_ordinal
}

///|
pub fn GuardedRecoveryQueryCallV3::dispatch_fencing_token(
  self : GuardedRecoveryQueryCallV3,
) -> Int64 {
  self.dispatch_fencing_token
}

///|
pub fn GuardedRecoveryQueryCallV3::reconciliation_fencing_token(
  self : GuardedRecoveryQueryCallV3,
) -> Int64 {
  self.reconciliation_fencing_token
}

///|
pub fn GuardedRecoveryQueryCallV3::reconciliation_claim_ref(
  self : GuardedRecoveryQueryCallV3,
) -> @contracts.RecordRef {
  self.reconciliation_claim_ref
}

///|
pub fn GuardedRecoveryQueryCallV3::permitted_evidence(
  self : GuardedRecoveryQueryCallV3,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.permitted_evidence
}

///|
pub fn GuardedRecoveryQueryCallV3::canonical_bytes(
  self : GuardedRecoveryQueryCallV3,
) -> Bytes {
  self.canonical
}

///|
pub fn GuardedRecoveryQueryCallV3::digest(
  self : GuardedRecoveryQueryCallV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn GuardedRecoveryQueryResultV3::disposition(
  self : GuardedRecoveryQueryResultV3,
) -> GuardedRecoveryQueryDispositionV3 {
  self.disposition
}

///|
pub fn GuardedRecoveryQueryResultV3::result_persisted(
  self : GuardedRecoveryQueryResultV3,
) -> Bool {
  self.result_persisted
}

///|
pub fn GuardedRecoveryQueryResultV3::reconciliation_claim_ref(
  self : GuardedRecoveryQueryResultV3,
) -> @contracts.RecordRef? {
  self.reconciliation_claim_ref
}

///|
pub fn GuardedRecoveryQueryResultV3::query_start_ref(
  self : GuardedRecoveryQueryResultV3,
) -> @contracts.RecordRef? {
  self.query_start_ref
}

///|
pub fn GuardedRecoveryQueryResultV3::provider_evidence(
  self : GuardedRecoveryQueryResultV3,
) -> ProviderQueryEvidenceV3? {
  self.provider_evidence
}

///|
pub fn ReconciliationResultRecordV3::record_ref(
  self : ReconciliationResultRecordV3,
) -> @contracts.RecordRef {
  self.result_ref
}

///|
pub fn ReconciliationResultRecordV3::outcome(
  self : ReconciliationResultRecordV3,
) -> ReconciliationOutcomeV3 {
  self.outcome
}

///|
pub fn ReconciliationResultRecordV3::intent_ref(
  self : ReconciliationResultRecordV3,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn ReconciliationResultRecordV3::provider_evidence(
  self : ReconciliationResultRecordV3,
) -> ProviderQueryEvidenceV3? {
  self.provider_evidence
}

///|
pub fn ReconciliationResultRecordV3::not_applied_proof(
  self : ReconciliationResultRecordV3,
) -> AuthoritativeNotAppliedProofV3? {
  match self.provider_evidence {
    Some(value) => value.not_applied_proof
    None => None
  }
}

///|
pub fn ReconciliationResultRecordV3::observed_at(
  self : ReconciliationResultRecordV3,
) -> Int64 {
  self.observed_at
}

///|
pub fn ReconciliationResultRecordV3::canonical_bytes(
  self : ReconciliationResultRecordV3,
) -> Bytes {
  self.canonical
}

///|
pub fn ReconciliationResultRecordV3::digest(
  self : ReconciliationResultRecordV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn RecoveryBackoffScheduledV3::next_due_at(
  self : RecoveryBackoffScheduledV3,
) -> Int64 {
  self.next_due_at
}

///|
pub fn RecoveryBackoffScheduledV3::record_ref(
  self : RecoveryBackoffScheduledV3,
) -> @contracts.RecordRef {
  self.backoff_ref
}

///|
pub fn RecoveryBackoffScheduledV3::intent_ref(
  self : RecoveryBackoffScheduledV3,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn RecoveryBackoffScheduledV3::deadline(
  self : RecoveryBackoffScheduledV3,
) -> Int64 {
  self.deadline
}

///|
pub fn RecoveryBackoffScheduledV3::ordinal(
  self : RecoveryBackoffScheduledV3,
) -> Int64 {
  self.reconciliation_ordinal
}

///|
pub fn RecoveryBackoffScheduledV3::canonical_bytes(
  self : RecoveryBackoffScheduledV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryBackoffScheduledV3::digest(
  self : RecoveryBackoffScheduledV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn RecoveryAutomationStoppedV3::reason(
  self : RecoveryAutomationStoppedV3,
) -> RecoveryAutomationStopReasonV3 {
  self.reason
}

///|
pub fn RecoveryAutomationStoppedV3::record_ref(
  self : RecoveryAutomationStoppedV3,
) -> @contracts.RecordRef {
  self.stopped_ref
}

///|
pub fn RecoveryAutomationStoppedV3::intent_ref(
  self : RecoveryAutomationStoppedV3,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn RecoveryAutomationStoppedV3::stopped_at(
  self : RecoveryAutomationStoppedV3,
) -> Int64 {
  self.stopped_at
}

///|
pub fn RecoveryAutomationStoppedV3::ordinal(
  self : RecoveryAutomationStoppedV3,
) -> Int64 {
  self.reconciliation_ordinal
}

///|
pub fn RecoveryAutomationStoppedV3::canonical_bytes(
  self : RecoveryAutomationStoppedV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryAutomationStoppedV3::digest(
  self : RecoveryAutomationStoppedV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn ProviderQueryEvidenceV3::provider_id(
  self : ProviderQueryEvidenceV3,
) -> String {
  self.provider_id
}

///|
pub fn ProviderQueryEvidenceV3::provider_event_id(
  self : ProviderQueryEvidenceV3,
) -> String {
  self.provider_event_id
}

///|
pub fn ProviderQueryEvidenceV3::evidence_kind(
  self : ProviderQueryEvidenceV3,
) -> ProviderQueryEvidenceKindV3 {
  self.evidence_kind
}

///|
pub fn ProviderQueryEvidenceV3::body_digest(
  self : ProviderQueryEvidenceV3,
) -> @contracts.ContentDigest {
  self.body_digest
}

///|
pub fn ProviderQueryEvidenceV3::source_at(
  self : ProviderQueryEvidenceV3,
) -> Int64 {
  self.source_at
}

///|
pub fn ProviderQueryEvidenceV3::retrieved_at(
  self : ProviderQueryEvidenceV3,
) -> Int64 {
  self.retrieved_at
}

///|
pub fn ProviderQueryEvidenceV3::not_applied_proof(
  self : ProviderQueryEvidenceV3,
) -> AuthoritativeNotAppliedProofV3? {
  self.not_applied_proof
}

///|
pub fn ProviderQueryEvidenceV3::canonical_bytes(
  self : ProviderQueryEvidenceV3,
) -> Bytes {
  self.canonical
}

///|
pub fn ProviderQueryEvidenceV3::digest(
  self : ProviderQueryEvidenceV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn AuthoritativeNotAppliedProofV3::record_ref(
  self : AuthoritativeNotAppliedProofV3,
) -> @contracts.RecordRef {
  self.proof_ref
}

///|
pub fn AuthoritativeNotAppliedProofV3::external_idempotency_key(
  self : AuthoritativeNotAppliedProofV3,
) -> String {
  self.external_idempotency_key
}

///|
pub fn AuthoritativeNotAppliedProofV3::barrier_id(
  self : AuthoritativeNotAppliedProofV3,
) -> String {
  self.barrier_id
}

///|
pub fn AuthoritativeNotAppliedProofV3::barrier_digest(
  self : AuthoritativeNotAppliedProofV3,
) -> @contracts.ContentDigest {
  self.barrier_digest
}

///|
pub fn AuthoritativeNotAppliedProofV3::query_identity(
  self : AuthoritativeNotAppliedProofV3,
) -> String {
  self.query_identity
}

///|
pub fn AuthoritativeNotAppliedProofV3::query_body_digest(
  self : AuthoritativeNotAppliedProofV3,
) -> @contracts.ContentDigest {
  self.query_body_digest
}

///|
pub fn AuthoritativeNotAppliedProofV3::provider_fence_floor(
  self : AuthoritativeNotAppliedProofV3,
) -> Int64 {
  self.provider_fence_floor
}
