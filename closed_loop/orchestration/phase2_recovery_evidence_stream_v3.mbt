///|
let recovery_callback_evidence_event_kind_v3 = "effect.recovery.callback-evidence.v3"

///|
let recovery_evidence_stream_binding_magic_v3 = b"FLOW7/RECOVERY-EVIDENCE-STREAM-BINDING-V3/3.0.0"

///|
let recovery_callback_record_magic_v3 = b"FLOW7/RECOVERY-CALLBACK-RECORD-V3/3.0.0"

///|
let provider_callback_evidence_magic_v3 = b"FLOW7/PROVIDER-CALLBACK-EVIDENCE-V3/3.0.0"

///|
let callback_not_applied_barrier_magic_v3 = b"FLOW7/CALLBACK-NOT-APPLIED-BARRIER-V3/3.0.0"

///|
pub struct RecoveryEvidenceStreamBindingV3 {
  binding_ref : @contracts.RecordRef
  evidence_workflow : @contracts.RecordRef
  work_workflow : @contracts.RecordRef
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn RecoveryEvidenceStreamBindingV3::new(
  binding_id : String,
  evidence_workflow : @contracts.RecordRef,
  work_workflow : @contracts.RecordRef,
) -> RecoveryEvidenceStreamBindingV3 raise OrchestrationError {
  require_text(binding_id, "recovery_evidence_stream_binding_id_v3")
  if evidence_workflow == work_workflow {
    raise RecoveryViolation(
      field="recovery_evidence_stream_independent_root_v3",
    )
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_evidence_stream_binding_magic_v3)
  writer.string("3.0.0")
  writer.string(binding_id)
  write_ref(writer, evidence_workflow)
  write_ref(writer, work_workflow)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    binding_ref: self_ref_v3(
      "orchestration-recovery-evidence-stream-binding-v3", binding_id, digest,
    ),
    evidence_workflow,
    work_workflow,
    canonical,
    digest,
  }
}

///|
pub fn RecoveryEvidenceStreamBindingV3::record_ref(
  self : RecoveryEvidenceStreamBindingV3,
) -> @contracts.RecordRef {
  self.binding_ref
}

///|
pub fn RecoveryEvidenceStreamBindingV3::evidence_workflow(
  self : RecoveryEvidenceStreamBindingV3,
) -> @contracts.RecordRef {
  self.evidence_workflow
}

///|
pub fn RecoveryEvidenceStreamBindingV3::work_workflow(
  self : RecoveryEvidenceStreamBindingV3,
) -> @contracts.RecordRef {
  self.work_workflow
}

///|
pub fn RecoveryEvidenceStreamBindingV3::canonical_bytes(
  self : RecoveryEvidenceStreamBindingV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryEvidenceStreamBindingV3::digest(
  self : RecoveryEvidenceStreamBindingV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub struct CallbackNotAppliedBarrierV3 {
  barrier_id : String
  barrier_digest : @contracts.ContentDigest
  provider_fence_floor : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn CallbackNotAppliedBarrierV3::new(
  barrier_id : String,
  barrier_digest : @contracts.ContentDigest,
  provider_fence_floor : Int64,
) -> CallbackNotAppliedBarrierV3 raise OrchestrationError {
  require_text(barrier_id, "callback_not_applied_barrier_id_v3")
  if provider_fence_floor < 0L {
    raise MalformedInput(field="callback_not_applied_barrier_fence_v3")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(callback_not_applied_barrier_magic_v3)
  writer.string("3.0.0")
  writer.string(barrier_id)
  writer.string(barrier_digest.text())
  writer.int64(provider_fence_floor)
  let canonical = writer.finish()
  {
    barrier_id,
    barrier_digest,
    provider_fence_floor,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
fn decode_callback_not_applied_barrier_v3(
  bytes : Bytes,
) -> CallbackNotAppliedBarrierV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != callback_not_applied_barrier_magic_v3 {
    raise MalformedInput(field="callback_not_applied_barrier_magic_v3")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="callback_not_applied_barrier_v3", version~)
  }
  let value = CallbackNotAppliedBarrierV3::new(
    reader.read_string(),
    reader.read_digest(),
    reader.read_int64(),
  )
  reader.require_end()
  if value.canonical != bytes {
    raise DigestMismatch(field="callback_not_applied_barrier_noncanonical_v3")
  }
  value
}

///|
pub fn CallbackNotAppliedBarrierV3::barrier_id(
  self : CallbackNotAppliedBarrierV3,
) -> String {
  self.barrier_id
}

///|
pub fn CallbackNotAppliedBarrierV3::barrier_digest(
  self : CallbackNotAppliedBarrierV3,
) -> @contracts.ContentDigest {
  self.barrier_digest
}

///|
pub fn CallbackNotAppliedBarrierV3::provider_fence_floor(
  self : CallbackNotAppliedBarrierV3,
) -> Int64 {
  self.provider_fence_floor
}

///|
pub fn CallbackNotAppliedBarrierV3::canonical_bytes(
  self : CallbackNotAppliedBarrierV3,
) -> Bytes {
  self.canonical
}

///|
pub fn CallbackNotAppliedBarrierV3::digest(
  self : CallbackNotAppliedBarrierV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub struct ProviderCallbackEvidenceV3 {
  provider_id : String
  provider_event_id : String
  body_digest : @contracts.ContentDigest
  external_idempotency_key : String
  dispatch_fence : Int64
  reconciliation_fence : Int64?
  provider_profile_digest : @contracts.ContentDigest
  outcome : @effects.ExternalRecoveryOutcomeV3
  not_applied_barrier : CallbackNotAppliedBarrierV3?
  source_at : Int64
  retrieved_at : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn provider_callback_evidence_signing_bytes_v3(
  provider_id : String,
  provider_event_id : String,
  body_digest : @contracts.ContentDigest,
  external_idempotency_key : String,
  dispatch_fence : Int64,
  reconciliation_fence : Int64?,
  provider_profile_digest : @contracts.ContentDigest,
  outcome : @effects.ExternalRecoveryOutcomeV3,
  not_applied_barrier : CallbackNotAppliedBarrierV3?,
  source_at : Int64,
  retrieved_at : Int64,
  evidence : ArrayView[@contracts.EvidenceRef],
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(provider_callback_evidence_magic_v3)
  writer.string("3.0.0")
  writer.string(provider_id)
  writer.string(provider_event_id)
  writer.string(body_digest.text())
  writer.string(external_idempotency_key)
  writer.int64(dispatch_fence)
  writer.optional_int64(reconciliation_fence)
  writer.string(provider_profile_digest.text())
  writer.bytes(@effects.encode_external_recovery_outcome_v3(outcome))
  match not_applied_barrier {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      writer.bytes(value.canonical)
    }
  }
  writer.int64(source_at)
  writer.int64(retrieved_at)
  write_evidence(writer, evidence)
  writer.finish()
}

///|
pub fn ProviderCallbackEvidenceV3::new(
  provider_id : String,
  provider_event_id : String,
  body_digest : @contracts.ContentDigest,
  external_idempotency_key : String,
  dispatch_fence : Int64,
  reconciliation_fence : Int64?,
  provider_profile_digest : @contracts.ContentDigest,
  outcome : @effects.ExternalRecoveryOutcomeV3,
  not_applied_barrier : CallbackNotAppliedBarrierV3?,
  source_at : Int64,
  retrieved_at : Int64,
  evidence : Array[@contracts.EvidenceRef],
) -> ProviderCallbackEvidenceV3 raise OrchestrationError {
  require_text(provider_id, "provider_callback_provider_id_v3")
  require_text(provider_event_id, "provider_callback_event_id_v3")
  require_text(external_idempotency_key, "provider_callback_external_key_v3")
  let invalid_reconciliation_fence = match reconciliation_fence {
    Some(value) => value < 0L
    None => false
  }
  if dispatch_fence < 0L ||
    invalid_reconciliation_fence ||
    source_at < 0L ||
    retrieved_at < source_at ||
    evidence.is_empty() {
    raise MalformedInput(field="provider_callback_bounds_v3")
  }
  if (outcome == @effects.RecoveryConfirmedNotAppliedV3) !=
    (not_applied_barrier is Some(_)) {
    raise RecoveryViolation(field="provider_callback_barrier_shape_v3")
  }
  let canonical = provider_callback_evidence_signing_bytes_v3(
    provider_id, provider_event_id, body_digest, external_idempotency_key, dispatch_fence,
    reconciliation_fence, provider_profile_digest, outcome, not_applied_barrier,
    source_at, retrieved_at, evidence,
  )
  {
    provider_id,
    provider_event_id,
    body_digest,
    external_idempotency_key,
    dispatch_fence,
    reconciliation_fence,
    provider_profile_digest,
    outcome,
    not_applied_barrier,
    source_at,
    retrieved_at,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
fn decode_provider_callback_evidence_v3(
  bytes : Bytes,
) -> ProviderCallbackEvidenceV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != provider_callback_evidence_magic_v3 {
    raise MalformedInput(field="provider_callback_evidence_magic_v3")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="provider_callback_evidence_v3", version~)
  }
  let provider_id = reader.read_string()
  let provider_event_id = reader.read_string()
  let body_digest = reader.read_digest()
  let external_idempotency_key = reader.read_string()
  let dispatch_fence = reader.read_int64()
  let reconciliation_fence = reader.read_optional_int64()
  let provider_profile_digest = reader.read_digest()
  let outcome = @effects.decode_external_recovery_outcome_v3(
    reader.read_bytes(),
  ) catch {
    _ => raise MalformedInput(field="provider_callback_outcome_v3")
  }
  let not_applied_barrier = match reader.read_byte() {
    0 => None
    1 => Some(decode_callback_not_applied_barrier_v3(reader.read_bytes()))
    _ => raise MalformedInput(field="provider_callback_barrier_tag_v3")
  }
  let source_at = reader.read_int64()
  let retrieved_at = reader.read_int64()
  let evidence = reader.read_evidence()
  reader.require_end()
  let value = ProviderCallbackEvidenceV3::new(
    provider_id, provider_event_id, body_digest, external_idempotency_key, dispatch_fence,
    reconciliation_fence, provider_profile_digest, outcome, not_applied_barrier,
    source_at, retrieved_at, evidence,
  )
  if value.canonical != bytes {
    raise DigestMismatch(field="provider_callback_evidence_noncanonical_v3")
  }
  value
}

///|
pub fn ProviderCallbackEvidenceV3::provider_id(
  self : ProviderCallbackEvidenceV3,
) -> String {
  self.provider_id
}

///|
pub fn ProviderCallbackEvidenceV3::provider_event_id(
  self : ProviderCallbackEvidenceV3,
) -> String {
  self.provider_event_id
}

///|
pub fn ProviderCallbackEvidenceV3::body_digest(
  self : ProviderCallbackEvidenceV3,
) -> @contracts.ContentDigest {
  self.body_digest
}

///|
pub fn ProviderCallbackEvidenceV3::external_idempotency_key(
  self : ProviderCallbackEvidenceV3,
) -> String {
  self.external_idempotency_key
}

///|
pub fn ProviderCallbackEvidenceV3::dispatch_fence(
  self : ProviderCallbackEvidenceV3,
) -> Int64 {
  self.dispatch_fence
}

///|
pub fn ProviderCallbackEvidenceV3::reconciliation_fence(
  self : ProviderCallbackEvidenceV3,
) -> Int64? {
  self.reconciliation_fence
}

///|
pub fn ProviderCallbackEvidenceV3::provider_profile_digest(
  self : ProviderCallbackEvidenceV3,
) -> @contracts.ContentDigest {
  self.provider_profile_digest
}

///|
pub fn ProviderCallbackEvidenceV3::outcome(
  self : ProviderCallbackEvidenceV3,
) -> @effects.ExternalRecoveryOutcomeV3 {
  self.outcome
}

///|
pub fn ProviderCallbackEvidenceV3::not_applied_barrier(
  self : ProviderCallbackEvidenceV3,
) -> CallbackNotAppliedBarrierV3? {
  self.not_applied_barrier
}

///|
pub fn ProviderCallbackEvidenceV3::source_at(
  self : ProviderCallbackEvidenceV3,
) -> Int64 {
  self.source_at
}

///|
pub fn ProviderCallbackEvidenceV3::retrieved_at(
  self : ProviderCallbackEvidenceV3,
) -> Int64 {
  self.retrieved_at
}

///|
pub fn ProviderCallbackEvidenceV3::evidence(
  self : ProviderCallbackEvidenceV3,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn ProviderCallbackEvidenceV3::canonical_bytes(
  self : ProviderCallbackEvidenceV3,
) -> Bytes {
  self.canonical
}

///|
pub fn ProviderCallbackEvidenceV3::digest(
  self : ProviderCallbackEvidenceV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub struct RecoveryCallbackRecordV3 {
  callback_ref : @contracts.RecordRef
  binding_ref : @contracts.RecordRef
  binding_digest : @contracts.ContentDigest
  evidence_workflow : @contracts.RecordRef
  work_workflow : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  dispatch_claim_ref : @contracts.RecordRef
  dispatch_claim_digest : @contracts.ContentDigest
  reconciliation_claim_ref : @contracts.RecordRef?
  reconciliation_claim_digest : @contracts.ContentDigest?
  external_idempotency_key : String
  dispatch_fence : Int64
  reconciliation_fence : Int64?
  provider_profile_digest : @contracts.ContentDigest
  callback : ProviderCallbackEvidenceV3
  event_id : String
  command_idempotency_key : String
  expected_evidence_revision : Int64
  expected_evidence_head_digest : @contracts.ContentDigest?
  expected_evidence_replay_digest : @contracts.ContentDigest
  expected_work_revision : Int64
  expected_work_head_digest : @contracts.ContentDigest
  expected_work_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn recovery_callback_record_signing_bytes_v3(
  callback_id : String,
  binding : RecoveryEvidenceStreamBindingV3,
  intent_ref : @contracts.RecordRef,
  governed_subject : @contracts.RecordRef,
  dispatch_claim_ref : @contracts.RecordRef,
  dispatch_claim_digest : @contracts.ContentDigest,
  reconciliation_claim_ref : @contracts.RecordRef?,
  reconciliation_claim_digest : @contracts.ContentDigest?,
  external_idempotency_key : String,
  dispatch_fence : Int64,
  reconciliation_fence : Int64?,
  provider_profile_digest : @contracts.ContentDigest,
  callback : ProviderCallbackEvidenceV3,
  event_id : String,
  command_idempotency_key : String,
  expected_evidence_revision : Int64,
  expected_evidence_head_digest : @contracts.ContentDigest?,
  expected_evidence_replay_digest : @contracts.ContentDigest,
  expected_work_revision : Int64,
  expected_work_head_digest : @contracts.ContentDigest,
  expected_work_replay_digest : @contracts.ContentDigest,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_callback_record_magic_v3)
  writer.string("3.0.0")
  writer.string(callback_id)
  write_ref(writer, binding.binding_ref)
  writer.string(binding.digest.text())
  write_ref(writer, binding.evidence_workflow)
  write_ref(writer, binding.work_workflow)
  write_ref(writer, intent_ref)
  write_ref(writer, governed_subject)
  write_ref(writer, dispatch_claim_ref)
  writer.string(dispatch_claim_digest.text())
  write_optional_ref(writer, reconciliation_claim_ref)
  writer.optional_digest(reconciliation_claim_digest)
  writer.string(external_idempotency_key)
  writer.int64(dispatch_fence)
  writer.optional_int64(reconciliation_fence)
  writer.string(provider_profile_digest.text())
  writer.bytes(callback.canonical)
  writer.string(event_id)
  writer.string(command_idempotency_key)
  writer.int64(expected_evidence_revision)
  writer.optional_digest(expected_evidence_head_digest)
  writer.string(expected_evidence_replay_digest.text())
  writer.int64(expected_work_revision)
  writer.string(expected_work_head_digest.text())
  writer.string(expected_work_replay_digest.text())
  writer.finish()
}

///|
fn decode_recovery_callback_record_v3(
  bytes : Bytes,
) -> RecoveryCallbackRecordV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != recovery_callback_record_magic_v3 {
    raise MalformedInput(field="recovery_callback_record_magic_v3")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="recovery_callback_record_v3", version~)
  }
  let callback_id = reader.read_string()
  let binding_ref = reader.read_ref()
  let binding_digest = reader.read_digest()
  let evidence_workflow = reader.read_ref()
  let work_workflow = reader.read_ref()
  let intent_ref = reader.read_ref()
  let governed_subject = reader.read_ref()
  let dispatch_claim_ref = reader.read_ref()
  let dispatch_claim_digest = reader.read_digest()
  let reconciliation_claim_ref = reader.read_optional_ref()
  let reconciliation_claim_digest = reader.read_optional_digest()
  let external_idempotency_key = reader.read_string()
  let dispatch_fence = reader.read_int64()
  let reconciliation_fence = reader.read_optional_int64()
  let provider_profile_digest = reader.read_digest()
  let callback = decode_provider_callback_evidence_v3(reader.read_bytes())
  let event_id = reader.read_string()
  let command_idempotency_key = reader.read_string()
  let expected_evidence_revision = reader.read_int64()
  let expected_evidence_head_digest = reader.read_optional_digest()
  let expected_evidence_replay_digest = reader.read_digest()
  let expected_work_revision = reader.read_int64()
  let expected_work_head_digest = reader.read_digest()
  let expected_work_replay_digest = reader.read_digest()
  reader.require_end()
  if expected_evidence_revision < 0L ||
    expected_work_revision <= 0L ||
    dispatch_fence < 0L ||
    (reconciliation_claim_ref is Some(_)) !=
    (reconciliation_claim_digest is Some(_)) ||
    (reconciliation_claim_ref is Some(_)) != (reconciliation_fence is Some(_)) {
    raise MalformedInput(field="recovery_callback_record_shape_v3")
  }
  let binding_canonical_writer = OrchestrationWriter::new()
  binding_canonical_writer.bytes(recovery_evidence_stream_binding_magic_v3)
  binding_canonical_writer.string("3.0.0")
  binding_canonical_writer.string(binding_ref.id())
  write_ref(binding_canonical_writer, evidence_workflow)
  write_ref(binding_canonical_writer, work_workflow)
  let binding_canonical = binding_canonical_writer.finish()
  let binding : RecoveryEvidenceStreamBindingV3 = {
    binding_ref,
    evidence_workflow,
    work_workflow,
    canonical: binding_canonical,
    digest: binding_digest,
  }
  if evidence_workflow == work_workflow ||
    @contracts.sha256_digest(binding_canonical) != binding_digest ||
    binding_ref !=
    self_ref_v3(
      "orchestration-recovery-evidence-stream-binding-v3",
      binding_ref.id(),
      binding_digest,
    ) {
    raise DigestMismatch(field="recovery_callback_binding_v3")
  }
  let canonical = recovery_callback_record_signing_bytes_v3(
    callback_id, binding, intent_ref, governed_subject, dispatch_claim_ref, dispatch_claim_digest,
    reconciliation_claim_ref, reconciliation_claim_digest, external_idempotency_key,
    dispatch_fence, reconciliation_fence, provider_profile_digest, callback, event_id,
    command_idempotency_key, expected_evidence_revision, expected_evidence_head_digest,
    expected_evidence_replay_digest, expected_work_revision, expected_work_head_digest,
    expected_work_replay_digest,
  )
  if canonical != bytes {
    raise DigestMismatch(field="recovery_callback_record_noncanonical_v3")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    callback_ref: self_ref_v3(
      "orchestration-recovery-callback-v3", callback_id, digest,
    ),
    binding_ref,
    binding_digest,
    evidence_workflow,
    work_workflow,
    intent_ref,
    governed_subject,
    dispatch_claim_ref,
    dispatch_claim_digest,
    reconciliation_claim_ref,
    reconciliation_claim_digest,
    external_idempotency_key,
    dispatch_fence,
    reconciliation_fence,
    provider_profile_digest,
    callback,
    event_id,
    command_idempotency_key,
    expected_evidence_revision,
    expected_evidence_head_digest,
    expected_evidence_replay_digest,
    expected_work_revision,
    expected_work_head_digest,
    expected_work_replay_digest,
    canonical,
    digest,
  }
}

///|
fn bytes_have_recovery_callback_record_magic_v3(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    value => value == recovery_callback_record_magic_v3
  }
}

///|
pub fn RecoveryCallbackRecordV3::record_ref(
  self : RecoveryCallbackRecordV3,
) -> @contracts.RecordRef {
  self.callback_ref
}

///|
pub fn RecoveryCallbackRecordV3::evidence_workflow(
  self : RecoveryCallbackRecordV3,
) -> @contracts.RecordRef {
  self.evidence_workflow
}

///|
pub fn RecoveryCallbackRecordV3::work_workflow(
  self : RecoveryCallbackRecordV3,
) -> @contracts.RecordRef {
  self.work_workflow
}

///|
pub fn RecoveryCallbackRecordV3::intent_ref(
  self : RecoveryCallbackRecordV3,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn RecoveryCallbackRecordV3::dispatch_claim_ref(
  self : RecoveryCallbackRecordV3,
) -> @contracts.RecordRef {
  self.dispatch_claim_ref
}

///|
pub fn RecoveryCallbackRecordV3::reconciliation_claim_ref(
  self : RecoveryCallbackRecordV3,
) -> @contracts.RecordRef? {
  self.reconciliation_claim_ref
}

///|
pub fn RecoveryCallbackRecordV3::external_idempotency_key(
  self : RecoveryCallbackRecordV3,
) -> String {
  self.external_idempotency_key
}

///|
pub fn RecoveryCallbackRecordV3::dispatch_fence(
  self : RecoveryCallbackRecordV3,
) -> Int64 {
  self.dispatch_fence
}

///|
pub fn RecoveryCallbackRecordV3::reconciliation_fence(
  self : RecoveryCallbackRecordV3,
) -> Int64? {
  self.reconciliation_fence
}

///|
pub fn RecoveryCallbackRecordV3::provider_profile_digest(
  self : RecoveryCallbackRecordV3,
) -> @contracts.ContentDigest {
  self.provider_profile_digest
}

///|
pub fn RecoveryCallbackRecordV3::callback_evidence(
  self : RecoveryCallbackRecordV3,
) -> ProviderCallbackEvidenceV3 {
  self.callback
}

///|
pub fn RecoveryCallbackRecordV3::provider_id(
  self : RecoveryCallbackRecordV3,
) -> String {
  self.callback.provider_id
}

///|
pub fn RecoveryCallbackRecordV3::provider_event_id(
  self : RecoveryCallbackRecordV3,
) -> String {
  self.callback.provider_event_id
}

///|
pub fn RecoveryCallbackRecordV3::body_digest(
  self : RecoveryCallbackRecordV3,
) -> @contracts.ContentDigest {
  self.callback.body_digest
}

///|
pub fn RecoveryCallbackRecordV3::outcome(
  self : RecoveryCallbackRecordV3,
) -> @effects.ExternalRecoveryOutcomeV3 {
  self.callback.outcome
}

///|
pub fn RecoveryCallbackRecordV3::source_at(
  self : RecoveryCallbackRecordV3,
) -> Int64 {
  self.callback.source_at
}

///|
pub fn RecoveryCallbackRecordV3::retrieved_at(
  self : RecoveryCallbackRecordV3,
) -> Int64 {
  self.callback.retrieved_at
}

///|
pub fn RecoveryCallbackRecordV3::evidence(
  self : RecoveryCallbackRecordV3,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.callback.evidence
}

///|
pub fn RecoveryCallbackRecordV3::canonical_bytes(
  self : RecoveryCallbackRecordV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryCallbackRecordV3::digest(
  self : RecoveryCallbackRecordV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub(all) enum RecoveryCallbackDispositionV3 {
  CallbackEvidenceAcceptedV3
  CallbackEvidenceExactDuplicateV3
  CallbackEvidenceChangedBodyConflictV3
  CallbackEvidenceStaleFenceV3
  CallbackEvidenceContradictoryOutcomeV3
  CallbackEvidenceManualHoldV3
} derive(Eq, Debug)

///|
fn recovery_callback_disposition_wire_v3(
  value : RecoveryCallbackDispositionV3,
) -> String {
  match value {
    CallbackEvidenceAcceptedV3 => "accepted"
    CallbackEvidenceExactDuplicateV3 => "exact_duplicate"
    CallbackEvidenceChangedBodyConflictV3 => "changed_body_conflict"
    CallbackEvidenceStaleFenceV3 => "stale_fence"
    CallbackEvidenceContradictoryOutcomeV3 => "contradictory_outcome"
    CallbackEvidenceManualHoldV3 => "manual_hold"
  }
}

///|
pub struct RecoveryCallbackProjectionEntryV3 {
  record : RecoveryCallbackRecordV3
  disposition : RecoveryCallbackDispositionV3
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn make_recovery_callback_projection_entry_v3(
  record : RecoveryCallbackRecordV3,
  disposition : RecoveryCallbackDispositionV3,
) -> RecoveryCallbackProjectionEntryV3 {
  let writer = OrchestrationWriter::new()
  try! writer.bytes(b"FLOW7/RECOVERY-CALLBACK-PROJECTION-ENTRY-V3/3.0.0")
  try! writer.string("3.0.0")
  try! writer.bytes(record.canonical)
  try! writer.string(recovery_callback_disposition_wire_v3(disposition))
  let canonical = writer.finish()
  {
    record,
    disposition,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn RecoveryCallbackProjectionEntryV3::record(
  self : RecoveryCallbackProjectionEntryV3,
) -> RecoveryCallbackRecordV3 {
  self.record
}

///|
pub fn RecoveryCallbackProjectionEntryV3::disposition(
  self : RecoveryCallbackProjectionEntryV3,
) -> RecoveryCallbackDispositionV3 {
  self.disposition
}

///|
pub fn RecoveryCallbackProjectionEntryV3::is_quarantined(
  self : RecoveryCallbackProjectionEntryV3,
) -> Bool {
  self.disposition == CallbackEvidenceChangedBodyConflictV3 ||
  self.disposition == CallbackEvidenceStaleFenceV3 ||
  self.disposition == CallbackEvidenceContradictoryOutcomeV3 ||
  self.disposition == CallbackEvidenceManualHoldV3
}

///|
pub fn RecoveryCallbackProjectionEntryV3::canonical_bytes(
  self : RecoveryCallbackProjectionEntryV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryCallbackProjectionEntryV3::digest(
  self : RecoveryCallbackProjectionEntryV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
priv struct RecoveryCallbackWorkSourceV3 {
  dispatch_claim : DispatchClaimRecordV3
  reconciliation_claim : ReconciliationClaimRecordV3?
  activation : RecoveryProtocolActivatedV3
  authoritative_outcomes : ReadOnlyArray[@effects.ExternalRecoveryOutcomeV3]
}

///|
fn recovery_callback_work_source_v3(
  record : RecoveryCallbackRecordV3,
  work_prefix : @storage.ReplayResult,
) -> RecoveryCallbackWorkSourceV3 raise OrchestrationError {
  let matching_dispatch_events = work_prefix
    .events()
    .filter(event => {
      event.payload().envelope_kind() == dispatch_claim_event_kind_v3 &&
      event.payload().idempotency_ref() == Some(record.dispatch_claim_ref.id())
    })
  if matching_dispatch_events.length() != 1 {
    raise ReplayBindingViolation(field="recovery_callback_dispatch_claim_v3")
  }
  let dispatch_event = matching_dispatch_events[0]
  let dispatch_claim = decode_dispatch_claim_record_v3(
    dispatch_event.payload().payload(),
  )
  require_dispatch_claim_event_binding_v3(dispatch_claim, dispatch_event)
  require_dispatch_claim_transaction_v3(
    dispatch_claim, dispatch_event, work_prefix,
  )
  if dispatch_claim.claim_ref != record.dispatch_claim_ref ||
    dispatch_claim.digest != record.dispatch_claim_digest ||
    dispatch_claim.intent_ref != record.intent_ref ||
    dispatch_claim.governed_subject != record.governed_subject ||
    dispatch_claim.workflow != record.work_workflow ||
    dispatch_claim.external_idempotency_key != record.external_idempotency_key ||
    dispatch_claim.fencing_token != record.dispatch_fence ||
    dispatch_claim.provider_profile_digest != record.provider_profile_digest {
    raise ReplayBindingViolation(field="recovery_callback_dispatch_binding_v3")
  }
  let matching_activations = work_prefix
    .events()
    .filter(event => {
      event.payload().envelope_kind() == recovery_activation_event_kind_v3 &&
      event.payload().idempotency_ref() ==
      Some(dispatch_claim.activation_ref.id())
    })
  if matching_activations.length() != 1 {
    raise ReplayBindingViolation(field="recovery_callback_activation_v3")
  }
  let activation_event = matching_activations[0]
  let activation = decode_recovery_protocol_activated_v3(
    activation_event.payload().payload(),
  )
  require_recovery_activation_event_binding_v3(activation, activation_event)
  require_recovery_activation_transaction_v3(
    activation, activation_event, work_prefix,
  )
  if activation.activation_ref != dispatch_claim.activation_ref ||
    activation.digest != dispatch_claim.activation_digest ||
    activation.profile.digest != record.provider_profile_digest {
    raise ReplayBindingViolation(
      field="recovery_callback_activation_binding_v3",
    )
  }
  let reconciliation_claims : Array[ReconciliationClaimRecordV3] = []
  for event in work_prefix.events() {
    if event.payload().envelope_kind() == reconciliation_claim_event_kind_v3 {
      let claim = decode_reconciliation_claim_record_v3(
        event.payload().payload(),
      )
      require_reconciliation_claim_event_binding_v3(claim, event)
      require_reconciliation_claim_transaction_v3(claim, event, work_prefix)
      if claim.intent_ref == record.intent_ref {
        reconciliation_claims.push(claim)
      }
    }
  }
  let mut latest_reconciliation : ReconciliationClaimRecordV3? = None
  for value in reconciliation_claims {
    match latest_reconciliation {
      None => latest_reconciliation = Some(value)
      Some(prior) if value.reconciliation_ordinal > prior.reconciliation_ordinal =>
        latest_reconciliation = Some(value)
      Some(_) => ()
    }
  }
  match (record.reconciliation_claim_ref, latest_reconciliation) {
    (None, None) => ()
    (Some(record_ref), Some(claim)) =>
      if record_ref != claim.reconciliation_claim_ref ||
        record.reconciliation_claim_digest != Some(claim.digest) ||
        record.reconciliation_fence != Some(claim.fencing_token) ||
        claim.dispatch_claim_ref != dispatch_claim.claim_ref {
        raise ReplayBindingViolation(
          field="recovery_callback_reconciliation_binding_v3",
        )
      }
    _ =>
      raise ReplayBindingViolation(
        field="recovery_callback_reconciliation_binding_v3",
      )
  }
  let authoritative_outcomes : Array[@effects.ExternalRecoveryOutcomeV3] = []
  for event in work_prefix.events() {
    if event.payload().envelope_kind() == dispatch_observation_event_kind_v3 {
      let observation = decode_dispatch_observation_record_v3(
        event.payload().payload(),
      )
      require_dispatch_observation_binding_v3(observation, event, work_prefix)
      if observation.intent_ref == record.intent_ref &&
        observation.outcome != @effects.RecoveryStillUnknownV3 {
        authoritative_outcomes.push(observation.outcome)
      }
    } else if event.payload().envelope_kind() ==
      reconciliation_result_event_kind_v3 {
      let result = decode_reconciliation_result_record_v3(
        event.payload().payload(),
      )
      require_reconciliation_result_binding_v3(result, event, work_prefix)
      if result.intent_ref == record.intent_ref {
        match result.outcome {
          ReconciliationAppliedV3 =>
            authoritative_outcomes.push(@effects.RecoveryKnownSucceededV3)
          ReconciliationTerminalFailedV3 =>
            authoritative_outcomes.push(@effects.RecoveryKnownFailedV3)
          ReconciliationConfirmedNotAppliedV3 =>
            authoritative_outcomes.push(@effects.RecoveryConfirmedNotAppliedV3)
          ReconciliationUnknownV3 => ()
        }
      }
    }
  }
  {
    dispatch_claim,
    reconciliation_claim: latest_reconciliation,
    activation,
    authoritative_outcomes: ReadOnlyArray::from_array(authoritative_outcomes),
  }
}

///|
fn recovery_callback_is_authoritative_v3(
  record : RecoveryCallbackRecordV3,
  source : RecoveryCallbackWorkSourceV3,
) -> Bool {
  recovery_callback_record_has_authoritative_shape_v3(record, source.activation)
}

///|
fn recovery_callback_record_has_authoritative_shape_v3(
  record : RecoveryCallbackRecordV3,
  activation : RecoveryProtocolActivatedV3,
) -> Bool {
  match record.callback.outcome {
    @effects.RecoveryKnownSucceededV3 | @effects.RecoveryKnownFailedV3 => true
    @effects.RecoveryConfirmedNotAppliedV3 =>
      match record.callback.not_applied_barrier {
        Some(barrier) => {
          let reconciliation_floor = record.reconciliation_fence.unwrap_or(
            record.dispatch_fence,
          )
          activation.profile.supports_authoritative_tombstone() &&
          barrier.provider_fence_floor > record.dispatch_fence &&
          barrier.provider_fence_floor >= reconciliation_floor
        }
        None => false
      }
    @effects.RecoveryStillUnknownV3 => false
  }
}

///|
fn recovery_callback_same_identity_v3(
  left : RecoveryCallbackRecordV3,
  right : RecoveryCallbackRecordV3,
) -> Bool {
  left.callback.provider_id == right.callback.provider_id &&
  left.callback.provider_event_id == right.callback.provider_event_id
}

///|
fn recovery_callback_same_bound_body_v3(
  left : RecoveryCallbackRecordV3,
  right : RecoveryCallbackRecordV3,
) -> Bool {
  left.callback.body_digest == right.callback.body_digest &&
  left.work_workflow == right.work_workflow &&
  left.intent_ref == right.intent_ref &&
  left.external_idempotency_key == right.external_idempotency_key &&
  left.provider_profile_digest == right.provider_profile_digest
}

///|
fn derive_recovery_callback_disposition_v3(
  record : RecoveryCallbackRecordV3,
  source : RecoveryCallbackWorkSourceV3,
  prior : ArrayView[RecoveryCallbackProjectionEntryV3],
) -> RecoveryCallbackDispositionV3 {
  match
    first(prior, entry => {
      recovery_callback_same_identity_v3(entry.record, record)
    }) {
    Some(entry) if recovery_callback_same_bound_body_v3(entry.record, record) =>
      CallbackEvidenceExactDuplicateV3
    Some(_) => CallbackEvidenceChangedBodyConflictV3
    None => {
      let active_reconciliation_fence = source.reconciliation_claim.map(claim => {
        claim.fencing_token
      })
      if record.callback.dispatch_fence != source.dispatch_claim.fencing_token ||
        record.callback.reconciliation_fence != active_reconciliation_fence {
        CallbackEvidenceStaleFenceV3
      } else if prior.any(entry => {
          entry.record.intent_ref == record.intent_ref &&
          (
            entry.disposition == CallbackEvidenceChangedBodyConflictV3 ||
            entry.disposition == CallbackEvidenceContradictoryOutcomeV3 ||
            entry.disposition == CallbackEvidenceManualHoldV3
          )
        }) {
        CallbackEvidenceManualHoldV3
      } else if recovery_callback_is_authoritative_v3(record, source) &&
        source.authoritative_outcomes.any(outcome => {
          outcome != record.callback.outcome
        }) {
        CallbackEvidenceContradictoryOutcomeV3
      } else if recovery_callback_is_authoritative_v3(record, source) &&
        prior.any(entry => {
          if entry.record.intent_ref != record.intent_ref ||
            entry.disposition != CallbackEvidenceAcceptedV3 {
            false
          } else {
            recovery_callback_record_has_authoritative_shape_v3(
              entry.record,
              source.activation,
            ) &&
            entry.record.callback.outcome != record.callback.outcome
          }
        }) {
        CallbackEvidenceContradictoryOutcomeV3
      } else {
        CallbackEvidenceAcceptedV3
      }
    }
  }
}

///|
fn require_recovery_callback_event_binding_v3(
  record : RecoveryCallbackRecordV3,
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let envelope = event.payload()
  if event.record_version().text() != orchestration_record_version ||
    event.schema_version().text() != orchestration_schema_version ||
    event.workflow() != record.evidence_workflow ||
    event.event_ref().id() != record.event_id ||
    event.sequence() != event.revision() ||
    event.revision() != record.expected_evidence_revision + 1L ||
    event.previous_event_digest() != record.expected_evidence_head_digest ||
    event.idempotency_key() != record.callback_ref.id() ||
    envelope.envelope_id() != event.event_ref().id() ||
    envelope.contract_id() != dispatch_claim_transport_contract_id_v3 ||
    envelope.contract_version().text() != orchestration_record_version ||
    envelope.producer_id() != dispatch_claim_transport_producer_id_v3 ||
    envelope.producer_version().text() != orchestration_record_version ||
    envelope.envelope_kind() != recovery_callback_evidence_event_kind_v3 ||
    envelope.subject() != record.governed_subject ||
    envelope.run_ref() != Some(record.evidence_workflow) ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() is Some(_) ||
    envelope.correlation_ref() != Some(record.work_workflow.id()) ||
    envelope.causation_ref() !=
    Some(
      record.reconciliation_claim_ref.unwrap_or(record.dispatch_claim_ref).id(),
    ) ||
    envelope.idempotency_ref() != Some(record.callback_ref.id()) ||
    envelope.schema() !=
    phase1b_effect_schema_v22(recovery_callback_evidence_event_kind_v3) ||
    envelope.payload() != record.canonical ||
    envelope.previous_digest() != record.expected_evidence_head_digest ||
    !same_evidence(event.evidence(), record.callback.evidence) ||
    !same_evidence(envelope.evidence(), record.callback.evidence) ||
    !envelope.artifacts().is_empty() ||
    !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(field="recovery_callback_transport_v3")
  }
  let matching = replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().length() == 1 &&
      batch.event_refs()[0] == event.event_ref()
    })
  if matching.length() != 1 ||
    matching[0].expected_revision() != record.expected_evidence_revision ||
    matching[0].command_idempotency_key() != record.command_idempotency_key ||
    !matching[0].intent_refs().is_empty() ||
    matching[0].guards().length() != 1 {
    raise ReplayBindingViolation(field="recovery_callback_transaction_v3")
  }
  let head_guard = matching[0].guards()[0]
  if head_guard.workflow() != record.work_workflow ||
    head_guard.expected_revision() != record.expected_work_revision ||
    head_guard.expected_head_digest() != Some(record.expected_work_head_digest) ||
    head_guard.expected_replay_digest() != record.expected_work_replay_digest {
    raise ReplayBindingViolation(field="recovery_callback_work_guard_v3")
  }
}

///|
pub struct CurrentRecoveryEvidenceProjectionV3 {
  binding : RecoveryEvidenceStreamBindingV3
  replay : @storage.ReplayResult
  bound_work_replay : @storage.ReplayResult
  entries : ReadOnlyArray[RecoveryCallbackProjectionEntryV3]
  state_digest : @contracts.ContentDigest
}

///|
fn recovery_evidence_event_consumption_v3(
  binding : RecoveryEvidenceStreamBindingV3,
  event : @storage.WorkflowEvent,
  evidence_replay : @storage.ReplayResult,
  work_replay : @storage.ReplayResult,
  prior : ArrayView[RecoveryCallbackProjectionEntryV3],
) -> RecoveryCallbackProjectionEntryV3 raise OrchestrationError {
  let payload = event.payload().payload()
  if event.payload().envelope_kind() != recovery_callback_evidence_event_kind_v3 {
    if bytes_have_recovery_callback_record_magic_v3(payload) {
      raise ReplayBindingViolation(field="recovery_callback_unknown_wrapper_v3")
    }
    raise RecoveryViolation(field="recovery_evidence_stream_foreign_event_v3")
  }
  let record = decode_recovery_callback_record_v3(payload)
  if record.binding_ref != binding.binding_ref ||
    record.binding_digest != binding.digest ||
    record.evidence_workflow != binding.evidence_workflow ||
    record.work_workflow != binding.work_workflow {
    raise ReplayBindingViolation(field="recovery_callback_stream_binding_v3")
  }
  require_recovery_callback_event_binding_v3(record, event, evidence_replay)
  let evidence_prefix = verified_prefix_v3(
    evidence_replay,
    record.expected_evidence_revision,
    "recovery_callback_evidence_prefix_v3",
  )
  if evidence_prefix.head().last_event_digest() !=
    record.expected_evidence_head_digest ||
    evidence_prefix.replay_digest() != record.expected_evidence_replay_digest {
    raise ReplayBindingViolation(field="recovery_callback_evidence_prefix_v3")
  }
  let work_prefix = verified_prefix_v3(
    work_replay,
    record.expected_work_revision,
    "recovery_callback_work_prefix_v3",
  )
  if work_prefix.head().last_event_digest() !=
    Some(record.expected_work_head_digest) ||
    work_prefix.replay_digest() != record.expected_work_replay_digest {
    raise ReplayBindingViolation(field="recovery_callback_work_prefix_v3")
  }
  let source = recovery_callback_work_source_v3(record, work_prefix)
  let disposition = derive_recovery_callback_disposition_v3(
    record, source, prior,
  )
  make_recovery_callback_projection_entry_v3(record, disposition)
}

///|
pub fn fold_recovery_evidence_stream_v3(
  binding : RecoveryEvidenceStreamBindingV3,
  evidence_replay : @storage.ReplayResult,
  work_replay : @storage.ReplayResult,
) -> CurrentRecoveryEvidenceProjectionV3 raise OrchestrationError {
  if evidence_replay.workflow() != binding.evidence_workflow ||
    work_replay.workflow() != binding.work_workflow {
    raise WorkflowMismatch(field="recovery_evidence_stream_binding_v3")
  }
  let entries : Array[RecoveryCallbackProjectionEntryV3] = []
  for event in evidence_replay.events() {
    entries.push(
      recovery_evidence_event_consumption_v3(
        binding, event, evidence_replay, work_replay, entries,
      ),
    )
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/CURRENT-RECOVERY-EVIDENCE-PROJECTION-V3/3.0.0")
  writer.string("3.0.0")
  writer.bytes(binding.canonical)
  writer.string(evidence_replay.replay_digest().text())
  writer.string(work_replay.replay_digest().text())
  writer.count(entries.length())
  for entry in entries {
    writer.bytes(entry.canonical)
  }
  {
    binding,
    replay: evidence_replay,
    bound_work_replay: work_replay,
    entries: ReadOnlyArray::from_array(entries),
    state_digest: @contracts.sha256_digest(writer.finish()),
  }
}

///|
pub fn CurrentRecoveryEvidenceProjectionV3::workflow(
  self : CurrentRecoveryEvidenceProjectionV3,
) -> @contracts.RecordRef {
  self.binding.evidence_workflow
}

///|
pub fn CurrentRecoveryEvidenceProjectionV3::bound_workflow(
  self : CurrentRecoveryEvidenceProjectionV3,
) -> @contracts.RecordRef {
  self.binding.work_workflow
}

///|
pub fn CurrentRecoveryEvidenceProjectionV3::revision(
  self : CurrentRecoveryEvidenceProjectionV3,
) -> Int64 {
  self.replay.head().revision()
}

///|
pub fn CurrentRecoveryEvidenceProjectionV3::head_digest(
  self : CurrentRecoveryEvidenceProjectionV3,
) -> @contracts.ContentDigest? {
  self.replay.head().last_event_digest()
}

///|
pub fn CurrentRecoveryEvidenceProjectionV3::replay_digest(
  self : CurrentRecoveryEvidenceProjectionV3,
) -> @contracts.ContentDigest {
  self.replay.replay_digest()
}

///|
pub fn CurrentRecoveryEvidenceProjectionV3::bound_work_replay_digest(
  self : CurrentRecoveryEvidenceProjectionV3,
) -> @contracts.ContentDigest {
  self.bound_work_replay.replay_digest()
}

///|
pub fn CurrentRecoveryEvidenceProjectionV3::entries(
  self : CurrentRecoveryEvidenceProjectionV3,
) -> ReadOnlyArray[RecoveryCallbackProjectionEntryV3] {
  self.entries
}

///|
pub fn CurrentRecoveryEvidenceProjectionV3::quarantined_entries(
  self : CurrentRecoveryEvidenceProjectionV3,
) -> ReadOnlyArray[RecoveryCallbackProjectionEntryV3] {
  ReadOnlyArray::from_array(
    self.entries.filter(entry => entry.is_quarantined()),
  )
}

///|
pub fn CurrentRecoveryEvidenceProjectionV3::state_digest(
  self : CurrentRecoveryEvidenceProjectionV3,
) -> @contracts.ContentDigest {
  self.state_digest
}
