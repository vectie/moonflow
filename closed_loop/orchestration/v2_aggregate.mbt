///|
/// Joint verified view of a mixed effects/orchestration workflow stream.
pub struct ClosedLoopProjectionV2 {
  effects : @effects.EffectsProjection
  orchestration : OrchestrationProjectionV2
  prefix_event : @storage.WorkflowEvent?
  replay_digest : @contracts.ContentDigest
  cancellation : ReplayedCancellationRequestV2?
  work_terminal : WorkTerminalRecordV2?
  terminal_batch_boundary : @storage.CommittedBatchBoundary?
}

///|
fn ClosedLoopProjectionV2::replay_digest(
  self : ClosedLoopProjectionV2,
) -> @contracts.ContentDigest {
  self.replay_digest
}

///|
pub fn ClosedLoopProjectionV2::effects(
  self : ClosedLoopProjectionV2,
) -> @effects.EffectsProjection {
  self.effects
}

///|
pub fn ClosedLoopProjectionV2::orchestration(
  self : ClosedLoopProjectionV2,
) -> OrchestrationProjectionV2 {
  self.orchestration
}

///|
/// Account for the request-only outbox carried by a native V3 recovery retry.
/// The legacy effects fold cannot match this record because its causative
/// event is a `RecoveryRetryIntentV3`, not an `EffectIntentV1`. Acceptance is
/// still strict: the outbox must be the sole outbox in the exact two-event
/// retry transaction, and both events must pass the native retry validator.
fn recovery_retry_outbox_consumption_v3(
  outbox : @storage.OutboxIntent,
  replay : @storage.ReplayResult,
) -> Int raise OrchestrationError {
  let batches = replay
    .committed_batches()
    .filter(batch => {
      batch.intent_refs().length() == 1 &&
      batch.intent_refs()[0] == outbox.intent_ref()
    })
  if batches.is_empty() {
    return 0
  }
  if batches.length() != 1 {
    raise ReplayBindingViolation(field="recovery_retry_v3_outbox_boundary")
  }
  let boundary = batches[0]
  if boundary.event_refs().length() != 2 {
    return 0
  }
  guard first(replay.events(), event => {
      event.event_ref() == boundary.event_refs()[0]
    })
    is Some(intent_event) else {
    raise ReplayBindingViolation(field="recovery_retry_v3_outbox_boundary")
  }
  guard first(replay.events(), event => {
      event.event_ref() == boundary.event_refs()[1]
    })
    is Some(schedule_event) else {
    raise ReplayBindingViolation(field="recovery_retry_v3_outbox_boundary")
  }
  if intent_event.payload().envelope_kind() !=
    recovery_retry_intent_event_kind_v3 ||
    schedule_event.payload().envelope_kind() !=
    recovery_retry_scheduled_event_kind_v3 {
    return 0
  }
  if recovery_retry_event_consumption_v3(intent_event, replay) != 1 ||
    recovery_retry_event_consumption_v3(schedule_event, replay) != 1 {
    raise ReplayBindingViolation(field="recovery_retry_v3_outbox_binding")
  }
  1
}

///|
pub fn ClosedLoopProjectionV2::prefix_event(
  self : ClosedLoopProjectionV2,
) -> @storage.WorkflowEvent? {
  self.prefix_event
}

///|
fn require_retry_atomic_batch_v2(
  replay : @storage.ReplayResult,
  plan : @retry_authority.RetryPlanProposalV2,
  attempt_event : @storage.WorkflowEvent,
  schedule_event : @storage.WorkflowEvent,
) -> Unit raise OrchestrationError {
  if attempt_event.sequence() != plan.prefix_sequence() + 1L ||
    attempt_event.revision() != plan.prefix_revision() + 1L ||
    attempt_event.previous_event_digest() != Some(plan.prefix_head_digest()) ||
    schedule_event.sequence() != plan.prefix_sequence() + 2L ||
    schedule_event.revision() != plan.prefix_revision() + 2L ||
    schedule_event.previous_event_digest() !=
    Some(attempt_event.event_ref().digest()) {
    raise ReplayBindingViolation(field="retry_atomic_pair_chain")
  }
  let matching = replay
    .committed_batches()
    .filter(batch => {
      let event_refs = batch.event_refs()
      event_refs.length() == 2 &&
      event_refs[0] == attempt_event.event_ref() &&
      event_refs[1] == schedule_event.event_ref() &&
      batch.intent_refs().is_empty() &&
      batch.expected_revision() == plan.prefix_revision() &&
      batch.command_idempotency_key() == plan.command_idempotency_key()
    })
  if matching.length() != 1 {
    raise ReplayBindingViolation(field="retry_atomic_batch_boundary")
  }
}

///|
fn require_retry_schedule_semantics_v2(
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
  plan : @retry_authority.RetryPlanProposalV2,
  schedule : ScheduleIntentV2,
) -> Unit raise OrchestrationError {
  let policy = RetryPolicyV2::decode(
    plan.policy_ref().id(),
    plan.policy_bytes(),
  )
  if policy.policy_ref() != plan.policy_ref() ||
    policy.digest() != plan.policy_digest() ||
    policy.canonical_bytes() != plan.policy_bytes() ||
    !policy.allows(receipt) {
    raise ReplayBindingViolation(field="retry_policy_binding")
  }
  let timing = RetryTimingV2::decode(policy, receipt, plan.timing_bytes())
  if timing.digest() != plan.timing_digest() ||
    timing.canonical_bytes() != plan.timing_bytes() ||
    timing.due_at() != plan.due_at() ||
    plan.due_at() != schedule.not_before() {
    raise ReplayBindingViolation(field="retry_timing_binding")
  }
  guard schedule.retry_policy() is Some(schedule_policy) else {
    raise ReplayBindingViolation(field="retry_schedule_policy_missing")
  }
  if schedule_policy.policy_ref() != policy.policy_ref() ||
    schedule_policy.digest() != policy.digest() ||
    schedule_policy.canonical_bytes() != policy.canonical_bytes() {
    raise ReplayBindingViolation(field="retry_schedule_policy_binding")
  }
}

///|
fn require_retry_request_admission_v2(
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
  plan : @retry_authority.RetryPlanProposalV2,
  schedule : ScheduleIntentV2,
) -> Unit raise OrchestrationError {
  let request = @retry_authority.RetryScheduleRequestV2::decode(
    plan.request_ref(),
    plan.request_bytes(),
  ) catch {
    _ => raise ReplayBindingViolation(field="retry_request_decode")
  }
  let admission = AdmissionV2::decode(
    plan.admission_ref().id(),
    plan.admission_bytes(),
  )
  let schedule_admission = schedule.admission()
  let planned = admission.planned()
  let governance = admission.governance()
  let head = admission.eligibility().authoritative_head()
  if request.digest() != plan.request_digest() ||
    request.canonical_bytes() != plan.request_bytes() ||
    request.workflow() != plan.workflow() ||
    request.workflow() != schedule.workflow() ||
    request.receipt_ref() != receipt.receipt_ref() ||
    request.receipt_digest() != receipt.digest() ||
    request.receipt_bytes() != receipt.canonical_bytes() ||
    request.policy_ref() != plan.policy_ref() ||
    request.policy_digest() != plan.policy_digest() ||
    request.policy_bytes() != plan.policy_bytes() ||
    request.timing_digest() != plan.timing_digest() ||
    request.timing_bytes() != plan.timing_bytes() ||
    request.due_at() != plan.due_at() ||
    request.due_at() != schedule.not_before() ||
    request.attempt_count() != plan.attempt_count() ||
    request.retry_count() != plan.retry_count() ||
    request.retry_ordinal() != plan.retry_ordinal() ||
    request.cause_key() != plan.cause_key() ||
    request.requested_work_ref() != plan.requested_work_ref() ||
    request.requested_work_digest() != plan.requested_work_digest() ||
    request.logical_attempt_id() != plan.logical_attempt_id() ||
    request.logical_attempt_version() != plan.logical_attempt_version() ||
    request.logical_effect_id() != plan.logical_effect_id() ||
    request.logical_effect_version() != plan.logical_effect_version() ||
    request.artifact_digest() != plan.artifact_digest() ||
    request.child_attempt_request_ref() != plan.child_attempt_request_ref() ||
    request.child_attempt_ordinal() != plan.child_attempt_ordinal() ||
    request.child_attempt_idempotency_key() !=
    plan.child_attempt_idempotency_key() ||
    request.child_schedule_request_ref() != plan.schedule_request_ref() ||
    request.schedule_id() != schedule.schedule_ref().id() ||
    request.schedule_idempotency_key() != schedule.idempotency_key() ||
    request.schedule_idempotency_key() != plan.schedule_idempotency_key() ||
    request.source_schedule_deadline() != plan.source_schedule_deadline() ||
    request.admission_governance_deadline() !=
    plan.admission_governance_deadline() ||
    request.admission_controls_deadline() != plan.admission_controls_deadline() ||
    request.requested_schedule_deadline() != plan.requested_schedule_deadline() ||
    request.governance_deadline() != plan.governance_deadline() ||
    request.effective_deadline() != plan.admission_deadline() ||
    schedule.deadline() != Some(request.effective_deadline()) ||
    request.prefix_head_ref() != plan.prefix_head_ref() ||
    request.prefix_head_digest() != plan.prefix_head_digest() ||
    request.prefix_sequence() != plan.prefix_sequence() ||
    request.prefix_revision() != plan.prefix_revision() ||
    request.prefix_replay_digest() != plan.prefix_replay_digest() ||
    request.command_idempotency_key() != plan.command_idempotency_key() {
    raise ReplayBindingViolation(field="retry_request_plan_binding")
  }
  if admission.proof_ref() != plan.admission_ref() ||
    admission.proof_digest() != plan.admission_digest() ||
    admission.proof_bytes() != plan.admission_bytes() ||
    schedule_admission.proof_ref() != admission.proof_ref() ||
    schedule_admission.proof_digest() != admission.proof_digest() ||
    schedule_admission.proof_bytes() != admission.proof_bytes() ||
    planned.workflow() != request.workflow() ||
    planned.subject() != governance.governed_subject() ||
    planned.requested_work_ref() != request.requested_work_ref() ||
    planned.requested_work_digest() != request.requested_work_digest() ||
    planned.logical_attempt_id() != request.logical_attempt_id() ||
    planned.logical_attempt_version() != request.logical_attempt_version() ||
    planned.logical_effect_id() != request.logical_effect_id() ||
    planned.logical_effect_version() != request.logical_effect_version() ||
    planned.artifact_digest() != request.artifact_digest() ||
    planned.effect_request_ref() != request.request_ref() ||
    planned.effect_request_digest() != request.digest() ||
    planned.next_ordinal() != request.child_attempt_ordinal() ||
    planned.external_idempotency() != request.child_attempt_idempotency_key() ||
    governance.valid_until_inclusive() !=
    request.admission_governance_deadline() ||
    admission.controls().deadline_inclusive() !=
    request.admission_controls_deadline() ||
    admission.eligibility().clock() != request.due_at() ||
    head.event_ref() != request.prefix_head_ref() ||
    head.event_digest() != request.prefix_head_digest() ||
    head.sequence() != request.prefix_sequence() ||
    head.revision() != request.prefix_revision() {
    raise ReplayBindingViolation(field="retry_request_admission_binding")
  }
}

///|
fn orchestration_event_kind_v2(kind : String) -> Bool {
  @replay.is_orchestration_event_kind_v2(kind)
}

///|
fn require_closed_replay_accounting_v2(
  replay : @storage.ReplayResult,
  effects : @effects.EffectsProjection,
) -> Unit raise OrchestrationError {
  let consumed = effects.strict_consumed_event_refs() catch {
    _ => raise ReplayBindingViolation(field="aggregate_effect_coverage")
  }
  for event in replay.events() {
    let strict_count = consumed
      .filter(value => value == event.event_ref())
      .length()
    let orchestration_count = if orchestration_event_kind_v2(
        event.payload().envelope_kind(),
      ) {
      1
    } else {
      0
    }
    // Phase 2 recovery facts remain outside the frozen V2 semantic state, but
    // the full aggregate must still strictly decode and account for each one
    // exactly once. This prevents a recognized wrapper from hiding arbitrary
    // bytes while preserving every V2 state transition and public contract.
    let recovery_count = recovery_event_consumption_v3(event, replay)
    if strict_count + orchestration_count + recovery_count != 1 {
      raise ReplayBindingViolation(field="aggregate_event_consumption")
    }
  }
  for consumed_ref in consumed {
    if replay
      .events()
      .filter(event => event.event_ref() == consumed_ref)
      .length() !=
      1 {
      raise ReplayBindingViolation(field="aggregate_consumed_event_ref")
    }
  }
  let matched = effects.strict_matched_outbox_refs() catch {
    _ => raise ReplayBindingViolation(field="aggregate_outbox_coverage")
  }
  for outbox in replay.intents() {
    let legacy_count = matched
      .filter(value => value == outbox.intent_ref())
      .length()
    let recovery_count = recovery_retry_outbox_consumption_v3(outbox, replay)
    if legacy_count + recovery_count != 1 {
      raise ReplayBindingViolation(field="aggregate_outbox_consumption")
    }
  }
  for matched_ref in matched {
    if replay
      .intents()
      .filter(outbox => outbox.intent_ref() == matched_ref)
      .length() !=
      1 {
      raise ReplayBindingViolation(field="aggregate_matched_outbox_ref")
    }
  }
}

///|
/// Validate the closed event catalog in both domain projections, then require
/// every retry attempt and schedule to be one exact adjacent two-event commit
/// with no outbox intents in that commit.
pub fn fold_closed_loop_v2(
  empty_effects : @effects.EffectsProjection,
  replay : @storage.ReplayResult,
) -> ClosedLoopProjectionV2 raise OrchestrationError {
  require_no_event_after_work_terminal_v22(replay)
  let effects = @effects.fold_committed_effects_bytes(empty_effects, replay) catch {
    _ => raise ReplayBindingViolation(field="aggregate_effects_replay")
  }
  let events = replay.events()
  let has_inline_effect_governance = events.any(event => {
    match event.payload().envelope_kind() {
      "attempt.registered.v1"
      | "EvidenceAttached"
      | "AuthorityRequested"
      | "AuthorityGranted"
      | "AuthorityDenied"
      | "AuthorityExpired"
      | "ReviewRequested"
      | "ReviewDecisionRecorded"
      | "ReviewReceiptBound" => true
      _ => false
    }
  })
  if has_inline_effect_governance && !effects.strict_semantic_governance_v2() {
    raise ReplayBindingViolation(field="aggregate_governance_v2_required")
  }
  for index, event in events {
    let envelope = event.payload()
    if envelope.envelope_kind() == "attempt.registered.v1" {
      guard envelope.attempt_ref() is Some(attempt_ref) else {
        raise ReplayBindingViolation(field="retry_attempt_transport_ref")
      }
      let plan = effects.committed_retry_plan(attempt_ref) catch {
        _ => raise ReplayBindingViolation(field="retry_attempt_plan_replay")
      }
      match plan {
        None => ()
        Some(retry_plan) => {
          if index + 1 >= events.length() {
            raise ReplayBindingViolation(field="retry_attempt_without_schedule")
          }
          let schedule_event = events[index + 1]
          if schedule_event.payload().envelope_kind() !=
            "schedule.registered.v2" {
            raise ReplayBindingViolation(
              field="retry_attempt_not_adjacent_schedule",
            )
          }
          let registered = ScheduleRegisteredV2::decode(
            schedule_event.payload().subject().id(),
            schedule_event.payload().payload(),
          )
          let schedule = registered.schedule()
          guard schedule.retry_plan() is Some(schedule_plan) else {
            raise ReplayBindingViolation(field="retry_schedule_plan_missing")
          }
          if schedule_plan.plan_ref() != retry_plan.plan_ref() ||
            schedule_plan.canonical_bytes() != retry_plan.canonical_bytes() ||
            schedule.retry_attempt_ref() != Some(attempt_ref) ||
            schedule.retry_attempt_event_ref() != Some(event.event_ref()) {
            raise ReplayBindingViolation(field="retry_pair_plan_binding")
          }
          let receipt = effects.committed_retry_receipt_for_attempt(attempt_ref) catch {
            _ =>
              raise ReplayBindingViolation(field="retry_attempt_receipt_replay")
          }
          guard receipt is Some(receipt) else {
            raise ReplayBindingViolation(field="retry_attempt_receipt_missing")
          }
          require_retry_schedule_semantics_v2(receipt, retry_plan, schedule)
          require_retry_request_admission_v2(receipt, retry_plan, schedule)
          require_retry_atomic_batch_v2(
            replay, retry_plan, event, schedule_event,
          )
        }
      }
    } else if envelope.envelope_kind() == "schedule.registered.v2" {
      let registered = ScheduleRegisteredV2::decode(
        envelope.subject().id(),
        envelope.payload(),
      )
      match registered.schedule().retry_plan() {
        None => ()
        Some(plan) => {
          if index == 0 {
            raise ReplayBindingViolation(field="retry_schedule_without_attempt")
          }
          let attempt_event = events[index - 1]
          if attempt_event.payload().envelope_kind() != "attempt.registered.v1" {
            raise ReplayBindingViolation(
              field="retry_schedule_not_adjacent_attempt",
            )
          }
          guard attempt_event.payload().attempt_ref() is Some(attempt_ref) else {
            raise ReplayBindingViolation(field="retry_pair_attempt_ref")
          }
          let replayed_plan = effects.committed_retry_plan(attempt_ref) catch {
            _ =>
              raise ReplayBindingViolation(
                field="retry_pair_attempt_plan_replay",
              )
          }
          guard replayed_plan is Some(attempt_plan) else {
            raise ReplayBindingViolation(
              field="retry_pair_attempt_plan_missing",
            )
          }
          let replayed_receipt = effects.committed_retry_receipt_for_attempt(
            attempt_ref,
          ) catch {
            _ =>
              raise ReplayBindingViolation(
                field="retry_pair_attempt_receipt_replay",
              )
          }
          guard replayed_receipt is Some(receipt) else {
            raise ReplayBindingViolation(
              field="retry_pair_attempt_receipt_missing",
            )
          }
          let schedule = registered.schedule()
          if attempt_plan.plan_ref() != plan.plan_ref() ||
            attempt_plan.digest() != plan.digest() ||
            attempt_plan.canonical_bytes() != plan.canonical_bytes() ||
            schedule.retry_attempt_ref() != Some(attempt_ref) ||
            schedule.retry_attempt_event_ref() !=
            Some(attempt_event.event_ref()) {
            raise ReplayBindingViolation(field="retry_pair_plan_binding")
          }
          if plan.receipt_ref() != receipt.receipt_ref() ||
            plan.receipt_digest() != receipt.digest() ||
            plan.receipt_bytes() != receipt.canonical_bytes() ||
            plan.source_intent_ref() != receipt.source_intent_ref() ||
            plan.source_attempt_ref() != receipt.source_attempt_ref() ||
            plan.root_intent_ref() != receipt.root_intent_ref() ||
            plan.root_attempt_ref() != receipt.root_attempt_ref() ||
            plan.lineage_digest() != receipt.lineage_digest() ||
            plan.attempt_count() != receipt.attempt_count() ||
            plan.retry_count() != receipt.retry_count() ||
            plan.retry_ordinal() != receipt.retry_ordinal() ||
            plan.cause_key() != receipt.cause_key() {
            raise ReplayBindingViolation(field="retry_pair_receipt_binding")
          }
          require_retry_atomic_batch_v2(replay, plan, attempt_event, event)
          require_retry_request_admission_v2(receipt, plan, schedule)
        }
      }
    }
  }
  let has_verified_root_prefix = events.length() >= 3 &&
    events[0].payload().envelope_kind() == schedule_registered_event_kind_v2 &&
    events[1].payload().envelope_kind() == retry_policy_bound_event_kind_v22 &&
    events[2].payload().envelope_kind() ==
    cancellation_governance_bound_event_kind_v22
  let orchestration = if has_verified_root_prefix {
    // The root-bound fold validates the exact committed three-event genesis
    // batch and returns the only projection capable of preparing lifecycle or
    // retry writes. Merely resembling the prefix never mints authority.
    fold_root_bound_orchestration_v22(empty_effects, replay)
  } else {
    // Historical streams remain readable for migration and diagnostics, but
    // this projection deliberately lacks root-binding authority.
    let legacy = fold_orchestration_v2_internal(replay, true, false)
    require_closed_replay_accounting_v2(replay, effects)
    legacy
  }
  let (cancellation, work_terminal) = fold_phase1b_cancellation_state_v22(
    replay, effects,
  )
  let terminal_batch_boundary = match work_terminal {
    None => None
    Some(terminal) => {
      let matching = replay
        .committed_batches()
        .filter(batch => {
          let refs = batch.event_refs()
          let terminal_ref = events.last().map(event => event.event_ref())
          let shape_ok = if terminal.outcome == CancelledBeforeEffectIntentV2 {
            refs.length() == 2 &&
            refs[0] == terminal.source_event_ref &&
            terminal_ref == Some(refs[1])
          } else {
            refs.length() == 1 && terminal_ref == Some(refs[0])
          }
          shape_ok &&
          batch.intent_refs().is_empty() &&
          batch.expected_revision() == terminal.prefix_revision &&
          batch.command_idempotency_key() == terminal.command_idempotency_key
        })
      if matching.length() != 1 {
        raise ReplayBindingViolation(field="work_batch_boundary_shape")
      }
      Some(matching[0])
    }
  }
  {
    effects,
    orchestration,
    prefix_event: events.last(),
    replay_digest: replay.replay_digest(),
    cancellation,
    work_terminal,
    terminal_batch_boundary,
  }
}

///|
pub struct PreparedAtomicRetryV2 {
  plan : @retry_authority.RetryPlanProposalV2
  attempt : @effects.AttemptRegistration
  registration : ScheduleRegisteredV2
  request : @storage.CommitRequest
}

///|
pub fn PreparedAtomicRetryV2::plan(
  self : PreparedAtomicRetryV2,
) -> @retry_authority.RetryPlanProposalV2 {
  self.plan
}

///|
pub fn PreparedAtomicRetryV2::attempt(
  self : PreparedAtomicRetryV2,
) -> @effects.AttemptRegistration {
  self.attempt
}

///|
pub fn PreparedAtomicRetryV2::registration(
  self : PreparedAtomicRetryV2,
) -> ScheduleRegisteredV2 {
  self.registration
}

///|
pub fn PreparedAtomicRetryV2::request(
  self : PreparedAtomicRetryV2,
) -> @storage.CommitRequest {
  self.request
}

///|
fn min_retry_deadline_v2(left : Int64, right : Int64) -> Int64 {
  if left < right {
    left
  } else {
    right
  }
}

///|
/// Freeze the exact retry scheduling request before authorization is minted.
/// The later AdmissionV2 must name this request byte-for-byte.
fn prepare_retry_schedule_request_v2(
  aggregate : ClosedLoopProjectionV2,
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
  policy : RetryPolicyV2,
  governance : @effects.GovernanceBinding,
  request_id : String,
  attempt_id : String,
  attempt_idempotency_key : String,
  requested_work : @contracts.WireEnvelope,
  logical_attempt_id : String,
  logical_attempt_version : String,
  logical_effect_id : String,
  logical_effect_version : String,
  artifact_digest : @contracts.ContentDigest,
  schedule_id : String,
  schedule_idempotency_key : String,
  schedule_deadline : Int64,
  admission_governance_deadline : Int64,
  admission_controls_deadline : Int64,
  command_idempotency_key : String,
) -> @retry_authority.RetryScheduleRequestV2 raise {
  let effects = aggregate.effects()
  let orchestration = aggregate.orchestration()
  require_root_binding_verified_v22(orchestration)
  if effects.workflow() != orchestration.workflow() ||
    effects.sequence() != orchestration.sequence() ||
    effects.revision() != orchestration.revision() ||
    effects.last_event_digest() != orchestration.last_event_digest() {
    raise ReplayBindingViolation(field="retry_request_aggregate_prefix")
  }
  receipt.validate_current(effects)
  if orchestration.schedule_count() == 0 ||
    orchestration.has_active_lease() ||
    !orchestration.has_terminal_lease() {
    raise ScheduleStateViolation(field="retry_request_lease_state")
  }
  if governance.workflow() != effects.workflow() ||
    governance.governed_subject() != requested_work.subject() {
    raise GovernanceMismatch(field="retry_request_governance")
  }
  let timing = RetryTimingV2::compute(policy, receipt)
  let due_at = timing.due_at()
  let source_schedule_deadline = orchestration.latest_schedule_deadline()
  match source_schedule_deadline {
    Some(value) if value < due_at =>
      raise AuthorityExpired(expires_at=value, observed_at=due_at)
    _ => ()
  }
  match governance.authority_expires_at() {
    Some(value) if value <= due_at =>
      raise AuthorityExpired(expires_at=value, observed_at=due_at)
    _ => ()
  }
  guard aggregate.prefix_event() is Some(prefix_event) else {
    raise ReplayBindingViolation(field="retry_request_prefix_event")
  }
  guard effects.last_event_digest() is Some(prefix_digest) else {
    raise ReplayBindingViolation(field="retry_request_prefix_digest")
  }
  if prefix_event.event_ref().digest() != prefix_digest ||
    prefix_event.sequence() != effects.sequence() ||
    prefix_event.revision() != effects.revision() {
    raise ReplayBindingViolation(field="retry_request_prefix")
  }
  let requested_work_ref = @contracts.RecordRef::new(
    "requested-work",
    requested_work.envelope_id(),
    "1.0.0",
    requested_work.envelope_digest().text(),
  ) catch {
    _ => raise MalformedInput(field="retry_request_requested_work_ref")
  }
  @retry_authority.RetryScheduleRequestV2::new(
    request_id,
    effects.workflow(),
    receipt.receipt_ref(),
    receipt.digest(),
    receipt.canonical_bytes(),
    policy.policy_ref(),
    policy.digest(),
    policy.canonical_bytes(),
    timing.digest(),
    timing.canonical_bytes(),
    due_at,
    receipt.attempt_count(),
    receipt.retry_count(),
    receipt.retry_ordinal(),
    receipt.cause_key(),
    requested_work_ref,
    requested_work.envelope_digest(),
    logical_attempt_id,
    logical_attempt_version,
    logical_effect_id,
    logical_effect_version,
    artifact_digest,
    attempt_id,
    receipt.attempt_count() + 1L,
    attempt_idempotency_key,
    schedule_id,
    schedule_idempotency_key,
    source_schedule_deadline,
    admission_governance_deadline,
    admission_controls_deadline,
    schedule_deadline,
    governance.authority_expires_at(),
    prefix_event.event_ref(),
    prefix_digest,
    effects.sequence(),
    effects.revision(),
    receipt.projection_replay_digest(),
    command_idempotency_key,
  )
}

///|
/// Build the only authorized retry append: one content-addressed effects
/// attempt followed by one content-addressed schedule registration in a single
/// CAS request. Due time is computed from policy; callers cannot supply it.
fn prepare_atomic_retry_v2(
  aggregate : ClosedLoopProjectionV2,
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
  policy : RetryPolicyV2,
  retry_request : @retry_authority.RetryScheduleRequestV2,
  admission : AdmissionV2,
  governance : @effects.GovernanceBinding,
  plan_id : String,
  attempt_id : String,
  attempt_event_id : String,
  attempt_idempotency_key : String,
  requested_work : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  created_at : Int64,
  schedule_id : String,
  schedule_idempotency_key : String,
  schedule_deadline : Int64,
  schedule_event_id : String,
  registration_id : String,
  command_idempotency_key : String,
) -> PreparedAtomicRetryV2 raise {
  let effects = aggregate.effects()
  let orchestration = aggregate.orchestration()
  require_root_binding_verified_v22(orchestration)
  if effects.workflow() != orchestration.workflow() ||
    effects.sequence() != orchestration.sequence() ||
    effects.revision() != orchestration.revision() ||
    effects.last_event_digest() != orchestration.last_event_digest() {
    raise ReplayBindingViolation(field="retry_prepare_aggregate_prefix")
  }
  receipt.validate_current(effects)
  if orchestration.schedule_count() == 0 ||
    orchestration.has_active_lease() ||
    !orchestration.has_terminal_lease() {
    raise ScheduleStateViolation(field="retry_prepare_lease_state")
  }
  let timing = RetryTimingV2::compute(policy, receipt)
  let due_at = timing.due_at()
  if created_at < receipt.source_observed_at() || created_at > due_at {
    raise ScheduleStateViolation(field="retry_prepare_created_at")
  }
  if schedule_deadline < due_at {
    raise AuthorityExpired(expires_at=schedule_deadline, observed_at=due_at)
  }
  let admission_governance_deadline = admission
    .governance()
    .valid_until_inclusive()
  let admission_controls_deadline = admission.controls().deadline_inclusive()
  let source_schedule_deadline = orchestration.latest_schedule_deadline()
  let mut effective_deadline = schedule_deadline
  effective_deadline = min_retry_deadline_v2(
    effective_deadline, admission_governance_deadline,
  )
  effective_deadline = min_retry_deadline_v2(
    effective_deadline, admission_controls_deadline,
  )
  match source_schedule_deadline {
    None => ()
    Some(value) => {
      if value < due_at {
        raise AuthorityExpired(expires_at=value, observed_at=due_at)
      }
      effective_deadline = min_retry_deadline_v2(effective_deadline, value)
    }
  }
  match governance.authority_expires_at() {
    None => ()
    Some(expires_at) => {
      if expires_at <= 0L || due_at >= expires_at {
        raise AuthorityExpired(expires_at~, observed_at=due_at)
      }
      effective_deadline = min_retry_deadline_v2(
        effective_deadline,
        expires_at - 1L,
      )
    }
  }
  if due_at > effective_deadline {
    raise AuthorityExpired(expires_at=effective_deadline, observed_at=due_at)
  }
  let planned = admission.planned()
  let expected_request = prepare_retry_schedule_request_v2(
    aggregate,
    receipt,
    policy,
    governance,
    retry_request.request_ref().id(),
    attempt_id,
    attempt_idempotency_key,
    requested_work,
    planned.logical_attempt_id(),
    planned.logical_attempt_version(),
    planned.logical_effect_id(),
    planned.logical_effect_version(),
    planned.artifact_digest(),
    schedule_id,
    schedule_idempotency_key,
    schedule_deadline,
    admission_governance_deadline,
    admission_controls_deadline,
    command_idempotency_key,
  )
  if retry_request.request_ref() != expected_request.request_ref() ||
    retry_request.digest() != expected_request.digest() ||
    retry_request.canonical_bytes() != expected_request.canonical_bytes() {
    raise EffectProofMismatch(field="retry_prepare_request")
  }
  if planned.workflow() != effects.workflow() ||
    planned.subject() != requested_work.subject() ||
    planned.subject() != governance.governed_subject() ||
    planned.requested_work_ref() != retry_request.requested_work_ref() ||
    planned.requested_work_digest() != requested_work.envelope_digest() ||
    planned.logical_attempt_id() != retry_request.logical_attempt_id() ||
    planned.logical_attempt_version() != retry_request.logical_attempt_version() ||
    planned.logical_effect_id() != retry_request.logical_effect_id() ||
    planned.logical_effect_version() != retry_request.logical_effect_version() ||
    planned.artifact_digest() != retry_request.artifact_digest() ||
    planned.effect_request_ref() != retry_request.request_ref() ||
    planned.effect_request_digest() != retry_request.digest() ||
    planned.next_ordinal() != receipt.attempt_count() + 1L ||
    planned.external_idempotency() != attempt_idempotency_key {
    raise EffectProofMismatch(field="retry_prepare_planned_work")
  }
  if admission.governance().governed_subject() != governance.governed_subject() ||
    admission.governance().policy_ref() != governance.policy_ref() ||
    admission.governance().policy_digest() != governance.policy_ref().digest() ||
    admission.governance().valid_until_inclusive() !=
    retry_request.admission_governance_deadline() ||
    admission.controls().deadline_inclusive() !=
    retry_request.admission_controls_deadline() ||
    !admission.governance().accepts(due_at) ||
    !admission.controls().accepts(due_at) {
    raise GovernanceMismatch(field="retry_prepare_admission_governance")
  }
  guard orchestration.last_event_digest() is Some(prefix_digest) else {
    raise ReplayBindingViolation(field="retry_prepare_prefix_head")
  }
  let events_head = admission.eligibility().authoritative_head()
  let prefix_head_ref = events_head.event_ref()
  if prefix_head_ref.digest() != prefix_digest ||
    events_head.event_digest() != prefix_digest ||
    events_head.sequence() != orchestration.sequence() ||
    events_head.revision() != orchestration.revision() ||
    admission.eligibility().clock() != due_at {
    raise ReplayBindingViolation(field="retry_prepare_admission_head")
  }
  let plan = @retry_authority.RetryPlanProposalV2::new(
    plan_id,
    effects.workflow(),
    receipt.receipt_ref(),
    receipt.digest(),
    receipt.canonical_bytes(),
    policy.policy_ref(),
    policy.digest(),
    policy.canonical_bytes(),
    timing.digest(),
    timing.canonical_bytes(),
    due_at,
    receipt.root_intent_ref(),
    receipt.root_attempt_ref(),
    receipt.source_intent_ref(),
    receipt.source_attempt_ref(),
    receipt.lineage_digest(),
    receipt.attempt_count(),
    receipt.retry_count(),
    receipt.retry_ordinal(),
    receipt.cause_key(),
    planned.requested_work_ref(),
    requested_work.envelope_digest(),
    planned.logical_attempt_id(),
    planned.logical_attempt_version(),
    planned.logical_effect_id(),
    planned.logical_effect_version(),
    planned.artifact_digest(),
    attempt_id,
    receipt.attempt_count() + 1L,
    attempt_idempotency_key,
    retry_request.request_ref(),
    retry_request.digest(),
    retry_request.canonical_bytes(),
    admission.proof_ref(),
    admission.proof_digest(),
    admission.proof_bytes(),
    effective_deadline,
    source_schedule_deadline,
    admission_governance_deadline,
    admission_controls_deadline,
    schedule_deadline,
    Some(governance.binding_digest()),
    Some(governance.canonical_bytes()),
    governance.authority_expires_at(),
    schedule_id,
    schedule_idempotency_key,
    command_idempotency_key,
    prefix_head_ref,
    prefix_digest,
    effects.sequence(),
    effects.revision(),
    receipt.projection_replay_digest(),
  )
  guard aggregate.prefix_event() is Some(causal_event) else {
    raise ReplayBindingViolation(field="retry_prepare_causal_event_missing")
  }
  if causal_event.event_ref() != prefix_head_ref ||
    causal_event.sequence() != effects.sequence() ||
    causal_event.revision() != effects.revision() {
    raise ReplayBindingViolation(field="retry_prepare_causal_event")
  }
  let attempt = match requested_work.stage_ref() {
    None =>
      @effects.AttemptRegistration::new(
        attempt_id,
        "1.0.0",
        effects.workflow(),
        causal_event,
        receipt.attempt_count() + 1L,
        requested_work,
        evidence.copy(),
        governance,
        created_at,
        attempt_idempotency_key,
        prefix_digest,
        retry_of_intent_ref=receipt.source_intent_ref(),
        retry_eligibility_receipt=receipt,
        retry_plan=plan,
      )
    Some(stage_ref) =>
      @effects.AttemptRegistration::new(
        attempt_id,
        "1.0.0",
        effects.workflow(),
        causal_event,
        receipt.attempt_count() + 1L,
        requested_work,
        evidence.copy(),
        governance,
        created_at,
        attempt_idempotency_key,
        prefix_digest,
        stage_ref~,
        retry_of_intent_ref=receipt.source_intent_ref(),
        retry_eligibility_receipt=receipt,
        retry_plan=plan,
      )
  }
  let attempt_evidence = [ for value in attempt.evidence() => value ]
  let attempt_payload = @contracts.WireEnvelope::new(
    "closed-loop.effects",
    "1.0.0",
    attempt_event_id,
    "attempt.registered.v1",
    attempt.governance().governed_subject(),
    phase1b_effect_schema_v22("attempt.registered.v1"),
    attempt.canonical_bytes(),
    "effects-protocol",
    "1.0.0",
    [],
    attempt_evidence,
    run_ref=effects.workflow(),
    attempt_ref=attempt.attempt_ref(),
    correlation_ref=effects.workflow().id(),
    causation_ref=attempt.causal_event_ref().id(),
    idempotency_ref=attempt.idempotency_key(),
    previous_digest=prefix_digest,
  ) catch {
    _ => raise MalformedInput(field="retry_attempt_event_payload")
  }
  let attempt_event = @storage.WorkflowEvent::new(
    "1.0.0",
    "1.0.0",
    effects.workflow(),
    attempt_event_id,
    effects.sequence() + 1L,
    effects.revision() + 1L,
    attempt.idempotency_key(),
    attempt_payload,
    attempt_evidence,
    previous_event_digest=prefix_digest,
  ) catch {
    _ => raise MalformedInput(field="retry_attempt_event")
  }
  let schedule = ScheduleIntentV2::new(
    schedule_id,
    "2.0.0",
    admission,
    effects.workflow(),
    due_at,
    Some(effective_deadline),
    evidence.copy(),
    attempt_event.event_ref(),
    schedule_idempotency_key,
    previous_digest=attempt_event.event_ref().digest(),
    retry_policy=policy,
    retry_plan=plan,
    retry_attempt_ref=attempt.attempt_ref(),
    retry_attempt_event_ref=attempt_event.event_ref(),
  )
  let registration = ScheduleRegisteredV2::new(registration_id, schedule)
  require_retry_schedule_admission_head_v2(
    effects.workflow(),
    plan,
    registration,
  )
  let schedule_envelope = v2_lifecycle_envelope(
    schedule_event_id,
    schedule_registered_event_kind_v2,
    effects.workflow(),
    registration.record_ref(),
    registration.canonical_bytes(),
    evidence.copy(),
    attempt_event.event_ref(),
    schedule_idempotency_key,
    Some(attempt_event.event_ref().digest()),
  )
  let schedule_event = @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    effects.workflow(),
    schedule_event_id,
    effects.sequence() + 2L,
    effects.revision() + 2L,
    schedule_idempotency_key,
    schedule_envelope,
    evidence,
    previous_event_digest=attempt_event.event_ref().digest(),
  )
  let request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    effects.workflow(),
    effects.revision(),
    command_idempotency_key,
    [attempt_event, schedule_event],
    [],
  )
  { plan, attempt, registration, request }
}
