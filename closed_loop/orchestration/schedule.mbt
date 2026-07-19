///|
/// An immutable schedule for one already-authoritative FLOW-6 effect intent.
/// Registration never creates governance, an attempt, intent, or eligibility.
pub struct ScheduleIntent {
  record_version : @contracts.Version
  schedule_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  policy_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  governance_binding : @effects.GovernanceBinding
  governance_digest : @contracts.ContentDigest
  effect_intent : @effects.EffectIntent
  effect_intent_digest : @contracts.ContentDigest
  not_before : Int64
  deadline : Int64?
  retry_policy_ref : @contracts.RecordRef?
  retry_policy_digest : @contracts.ContentDigest?
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation_ref : @contracts.RecordRef
  previous_digest : @contracts.ContentDigest?
  idempotency_key : String
  canonical : Bytes
}

///|
pub fn ScheduleIntent::new(
  schedule_id : String,
  schedule_version : String,
  workflow : @contracts.RecordRef,
  policy_ref : @contracts.RecordRef,
  governed_subject : @contracts.RecordRef,
  governance_binding : @effects.GovernanceBinding,
  effect_intent : @effects.EffectIntent,
  effects_projection : @effects.EffectsProjection,
  not_before : Int64,
  deadline : Int64?,
  evidence : Array[@contracts.EvidenceRef],
  causation_ref : @contracts.RecordRef,
  idempotency_key : String,
  previous_digest? : @contracts.ContentDigest,
  retry_policy? : RetryPolicy,
) -> ScheduleIntent raise {
  require_version(schedule_version, "schedule_intent")
  require_text(schedule_id, "schedule_id")
  require_text(idempotency_key, "schedule_idempotency_key")
  require_non_negative(not_before, "not_before")
  match deadline {
    Some(value) => {
      require_non_negative(value, "deadline")
      if value < not_before {
        raise ScheduleStateViolation(field="deadline_before_not_before")
      }
    }
    None => ()
  }
  if effects_projection.workflow() != workflow ||
    effect_intent.workflow() != workflow ||
    governance_binding.workflow() != workflow {
    raise WorkflowMismatch(field="schedule_workflow")
  }
  if governance_binding.policy_ref() != policy_ref ||
    effect_intent.governance().policy_ref() != policy_ref {
    raise PolicyMismatch(field="schedule_policy")
  }
  if governance_binding.governed_subject() != governed_subject ||
    effect_intent.governance().governed_subject() != governed_subject ||
    effect_intent.governance().binding_digest() !=
    governance_binding.binding_digest() {
    raise GovernanceMismatch(field="schedule_governance_binding")
  }
  if !effects_projection.intents().any(value => value == effect_intent) {
    raise EffectProofMismatch(field="durable_dispatch_eligible_intent")
  }
  let replay_state = effects_projection.state_for(effect_intent.intent_ref()) catch {
    _ => raise EffectProofMismatch(field="durable_dispatch_eligible_intent")
  }
  if replay_state != @effects.DurableIntentDispatchEligible {
    raise EffectProofMismatch(field="durable_dispatch_eligible_intent")
  }
  match governance_binding.authority_expires_at() {
    Some(expires_at) if expires_at < not_before =>
      raise AuthorityExpired(expires_at~, observed_at=not_before)
    _ => ()
  }
  let snapshot = evidence.copy()
  let writer = OrchestrationWriter::new()
  writer.bytes(b"MF7ASCHED1")
  writer.string(schedule_version)
  writer.string(schedule_id)
  write_ref(writer, workflow)
  write_ref(writer, policy_ref)
  write_ref(writer, governed_subject)
  writer.bytes(governance_binding.canonical_bytes())
  writer.string(governance_binding.binding_digest().text())
  writer.bytes(effect_intent.canonical_bytes())
  writer.string(effect_intent.binding_digest().text())
  writer.int64(not_before)
  writer.optional_int64(deadline)
  match retry_policy {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value.policy_ref())
      writer.string(value.binding_digest().text())
    }
  }
  write_evidence(writer, snapshot)
  write_ref(writer, causation_ref)
  writer.optional_digest(previous_digest)
  writer.string(idempotency_key)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_version: orchestration_version(),
    schedule_ref: self_ref("orchestration-schedule", schedule_id, digest),
    workflow,
    policy_ref,
    governed_subject,
    governance_binding,
    governance_digest: governance_binding.binding_digest(),
    effect_intent,
    effect_intent_digest: effect_intent.binding_digest(),
    not_before,
    deadline,
    retry_policy_ref: retry_policy.map(value => value.policy_ref()),
    retry_policy_digest: retry_policy.map(value => value.binding_digest()),
    evidence: ReadOnlyArray::from_array(snapshot),
    causation_ref,
    previous_digest,
    idempotency_key,
    canonical,
  }
}

///|
pub fn ScheduleIntent::schedule_ref(
  self : ScheduleIntent,
) -> @contracts.RecordRef {
  self.schedule_ref
}

///|
pub fn ScheduleIntent::workflow(self : ScheduleIntent) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn ScheduleIntent::policy_ref(
  self : ScheduleIntent,
) -> @contracts.RecordRef {
  self.policy_ref
}

///|
pub fn ScheduleIntent::governed_subject(
  self : ScheduleIntent,
) -> @contracts.RecordRef {
  self.governed_subject
}

///|
pub fn ScheduleIntent::governance_binding(
  self : ScheduleIntent,
) -> @effects.GovernanceBinding {
  self.governance_binding
}

///|
pub fn ScheduleIntent::effect_intent(
  self : ScheduleIntent,
) -> @effects.EffectIntent {
  self.effect_intent
}

///|
pub fn ScheduleIntent::not_before(self : ScheduleIntent) -> Int64 {
  self.not_before
}

///|
pub fn ScheduleIntent::deadline(self : ScheduleIntent) -> Int64? {
  self.deadline
}

///|
pub fn ScheduleIntent::retry_policy_ref(
  self : ScheduleIntent,
) -> @contracts.RecordRef? {
  self.retry_policy_ref
}

///|
pub fn ScheduleIntent::evidence(
  self : ScheduleIntent,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn ScheduleIntent::causation_ref(
  self : ScheduleIntent,
) -> @contracts.RecordRef {
  self.causation_ref
}

///|
pub fn ScheduleIntent::previous_digest(
  self : ScheduleIntent,
) -> @contracts.ContentDigest? {
  self.previous_digest
}

///|
pub fn ScheduleIntent::idempotency_key(self : ScheduleIntent) -> String {
  self.idempotency_key
}

///|
pub fn ScheduleIntent::canonical_bytes(self : ScheduleIntent) -> Bytes {
  self.canonical
}

///|
pub fn ScheduleIntent::binding_digest(
  self : ScheduleIntent,
) -> @contracts.ContentDigest {
  self.schedule_ref.digest()
}

///|
pub impl Eq for ScheduleIntent with fn equal(left, right) {
  left.canonical_bytes() == right.canonical_bytes()
}

///|
/// Frozen scheduler state vocabulary. Effect facts remain explicitly distinct.
pub(all) enum ScheduleState {
  ScheduleAbsent
  RegisteredWaiting
  DueUnclaimed
  BlockedGovernance
  BlockedDeadline
  ClaimedRunning
  LeaseExpiredReclaimable
  EffectObservationPending
  KnownEffectSuccess
  KnownEffectFailure
  UnknownOutcomeRequiresReconciliation
  ReconciliationRequested
  ReconciledSuccess
  ReconciledFailure
  ReconciledNotAppliedRetryEligible
  CancelledBeforeWork
  CancellationRequestedOutcomeUnresolved
  Terminal
} derive(Eq, Debug)

///|
pub struct DueProof {
  record_version : @contracts.Version
  schedule_ref : @contracts.RecordRef
  schedule_digest : @contracts.ContentDigest
  workflow : @contracts.RecordRef
  clock_ref : @contracts.RecordRef
  replay_digest : @contracts.ContentDigest
  fencing_floor : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn due_proof(
  schedule : ScheduleIntent,
  clock : ClockInput,
  replay_digest : @contracts.ContentDigest,
  fencing_floor : Int64,
) -> DueProof {
  let writer = OrchestrationWriter::new()
  try! writer.bytes(b"MF7ADUEP1")
  try! write_ref(writer, schedule.schedule_ref())
  try! write_ref(writer, schedule.workflow())
  try! write_ref(writer, clock.clock_ref())
  try! writer.string(replay_digest.text())
  writer.int64(fencing_floor)
  let canonical = writer.finish()
  {
    record_version: orchestration_version(),
    schedule_ref: schedule.schedule_ref(),
    schedule_digest: schedule.binding_digest(),
    workflow: schedule.workflow(),
    clock_ref: clock.clock_ref(),
    replay_digest,
    fencing_floor,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn DueProof::schedule_ref(self : DueProof) -> @contracts.RecordRef {
  self.schedule_ref
}

///|
pub fn DueProof::clock_ref(self : DueProof) -> @contracts.RecordRef {
  self.clock_ref
}

///|
pub fn DueProof::replay_digest(self : DueProof) -> @contracts.ContentDigest {
  self.replay_digest
}

///|
pub fn DueProof::fencing_floor(self : DueProof) -> Int64 {
  self.fencing_floor
}

///|
pub fn DueProof::canonical_bytes(self : DueProof) -> Bytes {
  self.canonical
}

///|
pub fn DueProof::binding_digest(self : DueProof) -> @contracts.ContentDigest {
  self.digest
}
