///|
let dispatch_observation_event_kind_v3 = "effect.dispatch.observed.v3"

///|
let dispatch_observation_record_magic_v3 = b"FLOW7/DISPATCH-OBSERVATION-V3/3.0.0"

///|
pub(all) enum ProviderEvidenceKindV3 {
  ProviderAppliedEvidenceV3
  ProviderFailedEvidenceV3
  ProviderTombstoneNotAppliedEvidenceV3
  ProviderUnknownEvidenceV3
} derive(Eq, Debug)

///|
fn ProviderEvidenceKindV3::wire(self : ProviderEvidenceKindV3) -> String {
  match self {
    ProviderAppliedEvidenceV3 => "applied"
    ProviderFailedEvidenceV3 => "failed"
    ProviderTombstoneNotAppliedEvidenceV3 => "tombstone_not_applied"
    ProviderUnknownEvidenceV3 => "unknown"
  }
}

///|
fn provider_evidence_kind_from_wire_v3(
  value : String,
) -> ProviderEvidenceKindV3 raise OrchestrationError {
  match value {
    "applied" => ProviderAppliedEvidenceV3
    "failed" => ProviderFailedEvidenceV3
    "tombstone_not_applied" => ProviderTombstoneNotAppliedEvidenceV3
    "unknown" => ProviderUnknownEvidenceV3
    _ => raise MalformedInput(field="provider_create_evidence_v3_kind")
  }
}

///|
/// Provider evidence returned by an adapter. The combined dispatcher validates
/// its exact key/fence binding before it can become a known observation.
pub struct ProviderCreateEvidenceV3 {
  provider_id : String
  provider_event_id : String
  evidence_kind : ProviderEvidenceKindV3
  body_digest : @contracts.ContentDigest
  external_idempotency_key : String
  fencing_token : Int64
  observed_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn ProviderCreateEvidenceV3::new(
  provider_id : String,
  provider_event_id : String,
  evidence_kind : ProviderEvidenceKindV3,
  body_digest : @contracts.ContentDigest,
  external_idempotency_key : String,
  fencing_token : Int64,
  observed_at : Int64,
) -> ProviderCreateEvidenceV3 raise OrchestrationError {
  require_text(provider_id, "provider_create_evidence_v3_provider")
  require_text(provider_event_id, "provider_create_evidence_v3_event")
  require_text(
    external_idempotency_key, "provider_create_evidence_v3_external_key",
  )
  if fencing_token < 0L || observed_at < 0L {
    raise MalformedInput(field="provider_create_evidence_v3_bounds")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/PROVIDER-CREATE-EVIDENCE-V3/3.0.0")
  writer.string("3.0.0")
  writer.string(provider_id)
  writer.string(provider_event_id)
  writer.string(evidence_kind.wire())
  writer.string(body_digest.text())
  writer.string(external_idempotency_key)
  writer.int64(fencing_token)
  writer.int64(observed_at)
  let canonical = writer.finish()
  {
    provider_id,
    provider_event_id,
    evidence_kind,
    body_digest,
    external_idempotency_key,
    fencing_token,
    observed_at,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn ProviderCreateEvidenceV3::provider_id(
  self : ProviderCreateEvidenceV3,
) -> String {
  self.provider_id
}

///|
pub fn ProviderCreateEvidenceV3::provider_event_id(
  self : ProviderCreateEvidenceV3,
) -> String {
  self.provider_event_id
}

///|
pub fn ProviderCreateEvidenceV3::body_digest(
  self : ProviderCreateEvidenceV3,
) -> @contracts.ContentDigest {
  self.body_digest
}

///|
pub fn ProviderCreateEvidenceV3::evidence_kind(
  self : ProviderCreateEvidenceV3,
) -> ProviderEvidenceKindV3 {
  self.evidence_kind
}

///|
pub fn ProviderCreateEvidenceV3::canonical_bytes(
  self : ProviderCreateEvidenceV3,
) -> Bytes {
  self.canonical
}

///|
pub fn ProviderCreateEvidenceV3::digest(
  self : ProviderCreateEvidenceV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Closed adapter response. A known failure is not proof of non-application.
pub(all) enum ProviderCreateResultV3 {
  ProviderCreateKnownSucceededV3(ProviderCreateEvidenceV3)
  ProviderCreateKnownFailedV3(ProviderCreateEvidenceV3)
  ProviderCreateConfirmedNotAppliedV3(ProviderCreateEvidenceV3)
  ProviderCreateStillUnknownV3(ProviderCreateEvidenceV3?)
}

///|
/// Opaque call envelope. Only the sole combined V3 operation can construct it.
pub struct GuardedProviderCreateCallV3 {
  claim_ref : @contracts.RecordRef
  invocation_start_ref : @contracts.RecordRef
  provider_operation : @contracts.WireEnvelope
  external_idempotency_key : String
  owner : @contracts.RecordRef
  lease_epoch : Int64
  fencing_token : Int64
  capability_ref : @contracts.RecordRef
  capability_kind : String
  permitted_evidence : ReadOnlyArray[@contracts.EvidenceRef]
  provider_profile_digest : @contracts.ContentDigest
  durable_work_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn GuardedProviderCreateCallV3::claim_ref(
  self : GuardedProviderCreateCallV3,
) -> @contracts.RecordRef {
  self.claim_ref
}

///|
pub fn GuardedProviderCreateCallV3::invocation_start_ref(
  self : GuardedProviderCreateCallV3,
) -> @contracts.RecordRef {
  self.invocation_start_ref
}

///|
pub fn GuardedProviderCreateCallV3::provider_operation(
  self : GuardedProviderCreateCallV3,
) -> @contracts.WireEnvelope {
  self.provider_operation
}

///|
pub fn GuardedProviderCreateCallV3::external_idempotency_key(
  self : GuardedProviderCreateCallV3,
) -> String {
  self.external_idempotency_key
}

///|
pub fn GuardedProviderCreateCallV3::owner(
  self : GuardedProviderCreateCallV3,
) -> @contracts.RecordRef {
  self.owner
}

///|
pub fn GuardedProviderCreateCallV3::lease_epoch(
  self : GuardedProviderCreateCallV3,
) -> Int64 {
  self.lease_epoch
}

///|
pub fn GuardedProviderCreateCallV3::fencing_token(
  self : GuardedProviderCreateCallV3,
) -> Int64 {
  self.fencing_token
}

///|
pub fn GuardedProviderCreateCallV3::capability_ref(
  self : GuardedProviderCreateCallV3,
) -> @contracts.RecordRef {
  self.capability_ref
}

///|
pub fn GuardedProviderCreateCallV3::capability_kind(
  self : GuardedProviderCreateCallV3,
) -> String {
  self.capability_kind
}

///|
pub fn GuardedProviderCreateCallV3::permitted_evidence(
  self : GuardedProviderCreateCallV3,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.permitted_evidence
}

///|
pub fn GuardedProviderCreateCallV3::provider_profile_digest(
  self : GuardedProviderCreateCallV3,
) -> @contracts.ContentDigest {
  self.provider_profile_digest
}

///|
pub fn GuardedProviderCreateCallV3::durable_work_replay_digest(
  self : GuardedProviderCreateCallV3,
) -> @contracts.ContentDigest {
  self.durable_work_replay_digest
}

///|
pub fn GuardedProviderCreateCallV3::canonical_bytes(
  self : GuardedProviderCreateCallV3,
) -> Bytes {
  self.canonical
}

///|
pub fn GuardedProviderCreateCallV3::digest(
  self : GuardedProviderCreateCallV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Generic host adapter boundary. Implementing this trait proves only the
/// profile and bytes supplied locally; remote enforcement remains an adapter
/// certification and integration-test obligation.
pub(open) trait GuardedEffectProviderPortV3 {
  fn recovery_profile(Self) -> ProviderRecoveryProfileV3
  fn create_guarded_effect(Self, GuardedProviderCreateCallV3) -> ProviderCreateResultV3 raise
}

///|
fn guarded_provider_create_call_v3(
  claim : DispatchClaimRecordV3,
  started : DispatchInvocationStartedV3,
  durable_work_replay_digest : @contracts.ContentDigest,
) -> GuardedProviderCreateCallV3 raise OrchestrationError {
  if started.claim_ref != claim.claim_ref ||
    started.claim_digest != claim.digest {
    raise ReplayBindingViolation(field="provider_create_v3_invocation")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/GUARDED-PROVIDER-CREATE-CALL-V3/3.0.0")
  write_ref(writer, claim.claim_ref)
  write_ref(writer, started.start_ref)
  writer.bytes(@contracts.encode_wire_envelope(claim.provider_operation))
  writer.string(claim.external_idempotency_key)
  write_ref(writer, claim.owner)
  writer.int64(claim.lease_epoch)
  writer.int64(claim.fencing_token)
  write_ref(writer, claim.capability_ref)
  writer.string(claim.capability_kind)
  write_evidence(writer, claim.evidence)
  writer.string(claim.provider_profile_digest.text())
  writer.string(durable_work_replay_digest.text())
  let canonical = writer.finish()
  {
    claim_ref: claim.claim_ref,
    invocation_start_ref: started.start_ref,
    provider_operation: claim.provider_operation,
    external_idempotency_key: claim.external_idempotency_key,
    owner: claim.owner,
    lease_epoch: claim.lease_epoch,
    fencing_token: claim.fencing_token,
    capability_ref: claim.capability_ref,
    capability_kind: claim.capability_kind,
    permitted_evidence: claim.evidence,
    provider_profile_digest: claim.provider_profile_digest,
    durable_work_replay_digest,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub(all) enum GuardedDispatchDispositionV3 {
  GuardedDispatchProviderObservedV3(@effects.ExternalRecoveryOutcomeV3)
  GuardedDispatchAlreadyCommittedQueryOnlyV3
  GuardedDispatchRaceLostNoCallV3
  GuardedDispatchStaleGovernanceNoCallV3
} derive(Eq, Debug)

///|
/// Inert result of the combined operation. It cannot be converted back into a
/// provider call or used as a reusable invocation token.
pub struct GuardedDispatchResultV3 {
  disposition : GuardedDispatchDispositionV3
  claim_ref : @contracts.RecordRef?
  invocation_start_ref : @contracts.RecordRef?
  provider_evidence : ProviderCreateEvidenceV3?
  observation_persisted : Bool
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn GuardedDispatchResultV3::disposition(
  self : GuardedDispatchResultV3,
) -> GuardedDispatchDispositionV3 {
  self.disposition
}

///|
pub fn GuardedDispatchResultV3::claim_ref(
  self : GuardedDispatchResultV3,
) -> @contracts.RecordRef? {
  self.claim_ref
}

///|
pub fn GuardedDispatchResultV3::invocation_start_ref(
  self : GuardedDispatchResultV3,
) -> @contracts.RecordRef? {
  self.invocation_start_ref
}

///|
pub fn GuardedDispatchResultV3::provider_evidence(
  self : GuardedDispatchResultV3,
) -> ProviderCreateEvidenceV3? {
  self.provider_evidence
}

///|
pub fn GuardedDispatchResultV3::observation_persisted(
  self : GuardedDispatchResultV3,
) -> Bool {
  self.observation_persisted
}

///|
pub fn GuardedDispatchResultV3::canonical_bytes(
  self : GuardedDispatchResultV3,
) -> Bytes {
  self.canonical
}

///|
pub fn GuardedDispatchResultV3::digest(
  self : GuardedDispatchResultV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
fn guarded_dispatch_result_v3(
  disposition : GuardedDispatchDispositionV3,
  claim_ref : @contracts.RecordRef?,
  invocation_start_ref : @contracts.RecordRef?,
  provider_evidence : ProviderCreateEvidenceV3?,
  observation_persisted : Bool,
) -> GuardedDispatchResultV3 raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/GUARDED-DISPATCH-RESULT-V3/3.0.0")
  match disposition {
    GuardedDispatchProviderObservedV3(outcome) => {
      writer.byte(1)
      writer.bytes(@effects.encode_external_recovery_outcome_v3(outcome))
    }
    GuardedDispatchAlreadyCommittedQueryOnlyV3 => writer.byte(2)
    GuardedDispatchRaceLostNoCallV3 => writer.byte(3)
    GuardedDispatchStaleGovernanceNoCallV3 => writer.byte(4)
  }
  match claim_ref {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value)
    }
  }
  match invocation_start_ref {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value)
    }
  }
  match provider_evidence {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      writer.bytes(value.canonical)
    }
  }
  writer.byte(if observation_persisted { 1 } else { 0 })
  let canonical = writer.finish()
  {
    disposition,
    claim_ref,
    invocation_start_ref,
    provider_evidence,
    observation_persisted,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub struct DispatchObservationRecordV3 {
  observation_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  claim_ref : @contracts.RecordRef
  claim_digest : @contracts.ContentDigest
  invocation_start_ref : @contracts.RecordRef
  invocation_start_digest : @contracts.ContentDigest
  provider_profile_digest : @contracts.ContentDigest
  outcome : @effects.ExternalRecoveryOutcomeV3
  provider_evidence : ProviderCreateEvidenceV3?
  event_id : String
  command_idempotency_key : String
  observed_at : Int64
  expected_work_revision : Int64
  expected_work_head_digest : @contracts.ContentDigest
  expected_work_replay_digest : @contracts.ContentDigest
  expected_governance_workflow : @contracts.RecordRef
  expected_governance_revision : Int64
  expected_governance_head_digest : @contracts.ContentDigest?
  expected_governance_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn dispatch_observation_signing_bytes_v3(
  event_id : String,
  workflow : @contracts.RecordRef,
  intent_ref : @contracts.RecordRef,
  governed_subject : @contracts.RecordRef,
  claim_ref : @contracts.RecordRef,
  claim_digest : @contracts.ContentDigest,
  invocation_start_ref : @contracts.RecordRef,
  invocation_start_digest : @contracts.ContentDigest,
  provider_profile_digest : @contracts.ContentDigest,
  outcome : @effects.ExternalRecoveryOutcomeV3,
  provider_evidence : ProviderCreateEvidenceV3?,
  command_idempotency_key : String,
  observed_at : Int64,
  expected_work_revision : Int64,
  expected_work_head_digest : @contracts.ContentDigest,
  expected_work_replay_digest : @contracts.ContentDigest,
  expected_governance_workflow : @contracts.RecordRef,
  expected_governance_revision : Int64,
  expected_governance_head_digest : @contracts.ContentDigest?,
  expected_governance_replay_digest : @contracts.ContentDigest,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(dispatch_observation_record_magic_v3)
  writer.string("3.0.0")
  writer.string(event_id)
  write_ref(writer, workflow)
  write_ref(writer, intent_ref)
  write_ref(writer, governed_subject)
  write_ref(writer, claim_ref)
  writer.string(claim_digest.text())
  write_ref(writer, invocation_start_ref)
  writer.string(invocation_start_digest.text())
  writer.string(provider_profile_digest.text())
  writer.bytes(@effects.encode_external_recovery_outcome_v3(outcome))
  match provider_evidence {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      writer.bytes(value.canonical)
    }
  }
  writer.string(command_idempotency_key)
  writer.int64(observed_at)
  writer.int64(expected_work_revision)
  writer.string(expected_work_head_digest.text())
  writer.string(expected_work_replay_digest.text())
  write_ref(writer, expected_governance_workflow)
  writer.int64(expected_governance_revision)
  writer.optional_digest(expected_governance_head_digest)
  writer.string(expected_governance_replay_digest.text())
  writer.finish()
}

///|
fn make_dispatch_observation_record_v3(
  claim : DispatchClaimRecordV3,
  started : DispatchInvocationStartedV3,
  outcome : @effects.ExternalRecoveryOutcomeV3,
  provider_evidence : ProviderCreateEvidenceV3?,
  event_id : String,
  observed_at : Int64,
  expected_work_revision : Int64,
  expected_work_head_digest : @contracts.ContentDigest,
  expected_work_replay_digest : @contracts.ContentDigest,
  current_governance : @storage.ReplayResult,
) -> DispatchObservationRecordV3 raise OrchestrationError {
  require_text(event_id, "dispatch_observation_v3_event_id")
  if observed_at < claim.claimed_at {
    raise MalformedInput(field="dispatch_observation_v3_time")
  }
  let command_idempotency_key = claim.command_idempotency_key + ":observation"
  let canonical = dispatch_observation_signing_bytes_v3(
    event_id,
    claim.workflow,
    claim.intent_ref,
    claim.governed_subject,
    claim.claim_ref,
    claim.digest,
    started.start_ref,
    started.digest,
    claim.provider_profile_digest,
    outcome,
    provider_evidence,
    command_idempotency_key,
    observed_at,
    expected_work_revision,
    expected_work_head_digest,
    expected_work_replay_digest,
    current_governance.workflow(),
    current_governance.head().revision(),
    current_governance.head().last_event_digest(),
    current_governance.replay_digest(),
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    observation_ref: self_ref_v3(
      "orchestration-dispatch-observation-v3", event_id, digest,
    ),
    workflow: claim.workflow,
    intent_ref: claim.intent_ref,
    governed_subject: claim.governed_subject,
    claim_ref: claim.claim_ref,
    claim_digest: claim.digest,
    invocation_start_ref: started.start_ref,
    invocation_start_digest: started.digest,
    provider_profile_digest: claim.provider_profile_digest,
    outcome,
    provider_evidence,
    event_id,
    command_idempotency_key,
    observed_at,
    expected_work_revision,
    expected_work_head_digest,
    expected_work_replay_digest,
    expected_governance_workflow: current_governance.workflow(),
    expected_governance_revision: current_governance.head().revision(),
    expected_governance_head_digest: current_governance
    .head()
    .last_event_digest(),
    expected_governance_replay_digest: current_governance.replay_digest(),
    canonical,
    digest,
  }
}

///|
fn decode_provider_create_evidence_v3(
  bytes : Bytes,
) -> ProviderCreateEvidenceV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/PROVIDER-CREATE-EVIDENCE-V3/3.0.0" {
    raise MalformedInput(field="provider_create_evidence_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="provider_create_evidence_v3", version~)
  }
  let value = ProviderCreateEvidenceV3::new(
    reader.read_string(),
    reader.read_string(),
    provider_evidence_kind_from_wire_v3(reader.read_string()),
    reader.read_digest(),
    reader.read_string(),
    reader.read_int64(),
    reader.read_int64(),
  )
  reader.require_end()
  if value.canonical != bytes {
    raise DigestMismatch(field="provider_create_evidence_v3_noncanonical")
  }
  value
}

///|
fn decode_dispatch_observation_record_v3(
  bytes : Bytes,
) -> DispatchObservationRecordV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != dispatch_observation_record_magic_v3 {
    raise MalformedInput(field="dispatch_observation_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="dispatch_observation_v3", version~)
  }
  let event_id = reader.read_string()
  let workflow = reader.read_ref()
  let intent_ref = reader.read_ref()
  let governed_subject = reader.read_ref()
  let claim_ref = reader.read_ref()
  let claim_digest = reader.read_digest()
  let invocation_start_ref = reader.read_ref()
  let invocation_start_digest = reader.read_digest()
  let provider_profile_digest = reader.read_digest()
  let outcome = @effects.decode_external_recovery_outcome_v3(
    reader.read_bytes(),
  ) catch {
    _ => raise MalformedInput(field="dispatch_observation_v3_outcome")
  }
  let provider_evidence = match reader.read_byte() {
    0 => None
    1 => Some(decode_provider_create_evidence_v3(reader.read_bytes()))
    _ => raise MalformedInput(field="dispatch_observation_v3_evidence")
  }
  let command_idempotency_key = reader.read_string()
  let observed_at = reader.read_int64()
  let expected_work_revision = reader.read_int64()
  let expected_work_head_digest = reader.read_digest()
  let expected_work_replay_digest = reader.read_digest()
  let expected_governance_workflow = reader.read_ref()
  let expected_governance_revision = reader.read_int64()
  let expected_governance_head_digest = reader.read_optional_digest()
  let expected_governance_replay_digest = reader.read_digest()
  reader.require_end()
  let canonical = dispatch_observation_signing_bytes_v3(
    event_id, workflow, intent_ref, governed_subject, claim_ref, claim_digest, invocation_start_ref,
    invocation_start_digest, provider_profile_digest, outcome, provider_evidence,
    command_idempotency_key, observed_at, expected_work_revision, expected_work_head_digest,
    expected_work_replay_digest, expected_governance_workflow, expected_governance_revision,
    expected_governance_head_digest, expected_governance_replay_digest,
  )
  if canonical != bytes {
    raise DigestMismatch(field="dispatch_observation_v3_noncanonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    observation_ref: self_ref_v3(
      "orchestration-dispatch-observation-v3", event_id, digest,
    ),
    workflow,
    intent_ref,
    governed_subject,
    claim_ref,
    claim_digest,
    invocation_start_ref,
    invocation_start_digest,
    provider_profile_digest,
    outcome,
    provider_evidence,
    event_id,
    command_idempotency_key,
    observed_at,
    expected_work_revision,
    expected_work_head_digest,
    expected_work_replay_digest,
    expected_governance_workflow,
    expected_governance_revision,
    expected_governance_head_digest,
    expected_governance_replay_digest,
    canonical,
    digest,
  }
}

///|
fn bytes_have_dispatch_observation_magic_v3(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    magic => magic == dispatch_observation_record_magic_v3
  }
}

///|
fn dispatch_observation_event_v3(
  record : DispatchObservationRecordV3,
) -> @storage.WorkflowEvent raise OrchestrationError {
  let evidence : Array[@contracts.EvidenceRef] = []
  let envelope = @contracts.WireEnvelope::new(
    dispatch_claim_transport_contract_id_v3,
    orchestration_record_version,
    record.event_id,
    dispatch_observation_event_kind_v3,
    record.governed_subject,
    phase1b_effect_schema_v22(dispatch_observation_event_kind_v3),
    record.canonical,
    dispatch_claim_transport_producer_id_v3,
    orchestration_record_version,
    [],
    evidence,
    run_ref=record.workflow,
    correlation_ref=record.workflow.id(),
    causation_ref=record.claim_ref.id(),
    idempotency_ref=record.observation_ref.id(),
    previous_digest=record.expected_work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="dispatch_observation_v3_envelope")
  }
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    record.workflow,
    record.event_id,
    record.expected_work_revision + 1L,
    record.expected_work_revision + 1L,
    record.observation_ref.id(),
    envelope,
    evidence,
    previous_event_digest=record.expected_work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="dispatch_observation_v3_event")
  }
}

///|
fn require_dispatch_observation_binding_v3(
  record : DispatchObservationRecordV3,
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  if record.outcome == @effects.RecoveryConfirmedNotAppliedV3 {
    raise ReplayBindingViolation(
      field="dispatch_observation_v3_not_applied_proof",
    )
  }
  let claim_events = replay
    .events()
    .filter(candidate => {
      candidate.payload().envelope_kind() == dispatch_claim_event_kind_v3 &&
      candidate.payload().idempotency_ref() == Some(record.claim_ref.id())
    })
  if claim_events.length() != 1 {
    raise ReplayBindingViolation(field="dispatch_observation_v3_claim")
  }
  let claim = decode_dispatch_claim_record_v3(
    claim_events[0].payload().payload(),
  )
  let start_events = replay
    .events()
    .filter(candidate => {
      candidate.payload().envelope_kind() == invocation_started_event_kind_v3 &&
      candidate.payload().idempotency_ref() ==
      Some(record.invocation_start_ref.id())
    })
  if start_events.length() != 1 {
    raise ReplayBindingViolation(field="dispatch_observation_v3_start")
  }
  let started = decode_dispatch_invocation_started_v3(
    start_events[0].payload().payload(),
  )
  let evidence_binding_ok = match (record.outcome, record.provider_evidence) {
    (@effects.RecoveryKnownSucceededV3, Some(value)) =>
      value.evidence_kind == ProviderAppliedEvidenceV3 &&
      value.external_idempotency_key == claim.external_idempotency_key &&
      value.fencing_token == claim.fencing_token &&
      value.observed_at == record.observed_at
    (@effects.RecoveryKnownFailedV3, Some(value)) =>
      value.evidence_kind == ProviderFailedEvidenceV3 &&
      value.external_idempotency_key == claim.external_idempotency_key &&
      value.fencing_token == claim.fencing_token &&
      value.observed_at == record.observed_at
    // Rejected unconditionally above until a later slice owns a strict
    // reconciliation-only query+tombstone barrier and fence-floor proof.
    (@effects.RecoveryConfirmedNotAppliedV3, _) => false
    (@effects.RecoveryStillUnknownV3, None) => true
    (@effects.RecoveryStillUnknownV3, Some(value)) =>
      value.evidence_kind == ProviderUnknownEvidenceV3 &&
      value.external_idempotency_key == claim.external_idempotency_key &&
      value.fencing_token == claim.fencing_token &&
      value.observed_at == record.observed_at
    _ => false
  }
  if record.claim_digest != claim.digest ||
    record.invocation_start_digest != started.digest ||
    record.intent_ref != claim.intent_ref ||
    record.governed_subject != claim.governed_subject ||
    record.provider_profile_digest != claim.provider_profile_digest ||
    record.expected_work_revision < claim.expected_work_revision + 2L ||
    record.expected_governance_workflow != claim.governance_workflow ||
    record.expected_governance_revision < claim.expected_governance_revision ||
    !evidence_binding_ok ||
    event.record_version().text() != orchestration_record_version ||
    event.schema_version().text() != orchestration_schema_version ||
    event.workflow() != record.workflow ||
    event.sequence() != event.revision() ||
    event.idempotency_key() != record.observation_ref.id() ||
    event.event_ref().id() != record.event_id ||
    event.revision() != record.expected_work_revision + 1L ||
    event.previous_event_digest() != Some(record.expected_work_head_digest) ||
    !event.evidence().is_empty() ||
    event.payload().envelope_id() != event.event_ref().id() ||
    event.payload().contract_id() != dispatch_claim_transport_contract_id_v3 ||
    event.payload().contract_version().text() != orchestration_record_version ||
    event.payload().producer_id() != dispatch_claim_transport_producer_id_v3 ||
    event.payload().producer_version().text() != orchestration_record_version ||
    event.payload().envelope_kind() != dispatch_observation_event_kind_v3 ||
    event.payload().subject() != record.governed_subject ||
    event.payload().run_ref() != Some(record.workflow) ||
    event.payload().stage_ref() is Some(_) ||
    event.payload().attempt_ref() is Some(_) ||
    event.payload().correlation_ref() != Some(record.workflow.id()) ||
    event.payload().causation_ref() != Some(record.claim_ref.id()) ||
    event.payload().idempotency_ref() != Some(record.observation_ref.id()) ||
    event.payload().schema() !=
    phase1b_effect_schema_v22(dispatch_observation_event_kind_v3) ||
    event.payload().payload() != record.canonical ||
    event.payload().previous_digest() != Some(record.expected_work_head_digest) ||
    !event.payload().evidence().is_empty() ||
    !event.payload().artifacts().is_empty() ||
    !event.payload().extensions().is_empty() {
    raise ReplayBindingViolation(field="dispatch_observation_v3_binding")
  }
  let matching = replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().length() == 1 &&
      batch.event_refs()[0] == event.event_ref()
    })
  if matching.length() != 1 ||
    matching[0].expected_revision() != record.expected_work_revision ||
    matching[0].command_idempotency_key() != record.command_idempotency_key ||
    !matching[0].intent_refs().is_empty() ||
    matching[0].guards().length() != 1 {
    raise ReplayBindingViolation(field="dispatch_observation_v3_transaction")
  }
  let head_guard = matching[0].guards()[0]
  if head_guard.workflow() != record.expected_governance_workflow ||
    head_guard.expected_revision() != record.expected_governance_revision ||
    head_guard.expected_head_digest() != record.expected_governance_head_digest ||
    head_guard.expected_replay_digest() !=
    record.expected_governance_replay_digest {
    raise ReplayBindingViolation(field="dispatch_observation_v3_guard")
  }
  let prefix = verified_prefix_v3(
    replay,
    record.expected_work_revision,
    "dispatch_observation_v3_prefix",
  )
  if prefix.head().last_event_digest() != Some(record.expected_work_head_digest) ||
    prefix.replay_digest() != record.expected_work_replay_digest ||
    !prefix
    .events()
    .any(value => value.event_ref() == start_events[0].event_ref()) {
    raise ReplayBindingViolation(field="dispatch_observation_v3_prefix")
  }
}

///|
fn require_dispatch_observation_governance_v3(
  record : DispatchObservationRecordV3,
  governance_replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let prefix = verified_prefix_v3(
    governance_replay,
    record.expected_governance_revision,
    "dispatch_observation_v3_governance_prefix",
  )
  if prefix.workflow() != record.expected_governance_workflow ||
    prefix.head().last_event_digest() != record.expected_governance_head_digest ||
    prefix.replay_digest() != record.expected_governance_replay_digest {
    raise ReplayBindingViolation(field="dispatch_observation_v3_governance")
  }
}

///|
fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] persist_dispatch_observation_best_effort_v3(
  store : S,
  candidate : DispatchClaimCommitCandidateV3,
  started : DispatchInvocationStartedV3,
  outcome : @effects.ExternalRecoveryOutcomeV3,
  evidence : ProviderCreateEvidenceV3?,
  event_id : String,
  observed_at : Int64,
) -> Bool {
  try {
    let current_work = store.replay(candidate.claim.workflow)
    let current_governance = store.replay_registered_guard(
      candidate.claim.governance_workflow,
    )
    // Ensure the newly observed head is semantically replayable before using
    // it as the CAS prefix. A pending cancellation is allowed; a terminal or
    // corrupt stream is not.
    ignore(
      fold_governed_recovery_v3(
        candidate.empty_effects,
        current_work,
        current_governance,
      ),
    )
    guard current_work.head().last_event_digest() is Some(current_head) else {
      return false
    }
    let record = make_dispatch_observation_record_v3(
      candidate.claim,
      started,
      outcome,
      evidence,
      event_id,
      observed_at,
      current_work.head().revision(),
      current_head,
      current_work.replay_digest(),
      current_governance,
    )
    let event = dispatch_observation_event_v3(record)
    let request = @storage.CommitRequest::new(
      orchestration_record_version,
      orchestration_schema_version,
      record.workflow,
      record.expected_work_revision,
      record.command_idempotency_key,
      [event],
      [],
    )
    let guarded = @storage.GuardedCommitRequest::new(request, [
      @storage.WorkflowHeadGuard::new(
        current_governance.workflow(),
        current_governance.head().revision(),
        current_governance.head().last_event_digest(),
        current_governance.replay_digest(),
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
fn normalize_provider_result_v3(
  result : ProviderCreateResultV3,
  claim : DispatchClaimRecordV3,
  expected_observed_at : Int64,
) -> (@effects.ExternalRecoveryOutcomeV3, ProviderCreateEvidenceV3?) {
  let validate = fn(evidence : ProviderCreateEvidenceV3) {
    evidence.external_idempotency_key == claim.external_idempotency_key &&
    evidence.fencing_token == claim.fencing_token &&
    evidence.observed_at == expected_observed_at
  }
  match result {
    ProviderCreateKnownSucceededV3(evidence) if validate(evidence) &&
      evidence.evidence_kind == ProviderAppliedEvidenceV3 =>
      (@effects.RecoveryKnownSucceededV3, Some(evidence))
    ProviderCreateKnownFailedV3(evidence) if validate(evidence) &&
      evidence.evidence_kind == ProviderFailedEvidenceV3 =>
      (@effects.RecoveryKnownFailedV3, Some(evidence))
    // A create response alone cannot prove absence across an outcome race. The
    // future reconciliation protocol must bind a provider query, tombstone or
    // barrier identity, and an enforced fence floor before retry is eligible.
    ProviderCreateConfirmedNotAppliedV3(_) =>
      (@effects.RecoveryStillUnknownV3, None)
    ProviderCreateStillUnknownV3(Some(evidence)) if validate(evidence) &&
      evidence.evidence_kind == ProviderUnknownEvidenceV3 =>
      (@effects.RecoveryStillUnknownV3, Some(evidence))
    ProviderCreateStillUnknownV3(_) => (@effects.RecoveryStillUnknownV3, None)
    _ => (@effects.RecoveryStillUnknownV3, None)
  }
}

///|
/// Invoke one provider only from the fresh claim publication branch after the
/// caller has established every additional durable prerequisite.
fn[
  S : @storage.ClassifiedRegistryBoundGuardedStoragePort,
  P : GuardedEffectProviderPortV3,
] invoke_fresh_guarded_effect_candidate_v3(
  store : S,
  candidate : DispatchClaimCommitCandidateV3,
  port : P,
  intent_ref : @contracts.RecordRef,
  observation_event_id : String,
  observed_at : Int64,
) -> GuardedDispatchResultV3 raise {
  let durable = store.replay(candidate.claim.workflow)
  let durable_governance = store.replay_registered_guard(
    candidate.claim.governance_workflow,
  )
  let projection = fold_governed_recovery_v3(
    candidate.empty_effects,
    durable,
    durable_governance,
  )
  guard projection.current_claim(intent_ref) is Some(claim) else {
    raise RecoveryViolation(field="guarded_dispatch_v3_claim_missing")
  }
  guard first(projection.invocation_starts, started => {
      started.claim_ref == claim.claim_ref
    })
    is Some(started) else {
    raise RecoveryViolation(field="guarded_dispatch_v3_start_missing")
  }
  if candidate.claim.canonical != claim.canonical {
    raise RecoveryViolation(field="guarded_dispatch_v3_receipt_binding")
  }
  let call = guarded_provider_create_call_v3(
    claim,
    started,
    durable.replay_digest(),
  )
  let (outcome, evidence) = normalize_provider_result_v3(
    port.create_guarded_effect(call),
    claim,
    observed_at,
  ) catch {
    _ => (@effects.RecoveryStillUnknownV3, None)
  }
  let persisted = persist_dispatch_observation_best_effort_v3(
    store, candidate, started, outcome, evidence, observation_event_id, observed_at,
  )
  guarded_dispatch_result_v3(
    GuardedDispatchProviderObservedV3(outcome),
    Some(claim.claim_ref),
    Some(started.start_ref),
    evidence,
    persisted,
  )
}

///|
/// Legacy package-local unbound create path retained only for migration
/// coverage. Production callers use the policy-bound entrypoint below.
fn[
  S : @storage.ClassifiedRegistryBoundGuardedStoragePort,
  P : GuardedEffectProviderPortV3,
] dispatch_guarded_effect_v3(
  store : S,
  current : CurrentGovernedRecoveryProjectionV3,
  port : P,
  intent_ref : @contracts.RecordRef,
  claim_id : String,
  claim_event_id : String,
  command_idempotency_key : String,
  observation_event_id : String,
  claimed_at : Int64,
  expires_at : Int64,
  observed_at : Int64,
) -> GuardedDispatchResultV3 raise {
  // Validate all caller-proposed observation metadata before publishing the
  // durable claim or crossing any provider boundary.
  require_text(observation_event_id, "dispatch_observation_v3_event_id")
  if observed_at < 0L || observed_at < claimed_at {
    raise MalformedInput(field="dispatch_observation_v3_bounds")
  }
  let candidate = current.prepare_dispatch_claim_v3(
    intent_ref,
    claim_id,
    claim_event_id,
    command_idempotency_key,
    claimed_at,
    expires_at,
    [],
  )
  let profile = port.recovery_profile()
  if profile.digest != candidate.claim.provider_profile_digest ||
    !profile.supports_automatic_create() {
    raise RecoveryViolation(field="guarded_dispatch_v3_provider_profile")
  }
  match commit_dispatch_claim_v3(store, candidate) {
    DispatchClaimAlreadyCommittedV3(receipt) =>
      guarded_dispatch_result_v3(
        GuardedDispatchAlreadyCommittedQueryOnlyV3,
        Some(receipt.claim.claim_ref),
        None,
        None,
        false,
      )
    DispatchClaimLostV3(_) =>
      guarded_dispatch_result_v3(
        GuardedDispatchRaceLostNoCallV3,
        None,
        None,
        None,
        false,
      )
    DispatchClaimStaleGovernanceV3(_) =>
      guarded_dispatch_result_v3(
        GuardedDispatchStaleGovernanceNoCallV3,
        None,
        None,
        None,
        false,
      )
    DispatchClaimFreshlyCommittedV3(receipt) => {
      if receipt.claim.canonical != candidate.claim.canonical {
        raise RecoveryViolation(field="guarded_dispatch_v3_receipt_binding")
      }
      invoke_fresh_guarded_effect_candidate_v3(
        store, candidate, port, intent_ref, observation_event_id, observed_at,
      )
    }
  }
}

///|
/// Production provider-create operation. Claim/start are published first;
/// both policy bindings are then committed and replayed from the exact durable
/// head before the one fresh process is permitted to invoke the provider.
/// Any pre-existing claim—including a restart after a crash before policy
/// binding—remains query-only and can never recreate the external effect.
pub fn[
  S : @storage.ClassifiedRegistryBoundGuardedStoragePort,
  P : GuardedEffectProviderPortV3,
] dispatch_guarded_effect_with_recovery_policies_v3(
  store : S,
  current : CurrentGovernedRecoveryProjectionV3,
  port : P,
  intent_ref : @contracts.RecordRef,
  recovery_policy : RecoveryPolicyV3,
  effect_retry_policy : EffectRetryPolicyV3,
  claim_id : String,
  claim_event_id : String,
  command_idempotency_key : String,
  observation_event_id : String,
  claimed_at : Int64,
  expires_at : Int64,
  observed_at : Int64,
) -> GuardedDispatchResultV3 raise {
  require_text(observation_event_id, "dispatch_observation_v3_event_id")
  if observed_at < 0L || observed_at < claimed_at {
    raise MalformedInput(field="dispatch_observation_v3_bounds")
  }
  if current.current_claim(intent_ref) is Some(existing) {
    // A restart may observe the claim/start durable while one or both policy
    // commits are missing. Finish only those inert bindings, then remain
    // query-only; freshness of the provider-create branch is never recreated.
    if current.state_for(intent_ref) == @effects.RecoveryDispatchAttemptedV3 {
      if current.recovery_policy_for_v3(intent_ref) is None {
        ignore(
          bind_recovery_policy_v3(
            store,
            current,
            intent_ref,
            recovery_policy,
            claim_id + ":recovery-policy",
            claim_event_id + ":recovery-policy",
            command_idempotency_key + ":recovery-policy",
            claimed_at,
          ),
        )
      }
      let resumed_work = store.replay(existing.workflow)
      let resumed_governance = store.replay_registered_guard(
        existing.governance_workflow,
      )
      let resumed = fold_governed_recovery_v3(
        current.empty_effects,
        resumed_work,
        resumed_governance,
      )
      if resumed.effect_retry_policy_for_v3(intent_ref) is None {
        ignore(
          bind_effect_retry_policy_v3(
            store,
            resumed,
            intent_ref,
            effect_retry_policy,
            claim_id + ":effect-retry-policy",
            claim_event_id + ":effect-retry-policy",
            command_idempotency_key + ":effect-retry-policy",
            claimed_at,
          ),
        )
      }
      let rebound_work = store.replay(existing.workflow)
      let rebound_governance = store.replay_registered_guard(
        existing.governance_workflow,
      )
      let rebound = fold_governed_recovery_v3(
        current.empty_effects,
        rebound_work,
        rebound_governance,
      )
      guard rebound.recovery_policy_for_v3(intent_ref) is Some(recovery_binding) else {
        raise RecoveryViolation(field="guarded_dispatch_v3_policy_missing")
      }
      guard rebound.effect_retry_policy_for_v3(intent_ref)
        is Some(retry_binding) else {
        raise RecoveryViolation(field="guarded_dispatch_v3_policy_missing")
      }
      if recovery_binding.policy.digest != recovery_policy.digest() ||
        retry_binding.policy.digest != effect_retry_policy.digest() {
        raise PolicyMismatch(field="guarded_dispatch_v3_policy_binding")
      }
    }
    return guarded_dispatch_result_v3(
      GuardedDispatchAlreadyCommittedQueryOnlyV3,
      Some(existing.claim_ref),
      None,
      None,
      false,
    )
  }
  let candidate = current.prepare_dispatch_claim_v3(
    intent_ref,
    claim_id,
    claim_event_id,
    command_idempotency_key,
    claimed_at,
    expires_at,
    [],
  )
  let profile = port.recovery_profile()
  if profile.digest != candidate.claim.provider_profile_digest ||
    !profile.supports_automatic_create() {
    raise RecoveryViolation(field="guarded_dispatch_v3_provider_profile")
  }
  match commit_dispatch_claim_v3(store, candidate) {
    DispatchClaimAlreadyCommittedV3(receipt) =>
      guarded_dispatch_result_v3(
        GuardedDispatchAlreadyCommittedQueryOnlyV3,
        Some(receipt.claim.claim_ref),
        None,
        None,
        false,
      )
    DispatchClaimLostV3(_) =>
      guarded_dispatch_result_v3(
        GuardedDispatchRaceLostNoCallV3,
        None,
        None,
        None,
        false,
      )
    DispatchClaimStaleGovernanceV3(_) =>
      guarded_dispatch_result_v3(
        GuardedDispatchStaleGovernanceNoCallV3,
        None,
        None,
        None,
        false,
      )
    DispatchClaimFreshlyCommittedV3(receipt) => {
      if receipt.claim.canonical != candidate.claim.canonical {
        raise RecoveryViolation(field="guarded_dispatch_v3_receipt_binding")
      }
      let after_claim_work = store.replay(candidate.claim.workflow)
      let after_claim_governance = store.replay_registered_guard(
        candidate.claim.governance_workflow,
      )
      let after_claim = fold_governed_recovery_v3(
        candidate.empty_effects,
        after_claim_work,
        after_claim_governance,
      )
      ignore(
        bind_recovery_policy_v3(
          store,
          after_claim,
          intent_ref,
          recovery_policy,
          claim_id + ":recovery-policy",
          claim_event_id + ":recovery-policy",
          command_idempotency_key + ":recovery-policy",
          claimed_at,
        ),
      )
      let after_recovery_work = store.replay(candidate.claim.workflow)
      let after_recovery_governance = store.replay_registered_guard(
        candidate.claim.governance_workflow,
      )
      let after_recovery = fold_governed_recovery_v3(
        candidate.empty_effects,
        after_recovery_work,
        after_recovery_governance,
      )
      ignore(
        bind_effect_retry_policy_v3(
          store,
          after_recovery,
          intent_ref,
          effect_retry_policy,
          claim_id + ":effect-retry-policy",
          claim_event_id + ":effect-retry-policy",
          command_idempotency_key + ":effect-retry-policy",
          claimed_at,
        ),
      )
      let policy_work = store.replay(candidate.claim.workflow)
      let policy_governance = store.replay_registered_guard(
        candidate.claim.governance_workflow,
      )
      let policy_current = fold_governed_recovery_v3(
        candidate.empty_effects,
        policy_work,
        policy_governance,
      )
      guard policy_current.recovery_policy_for_v3(intent_ref)
        is Some(recovery_binding) else {
        raise RecoveryViolation(field="guarded_dispatch_v3_policy_missing")
      }
      guard policy_current.effect_retry_policy_for_v3(intent_ref)
        is Some(retry_binding) else {
        raise RecoveryViolation(field="guarded_dispatch_v3_policy_missing")
      }
      if recovery_binding.policy.digest != recovery_policy.digest() ||
        retry_binding.policy.digest != effect_retry_policy.digest() {
        raise PolicyMismatch(field="guarded_dispatch_v3_policy_binding")
      }
      invoke_fresh_guarded_effect_candidate_v3(
        store, candidate, port, intent_ref, observation_event_id, observed_at,
      )
    }
  }
}
