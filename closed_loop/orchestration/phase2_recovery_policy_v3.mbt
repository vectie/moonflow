///|
let recovery_policy_bound_event_kind_v3 = "effect.recovery.policy-bound.v3"

///|
let recovery_policy_magic_v3 = b"FLOW7/RECOVERY-POLICY-V3/3.0.0"

///|
let recovery_policy_bound_magic_v3 = b"FLOW7/RECOVERY-POLICY-BOUND-V3/3.0.0"

///|
/// Immutable, domain-neutral automation bound. It controls query attempts only;
/// it never establishes a provider outcome or grants create authority.
pub struct RecoveryPolicyV3 {
  policy_ref : @contracts.RecordRef
  policy_id : String
  maximum_reconciliation_attempts : Int64
  maximum_elapsed : Int64
  claim_ttl : Int64
  base_delay : Int64
  maximum_delay : Int64
  backoff_numerator : Int64
  backoff_denominator : Int64
  jitter_range : Int64
  seed : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn RecoveryPolicyV3::new(
  policy_id : String,
  maximum_reconciliation_attempts : Int64,
  maximum_elapsed : Int64,
  claim_ttl : Int64,
  base_delay : Int64,
  maximum_delay : Int64,
  backoff_numerator : Int64,
  backoff_denominator : Int64,
  jitter_range : Int64,
  seed : @contracts.ContentDigest,
) -> RecoveryPolicyV3 raise OrchestrationError {
  require_text(policy_id, "recovery_policy_v3_id")
  if maximum_reconciliation_attempts <= 0L ||
    maximum_elapsed <= 0L ||
    claim_ttl <= 0L ||
    base_delay < 0L ||
    maximum_delay < base_delay ||
    backoff_numerator <= 0L ||
    backoff_denominator <= 0L ||
    jitter_range < 0L {
    raise RetryBoundViolation(field="recovery_policy_v3_bounds")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_policy_magic_v3)
  writer.string("3.0.0")
  writer.string(policy_id)
  writer.int64(maximum_reconciliation_attempts)
  writer.int64(maximum_elapsed)
  writer.int64(claim_ttl)
  writer.int64(base_delay)
  writer.int64(maximum_delay)
  writer.int64(backoff_numerator)
  writer.int64(backoff_denominator)
  writer.int64(jitter_range)
  writer.string(seed.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    policy_ref: self_ref_v3(
      "orchestration-recovery-policy-v3", policy_id, digest,
    ),
    policy_id,
    maximum_reconciliation_attempts,
    maximum_elapsed,
    claim_ttl,
    base_delay,
    maximum_delay,
    backoff_numerator,
    backoff_denominator,
    jitter_range,
    seed,
    canonical,
    digest,
  }
}

///|
fn decode_recovery_policy_v3(
  bytes : Bytes,
) -> RecoveryPolicyV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != recovery_policy_magic_v3 {
    raise MalformedInput(field="recovery_policy_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="recovery_policy_v3", version~)
  }
  let value = RecoveryPolicyV3::new(
    reader.read_string(),
    reader.read_int64(),
    reader.read_int64(),
    reader.read_int64(),
    reader.read_int64(),
    reader.read_int64(),
    reader.read_int64(),
    reader.read_int64(),
    reader.read_int64(),
    reader.read_digest(),
  )
  reader.require_end()
  if value.canonical != bytes {
    raise DigestMismatch(field="recovery_policy_v3_noncanonical")
  }
  value
}

///|
pub fn RecoveryPolicyV3::record_ref(
  self : RecoveryPolicyV3,
) -> @contracts.RecordRef {
  self.policy_ref
}

///|
pub fn RecoveryPolicyV3::maximum_reconciliation_attempts(
  self : RecoveryPolicyV3,
) -> Int64 {
  self.maximum_reconciliation_attempts
}

///|
pub fn RecoveryPolicyV3::maximum_elapsed(self : RecoveryPolicyV3) -> Int64 {
  self.maximum_elapsed
}

///|
pub fn RecoveryPolicyV3::claim_ttl(self : RecoveryPolicyV3) -> Int64 {
  self.claim_ttl
}

///|
pub fn RecoveryPolicyV3::base_delay(self : RecoveryPolicyV3) -> Int64 {
  self.base_delay
}

///|
pub fn RecoveryPolicyV3::maximum_delay(self : RecoveryPolicyV3) -> Int64 {
  self.maximum_delay
}

///|
pub fn RecoveryPolicyV3::backoff_numerator(self : RecoveryPolicyV3) -> Int64 {
  self.backoff_numerator
}

///|
pub fn RecoveryPolicyV3::backoff_denominator(self : RecoveryPolicyV3) -> Int64 {
  self.backoff_denominator
}

///|
pub fn RecoveryPolicyV3::jitter_range(self : RecoveryPolicyV3) -> Int64 {
  self.jitter_range
}

///|
pub fn RecoveryPolicyV3::seed(
  self : RecoveryPolicyV3,
) -> @contracts.ContentDigest {
  self.seed
}

///|
pub fn RecoveryPolicyV3::canonical_bytes(self : RecoveryPolicyV3) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryPolicyV3::digest(
  self : RecoveryPolicyV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub struct RecoveryPolicyBoundV3 {
  binding_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  dispatch_claim_ref : @contracts.RecordRef
  dispatch_claim_digest : @contracts.ContentDigest
  activation_ref : @contracts.RecordRef
  activation_digest : @contracts.ContentDigest
  provider_profile_digest : @contracts.ContentDigest
  policy : RecoveryPolicyV3
  event_id : String
  command_idempotency_key : String
  bound_at : Int64
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
fn recovery_policy_bound_signing_bytes_v3(
  binding_id : String,
  workflow : @contracts.RecordRef,
  intent_ref : @contracts.RecordRef,
  governed_subject : @contracts.RecordRef,
  dispatch_claim_ref : @contracts.RecordRef,
  dispatch_claim_digest : @contracts.ContentDigest,
  activation_ref : @contracts.RecordRef,
  activation_digest : @contracts.ContentDigest,
  provider_profile_digest : @contracts.ContentDigest,
  policy : RecoveryPolicyV3,
  event_id : String,
  command_idempotency_key : String,
  bound_at : Int64,
  expected_work_revision : Int64,
  expected_work_head_digest : @contracts.ContentDigest,
  expected_work_replay_digest : @contracts.ContentDigest,
  governance_workflow : @contracts.RecordRef,
  expected_governance_revision : Int64,
  expected_governance_head_digest : @contracts.ContentDigest?,
  expected_governance_replay_digest : @contracts.ContentDigest,
  evidence : ArrayView[@contracts.EvidenceRef],
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_policy_bound_magic_v3)
  writer.string("3.0.0")
  writer.string(binding_id)
  write_ref(writer, workflow)
  write_ref(writer, intent_ref)
  write_ref(writer, governed_subject)
  write_ref(writer, dispatch_claim_ref)
  writer.string(dispatch_claim_digest.text())
  write_ref(writer, activation_ref)
  writer.string(activation_digest.text())
  writer.string(provider_profile_digest.text())
  write_ref(writer, policy.policy_ref)
  writer.bytes(policy.canonical)
  writer.string(event_id)
  writer.string(command_idempotency_key)
  writer.int64(bound_at)
  writer.int64(expected_work_revision)
  writer.string(expected_work_head_digest.text())
  writer.string(expected_work_replay_digest.text())
  write_ref(writer, governance_workflow)
  writer.int64(expected_governance_revision)
  writer.optional_digest(expected_governance_head_digest)
  writer.string(expected_governance_replay_digest.text())
  write_evidence(writer, evidence)
  writer.finish()
}

///|
fn make_recovery_policy_bound_v3(
  binding_id : String,
  current : CurrentGovernedRecoveryProjectionV3,
  claim : DispatchClaimRecordV3,
  policy : RecoveryPolicyV3,
  event_id : String,
  command_idempotency_key : String,
  bound_at : Int64,
) -> RecoveryPolicyBoundV3 raise OrchestrationError {
  require_text(binding_id, "recovery_policy_binding_v3_id")
  require_text(event_id, "recovery_policy_binding_v3_event")
  require_text(command_idempotency_key, "recovery_policy_binding_v3_command")
  if bound_at < claim.claimed_at {
    raise OrderingViolation(field="recovery_policy_binding_v3_time")
  }
  let canonical = recovery_policy_bound_signing_bytes_v3(
    binding_id,
    claim.workflow,
    claim.intent_ref,
    claim.governed_subject,
    claim.claim_ref,
    claim.digest,
    claim.activation_ref,
    claim.activation_digest,
    claim.provider_profile_digest,
    policy,
    event_id,
    command_idempotency_key,
    bound_at,
    current.current.work_revision,
    current.current.work_head_digest,
    current.current.work_replay_digest,
    current.governance_replay.workflow(),
    current.current.governance_revision,
    current.current.governance_head_digest,
    current.current.governance_replay_digest,
    claim.evidence,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    binding_ref: self_ref_v3(
      "orchestration-recovery-policy-binding-v3", binding_id, digest,
    ),
    workflow: claim.workflow,
    intent_ref: claim.intent_ref,
    governed_subject: claim.governed_subject,
    dispatch_claim_ref: claim.claim_ref,
    dispatch_claim_digest: claim.digest,
    activation_ref: claim.activation_ref,
    activation_digest: claim.activation_digest,
    provider_profile_digest: claim.provider_profile_digest,
    policy,
    event_id,
    command_idempotency_key,
    bound_at,
    expected_work_revision: current.current.work_revision,
    expected_work_head_digest: current.current.work_head_digest,
    expected_work_replay_digest: current.current.work_replay_digest,
    governance_workflow: current.governance_replay.workflow(),
    expected_governance_revision: current.current.governance_revision,
    expected_governance_head_digest: current.current.governance_head_digest,
    expected_governance_replay_digest: current.current.governance_replay_digest,
    evidence: claim.evidence,
    canonical,
    digest,
  }
}

///|
fn decode_recovery_policy_bound_v3(
  bytes : Bytes,
) -> RecoveryPolicyBoundV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != recovery_policy_bound_magic_v3 {
    raise MalformedInput(field="recovery_policy_binding_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="recovery_policy_binding_v3", version~)
  }
  let binding_id = reader.read_string()
  let workflow = reader.read_ref()
  let intent_ref = reader.read_ref()
  let governed_subject = reader.read_ref()
  let dispatch_claim_ref = reader.read_ref()
  let dispatch_claim_digest = reader.read_digest()
  let activation_ref = reader.read_ref()
  let activation_digest = reader.read_digest()
  let provider_profile_digest = reader.read_digest()
  let policy_ref = reader.read_ref()
  let policy = decode_recovery_policy_v3(reader.read_bytes())
  let event_id = reader.read_string()
  let command_idempotency_key = reader.read_string()
  let bound_at = reader.read_int64()
  let expected_work_revision = reader.read_int64()
  let expected_work_head_digest = reader.read_digest()
  let expected_work_replay_digest = reader.read_digest()
  let governance_workflow = reader.read_ref()
  let expected_governance_revision = reader.read_int64()
  let expected_governance_head_digest = reader.read_optional_digest()
  let expected_governance_replay_digest = reader.read_digest()
  let evidence = reader.read_evidence()
  reader.require_end()
  if policy_ref != policy.policy_ref {
    raise ReplayBindingViolation(field="recovery_policy_binding_v3_policy")
  }
  let canonical = recovery_policy_bound_signing_bytes_v3(
    binding_id, workflow, intent_ref, governed_subject, dispatch_claim_ref, dispatch_claim_digest,
    activation_ref, activation_digest, provider_profile_digest, policy, event_id,
    command_idempotency_key, bound_at, expected_work_revision, expected_work_head_digest,
    expected_work_replay_digest, governance_workflow, expected_governance_revision,
    expected_governance_head_digest, expected_governance_replay_digest, evidence,
  )
  if canonical != bytes {
    raise DigestMismatch(field="recovery_policy_binding_v3_noncanonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    binding_ref: self_ref_v3(
      "orchestration-recovery-policy-binding-v3", binding_id, digest,
    ),
    workflow,
    intent_ref,
    governed_subject,
    dispatch_claim_ref,
    dispatch_claim_digest,
    activation_ref,
    activation_digest,
    provider_profile_digest,
    policy,
    event_id,
    command_idempotency_key,
    bound_at,
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
fn bytes_have_recovery_policy_bound_magic_v3(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    magic => magic == recovery_policy_bound_magic_v3
  }
}

///|
fn recovery_policy_bound_event_v3(
  record : RecoveryPolicyBoundV3,
) -> @storage.WorkflowEvent raise OrchestrationError {
  let evidence = [ for value in record.evidence => value ]
  let envelope = @contracts.WireEnvelope::new(
    dispatch_claim_transport_contract_id_v3,
    orchestration_record_version,
    record.event_id,
    recovery_policy_bound_event_kind_v3,
    record.governed_subject,
    phase1b_effect_schema_v22(recovery_policy_bound_event_kind_v3),
    record.canonical,
    dispatch_claim_transport_producer_id_v3,
    orchestration_record_version,
    [],
    evidence,
    run_ref=record.workflow,
    correlation_ref=record.workflow.id(),
    causation_ref=record.dispatch_claim_ref.id(),
    idempotency_ref=record.binding_ref.id(),
    previous_digest=record.expected_work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="recovery_policy_bound_envelope_v3")
  }
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    record.workflow,
    record.event_id,
    record.expected_work_revision + 1L,
    record.expected_work_revision + 1L,
    record.binding_ref.id(),
    envelope,
    evidence,
    previous_event_digest=record.expected_work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="recovery_policy_bound_event_v3")
  }
}

///|
fn require_recovery_policy_bound_binding_v3(
  record : RecoveryPolicyBoundV3,
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let envelope = event.payload()
  if event.record_version().text() != orchestration_record_version ||
    event.schema_version().text() != orchestration_schema_version ||
    event.workflow() != record.workflow ||
    event.event_ref().id() != record.event_id ||
    event.sequence() != event.revision() ||
    event.revision() != record.expected_work_revision + 1L ||
    event.previous_event_digest() != Some(record.expected_work_head_digest) ||
    event.idempotency_key() != record.binding_ref.id() ||
    envelope.envelope_id() != event.event_ref().id() ||
    envelope.contract_id() != dispatch_claim_transport_contract_id_v3 ||
    envelope.contract_version().text() != orchestration_record_version ||
    envelope.producer_id() != dispatch_claim_transport_producer_id_v3 ||
    envelope.producer_version().text() != orchestration_record_version ||
    envelope.envelope_kind() != recovery_policy_bound_event_kind_v3 ||
    envelope.subject() != record.governed_subject ||
    envelope.run_ref() != Some(record.workflow) ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() is Some(_) ||
    envelope.correlation_ref() != Some(record.workflow.id()) ||
    envelope.causation_ref() != Some(record.dispatch_claim_ref.id()) ||
    envelope.idempotency_ref() != Some(record.binding_ref.id()) ||
    envelope.previous_digest() != Some(record.expected_work_head_digest) ||
    envelope.schema() !=
    phase1b_effect_schema_v22(recovery_policy_bound_event_kind_v3) ||
    envelope.payload() != record.canonical ||
    !same_evidence(event.evidence(), record.evidence) ||
    !same_evidence(envelope.evidence(), record.evidence) ||
    !envelope.artifacts().is_empty() ||
    !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(field="recovery_policy_binding_v3_transport")
  }
  let batches = replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().length() == 1 &&
      batch.event_refs()[0] == event.event_ref()
    })
  if batches.length() != 1 ||
    batches[0].expected_revision() != record.expected_work_revision ||
    batches[0].command_idempotency_key() != record.command_idempotency_key ||
    !batches[0].intent_refs().is_empty() ||
    batches[0].guards().length() != 1 {
    raise ReplayBindingViolation(field="recovery_policy_binding_v3_transaction")
  }
  let head_guard = batches[0].guards()[0]
  if head_guard.workflow() != record.governance_workflow ||
    head_guard.expected_revision() != record.expected_governance_revision ||
    head_guard.expected_head_digest() != record.expected_governance_head_digest ||
    head_guard.expected_replay_digest() !=
    record.expected_governance_replay_digest {
    raise ReplayBindingViolation(field="recovery_policy_binding_v3_guard")
  }
}

///|
fn require_recovery_policy_prefix_v3(
  empty : @effects.EffectsProjection,
  record : RecoveryPolicyBoundV3,
  work_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let work_prefix = verified_prefix_v3(
    work_replay,
    record.expected_work_revision,
    "recovery_policy_binding_v3_work_prefix",
  )
  let governance_prefix = verified_prefix_v3(
    governance_replay,
    record.expected_governance_revision,
    "recovery_policy_binding_v3_governance_prefix",
  )
  if work_prefix.head().last_event_digest() !=
    Some(record.expected_work_head_digest) ||
    work_prefix.replay_digest() != record.expected_work_replay_digest ||
    governance_prefix.workflow() != record.governance_workflow ||
    governance_prefix.head().last_event_digest() !=
    record.expected_governance_head_digest ||
    governance_prefix.replay_digest() !=
    record.expected_governance_replay_digest {
    raise ReplayBindingViolation(field="recovery_policy_binding_v3_prefix")
  }
  let prefix = fold_governed_recovery_v3(empty, work_prefix, governance_prefix)
  guard prefix.current_claim(record.intent_ref) is Some(claim) else {
    raise ReplayBindingViolation(field="recovery_policy_binding_v3_claim")
  }
  if claim.claim_ref != record.dispatch_claim_ref ||
    claim.digest != record.dispatch_claim_digest ||
    claim.activation_ref != record.activation_ref ||
    claim.activation_digest != record.activation_digest ||
    claim.provider_profile_digest != record.provider_profile_digest ||
    claim.governed_subject != record.governed_subject ||
    claim.workflow != record.workflow ||
    record.bound_at < claim.claimed_at ||
    !same_evidence(claim.evidence, record.evidence) ||
    prefix.current.work.work_terminal is Some(_) ||
    prefix.current_reconciliation_claim_v3(record.intent_ref) is Some(_) ||
    prefix.recovery_policy_for_v3(record.intent_ref) is Some(_) {
    raise ReplayBindingViolation(field="recovery_policy_binding_v3_source")
  }
  match prefix.state_for(record.intent_ref) {
    @effects.RecoveryDispatchAttemptedV3
    | @effects.RecoveryUnknownRequiresReconciliationV3 => ()
    _ => raise ReplayBindingViolation(field="recovery_policy_binding_v3_state")
  }
}

///|
pub(all) enum RecoveryPolicyBindingResultV3 {
  RecoveryPolicyBindingFreshV3
  RecoveryPolicyBindingAlreadyCommittedV3
  RecoveryPolicyBindingRaceLostV3
  RecoveryPolicyBindingStaleGovernanceV3
} derive(Eq, Debug)

///|
/// Bind policy before the first reconciliation claim. A pending cancellation
/// is allowed because dispatch already crossed its point of no return.
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] bind_recovery_policy_v3(
  store : S,
  current : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
  policy : RecoveryPolicyV3,
  binding_id : String,
  event_id : String,
  command_idempotency_key : String,
  bound_at : Int64,
) -> RecoveryPolicyBindingResultV3 raise {
  if current.current.work.work_terminal is Some(_) {
    raise RecoveryViolation(field="recovery_policy_binding_v3_terminal")
  }
  match current.recovery_policy_for_v3(intent_ref) {
    Some(existing) => {
      if existing.command_idempotency_key == command_idempotency_key &&
        existing.binding_ref.id() == binding_id &&
        existing.event_id == event_id &&
        existing.bound_at == bound_at &&
        existing.policy.digest == policy.digest {
        return RecoveryPolicyBindingAlreadyCommittedV3
      }
      if existing.command_idempotency_key == command_idempotency_key {
        raise IdempotencyConflict(key=command_idempotency_key)
      }
      raise RecoveryViolation(field="recovery_policy_binding_v3_existing")
    }
    None => ()
  }
  if current.current_reconciliation_claim_v3(intent_ref) is Some(_) {
    raise RecoveryViolation(field="recovery_policy_binding_v3_too_late")
  }
  guard current.current_claim(intent_ref) is Some(claim) else {
    raise RecoveryViolation(field="recovery_policy_binding_v3_claim")
  }
  match current.state_for(intent_ref) {
    @effects.RecoveryDispatchAttemptedV3
    | @effects.RecoveryUnknownRequiresReconciliationV3 => ()
    _ => raise RecoveryViolation(field="recovery_policy_binding_v3_state")
  }
  let record = make_recovery_policy_bound_v3(
    binding_id, current, claim, policy, event_id, command_idempotency_key, bound_at,
  )
  let event = recovery_policy_bound_event_v3(record)
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
      record.governance_workflow,
      record.expected_governance_revision,
      record.expected_governance_head_digest,
      record.expected_governance_replay_digest,
    ),
  ])
  require_phase2_governance_guard_profile_v3(store, guarded)
  try {
    match store.classified_guarded_commit(guarded) {
      @storage.FreshlyApplied(_) => RecoveryPolicyBindingFreshV3
      @storage.AlreadyCommitted(_) => RecoveryPolicyBindingAlreadyCommittedV3
      @storage.GuardRejected(_) => RecoveryPolicyBindingStaleGovernanceV3
    }
  } catch {
    @storage.OptimisticRevisionConflict(..) => RecoveryPolicyBindingRaceLostV3
    error => raise error
  }
}

///|
pub fn RecoveryPolicyBoundV3::record_ref(
  self : RecoveryPolicyBoundV3,
) -> @contracts.RecordRef {
  self.binding_ref
}

///|
pub fn RecoveryPolicyBoundV3::intent_ref(
  self : RecoveryPolicyBoundV3,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn RecoveryPolicyBoundV3::bound_at(self : RecoveryPolicyBoundV3) -> Int64 {
  self.bound_at
}

///|
pub fn RecoveryPolicyBoundV3::policy(
  self : RecoveryPolicyBoundV3,
) -> RecoveryPolicyV3 {
  self.policy
}

///|
pub fn RecoveryPolicyBoundV3::canonical_bytes(
  self : RecoveryPolicyBoundV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryPolicyBoundV3::digest(
  self : RecoveryPolicyBoundV3,
) -> @contracts.ContentDigest {
  self.digest
}
