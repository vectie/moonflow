///|
/// Closed external-application result used by the recovery protocol. `StillUnknownV3`
/// is deliberately nonterminal and must never be interpreted as a failure.
pub(all) enum ExternalRecoveryOutcomeV3 {
  RecoveryKnownSucceededV3
  RecoveryKnownFailedV3
  RecoveryConfirmedNotAppliedV3
  RecoveryStillUnknownV3
} derive(Eq, Debug)

///|
/// Domain-neutral recovery states. The complete vocabulary is frozen before
/// provider dispatch is added so later slices can only move through reviewed
/// transitions instead of inventing ad-hoc retry states.
pub(all) enum EffectRecoveryStateV3 {
  RecoveryDispatchEligibleV3
  RecoveryDispatchClaimedV3
  RecoveryDispatchAttemptedV3
  RecoveryKnownSuccessV3
  RecoveryKnownFailureV3
  RecoveryUnknownRequiresReconciliationV3
  RecoveryReconciliationClaimedV3
  RecoveryReconciledSuccessV3
  RecoveryReconciledFailureV3
  RecoveryConfirmedNotAppliedRetryEligibleV3
  RecoveryBackoffPendingV3
  RecoveryExhaustedV3
  RecoveryManualInterventionV3
} derive(Eq, Debug)

///|
fn ExternalRecoveryOutcomeV3::wire(self : ExternalRecoveryOutcomeV3) -> String {
  match self {
    RecoveryKnownSucceededV3 => "known_succeeded_v3"
    RecoveryKnownFailedV3 => "known_failed_v3"
    RecoveryConfirmedNotAppliedV3 => "confirmed_not_applied_v3"
    RecoveryStillUnknownV3 => "still_unknown_v3"
  }
}

///|
/// Opaque, immutable identity and provenance for one committed durable intent.
/// Unlike `StrictRecoveryTargetV3`, this value is state-independent and grants
/// no dispatch eligibility or provider-call authority.
pub struct StrictRecoveryIntentIdentityV3 {
  intent_ref : @contracts.RecordRef
  attempt_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  outbox_ref : @contracts.RecordRef
  capability_ref : @contracts.RecordRef
  capability_kind : String
  authoritative_replay_digest : @contracts.ContentDigest
  intent_canonical : Bytes
}

///|
/// Reconstruct every committed intent identity from the authoritative strict
/// replay, regardless of its current V2 effect state. Any malformed intent or
/// outbox binding makes the entire catalog unavailable.
pub fn EffectsProjection::strict_recovery_intent_catalog_v3(
  self : EffectsProjection,
) -> ReadOnlyArray[StrictRecoveryIntentIdentityV3] raise EffectsError {
  let snapshot = self.require_strict_retry_snapshot(
    "strict_recovery_intent_catalog_requires_replay",
  )
  if snapshot.intents.length() != snapshot.matched_outbox_refs.length() {
    raise OutboxAtomicityViolation(field="strict_event_outbox_binding")
  }
  let values : Array[StrictRecoveryIntentIdentityV3] = []
  for index, intent in snapshot.intents {
    values.push({
      intent_ref: intent.intent_ref,
      attempt_ref: intent.attempt_ref,
      governed_subject: intent.governed_subject,
      outbox_ref: snapshot.matched_outbox_refs[index],
      capability_ref: intent.capability_ref,
      capability_kind: intent.capability_kind,
      authoritative_replay_digest: snapshot.replay_digest,
      intent_canonical: intent.canonical,
    })
  }
  ReadOnlyArray::from_array(values)
}

///|
pub fn StrictRecoveryIntentIdentityV3::intent_ref(
  self : StrictRecoveryIntentIdentityV3,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn StrictRecoveryIntentIdentityV3::attempt_ref(
  self : StrictRecoveryIntentIdentityV3,
) -> @contracts.RecordRef {
  self.attempt_ref
}

///|
pub fn StrictRecoveryIntentIdentityV3::governed_subject(
  self : StrictRecoveryIntentIdentityV3,
) -> @contracts.RecordRef {
  self.governed_subject
}

///|
pub fn StrictRecoveryIntentIdentityV3::outbox_ref(
  self : StrictRecoveryIntentIdentityV3,
) -> @contracts.RecordRef {
  self.outbox_ref
}

///|
pub fn StrictRecoveryIntentIdentityV3::capability_ref(
  self : StrictRecoveryIntentIdentityV3,
) -> @contracts.RecordRef {
  self.capability_ref
}

///|
pub fn StrictRecoveryIntentIdentityV3::capability_kind(
  self : StrictRecoveryIntentIdentityV3,
) -> String {
  self.capability_kind
}

///|
pub fn StrictRecoveryIntentIdentityV3::authoritative_replay_digest(
  self : StrictRecoveryIntentIdentityV3,
) -> @contracts.ContentDigest {
  self.authoritative_replay_digest
}

///|
pub fn StrictRecoveryIntentIdentityV3::intent_canonical_bytes(
  self : StrictRecoveryIntentIdentityV3,
) -> Bytes {
  self.intent_canonical
}

///|
fn EffectRecoveryStateV3::wire(self : EffectRecoveryStateV3) -> String {
  match self {
    RecoveryDispatchEligibleV3 => "dispatch_eligible_v3"
    RecoveryDispatchClaimedV3 => "dispatch_claimed_v3"
    RecoveryDispatchAttemptedV3 => "dispatch_attempted_v3"
    RecoveryKnownSuccessV3 => "known_success_v3"
    RecoveryKnownFailureV3 => "known_failure_v3"
    RecoveryUnknownRequiresReconciliationV3 =>
      "unknown_requires_reconciliation_v3"
    RecoveryReconciliationClaimedV3 => "reconciliation_claimed_v3"
    RecoveryReconciledSuccessV3 => "reconciled_success_v3"
    RecoveryReconciledFailureV3 => "reconciled_failure_v3"
    RecoveryConfirmedNotAppliedRetryEligibleV3 =>
      "confirmed_not_applied_retry_eligible_v3"
    RecoveryBackoffPendingV3 => "backoff_pending_v3"
    RecoveryExhaustedV3 => "exhausted_v3"
    RecoveryManualInterventionV3 => "manual_intervention_v3"
  }
}

///|
fn external_recovery_outcome_from_wire_v3(
  value : String,
) -> ExternalRecoveryOutcomeV3 raise EffectsError {
  match value {
    "known_succeeded_v3" => RecoveryKnownSucceededV3
    "known_failed_v3" => RecoveryKnownFailedV3
    "confirmed_not_applied_v3" => RecoveryConfirmedNotAppliedV3
    "still_unknown_v3" => RecoveryStillUnknownV3
    _ => raise MalformedRecord(field="external_recovery_outcome_v3")
  }
}

///|
fn effect_recovery_state_from_wire_v3(
  value : String,
) -> EffectRecoveryStateV3 raise EffectsError {
  match value {
    "dispatch_eligible_v3" => RecoveryDispatchEligibleV3
    "dispatch_claimed_v3" => RecoveryDispatchClaimedV3
    "dispatch_attempted_v3" => RecoveryDispatchAttemptedV3
    "known_success_v3" => RecoveryKnownSuccessV3
    "known_failure_v3" => RecoveryKnownFailureV3
    "unknown_requires_reconciliation_v3" =>
      RecoveryUnknownRequiresReconciliationV3
    "reconciliation_claimed_v3" => RecoveryReconciliationClaimedV3
    "reconciled_success_v3" => RecoveryReconciledSuccessV3
    "reconciled_failure_v3" => RecoveryReconciledFailureV3
    "confirmed_not_applied_retry_eligible_v3" =>
      RecoveryConfirmedNotAppliedRetryEligibleV3
    "backoff_pending_v3" => RecoveryBackoffPendingV3
    "exhausted_v3" => RecoveryExhaustedV3
    "manual_intervention_v3" => RecoveryManualInterventionV3
    _ => raise MalformedRecord(field="effect_recovery_state_v3")
  }
}

///|
/// Canonical stable codec for recovery outcomes. This is a fact vocabulary,
/// not permission to dispatch, reconcile, or retry.
pub fn encode_external_recovery_outcome_v3(
  value : ExternalRecoveryOutcomeV3,
) -> Bytes {
  let writer = EffectsWriter::new()
  try! writer.bytes(b"MF6/EXTERNAL-RECOVERY-OUTCOME-V3/3.0.0")
  try! writer.string("3.0.0")
  try! writer.string(value.wire())
  writer.finish()
}

///|
pub fn decode_external_recovery_outcome_v3(
  bytes : Bytes,
) -> ExternalRecoveryOutcomeV3 raise EffectsError {
  let reader = EffectsReader::new(bytes)
  if reader.read_bytes() != b"MF6/EXTERNAL-RECOVERY-OUTCOME-V3/3.0.0" {
    raise MalformedRecord(field="external_recovery_outcome_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="external_recovery_outcome_v3", version~)
  }
  let value = external_recovery_outcome_from_wire_v3(reader.read_string())
  reader.require_end()
  if encode_external_recovery_outcome_v3(value) != bytes {
    raise MalformedRecord(field="external_recovery_outcome_v3_noncanonical")
  }
  value
}

///|
/// Canonical stable codec for the recovery state machine. This codec is kept
/// separate from workflow events; only strict replay may establish currentness.
pub fn encode_effect_recovery_state_v3(value : EffectRecoveryStateV3) -> Bytes {
  let writer = EffectsWriter::new()
  try! writer.bytes(b"MF6/EFFECT-RECOVERY-STATE-V3/3.0.0")
  try! writer.string("3.0.0")
  try! writer.string(value.wire())
  writer.finish()
}

///|
pub fn decode_effect_recovery_state_v3(
  bytes : Bytes,
) -> EffectRecoveryStateV3 raise EffectsError {
  let reader = EffectsReader::new(bytes)
  if reader.read_bytes() != b"MF6/EFFECT-RECOVERY-STATE-V3/3.0.0" {
    raise MalformedRecord(field="effect_recovery_state_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="effect_recovery_state_v3", version~)
  }
  let value = effect_recovery_state_from_wire_v3(reader.read_string())
  reader.require_end()
  if encode_effect_recovery_state_v3(value) != bytes {
    raise MalformedRecord(field="effect_recovery_state_v3_noncanonical")
  }
  value
}

///|
/// Opaque, inert Phase-2 recovery target reconstructed exclusively from the
/// strict committed intent/outbox pair. It exposes the generic provider
/// operation and capability bindings needed by orchestration, but owns no
/// provider call and grants no dispatch authority.
pub struct StrictRecoveryTargetV3 {
  intent_ref : @contracts.RecordRef
  attempt_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  provider_operation : @contracts.WireEnvelope
  external_idempotency_key : String
  outbox_ref : @contracts.RecordRef
  capability_ref : @contracts.RecordRef
  capability_kind : String
  permitted_evidence : ReadOnlyArray[@contracts.EvidenceRef]
  authoritative_replay_digest : @contracts.ContentDigest
  intent_canonical : Bytes
}

///|
/// Derive the complete generic recovery target from authoritative bytes. The
/// caller cannot substitute operation, key, capability, or permitted evidence.
pub fn EffectsProjection::strict_recovery_target_v3(
  self : EffectsProjection,
  intent_ref : @contracts.RecordRef,
) -> StrictRecoveryTargetV3 raise EffectsError {
  let snapshot = self.require_strict_retry_snapshot(
    "strict_recovery_target_requires_replay",
  )
  guard snapshot.intents.search_by(value => value.intent_ref == intent_ref)
    is Some(index) else {
    raise IdentityMismatch(field="strict_unknown_intent")
  }
  if snapshot.state_for(intent_ref) != DurableIntentDispatchEligible {
    raise InvalidState(field="intent_not_dispatch_eligible")
  }
  if index >= snapshot.matched_outbox_refs.length() {
    raise OutboxAtomicityViolation(field="strict_event_outbox_binding")
  }
  let intent = snapshot.intents[index]
  {
    intent_ref: intent.intent_ref,
    attempt_ref: intent.attempt_ref,
    governed_subject: intent.governed_subject,
    provider_operation: intent.effect_request,
    external_idempotency_key: intent.external_idempotency_key,
    outbox_ref: snapshot.matched_outbox_refs[index],
    capability_ref: intent.capability_ref,
    capability_kind: intent.capability_kind,
    permitted_evidence: intent.evidence,
    authoritative_replay_digest: snapshot.replay_digest,
    intent_canonical: intent.canonical,
  }
}

///|
pub fn StrictRecoveryTargetV3::intent_ref(
  self : StrictRecoveryTargetV3,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn StrictRecoveryTargetV3::attempt_ref(
  self : StrictRecoveryTargetV3,
) -> @contracts.RecordRef {
  self.attempt_ref
}

///|
pub fn StrictRecoveryTargetV3::governed_subject(
  self : StrictRecoveryTargetV3,
) -> @contracts.RecordRef {
  self.governed_subject
}

///|
pub fn StrictRecoveryTargetV3::provider_operation(
  self : StrictRecoveryTargetV3,
) -> @contracts.WireEnvelope {
  self.provider_operation
}

///|
pub fn StrictRecoveryTargetV3::external_idempotency_key(
  self : StrictRecoveryTargetV3,
) -> String {
  self.external_idempotency_key
}

///|
pub fn StrictRecoveryTargetV3::outbox_ref(
  self : StrictRecoveryTargetV3,
) -> @contracts.RecordRef {
  self.outbox_ref
}

///|
pub fn StrictRecoveryTargetV3::capability_ref(
  self : StrictRecoveryTargetV3,
) -> @contracts.RecordRef {
  self.capability_ref
}

///|
pub fn StrictRecoveryTargetV3::capability_kind(
  self : StrictRecoveryTargetV3,
) -> String {
  self.capability_kind
}

///|
pub fn StrictRecoveryTargetV3::permitted_evidence(
  self : StrictRecoveryTargetV3,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.permitted_evidence
}

///|
pub fn StrictRecoveryTargetV3::authoritative_replay_digest(
  self : StrictRecoveryTargetV3,
) -> @contracts.ContentDigest {
  self.authoritative_replay_digest
}

///|
pub fn StrictRecoveryTargetV3::intent_canonical_bytes(
  self : StrictRecoveryTargetV3,
) -> Bytes {
  self.intent_canonical
}
