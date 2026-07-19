///|
/// An immutable proposal/link between exact FLOW-6 identities. It cannot create
/// either attempt or intent and requires both to exist in authoritative replay.
pub struct RetryLink {
  record_version : @contracts.Version
  retry_ref : @contracts.RecordRef
  schedule_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  prior_intent_ref : @contracts.RecordRef
  new_intent_ref : @contracts.RecordRef
  prior_attempt_ref : @contracts.RecordRef
  new_attempt_ref : @contracts.RecordRef
  prior_attempt_ordinal : Int64
  new_attempt_ordinal : Int64
  decision : RetryabilityDecision
  policy_ref : @contracts.RecordRef
  policy_digest : @contracts.ContentDigest
  timing : RetryTiming
  clock : ClockInput
  idempotency_key : String
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation_ref : @contracts.RecordRef
  previous_digest : @contracts.ContentDigest
  canonical : Bytes
}

///|
fn write_retry_decision(
  writer : OrchestrationWriter,
  decision : RetryabilityDecision,
) -> Unit raise OrchestrationError {
  match decision {
    KnownFailureClass(value) => {
      writer.byte(1)
      writer.string(value)
    }
    ReconciledNotApplied => writer.byte(2)
    UnknownOutcome => writer.byte(3)
    MissingReceipt => writer.byte(4)
    ObservationTimeout => writer.byte(5)
    ProcessCrash => writer.byte(6)
    LeaseExpired => writer.byte(7)
    ElapsedTimeOnly => writer.byte(8)
  }
}

///|
pub fn RetryLink::new(
  retry_id : String,
  retry_version : String,
  schedule : ScheduleIntent,
  prior_intent : @effects.EffectIntent,
  new_intent : @effects.EffectIntent,
  effects_projection : @effects.EffectsProjection,
  policy : RetryPolicy,
  decision : RetryabilityDecision,
  prior_retry_count : Int64,
  clock : ClockInput,
  idempotency_key : String,
  evidence : Array[@contracts.EvidenceRef],
  causation_ref : @contracts.RecordRef,
  previous_digest : @contracts.ContentDigest,
) -> RetryLink raise {
  require_version(retry_version, "retry_link")
  require_text(retry_id, "retry_id")
  require_text(idempotency_key, "retry_idempotency_key")
  if schedule.workflow() != clock.workflow() ||
    schedule.workflow() != prior_intent.workflow() ||
    schedule.workflow() != new_intent.workflow() ||
    schedule.workflow() != effects_projection.workflow() {
    raise WorkflowMismatch(field="retry_workflow")
  }
  if schedule.retry_policy_ref() != Some(policy.policy_ref()) {
    raise PolicyMismatch(field="retry_policy")
  }
  if !effects_projection.intents().any(value => value == prior_intent) ||
    !effects_projection.intents().any(value => value == new_intent) {
    raise EffectProofMismatch(field="retry_intent_replay")
  }
  let new_intent_state = effects_projection.state_for(new_intent.intent_ref()) catch {
    _ => raise EffectProofMismatch(field="retry_intent_replay")
  }
  if new_intent_state != @effects.DurableIntentDispatchEligible {
    raise EffectProofMismatch(field="retry_intent_replay")
  }
  if prior_intent.intent_ref() == new_intent.intent_ref() ||
    prior_intent.attempt_ref() == new_intent.attempt_ref() ||
    prior_intent.external_idempotency_key() ==
    new_intent.external_idempotency_key() {
    raise RetryIdentityReuse(field="effect_attempt_or_idempotency")
  }
  match (prior_intent.fencing(), new_intent.fencing()) {
    (Some(prior), Some(next)) if prior.fence_ref() == next.fence_ref() &&
      (
        next.lease_epoch() <= prior.lease_epoch() ||
        next.fencing_token() <= prior.fencing_token()
      ) => raise RetryIdentityReuse(field="stale_fencing")
    (Some(_), None) => raise RetryIdentityReuse(field="missing_new_fencing")
    _ => ()
  }
  guard first(effects_projection.attempts(), value => {
      value.attempt_ref() == prior_intent.attempt_ref()
    })
    is Some(prior_attempt) else {
    raise EffectProofMismatch(field="prior_attempt")
  }
  guard first(effects_projection.attempts(), value => {
      value.attempt_ref() == new_intent.attempt_ref()
    })
    is Some(new_attempt) else {
    raise EffectProofMismatch(field="new_attempt")
  }
  if new_attempt.attempt_ordinal() != prior_attempt.attempt_ordinal() + 1L ||
    new_attempt.retry_of_intent_ref() != Some(prior_intent.intent_ref()) {
    raise OrderingViolation(field="retry_attempt_link")
  }
  let prior_state = effects_projection.state_for(prior_intent.intent_ref())
  match (prior_state, decision) {
    (ReconciledNotAppliedRetryEligible, ReconciledNotApplied) => ()
    (KnownFailure, KnownFailureClass(_)) => {
      // FLOW-6 currently exposes retry_eligible only for reconciled not-applied.
      // Therefore a known-failure policy decision is recordable timing evidence,
      // but cannot become a linked retry through this constructor.
      if !policy.allows(decision) {
        raise RetryClassificationViolation(field="known_failure_class")
      }
      raise EffectProofMismatch(field="flow6_retry_eligibility")
    }
    _ => raise RetryClassificationViolation(field="effect_state")
  }
  if !effects_projection.retry_eligible(prior_intent.intent_ref()) ||
    !policy.allows(decision) {
    raise RetryClassificationViolation(field="retry_not_eligible")
  }
  let timing = RetryTiming::compute(
    policy,
    schedule.schedule_ref(),
    prior_attempt.attempt_ordinal(),
    prior_retry_count,
    clock,
  )
  let snapshot = evidence.copy()
  let writer = OrchestrationWriter::new()
  writer.bytes(b"MF7ARETRYLINK1")
  writer.string(retry_version)
  writer.string(retry_id)
  write_ref(writer, schedule.schedule_ref())
  write_ref(writer, schedule.workflow())
  write_ref(writer, prior_intent.intent_ref())
  write_ref(writer, new_intent.intent_ref())
  write_ref(writer, prior_intent.attempt_ref())
  write_ref(writer, new_intent.attempt_ref())
  writer.int64(prior_attempt.attempt_ordinal())
  writer.int64(new_attempt.attempt_ordinal())
  write_retry_decision(writer, decision)
  write_ref(writer, policy.policy_ref())
  writer.string(policy.binding_digest().text())
  writer.bytes(timing.canonical_bytes())
  writer.bytes(clock.canonical_bytes())
  writer.string(idempotency_key)
  write_evidence(writer, snapshot)
  write_ref(writer, causation_ref)
  writer.string(previous_digest.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_version: orchestration_version(),
    retry_ref: self_ref("orchestration-retry-link", retry_id, digest),
    schedule_ref: schedule.schedule_ref(),
    workflow: schedule.workflow(),
    prior_intent_ref: prior_intent.intent_ref(),
    new_intent_ref: new_intent.intent_ref(),
    prior_attempt_ref: prior_intent.attempt_ref(),
    new_attempt_ref: new_intent.attempt_ref(),
    prior_attempt_ordinal: prior_attempt.attempt_ordinal(),
    new_attempt_ordinal: new_attempt.attempt_ordinal(),
    decision,
    policy_ref: policy.policy_ref(),
    policy_digest: policy.binding_digest(),
    timing,
    clock,
    idempotency_key,
    evidence: ReadOnlyArray::from_array(snapshot),
    causation_ref,
    previous_digest,
    canonical,
  }
}

///|
pub fn RetryLink::retry_ref(self : RetryLink) -> @contracts.RecordRef {
  self.retry_ref
}

///|
pub fn RetryLink::prior_intent_ref(self : RetryLink) -> @contracts.RecordRef {
  self.prior_intent_ref
}

///|
pub fn RetryLink::new_intent_ref(self : RetryLink) -> @contracts.RecordRef {
  self.new_intent_ref
}

///|
pub fn RetryLink::timing(self : RetryLink) -> RetryTiming {
  self.timing
}

///|
pub fn RetryLink::canonical_bytes(self : RetryLink) -> Bytes {
  self.canonical
}

///|
pub fn RetryLink::binding_digest(self : RetryLink) -> @contracts.ContentDigest {
  self.retry_ref.digest()
}
