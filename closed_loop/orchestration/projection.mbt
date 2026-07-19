///|
pub struct OrchestrationCatalog {
  schedules : ReadOnlyArray[ScheduleIntent]
  clocks : ReadOnlyArray[ClockInput]
  claims : ReadOnlyArray[LeaseClaim]
  renewals : ReadOnlyArray[LeaseRenewal]
  releases : ReadOnlyArray[LeaseRelease]
  expiries : ReadOnlyArray[LeaseExpiry]
  cancellations : ReadOnlyArray[CancellationRecord]
  retries : ReadOnlyArray[RetryLink]
}

///|
pub fn OrchestrationCatalog::new(
  schedules : Array[ScheduleIntent],
  clocks : Array[ClockInput],
  claims : Array[LeaseClaim],
  renewals : Array[LeaseRenewal],
  releases : Array[LeaseRelease],
  expiries : Array[LeaseExpiry],
  cancellations : Array[CancellationRecord],
  retries : Array[RetryLink],
) -> OrchestrationCatalog {
  {
    schedules: ReadOnlyArray::from_array(schedules.copy()),
    clocks: ReadOnlyArray::from_array(clocks.copy()),
    claims: ReadOnlyArray::from_array(claims.copy()),
    renewals: ReadOnlyArray::from_array(renewals.copy()),
    releases: ReadOnlyArray::from_array(releases.copy()),
    expiries: ReadOnlyArray::from_array(expiries.copy()),
    cancellations: ReadOnlyArray::from_array(cancellations.copy()),
    retries: ReadOnlyArray::from_array(retries.copy()),
  }
}

///|
pub struct OrchestrationProjection {
  projection_version : @contracts.Version
  workflow : @contracts.RecordRef
  policy_ref : @contracts.RecordRef
  sequence : Int64
  revision : Int64
  last_event_digest : @contracts.ContentDigest?
  replay_digest : @contracts.ContentDigest?
  schedule : ScheduleIntent?
  latest_clock : ClockInput?
  state : ScheduleState
  current_claim : LeaseClaim?
  current_owner : @contracts.RecordRef?
  current_epoch : Int64
  current_fencing : Int64
  current_expires_at : Int64?
  claim_active : Bool
  claim_released : Bool
  claim_expired : Bool
  cancellation : CancellationRecord?
  retry_links : ReadOnlyArray[RetryLink]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn schedule_state_tag(value : ScheduleState) -> String {
  match value {
    ScheduleAbsent => "absent"
    RegisteredWaiting => "registered-waiting"
    DueUnclaimed => "due-unclaimed"
    BlockedGovernance => "blocked-governance"
    BlockedDeadline => "blocked-deadline"
    ClaimedRunning => "claimed-running"
    LeaseExpiredReclaimable => "lease-expired-reclaimable"
    EffectObservationPending => "effect-observation-pending"
    KnownEffectSuccess => "known-effect-success"
    KnownEffectFailure => "known-effect-failure"
    UnknownOutcomeRequiresReconciliation => "unknown-requires-reconciliation"
    ReconciliationRequested => "reconciliation-requested"
    ReconciledSuccess => "reconciled-success"
    ReconciledFailure => "reconciled-failure"
    ReconciledNotAppliedRetryEligible => "reconciled-not-applied-retry-eligible"
    CancelledBeforeWork => "cancelled-before-work"
    CancellationRequestedOutcomeUnresolved => "cancellation-outcome-unresolved"
    Terminal => "terminal"
  }
}

///|
fn projection_canonical(
  workflow : @contracts.RecordRef,
  policy_ref : @contracts.RecordRef,
  sequence : Int64,
  revision : Int64,
  last_event_digest : @contracts.ContentDigest?,
  replay_digest : @contracts.ContentDigest?,
  schedule : ScheduleIntent?,
  latest_clock : ClockInput?,
  state : ScheduleState,
  current_claim : LeaseClaim?,
  current_owner : @contracts.RecordRef?,
  current_epoch : Int64,
  current_fencing : Int64,
  current_expires_at : Int64?,
  claim_active : Bool,
  claim_released : Bool,
  claim_expired : Bool,
  cancellation : CancellationRecord?,
  retry_links : ArrayView[RetryLink],
) -> Bytes {
  let writer = OrchestrationWriter::new()
  try! writer.bytes(b"MF7APROJ1")
  try! writer.string(orchestration_record_version)
  try! write_ref(writer, workflow)
  try! write_ref(writer, policy_ref)
  writer.int64(sequence)
  writer.int64(revision)
  try! writer.optional_digest(last_event_digest)
  try! writer.optional_digest(replay_digest)
  match schedule {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      try! writer.bytes(value.canonical_bytes())
    }
  }
  match latest_clock {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      try! writer.bytes(value.canonical_bytes())
    }
  }
  try! writer.string(schedule_state_tag(state))
  match current_claim {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      try! writer.bytes(value.canonical_bytes())
    }
  }
  try! write_optional_ref(writer, current_owner)
  writer.int64(current_epoch)
  writer.int64(current_fencing)
  writer.optional_int64(current_expires_at)
  writer.byte(if claim_active { 1 } else { 0 })
  writer.byte(if claim_released { 1 } else { 0 })
  writer.byte(if claim_expired { 1 } else { 0 })
  match cancellation {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      try! writer.bytes(value.canonical_bytes())
    }
  }
  try! writer.count(retry_links.length())
  for value in retry_links {
    try! writer.bytes(value.canonical_bytes())
  }
  writer.finish()
}

///|
fn build_projection(
  workflow : @contracts.RecordRef,
  policy_ref : @contracts.RecordRef,
  sequence : Int64,
  revision : Int64,
  last_event_digest : @contracts.ContentDigest?,
  replay_digest : @contracts.ContentDigest?,
  schedule : ScheduleIntent?,
  latest_clock : ClockInput?,
  state : ScheduleState,
  current_claim : LeaseClaim?,
  current_owner : @contracts.RecordRef?,
  current_epoch : Int64,
  current_fencing : Int64,
  current_expires_at : Int64?,
  claim_active : Bool,
  claim_released : Bool,
  claim_expired : Bool,
  cancellation : CancellationRecord?,
  retry_links : Array[RetryLink],
) -> OrchestrationProjection {
  let canonical = projection_canonical(
    workflow, policy_ref, sequence, revision, last_event_digest, replay_digest, schedule,
    latest_clock, state, current_claim, current_owner, current_epoch, current_fencing,
    current_expires_at, claim_active, claim_released, claim_expired, cancellation,
    retry_links,
  )
  {
    projection_version: orchestration_version(),
    workflow,
    policy_ref,
    sequence,
    revision,
    last_event_digest,
    replay_digest,
    schedule,
    latest_clock,
    state,
    current_claim,
    current_owner,
    current_epoch,
    current_fencing,
    current_expires_at,
    claim_active,
    claim_released,
    claim_expired,
    cancellation,
    retry_links: ReadOnlyArray::from_array(retry_links.copy()),
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn OrchestrationProjection::new(
  workflow : @contracts.RecordRef,
  policy_ref : @contracts.RecordRef,
) -> OrchestrationProjection {
  build_projection(
    workflow,
    policy_ref,
    0L,
    0L,
    None,
    None,
    None,
    None,
    ScheduleAbsent,
    None,
    None,
    0L,
    0L,
    None,
    false,
    false,
    false,
    None,
    [],
  )
}

///|
pub fn OrchestrationProjection::workflow(
  self : OrchestrationProjection,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn OrchestrationProjection::sequence(
  self : OrchestrationProjection,
) -> Int64 {
  self.sequence
}

///|
pub fn OrchestrationProjection::revision(
  self : OrchestrationProjection,
) -> Int64 {
  self.revision
}

///|
pub fn OrchestrationProjection::last_event_digest(
  self : OrchestrationProjection,
) -> @contracts.ContentDigest? {
  self.last_event_digest
}

///|
pub fn OrchestrationProjection::schedule(
  self : OrchestrationProjection,
) -> ScheduleIntent? {
  self.schedule
}

///|
pub fn OrchestrationProjection::latest_clock(
  self : OrchestrationProjection,
) -> ClockInput? {
  self.latest_clock
}

///|
pub fn OrchestrationProjection::state(
  self : OrchestrationProjection,
) -> ScheduleState {
  self.state
}

///|
pub fn OrchestrationProjection::canonical_bytes(
  self : OrchestrationProjection,
) -> Bytes {
  self.canonical
}

///|
pub fn OrchestrationProjection::state_digest(
  self : OrchestrationProjection,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn OrchestrationProjection::due_proof(
  self : OrchestrationProjection,
) -> DueProof raise OrchestrationError {
  if self.state != DueUnclaimed && self.state != LeaseExpiredReclaimable {
    raise ScheduleStateViolation(field="not_due_or_reclaimable")
  }
  guard self.schedule is Some(schedule) &&
    self.latest_clock is Some(clock) &&
    self.replay_digest is Some(replay_digest) else {
    raise RecoveryViolation(field="due_proof_missing_replay")
  }
  due_proof(schedule, clock, replay_digest, self.current_fencing)
}

///|
pub fn OrchestrationProjection::claimed_proof(
  self : OrchestrationProjection,
) -> ClaimedProof raise OrchestrationError {
  if self.state != ClaimedRunning || !self.claim_active {
    raise ScheduleStateViolation(field="not_actively_claimed")
  }
  guard self.current_claim is Some(claim) &&
    self.current_expires_at is Some(expires_at) &&
    self.replay_digest is Some(replay_digest) else {
    raise RecoveryViolation(field="claimed_proof_missing_replay")
  }
  claimed_proof(
    claim,
    self.current_epoch,
    self.current_fencing,
    expires_at,
    replay_digest,
  )
}

///|
fn state_from_clock(
  schedule : ScheduleIntent,
  clock : ClockInput,
) -> ScheduleState {
  match schedule.deadline() {
    Some(deadline) if clock.logical_instant() > deadline => BlockedDeadline
    _ =>
      match schedule.governance_binding().authority_expires_at() {
        Some(expires_at) if clock.logical_instant() > expires_at =>
          BlockedGovernance
        _ =>
          if clock.logical_instant() < schedule.not_before() {
            RegisteredWaiting
          } else {
            DueUnclaimed
          }
      }
  }
}

///|
fn effect_state(
  schedule : ScheduleIntent,
  effects_projection : @effects.EffectsProjection,
) -> ScheduleState raise {
  match effects_projection.state_for(schedule.effect_intent().intent_ref()) {
    RegisteredNoIntent => RegisteredWaiting
    DurableIntentDispatchEligible => DueUnclaimed
    DispatchObservationPending => EffectObservationPending
    KnownSuccess => KnownEffectSuccess
    KnownFailure => KnownEffectFailure
    UnknownOutcomeRequiresReconciliation => UnknownOutcomeRequiresReconciliation
    ReconciliationRequestedState => ReconciliationRequested
    ReconciledSuccessState => ReconciledSuccess
    ReconciledFailureState => ReconciledFailure
    ReconciledNotAppliedRetryEligible => ReconciledNotAppliedRetryEligible
  }
}

///|
fn terminal_effect_state(value : ScheduleState) -> Bool {
  value == KnownEffectSuccess ||
  value == KnownEffectFailure ||
  value == ReconciledSuccess ||
  value == ReconciledFailure
}

///|
