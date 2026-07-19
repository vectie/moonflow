///|
let effect_retry_policy_bound_event_kind_v3 = "effect.retry.policy-bound.v3"

///|
let recovery_retry_intent_event_kind_v3 = "effect.retry.intent-created.v3"

///|
let recovery_retry_scheduled_event_kind_v3 = "effect.retry.scheduled.v3"

///|
let effect_retry_policy_magic_v3 = b"FLOW7/EFFECT-RETRY-POLICY-V3/3.0.0"

///|
let effect_retry_policy_bound_magic_v3 = b"FLOW7/EFFECT-RETRY-POLICY-BOUND-V3/3.0.0"

///|
let recovery_retry_intent_magic_v3 = b"FLOW7/RECOVERY-RETRY-INTENT-V3/3.0.0"

///|
let recovery_retry_scheduled_magic_v3 = b"FLOW7/RECOVERY-RETRY-SCHEDULED-V3/3.0.0"

///|
/// A separate immutable policy for creating a new effect only after an
/// authoritative non-application settlement. It is not the reconciliation
/// backoff policy and contains no caller-selectable failure class.
pub struct EffectRetryPolicyV3 {
  policy_ref : @contracts.RecordRef
  maximum_effect_attempts : Int64
  maximum_effect_retries : Int64
  maximum_elapsed : Int64
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
pub fn EffectRetryPolicyV3::new(
  policy_id : String,
  maximum_effect_attempts : Int64,
  maximum_effect_retries : Int64,
  maximum_elapsed : Int64,
  base_delay : Int64,
  maximum_delay : Int64,
  backoff_numerator : Int64,
  backoff_denominator : Int64,
  jitter_range : Int64,
  seed : @contracts.ContentDigest,
) -> EffectRetryPolicyV3 raise OrchestrationError {
  require_text(policy_id, "effect_retry_policy_v3_id")
  if maximum_effect_attempts <= 1L ||
    maximum_effect_retries <= 0L ||
    maximum_effect_retries >= maximum_effect_attempts ||
    maximum_elapsed <= 0L ||
    base_delay < 0L ||
    maximum_delay < base_delay ||
    backoff_numerator <= 0L ||
    backoff_denominator <= 0L ||
    jitter_range < 0L ||
    jitter_range > maximum_delay {
    raise RetryBoundViolation(field="effect_retry_policy_v3_bounds")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(effect_retry_policy_magic_v3)
  writer.string("3.0.0")
  writer.string(policy_id)
  writer.int64(maximum_effect_attempts)
  writer.int64(maximum_effect_retries)
  writer.int64(maximum_elapsed)
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
      "orchestration-effect-retry-policy-v3", policy_id, digest,
    ),
    maximum_effect_attempts,
    maximum_effect_retries,
    maximum_elapsed,
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
fn decode_effect_retry_policy_v3(
  bytes : Bytes,
) -> EffectRetryPolicyV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != effect_retry_policy_magic_v3 {
    raise MalformedInput(field="effect_retry_policy_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="effect_retry_policy_v3", version~)
  }
  let value = EffectRetryPolicyV3::new(
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
    raise DigestMismatch(field="effect_retry_policy_v3_noncanonical")
  }
  value
}

///|
pub fn EffectRetryPolicyV3::record_ref(
  self : EffectRetryPolicyV3,
) -> @contracts.RecordRef {
  self.policy_ref
}

///|
pub fn EffectRetryPolicyV3::maximum_effect_attempts(
  self : EffectRetryPolicyV3,
) -> Int64 {
  self.maximum_effect_attempts
}

///|
pub fn EffectRetryPolicyV3::maximum_effect_retries(
  self : EffectRetryPolicyV3,
) -> Int64 {
  self.maximum_effect_retries
}

///|
pub fn EffectRetryPolicyV3::canonical_bytes(
  self : EffectRetryPolicyV3,
) -> Bytes {
  self.canonical
}

///|
pub fn EffectRetryPolicyV3::digest(
  self : EffectRetryPolicyV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub struct EffectRetryPolicyBoundV3 {
  binding_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  source_intent_ref : @contracts.RecordRef
  dispatch_claim_ref : @contracts.RecordRef
  dispatch_claim_digest : @contracts.ContentDigest
  activation_ref : @contracts.RecordRef
  activation_digest : @contracts.ContentDigest
  policy : EffectRetryPolicyV3
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
fn effect_retry_policy_bound_signing_bytes_v3(
  binding_id : String,
  current : CurrentGovernedRecoveryProjectionV3,
  claim : DispatchClaimRecordV3,
  policy : EffectRetryPolicyV3,
  event_id : String,
  command_idempotency_key : String,
  bound_at : Int64,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(effect_retry_policy_bound_magic_v3)
  writer.string("3.0.0")
  writer.string(binding_id)
  write_ref(writer, claim.workflow)
  write_ref(writer, claim.governed_subject)
  write_ref(writer, claim.intent_ref)
  write_ref(writer, claim.claim_ref)
  writer.string(claim.digest.text())
  write_ref(writer, claim.activation_ref)
  writer.string(claim.activation_digest.text())
  write_ref(writer, policy.policy_ref)
  writer.bytes(policy.canonical)
  writer.string(event_id)
  writer.string(command_idempotency_key)
  writer.int64(bound_at)
  writer.int64(current.current.work_revision)
  writer.string(current.current.work_head_digest.text())
  writer.string(current.current.work_replay_digest.text())
  write_ref(writer, current.governance_replay.workflow())
  writer.int64(current.current.governance_revision)
  writer.optional_digest(current.current.governance_head_digest)
  writer.string(current.current.governance_replay_digest.text())
  write_evidence(writer, claim.evidence)
  writer.finish()
}

///|
fn decode_effect_retry_policy_bound_v3(
  bytes : Bytes,
) -> EffectRetryPolicyBoundV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != effect_retry_policy_bound_magic_v3 {
    raise MalformedInput(field="effect_retry_policy_bound_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="effect_retry_policy_bound_v3", version~)
  }
  let binding_id = reader.read_string()
  let workflow = reader.read_ref()
  let governed_subject = reader.read_ref()
  let source_intent_ref = reader.read_ref()
  let dispatch_claim_ref = reader.read_ref()
  let dispatch_claim_digest = reader.read_digest()
  let activation_ref = reader.read_ref()
  let activation_digest = reader.read_digest()
  let policy = decode_effect_retry_policy_v3(reader.read_bytes())
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
  if bound_at < 0L ||
    expected_work_revision < 0L ||
    expected_governance_revision < 0L {
    raise MalformedInput(field="effect_retry_policy_bound_v3_bounds")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(effect_retry_policy_bound_magic_v3)
  writer.string("3.0.0")
  writer.string(binding_id)
  write_ref(writer, workflow)
  write_ref(writer, governed_subject)
  write_ref(writer, source_intent_ref)
  write_ref(writer, dispatch_claim_ref)
  writer.string(dispatch_claim_digest.text())
  write_ref(writer, activation_ref)
  writer.string(activation_digest.text())
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
  let canonical = writer.finish()
  if canonical != bytes {
    raise DigestMismatch(field="effect_retry_policy_bound_v3_noncanonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    binding_ref: self_ref_v3(
      "orchestration-effect-retry-policy-bound-v3", binding_id, digest,
    ),
    workflow,
    governed_subject,
    source_intent_ref,
    dispatch_claim_ref,
    dispatch_claim_digest,
    activation_ref,
    activation_digest,
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
fn effect_retry_policy_bound_event_v3(
  record : EffectRetryPolicyBoundV3,
) -> @storage.WorkflowEvent raise OrchestrationError {
  let evidence = [ for value in record.evidence => value ]
  let envelope = @contracts.WireEnvelope::new(
    dispatch_claim_transport_contract_id_v3,
    orchestration_record_version,
    record.event_id,
    effect_retry_policy_bound_event_kind_v3,
    record.governed_subject,
    phase1b_effect_schema_v22(effect_retry_policy_bound_event_kind_v3),
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
    _ => raise MalformedInput(field="effect_retry_policy_envelope_v3")
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
    _ => raise MalformedInput(field="effect_retry_policy_event_v3")
  }
}

///|
fn CurrentGovernedRecoveryProjectionV3::effect_retry_policy_for_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
) -> EffectRetryPolicyBoundV3? raise OrchestrationError {
  let values : Array[EffectRetryPolicyBoundV3] = []
  for event in self.work_replay.events() {
    if event.payload().envelope_kind() ==
      effect_retry_policy_bound_event_kind_v3 {
      let record = decode_effect_retry_policy_bound_v3(
        event.payload().payload(),
      )
      if record.source_intent_ref == intent_ref {
        if event.workflow() != record.workflow ||
          event.event_ref().id() != record.event_id ||
          event.revision() != record.expected_work_revision + 1L ||
          event.previous_event_digest() !=
          Some(record.expected_work_head_digest) ||
          event.payload().subject() != record.governed_subject {
          raise ReplayBindingViolation(
            field="effect_retry_policy_bound_v3_transport",
          )
        }
        let batches = self.work_replay
          .committed_batches()
          .filter(batch => {
            batch.event_refs().length() == 1 &&
            batch.event_refs()[0] == event.event_ref() &&
            batch.intent_refs().is_empty() &&
            batch.expected_revision() == record.expected_work_revision &&
            batch.command_idempotency_key() == record.command_idempotency_key &&
            batch.guards().length() == 1
          })
        if batches.length() != 1 {
          raise ReplayBindingViolation(
            field="effect_retry_policy_bound_v3_transaction",
          )
        }
        let head_guard = batches[0].guards()[0]
        if head_guard.workflow() != record.governance_workflow ||
          head_guard.expected_revision() != record.expected_governance_revision ||
          head_guard.expected_head_digest() !=
          record.expected_governance_head_digest ||
          head_guard.expected_replay_digest() !=
          record.expected_governance_replay_digest {
          raise ReplayBindingViolation(
            field="effect_retry_policy_bound_v3_guard",
          )
        }
        values.push(record)
      }
    }
  }
  if values.length() > 1 {
    raise RecoveryViolation(field="effect_retry_policy_bound_v3_duplicate")
  }
  if values.is_empty() {
    None
  } else {
    Some(values[0])
  }
}

///|
pub(all) enum EffectRetryPolicyBindingResultV3 {
  EffectRetryPolicyBindingFreshV3
  EffectRetryPolicyBindingAlreadyCommittedV3
  EffectRetryPolicyBindingRaceLostV3
  EffectRetryPolicyBindingStaleGovernanceV3
} derive(Eq, Debug)

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] bind_effect_retry_policy_v3(
  store : S,
  current : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
  policy : EffectRetryPolicyV3,
  binding_id : String,
  event_id : String,
  command_idempotency_key : String,
  bound_at : Int64,
) -> EffectRetryPolicyBindingResultV3 raise {
  if current.current.work.work_terminal is Some(_) ||
    current.current.work.cancellation is Some(_) ||
    current.effect_retry_policy_for_v3(intent_ref) is Some(_) ||
    current.current_reconciliation_claim_v3(intent_ref) is Some(_) {
    raise RecoveryViolation(field="effect_retry_policy_bound_v3_state")
  }
  guard current.current_claim(intent_ref) is Some(claim) else {
    raise RecoveryViolation(field="effect_retry_policy_bound_v3_claim")
  }
  require_text(binding_id, "effect_retry_policy_bound_v3_id")
  require_text(event_id, "effect_retry_policy_bound_v3_event")
  require_text(command_idempotency_key, "effect_retry_policy_bound_v3_command")
  if bound_at < claim.claimed_at {
    raise OrderingViolation(field="effect_retry_policy_bound_v3_time")
  }
  let canonical = effect_retry_policy_bound_signing_bytes_v3(
    binding_id, current, claim, policy, event_id, command_idempotency_key, bound_at,
  )
  let digest = @contracts.sha256_digest(canonical)
  let record : EffectRetryPolicyBoundV3 = {
    binding_ref: self_ref_v3(
      "orchestration-effect-retry-policy-bound-v3", binding_id, digest,
    ),
    workflow: claim.workflow,
    governed_subject: claim.governed_subject,
    source_intent_ref: claim.intent_ref,
    dispatch_claim_ref: claim.claim_ref,
    dispatch_claim_digest: claim.digest,
    activation_ref: claim.activation_ref,
    activation_digest: claim.activation_digest,
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
  let event = effect_retry_policy_bound_event_v3(record)
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
      @storage.FreshlyApplied(_) => EffectRetryPolicyBindingFreshV3
      @storage.AlreadyCommitted(_) => EffectRetryPolicyBindingAlreadyCommittedV3
      @storage.GuardRejected(_) => EffectRetryPolicyBindingStaleGovernanceV3
    }
  } catch {
    @storage.OptimisticRevisionConflict(..) =>
      EffectRetryPolicyBindingRaceLostV3
    error => raise error
  }
}

///|
pub fn EffectRetryPolicyBoundV3::record_ref(
  self : EffectRetryPolicyBoundV3,
) -> @contracts.RecordRef {
  self.binding_ref
}

///|
pub fn EffectRetryPolicyBoundV3::source_intent_ref(
  self : EffectRetryPolicyBoundV3,
) -> @contracts.RecordRef {
  self.source_intent_ref
}

///|
pub fn EffectRetryPolicyBoundV3::policy(
  self : EffectRetryPolicyBoundV3,
) -> EffectRetryPolicyV3 {
  self.policy
}

///|
pub fn EffectRetryPolicyBoundV3::canonical_bytes(
  self : EffectRetryPolicyBoundV3,
) -> Bytes {
  self.canonical
}

///|
pub fn EffectRetryPolicyBoundV3::digest(
  self : EffectRetryPolicyBoundV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub struct RecoveryRetryIntentV3 {
  retry_intent_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  source_settlement_ref : @contracts.RecordRef
  source_settlement_digest : @contracts.ContentDigest
  source_settlement_bytes : Bytes
  source_intent_ref : @contracts.RecordRef
  source_attempt_ref : @contracts.RecordRef
  source_dispatch_claim_ref : @contracts.RecordRef
  policy_binding_ref : @contracts.RecordRef
  policy_binding_digest : @contracts.ContentDigest
  policy_ref : @contracts.RecordRef
  policy_digest : @contracts.ContentDigest
  retry_ordinal : Int64
  attempt_ordinal : Int64
  requested_work : @contracts.WireEnvelope
  external_idempotency_key : String
  capability_ref : @contracts.RecordRef
  capability_kind : String
  due_at : Int64
  deadline : Int64
  created_at : Int64
  expected_work_revision : Int64
  expected_work_head_digest : @contracts.ContentDigest
  expected_work_replay_digest : @contracts.ContentDigest
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn recovery_retry_intent_signing_bytes_v3(
  retry_intent_id : String,
  current : CurrentGovernedRecoveryProjectionV3,
  source : RecoverySettlementSourceV3,
  claim : DispatchClaimRecordV3,
  binding : EffectRetryPolicyBoundV3,
  source_attempt_ref : @contracts.RecordRef,
  retry_ordinal : Int64,
  attempt_ordinal : Int64,
  requested_work : @contracts.WireEnvelope,
  external_idempotency_key : String,
  due_at : Int64,
  deadline : Int64,
  created_at : Int64,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_retry_intent_magic_v3)
  writer.string("3.0.0")
  writer.string(retry_intent_id)
  write_ref(writer, claim.workflow)
  write_ref(writer, claim.governed_subject)
  write_ref(writer, source.source_ref)
  writer.string(source.digest.text())
  writer.bytes(source.canonical)
  write_ref(writer, source.intent_ref)
  write_ref(writer, source_attempt_ref)
  write_ref(writer, claim.claim_ref)
  write_ref(writer, binding.binding_ref)
  writer.string(binding.digest.text())
  write_ref(writer, binding.policy.policy_ref)
  writer.string(binding.policy.digest.text())
  writer.int64(retry_ordinal)
  writer.int64(attempt_ordinal)
  writer.bytes(@contracts.encode_wire_envelope(requested_work))
  writer.string(external_idempotency_key)
  write_ref(writer, claim.capability_ref)
  writer.string(claim.capability_kind)
  writer.int64(due_at)
  writer.int64(deadline)
  writer.int64(created_at)
  writer.int64(current.current.work_revision)
  writer.string(current.current.work_head_digest.text())
  writer.string(current.current.work_replay_digest.text())
  write_evidence(writer, claim.evidence)
  writer.finish()
}

///|
fn decode_recovery_retry_intent_v3(
  bytes : Bytes,
) -> RecoveryRetryIntentV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != recovery_retry_intent_magic_v3 {
    raise MalformedInput(field="recovery_retry_v3_intent_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="recovery_retry_v3_intent", version~)
  }
  let retry_intent_id = reader.read_string()
  let workflow = reader.read_ref()
  let governed_subject = reader.read_ref()
  let source_settlement_ref = reader.read_ref()
  let source_settlement_digest = reader.read_digest()
  let source_settlement_bytes = reader.read_bytes()
  let source_intent_ref = reader.read_ref()
  let source_attempt_ref = reader.read_ref()
  let source_dispatch_claim_ref = reader.read_ref()
  let policy_binding_ref = reader.read_ref()
  let policy_binding_digest = reader.read_digest()
  let policy_ref = reader.read_ref()
  let policy_digest = reader.read_digest()
  let retry_ordinal = reader.read_int64()
  let attempt_ordinal = reader.read_int64()
  let requested_work = @contracts.decode_wire_envelope(reader.read_bytes()) catch {
    _ => raise MalformedInput(field="recovery_retry_v3_requested_work")
  }
  let external_idempotency_key = reader.read_string()
  let capability_ref = reader.read_ref()
  let capability_kind = reader.read_string()
  let due_at = reader.read_int64()
  let deadline = reader.read_int64()
  let created_at = reader.read_int64()
  let expected_work_revision = reader.read_int64()
  let expected_work_head_digest = reader.read_digest()
  let expected_work_replay_digest = reader.read_digest()
  let evidence = reader.read_evidence()
  reader.require_end()
  require_text(retry_intent_id, "recovery_retry_v3_intent_id")
  require_text(external_idempotency_key, "recovery_retry_v3_external_key")
  require_text(capability_kind, "recovery_retry_v3_capability_kind")
  if retry_ordinal <= 0L ||
    attempt_ordinal <= 1L ||
    due_at < 0L ||
    deadline < due_at ||
    created_at < 0L ||
    created_at > due_at ||
    expected_work_revision < 0L ||
    source_settlement_ref.digest() != source_settlement_digest ||
    @contracts.sha256_digest(source_settlement_bytes) !=
    source_settlement_digest ||
    policy_binding_ref.digest() != policy_binding_digest ||
    policy_ref.digest() != policy_digest ||
    requested_work.subject() != governed_subject {
    raise ReplayBindingViolation(field="recovery_retry_v3_intent_binding")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_retry_intent_magic_v3)
  writer.string("3.0.0")
  writer.string(retry_intent_id)
  write_ref(writer, workflow)
  write_ref(writer, governed_subject)
  write_ref(writer, source_settlement_ref)
  writer.string(source_settlement_digest.text())
  writer.bytes(source_settlement_bytes)
  write_ref(writer, source_intent_ref)
  write_ref(writer, source_attempt_ref)
  write_ref(writer, source_dispatch_claim_ref)
  write_ref(writer, policy_binding_ref)
  writer.string(policy_binding_digest.text())
  write_ref(writer, policy_ref)
  writer.string(policy_digest.text())
  writer.int64(retry_ordinal)
  writer.int64(attempt_ordinal)
  writer.bytes(@contracts.encode_wire_envelope(requested_work))
  writer.string(external_idempotency_key)
  write_ref(writer, capability_ref)
  writer.string(capability_kind)
  writer.int64(due_at)
  writer.int64(deadline)
  writer.int64(created_at)
  writer.int64(expected_work_revision)
  writer.string(expected_work_head_digest.text())
  writer.string(expected_work_replay_digest.text())
  write_evidence(writer, evidence)
  let canonical = writer.finish()
  if canonical != bytes {
    raise DigestMismatch(field="recovery_retry_v3_intent_noncanonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    retry_intent_ref: self_ref_v3(
      "orchestration-recovery-retry-intent-v3", retry_intent_id, digest,
    ),
    workflow,
    governed_subject,
    source_settlement_ref,
    source_settlement_digest,
    source_settlement_bytes,
    source_intent_ref,
    source_attempt_ref,
    source_dispatch_claim_ref,
    policy_binding_ref,
    policy_binding_digest,
    policy_ref,
    policy_digest,
    retry_ordinal,
    attempt_ordinal,
    requested_work,
    external_idempotency_key,
    capability_ref,
    capability_kind,
    due_at,
    deadline,
    created_at,
    expected_work_revision,
    expected_work_head_digest,
    expected_work_replay_digest,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical,
    digest,
  }
}

///|
pub struct RecoveryRetryScheduledV3 {
  schedule_ref : @contracts.RecordRef
  retry_intent : RecoveryRetryIntentV3
  intent_event_id : String
  schedule_event_id : String
  outbox_intent_id : String
  command_idempotency_key : String
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn recovery_retry_schedule_signing_bytes_v3(
  schedule_id : String,
  retry_intent : RecoveryRetryIntentV3,
  intent_event_id : String,
  schedule_event_id : String,
  outbox_intent_id : String,
  command_idempotency_key : String,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(recovery_retry_scheduled_magic_v3)
  writer.string("3.0.0")
  writer.string(schedule_id)
  write_ref(writer, retry_intent.retry_intent_ref)
  writer.string(retry_intent.digest.text())
  writer.bytes(retry_intent.canonical)
  writer.string(intent_event_id)
  writer.string(schedule_event_id)
  writer.string(outbox_intent_id)
  writer.string(command_idempotency_key)
  writer.finish()
}

///|
fn decode_recovery_retry_scheduled_v3(
  bytes : Bytes,
) -> RecoveryRetryScheduledV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != recovery_retry_scheduled_magic_v3 {
    raise MalformedInput(field="recovery_retry_v3_schedule_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="recovery_retry_v3_schedule", version~)
  }
  let schedule_id = reader.read_string()
  let retry_intent_ref = reader.read_ref()
  let retry_intent_digest = reader.read_digest()
  let retry_intent = decode_recovery_retry_intent_v3(reader.read_bytes())
  let intent_event_id = reader.read_string()
  let schedule_event_id = reader.read_string()
  let outbox_intent_id = reader.read_string()
  let command_idempotency_key = reader.read_string()
  reader.require_end()
  require_text(schedule_id, "recovery_retry_v3_schedule_id")
  require_text(intent_event_id, "recovery_retry_v3_intent_event")
  require_text(schedule_event_id, "recovery_retry_v3_schedule_event")
  require_text(outbox_intent_id, "recovery_retry_v3_outbox")
  require_text(command_idempotency_key, "recovery_retry_v3_command")
  if retry_intent.retry_intent_ref != retry_intent_ref ||
    retry_intent.digest != retry_intent_digest {
    raise ReplayBindingViolation(field="recovery_retry_v3_schedule_intent")
  }
  let canonical = recovery_retry_schedule_signing_bytes_v3(
    schedule_id, retry_intent, intent_event_id, schedule_event_id, outbox_intent_id,
    command_idempotency_key,
  )
  if canonical != bytes {
    raise DigestMismatch(field="recovery_retry_v3_schedule_noncanonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    schedule_ref: self_ref_v3(
      "orchestration-recovery-retry-schedule-v3", schedule_id, digest,
    ),
    retry_intent,
    intent_event_id,
    schedule_event_id,
    outbox_intent_id,
    command_idempotency_key,
    canonical,
    digest,
  }
}

///|
fn recovery_retry_event_v3(
  record : RecoveryRetryIntentV3,
  event_id : String,
) -> @storage.WorkflowEvent raise OrchestrationError {
  let evidence = [ for value in record.evidence => value ]
  let envelope = @contracts.WireEnvelope::new(
    dispatch_claim_transport_contract_id_v3,
    orchestration_record_version,
    event_id,
    recovery_retry_intent_event_kind_v3,
    record.governed_subject,
    phase1b_effect_schema_v22(recovery_retry_intent_event_kind_v3),
    record.canonical,
    dispatch_claim_transport_producer_id_v3,
    orchestration_record_version,
    [],
    evidence,
    run_ref=record.workflow,
    correlation_ref=record.workflow.id(),
    causation_ref=record.source_settlement_ref.id(),
    idempotency_ref=record.retry_intent_ref.id(),
    previous_digest=record.expected_work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="recovery_retry_envelope_v3")
  }
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    record.workflow,
    event_id,
    record.expected_work_revision + 1L,
    record.expected_work_revision + 1L,
    record.retry_intent_ref.id(),
    envelope,
    evidence,
    previous_event_digest=record.expected_work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="recovery_retry_event_v3")
  }
}

///|
fn recovery_retry_schedule_event_v3(
  schedule : RecoveryRetryScheduledV3,
  prior : @storage.WorkflowEvent,
) -> @storage.WorkflowEvent raise OrchestrationError {
  let record = schedule.retry_intent
  let evidence = [ for value in record.evidence => value ]
  let envelope = @contracts.WireEnvelope::new(
    dispatch_claim_transport_contract_id_v3,
    orchestration_record_version,
    schedule.schedule_event_id,
    recovery_retry_scheduled_event_kind_v3,
    record.governed_subject,
    phase1b_effect_schema_v22(recovery_retry_scheduled_event_kind_v3),
    schedule.canonical,
    dispatch_claim_transport_producer_id_v3,
    orchestration_record_version,
    [],
    evidence,
    run_ref=record.workflow,
    correlation_ref=record.workflow.id(),
    causation_ref=record.retry_intent_ref.id(),
    idempotency_ref=schedule.schedule_ref.id(),
    previous_digest=prior.event_ref().digest(),
  ) catch {
    _ => raise MalformedInput(field="recovery_retry_schedule_envelope_v3")
  }
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    record.workflow,
    schedule.schedule_event_id,
    prior.sequence() + 1L,
    prior.revision() + 1L,
    schedule.schedule_ref.id(),
    envelope,
    evidence,
    previous_event_digest=prior.event_ref().digest(),
  ) catch {
    _ => raise MalformedInput(field="recovery_retry_schedule_event_v3")
  }
}

///|
pub struct RecoveryRetryCandidateV3 {
  candidate_ref : @contracts.RecordRef
  retry_intent : RecoveryRetryIntentV3
  schedule : RecoveryRetryScheduledV3
  outbox : @storage.OutboxIntent
  guarded_request : @storage.GuardedCommitRequest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn existing_recovery_retry_count_v3(
  current : CurrentGovernedRecoveryProjectionV3,
  source_intent_ref : @contracts.RecordRef,
) -> Int64 raise OrchestrationError {
  let mut count = 0L
  for event in current.work_replay.events() {
    if event.payload().envelope_kind() == recovery_retry_scheduled_event_kind_v3 {
      let schedule = decode_recovery_retry_scheduled_v3(
        event.payload().payload(),
      )
      if schedule.retry_intent.source_intent_ref == source_intent_ref {
        count = count + 1L
      }
    }
  }
  count
}

///|
/// Replay-derived attempt lineage for the effect being retried. The first V3
/// retry descends from the strict legacy attempt. A later V3 retry descends
/// from the immutable parent retry intent that served as its dispatch-attempt
/// identity; no legacy retry receipt or plan is synthesized for that branch.
struct RecoveryRetrySourceAttemptV3 {
  source_attempt_ref : @contracts.RecordRef
  source_attempt_ordinal : Int64
  next_retry_ordinal : Int64
}

///|
fn CurrentGovernedRecoveryProjectionV3::recovery_retry_source_attempt_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  claim : DispatchClaimRecordV3,
) -> RecoveryRetrySourceAttemptV3 raise OrchestrationError {
  let legacy = self.current.work.effects
    .attempts()
    .filter(attempt => attempt.attempt_ref() == claim.attempt_ref)
  let parents : Array[RecoveryRetryIntentV3] = []
  for event in self.work_replay.events() {
    if event.payload().envelope_kind() == recovery_retry_scheduled_event_kind_v3 {
      let schedule = decode_recovery_retry_scheduled_v3(
        event.payload().payload(),
      )
      if schedule.retry_intent.retry_intent_ref == claim.intent_ref {
        if recovery_retry_event_consumption_v3(event, self.work_replay) != 1 {
          raise ReplayBindingViolation(
            field="recovery_retry_v3_parent_transaction",
          )
        }
        parents.push(schedule.retry_intent)
      }
    }
  }
  if legacy.length() + parents.length() != 1 {
    raise ReplayBindingViolation(field="recovery_retry_v3_source_attempt")
  }
  if legacy.length() == 1 {
    let attempt = legacy[0]
    return {
      source_attempt_ref: attempt.attempt_ref(),
      source_attempt_ordinal: attempt.attempt_ordinal(),
      next_retry_ordinal: existing_recovery_retry_count_v3(
        self,
        claim.intent_ref,
      ) +
      1L,
    }
  }
  let parent = parents[0]
  if claim.attempt_ref != parent.retry_intent_ref ||
    claim.governed_subject != parent.governed_subject ||
    claim.capability_ref != parent.capability_ref ||
    claim.capability_kind != parent.capability_kind ||
    claim.external_idempotency_key != parent.external_idempotency_key {
    raise ReplayBindingViolation(field="recovery_retry_v3_parent_claim")
  }
  {
    source_attempt_ref: parent.retry_intent_ref,
    source_attempt_ordinal: parent.attempt_ordinal,
    next_retry_ordinal: parent.retry_ordinal + 1L,
  }
}

///|
pub fn prepare_recovery_retry_candidate_v3(
  current : CurrentGovernedRecoveryProjectionV3,
  source : RecoverySettlementSourceV3,
  requested_work : @contracts.WireEnvelope,
  retry_intent_id : String,
  schedule_id : String,
  intent_event_id : String,
  schedule_event_id : String,
  outbox_intent_id : String,
  command_idempotency_key : String,
  external_idempotency_key : String,
  created_at : Int64,
) -> RecoveryRetryCandidateV3 raise OrchestrationError {
  if current.current.work.work_terminal is Some(_) ||
    current.current.work.cancellation is Some(_) {
    raise CancellationPrecedenceViolation(field="recovery_retry_v3_cancelled")
  }
  source.validate_current_v3(current)
  if source.kind != RecoverySettlementConfirmedNotAppliedV3 {
    raise RetryClassificationViolation(field="recovery_retry_v3_source")
  }
  guard current.current_claim(source.intent_ref) is Some(claim) else {
    raise RecoveryViolation(field="recovery_retry_v3_claim")
  }
  guard current.effect_retry_policy_for_v3(source.intent_ref) is Some(binding) else {
    raise PolicyMismatch(field="effect_retry_policy_bound_v3_missing")
  }
  if binding.dispatch_claim_ref != claim.claim_ref ||
    binding.dispatch_claim_digest != claim.digest ||
    binding.activation_ref != claim.activation_ref ||
    binding.activation_digest != claim.activation_digest {
    raise ReplayBindingViolation(field="effect_retry_policy_bound_v3_source")
  }
  require_text(retry_intent_id, "recovery_retry_v3_intent_id")
  require_text(schedule_id, "recovery_retry_v3_schedule_id")
  require_text(intent_event_id, "recovery_retry_v3_intent_event")
  require_text(schedule_event_id, "recovery_retry_v3_schedule_event")
  require_text(outbox_intent_id, "recovery_retry_v3_outbox")
  require_text(command_idempotency_key, "recovery_retry_v3_command")
  require_text(external_idempotency_key, "recovery_retry_v3_external_key")
  if requested_work.subject() != claim.governed_subject ||
    external_idempotency_key == claim.external_idempotency_key {
    raise RetryIdentityReuse(field="recovery_retry_v3_identity")
  }
  if current.work_replay
    .intents()
    .any(outbox => outbox.idempotency_key() == external_idempotency_key) {
    raise RetryIdentityReuse(field="recovery_retry_v3_external_key")
  }
  for event in current.work_replay.events() {
    if event.payload().envelope_kind() == recovery_retry_scheduled_event_kind_v3 {
      let prior = decode_recovery_retry_scheduled_v3(event.payload().payload())
      if recovery_retry_event_consumption_v3(event, current.work_replay) != 1 {
        raise ReplayBindingViolation(field="recovery_retry_v3_transaction")
      }
      if prior.retry_intent.source_settlement_ref == source.source_ref {
        raise RetryIdentityReuse(field="recovery_retry_v3_settlement_reused")
      }
    }
  }
  let source_attempt = current.recovery_retry_source_attempt_v3(claim)
  let retry_ordinal = source_attempt.next_retry_ordinal
  let attempt_ordinal = source_attempt.source_attempt_ordinal + 1L
  let policy = binding.policy
  if retry_ordinal > policy.maximum_effect_retries ||
    attempt_ordinal > policy.maximum_effect_attempts {
    raise RetryBoundViolation(field="recovery_retry_v3_exhausted")
  }
  let material = @utf8.encode(
    "\{policy.seed.text()}:\{source.source_ref.id()}:\{retry_ordinal}",
  )
  let due_at = match
    @decision.recovery_due_at(
      source.settled_at,
      policy.base_delay,
      policy.maximum_delay,
      policy.backoff_numerator,
      policy.backoff_denominator,
      retry_ordinal,
      policy.jitter_range,
      material,
    ) {
    @decision.RecoveryDueAt(value) => value
    _ => raise ArithmeticOverflow(field="recovery_retry_v3_due_at")
  }
  let deadline = match
    @decision.recovery_deadline(source.settled_at, policy.maximum_elapsed) {
    @decision.RecoveryDueAt(value) => value
    _ => raise ArithmeticOverflow(field="recovery_retry_v3_deadline")
  }
  if created_at < source.settled_at || created_at > due_at || due_at > deadline {
    raise AuthorityExpired(expires_at=deadline, observed_at=due_at)
  }
  let intent_canonical = recovery_retry_intent_signing_bytes_v3(
    retry_intent_id,
    current,
    source,
    claim,
    binding,
    source_attempt.source_attempt_ref,
    retry_ordinal,
    attempt_ordinal,
    requested_work,
    external_idempotency_key,
    due_at,
    deadline,
    created_at,
  )
  let intent_digest = @contracts.sha256_digest(intent_canonical)
  let retry_intent : RecoveryRetryIntentV3 = {
    retry_intent_ref: self_ref_v3(
      "orchestration-recovery-retry-intent-v3", retry_intent_id, intent_digest,
    ),
    workflow: claim.workflow,
    governed_subject: claim.governed_subject,
    source_settlement_ref: source.source_ref,
    source_settlement_digest: source.digest,
    source_settlement_bytes: source.canonical,
    source_intent_ref: source.intent_ref,
    source_attempt_ref: source_attempt.source_attempt_ref,
    source_dispatch_claim_ref: claim.claim_ref,
    policy_binding_ref: binding.binding_ref,
    policy_binding_digest: binding.digest,
    policy_ref: policy.policy_ref,
    policy_digest: policy.digest,
    retry_ordinal,
    attempt_ordinal,
    requested_work,
    external_idempotency_key,
    capability_ref: claim.capability_ref,
    capability_kind: claim.capability_kind,
    due_at,
    deadline,
    created_at,
    expected_work_revision: current.current.work_revision,
    expected_work_head_digest: current.current.work_head_digest,
    expected_work_replay_digest: current.current.work_replay_digest,
    evidence: claim.evidence,
    canonical: intent_canonical,
    digest: intent_digest,
  }
  let schedule_canonical = recovery_retry_schedule_signing_bytes_v3(
    schedule_id, retry_intent, intent_event_id, schedule_event_id, outbox_intent_id,
    command_idempotency_key,
  )
  let schedule_digest = @contracts.sha256_digest(schedule_canonical)
  let schedule : RecoveryRetryScheduledV3 = {
    schedule_ref: self_ref_v3(
      "orchestration-recovery-retry-schedule-v3", schedule_id, schedule_digest,
    ),
    retry_intent,
    intent_event_id,
    schedule_event_id,
    outbox_intent_id,
    command_idempotency_key,
    canonical: schedule_canonical,
    digest: schedule_digest,
  }
  let intent_event = recovery_retry_event_v3(retry_intent, intent_event_id)
  let schedule_event = recovery_retry_schedule_event_v3(schedule, intent_event)
  let outbox = @storage.OutboxIntent::new(
    orchestration_record_version,
    orchestration_schema_version,
    outbox_intent_id,
    retry_intent.workflow,
    intent_event.event_ref(),
    external_idempotency_key,
    requested_work,
    [
      for value in retry_intent.evidence => value
    ],
  ) catch {
    _ => raise MalformedInput(field="recovery_retry_outbox_v3")
  }
  let request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    retry_intent.workflow,
    retry_intent.expected_work_revision,
    command_idempotency_key,
    [intent_event, schedule_event],
    [outbox],
  ) catch {
    _ => raise MalformedInput(field="recovery_retry_commit_request_v3")
  }
  let guards : Array[@storage.WorkflowHeadGuard] = [
    @storage.WorkflowHeadGuard::new(
      current.governance_replay.workflow(),
      current.current.governance_revision,
      current.current.governance_head_digest,
      current.current.governance_replay_digest,
    ) catch {
      _ => raise MalformedInput(field="recovery_retry_governance_guard_v3")
    },
  ]
  match source.recovery_evidence_head {
    None => ()
    Some(head) =>
      guards.push(
        @storage.WorkflowHeadGuard::new(
          head.evidence_workflow,
          head.revision,
          head.head_digest,
          head.replay_digest,
        ) catch {
          _ => raise MalformedInput(field="recovery_retry_evidence_guard_v3")
        },
      )
  }
  let guarded = @storage.GuardedCommitRequest::new(request, guards) catch {
    _ => raise MalformedInput(field="recovery_retry_guarded_request_v3")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/RECOVERY-RETRY-CANDIDATE-V3/3.0.0")
  writer.string("3.0.0")
  writer.bytes(schedule.canonical)
  writer.bytes(outbox.canonical_bytes())
  writer.bytes(guarded.canonical_bytes())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    candidate_ref: self_ref_v3(
      "orchestration-recovery-retry-candidate-v3", command_idempotency_key, digest,
    ),
    retry_intent,
    schedule,
    outbox,
    guarded_request: guarded,
    canonical,
    digest,
  }
}

///|
pub(all) enum RecoveryRetryCommitResultV3 {
  RecoveryRetryFreshV3
  RecoveryRetryAlreadyCommittedV3
  RecoveryRetryRaceLostV3
  RecoveryRetryStaleGovernanceV3
} derive(Eq, Debug)

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] commit_recovery_retry_v3(
  store : S,
  candidate : RecoveryRetryCandidateV3,
) -> RecoveryRetryCommitResultV3 raise {
  if candidate.guarded_request.guards().length() == 2 {
    require_phase2_recovery_evidence_guard_profile_v3(
      store,
      candidate.guarded_request,
    )
  } else {
    require_phase2_governance_guard_profile_v3(store, candidate.guarded_request)
  }
  try {
    match store.classified_guarded_commit(candidate.guarded_request) {
      @storage.FreshlyApplied(_) => RecoveryRetryFreshV3
      @storage.AlreadyCommitted(_) => RecoveryRetryAlreadyCommittedV3
      @storage.GuardRejected(_) => RecoveryRetryStaleGovernanceV3
    }
  } catch {
    @storage.OptimisticRevisionConflict(..) => RecoveryRetryRaceLostV3
    error => raise error
  }
}

///|
pub fn RecoveryRetryIntentV3::record_ref(
  self : RecoveryRetryIntentV3,
) -> @contracts.RecordRef {
  self.retry_intent_ref
}

///|
pub fn RecoveryRetryIntentV3::source_intent_ref(
  self : RecoveryRetryIntentV3,
) -> @contracts.RecordRef {
  self.source_intent_ref
}

///|
pub fn RecoveryRetryIntentV3::retry_ordinal(
  self : RecoveryRetryIntentV3,
) -> Int64 {
  self.retry_ordinal
}

///|
pub fn RecoveryRetryIntentV3::attempt_ordinal(
  self : RecoveryRetryIntentV3,
) -> Int64 {
  self.attempt_ordinal
}

///|
pub fn RecoveryRetryIntentV3::due_at(self : RecoveryRetryIntentV3) -> Int64 {
  self.due_at
}

///|
pub fn RecoveryRetryIntentV3::deadline(self : RecoveryRetryIntentV3) -> Int64 {
  self.deadline
}

///|
pub fn RecoveryRetryIntentV3::external_idempotency_key(
  self : RecoveryRetryIntentV3,
) -> String {
  self.external_idempotency_key
}

///|
pub fn RecoveryRetryIntentV3::requested_work(
  self : RecoveryRetryIntentV3,
) -> @contracts.WireEnvelope {
  self.requested_work
}

///|
pub fn RecoveryRetryIntentV3::canonical_bytes(
  self : RecoveryRetryIntentV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryRetryIntentV3::digest(
  self : RecoveryRetryIntentV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn RecoveryRetryScheduledV3::record_ref(
  self : RecoveryRetryScheduledV3,
) -> @contracts.RecordRef {
  self.schedule_ref
}

///|
pub fn RecoveryRetryScheduledV3::due_at(
  self : RecoveryRetryScheduledV3,
) -> Int64 {
  self.retry_intent.due_at
}

///|
pub fn RecoveryRetryScheduledV3::canonical_bytes(
  self : RecoveryRetryScheduledV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryRetryScheduledV3::digest(
  self : RecoveryRetryScheduledV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn RecoveryRetryCandidateV3::record_ref(
  self : RecoveryRetryCandidateV3,
) -> @contracts.RecordRef {
  self.candidate_ref
}

///|
pub fn RecoveryRetryCandidateV3::intent(
  self : RecoveryRetryCandidateV3,
) -> RecoveryRetryIntentV3 {
  self.retry_intent
}

///|
pub fn RecoveryRetryCandidateV3::schedule(
  self : RecoveryRetryCandidateV3,
) -> RecoveryRetryScheduledV3 {
  self.schedule
}

///|
pub fn RecoveryRetryCandidateV3::canonical_bytes(
  self : RecoveryRetryCandidateV3,
) -> Bytes {
  self.canonical
}

///|
pub fn RecoveryRetryCandidateV3::digest(
  self : RecoveryRetryCandidateV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Package-local fold hook for the exact two-event/one-outbox retry batch.
fn recovery_retry_event_consumption_v3(
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Int raise OrchestrationError {
  let kind = event.payload().envelope_kind()
  if kind != effect_retry_policy_bound_event_kind_v3 &&
    kind != recovery_retry_intent_event_kind_v3 &&
    kind != recovery_retry_scheduled_event_kind_v3 {
    return 0
  }
  if kind == effect_retry_policy_bound_event_kind_v3 {
    let record = decode_effect_retry_policy_bound_v3(event.payload().payload())
    let batches = replay
      .committed_batches()
      .filter(batch => {
        batch.event_refs().length() == 1 &&
        batch.event_refs()[0] == event.event_ref() &&
        batch.intent_refs().is_empty() &&
        batch.expected_revision() == record.expected_work_revision &&
        batch.command_idempotency_key() == record.command_idempotency_key &&
        batch.guards().length() == 1
      })
    if batches.length() != 1 ||
      event.workflow() != record.workflow ||
      event.event_ref().id() != record.event_id ||
      event.revision() != record.expected_work_revision + 1L ||
      event.previous_event_digest() != Some(record.expected_work_head_digest) {
      raise ReplayBindingViolation(
        field="effect_retry_policy_bound_v3_transaction",
      )
    }
    return 1
  }
  let batches = replay
    .committed_batches()
    .filter(batch => {
      let refs = batch.event_refs()
      refs.length() == 2 &&
      batch.intent_refs().length() == 1 &&
      (refs[0] == event.event_ref() || refs[1] == event.event_ref())
    })
  if batches.length() != 1 ||
    (batches[0].guards().length() != 1 && batches[0].guards().length() != 2) {
    raise ReplayBindingViolation(field="recovery_retry_v3_transaction")
  }
  let boundary = batches[0]
  guard first(replay.events(), value => {
      value.event_ref() == boundary.event_refs()[0]
    })
    is Some(intent_event) else {
    raise ReplayBindingViolation(field="recovery_retry_v3_transaction")
  }
  guard first(replay.events(), value => {
      value.event_ref() == boundary.event_refs()[1]
    })
    is Some(schedule_event) else {
    raise ReplayBindingViolation(field="recovery_retry_v3_transaction")
  }
  let intent = decode_recovery_retry_intent_v3(intent_event.payload().payload())
  let schedule = decode_recovery_retry_scheduled_v3(
    schedule_event.payload().payload(),
  )
  guard first(replay.intents(), value => {
      value.intent_ref() == boundary.intent_refs()[0]
    })
    is Some(outbox) else {
    raise ReplayBindingViolation(field="recovery_retry_v3_outbox")
  }
  if schedule.retry_intent.retry_intent_ref != intent.retry_intent_ref ||
    schedule.retry_intent.digest != intent.digest ||
    schedule.intent_event_id != intent_event.event_ref().id() ||
    schedule.schedule_event_id != schedule_event.event_ref().id() ||
    schedule.outbox_intent_id != outbox.intent_ref().id() ||
    schedule.command_idempotency_key != boundary.command_idempotency_key() ||
    boundary.expected_revision() != intent.expected_work_revision ||
    intent_event.revision() != intent.expected_work_revision + 1L ||
    schedule_event.revision() != intent_event.revision() + 1L ||
    schedule_event.previous_event_digest() !=
    Some(intent_event.event_ref().digest()) ||
    outbox.workflow() != intent.workflow ||
    outbox.causative_event() != intent_event.event_ref() ||
    outbox.idempotency_key() != intent.external_idempotency_key ||
    outbox.payload() != intent.requested_work ||
    !same_evidence(outbox.evidence(), intent.evidence) {
    raise ReplayBindingViolation(field="recovery_retry_v3_transaction")
  }
  if replay
    .intents()
    .filter(value => value.idempotency_key() == intent.external_idempotency_key)
    .length() !=
    1 {
    raise RetryIdentityReuse(field="recovery_retry_v3_external_key")
  }
  let source_claims : Array[DispatchClaimRecordV3] = []
  let policy_bindings : Array[EffectRetryPolicyBoundV3] = []
  let parent_retries : Array[RecoveryRetryIntentV3] = []
  let mut direct_prior_retries = 0L
  let mut settlement_uses = 0
  let mut retry_intent_uses = 0
  for prior_event in replay.events() {
    let prior_kind = prior_event.payload().envelope_kind()
    if prior_kind == dispatch_claim_event_kind_v3 &&
      prior_event.revision() < intent_event.revision() {
      let prior_claim = decode_dispatch_claim_record_v3(
        prior_event.payload().payload(),
      )
      if prior_claim.claim_ref == intent.source_dispatch_claim_ref {
        source_claims.push(prior_claim)
      }
    } else if prior_kind == effect_retry_policy_bound_event_kind_v3 &&
      prior_event.revision() < intent_event.revision() {
      let prior_binding = decode_effect_retry_policy_bound_v3(
        prior_event.payload().payload(),
      )
      if prior_binding.binding_ref == intent.policy_binding_ref {
        policy_bindings.push(prior_binding)
      }
    } else if prior_kind == recovery_retry_scheduled_event_kind_v3 {
      let prior_schedule = decode_recovery_retry_scheduled_v3(
        prior_event.payload().payload(),
      )
      let prior_retry = prior_schedule.retry_intent
      if prior_retry.retry_intent_ref == intent.retry_intent_ref {
        retry_intent_uses = retry_intent_uses + 1
      }
      if prior_retry.source_settlement_ref == intent.source_settlement_ref {
        settlement_uses = settlement_uses + 1
      }
      if prior_event.revision() < intent_event.revision() {
        if prior_retry.retry_intent_ref == intent.source_attempt_ref {
          parent_retries.push(prior_retry)
        }
        if prior_retry.source_intent_ref == intent.source_intent_ref {
          direct_prior_retries = direct_prior_retries + 1L
        }
      }
    }
  }
  if source_claims.length() != 1 ||
    policy_bindings.length() != 1 ||
    retry_intent_uses != 1 ||
    settlement_uses != 1 ||
    parent_retries.length() > 1 {
    raise ReplayBindingViolation(field="recovery_retry_v3_lineage")
  }
  let source_claim = source_claims[0]
  let policy_binding = policy_bindings[0]
  if source_claim.intent_ref != intent.source_intent_ref ||
    source_claim.attempt_ref != intent.source_attempt_ref ||
    source_claim.governed_subject != intent.governed_subject ||
    source_claim.capability_ref != intent.capability_ref ||
    source_claim.capability_kind != intent.capability_kind ||
    policy_binding.source_intent_ref != intent.source_intent_ref ||
    policy_binding.dispatch_claim_ref != source_claim.claim_ref ||
    policy_binding.binding_ref.digest() != intent.policy_binding_digest ||
    policy_binding.digest != intent.policy_binding_digest ||
    policy_binding.policy.policy_ref != intent.policy_ref ||
    policy_binding.policy.digest != intent.policy_digest ||
    intent.retry_ordinal > policy_binding.policy.maximum_effect_retries ||
    intent.attempt_ordinal > policy_binding.policy.maximum_effect_attempts {
    raise ReplayBindingViolation(field="recovery_retry_v3_lineage")
  }
  match parent_retries {
    [] =>
      if intent.retry_ordinal != direct_prior_retries + 1L {
        raise ReplayBindingViolation(field="recovery_retry_v3_ordinal")
      }
    [parent] =>
      if intent.source_intent_ref != parent.retry_intent_ref ||
        intent.source_attempt_ref != parent.retry_intent_ref ||
        intent.retry_ordinal != parent.retry_ordinal + 1L ||
        intent.attempt_ordinal != parent.attempt_ordinal + 1L {
        raise ReplayBindingViolation(field="recovery_retry_v3_ordinal")
      }
    _ => raise ReplayBindingViolation(field="recovery_retry_v3_lineage")
  }
  1
}
