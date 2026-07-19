///|
priv enum Phase2ProviderBehaviorV3 {
  Phase2ProviderSucceedsV3
  Phase2ProviderFailsV3
  Phase2ProviderNotAppliedV3
  Phase2ProviderUnknownV3
  Phase2ProviderMalformedSuccessV3
  Phase2ProviderEvidenceTimeMismatchV3
  Phase2ProviderThrowsV3
} derive(Eq)

///|
priv struct Phase2GuardedProviderSpyV3 {
  profile : ProviderRecoveryProfileV3
  store : @storage.MemoryStore
  empty_effects : @effects.EffectsProjection
  work : @contracts.RecordRef
  governance : @contracts.RecordRef
  behavior : Phase2ProviderBehaviorV3
  observed_at : Int64
  cancellation_before_return : CancellationRequestV2?
  cancellation_committed : Ref[Bool]
  cancellation_error : Ref[String]
  calls : Ref[Int]
  durable_at_entry : Ref[Bool]
}

///|
impl GuardedEffectProviderPortV3 for Phase2GuardedProviderSpyV3 with fn recovery_profile(
  self,
) {
  self.profile
}

///|
impl GuardedEffectProviderPortV3 for Phase2GuardedProviderSpyV3 with fn create_guarded_effect(
  self,
  call,
) {
  let work_replay = self.store.replay(self.work)
  let governance_replay = self.store.replay(self.governance)
  let current = fold_governed_recovery_v3(
    self.empty_effects,
    work_replay,
    governance_replay,
  )
  guard current.current_claim_by_ref_v3(call.claim_ref()) is Some(claim) else {
    raise RecoveryViolation(field="phase2_spy_claim_not_durable")
  }
  if work_replay.replay_digest() != call.durable_work_replay_digest() ||
    claim.external_idempotency_key != call.external_idempotency_key() ||
    claim.fencing_token != call.fencing_token() ||
    claim.provider_profile_digest != call.provider_profile_digest() ||
    current.state_for(claim.intent_ref) != @effects.RecoveryDispatchAttemptedV3 ||
    !current.invocation_starts.any(started => {
      started.start_ref == call.invocation_start_ref() &&
      started.claim_ref == call.claim_ref()
    }) {
    raise RecoveryViolation(field="phase2_spy_call_not_durable")
  }
  self.durable_at_entry.val = true
  self.calls.val = self.calls.val + 1
  match self.cancellation_before_return {
    None => ()
    Some(request) =>
      try {
        let activation = self.store.activate_guarded_workflow(self.work, [
          self.governance,
        ])
        let bound = @storage.GuardedMemoryStore::new(self.store, activation)
        let cancellation = prepare_lifecycle_cancellation_candidate_v3(
          current, request,
        )
        guard commit_lifecycle_candidate_v2(bound, cancellation)
          is LifecycleCommittedV2(_) else {
          raise RecoveryViolation(field="phase2_spy_cancellation_lost")
        }
        self.cancellation_committed.val = true
      } catch {
        error => self.cancellation_error.val = "\{to_repr(error)}"
      }
  }
  let evidence_kind = match self.behavior {
    Phase2ProviderSucceedsV3
    | Phase2ProviderMalformedSuccessV3
    | Phase2ProviderEvidenceTimeMismatchV3 => ProviderAppliedEvidenceV3
    Phase2ProviderFailsV3 => ProviderFailedEvidenceV3
    Phase2ProviderNotAppliedV3 => ProviderTombstoneNotAppliedEvidenceV3
    Phase2ProviderUnknownV3 | Phase2ProviderThrowsV3 =>
      ProviderUnknownEvidenceV3
  }
  let evidence = ProviderCreateEvidenceV3::new(
    "phase2-spy-provider",
    "phase2-spy-provider-event-" + self.calls.val.to_string(),
    evidence_kind,
    @contracts.sha256_digest(b"phase2-spy-provider-body"),
    if self.behavior == Phase2ProviderMalformedSuccessV3 {
      call.external_idempotency_key() + ":substituted"
    } else {
      call.external_idempotency_key()
    },
    call.fencing_token(),
    if self.behavior == Phase2ProviderEvidenceTimeMismatchV3 {
      self.observed_at + 1L
    } else {
      self.observed_at
    },
  )
  match self.behavior {
    Phase2ProviderSucceedsV3 => ProviderCreateKnownSucceededV3(evidence)
    Phase2ProviderFailsV3 => ProviderCreateKnownFailedV3(evidence)
    Phase2ProviderNotAppliedV3 => ProviderCreateConfirmedNotAppliedV3(evidence)
    Phase2ProviderUnknownV3 => ProviderCreateStillUnknownV3(Some(evidence))
    Phase2ProviderMalformedSuccessV3 => ProviderCreateKnownSucceededV3(evidence)
    Phase2ProviderEvidenceTimeMismatchV3 =>
      ProviderCreateKnownSucceededV3(evidence)
    Phase2ProviderThrowsV3 =>
      raise RecoveryViolation(field="phase2_spy_provider_throw")
  }
}

///|
fn CurrentGovernedRecoveryProjectionV3::current_claim_by_ref_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  claim_ref : @contracts.RecordRef,
) -> DispatchClaimRecordV3? {
  first(self.claims, claim => claim.claim_ref == claim_ref)
}

///|
fn phase2_guarded_memory_fixture_v3(
  suffix : String,
  behavior : Phase2ProviderBehaviorV3,
  cancel_before_return? : Bool = false,
) -> (
  Phase1bPendingFixture,
  @storage.MemoryStore,
  @storage.GuardedMemoryStore,
  CurrentGovernedRecoveryProjectionV3,
  ProviderRecoveryProfileV3,
  Phase2GuardedProviderSpyV3,
) raise {
  let (fixture, store, work, governance) = phase2_active_pending_fixture(suffix)
  let current = fold_governed_recovery_v3(
    fixture.empty_effects,
    work,
    governance,
  )
  let profile = ProviderRecoveryProfileV3::new(
    "phase2-test-profile-" + suffix,
    true,
    true,
    true,
    true,
  )
  let activation = store.activate_guarded_workflow(
    fixture.registration.workflow(),
    [governance.workflow()],
  )
  let bound = @storage.GuardedMemoryStore::new(store, activation)
  let cancellation_before_return = if cancel_before_return {
    Some(
      current.authorize_claim_first_cancellation_v3(
        fixture.request.proposal,
        "phase2-spy-current-cancellation-authorization",
        "phase2-spy-current-cancellation-request",
      ),
    )
  } else {
    None
  }
  let spy = Phase2GuardedProviderSpyV3::{
    profile,
    store,
    empty_effects: fixture.empty_effects,
    work: fixture.registration.workflow(),
    governance: governance.workflow(),
    behavior,
    observed_at: 13L,
    cancellation_before_return,
    cancellation_committed: Ref(false),
    cancellation_error: Ref(""),
    calls: Ref(0),
    durable_at_entry: Ref(false),
  }
  (fixture, store, bound, current, profile, spy)
}

///|
fn phase2_append_same_capability_intent_v3(
  fixture : Phase1bPendingFixture,
  store : @storage.MemoryStore,
  bound : @storage.GuardedMemoryStore,
  current : CurrentGovernedRecoveryProjectionV3,
  suffix : String,
) -> @effects.EffectIntent raise {
  let evidence = [ for value in fixture.intent.evidence() => value ]
  let intent = @effects.EffectIntent::new(
    "phase2-shared-capability-intent-" + suffix,
    "1.0.0",
    fixture.attempt,
    fixture.intent.governance(),
    fixture.intent.effect_request(),
    evidence,
    "phase2-shared-capability-key-" + suffix,
    fixture.intent.capability_ref(),
    fixture.intent.capability_kind(),
    11L,
    fixture.attempt.attempt_ref(),
    current.current.work_head_digest,
    true,
    fencing?=fixture.intent.fencing(),
  )
  guard first(store.replay(fixture.registration.workflow()).events(), event => {
      event.payload().envelope_kind() == "effect.intent.requested.v1"
    })
    is Some(template) else {
    raise RecoveryViolation(field="phase2_shared_capability_template")
  }
  let event_id = "phase2-shared-capability-event-" + suffix
  let event_key = "effect-event/" + intent.external_idempotency_key()
  let envelope = @contracts.WireEnvelope::new(
    template.payload().contract_id(),
    template.payload().contract_version().text(),
    event_id,
    "effect.intent.requested.v1",
    fixture.intent.governance().governed_subject(),
    template.payload().schema(),
    intent.canonical_bytes(),
    template.payload().producer_id(),
    template.payload().producer_version().text(),
    [],
    evidence,
    run_ref=fixture.registration.workflow(),
    attempt_ref=fixture.attempt.attempt_ref(),
    correlation_ref=fixture.registration.workflow().id(),
    causation_ref=fixture.attempt.attempt_ref().id(),
    idempotency_ref=intent.external_idempotency_key(),
    previous_digest=current.current.work_head_digest,
  )
  let event = @storage.WorkflowEvent::new(
    template.record_version().text(),
    template.schema_version().text(),
    fixture.registration.workflow(),
    event_id,
    current.current.work_sequence + 1L,
    current.current.work_revision + 1L,
    event_key,
    envelope,
    evidence,
    previous_event_digest=current.current.work_head_digest,
  )
  let outbox = @storage.OutboxIntent::new(
    template.record_version().text(),
    template.schema_version().text(),
    "phase2-shared-capability-outbox-" + suffix,
    fixture.registration.workflow(),
    event.event_ref(),
    intent.external_idempotency_key(),
    intent.effect_request(),
    evidence,
  )
  let request = @storage.CommitRequest::new(
    template.record_version().text(),
    template.schema_version().text(),
    fixture.registration.workflow(),
    current.current.work_revision,
    "phase2-shared-capability-command-" + suffix,
    [event],
    [outbox],
  )
  let guarded = @storage.GuardedCommitRequest::new(request, [
    phase2_replay_head_guard(current.governance_replay),
  ])
  guard bound.guarded_commit(guarded) is @storage.GuardedCommitSucceeded(_) else {
    raise RecoveryViolation(field="phase2_shared_capability_commit")
  }
  intent
}

///|
fn phase2_preactivation_two_intent_fixture_v3(
  suffix : String,
) -> (
  Phase1bPendingFixture,
  @storage.MemoryStore,
  @storage.GuardedMemoryStore,
  CurrentGovernedRecoveryProjectionV3,
  @effects.EffectIntent,
) raise {
  let (fixture, store, work, governance) = phase2_leased_pending_fixture(suffix)
  let current = fold_governed_recovery_v3(
    fixture.empty_effects,
    work,
    governance,
  )
  let registration = store.activate_guarded_workflow(
    fixture.registration.workflow(),
    [governance.workflow()],
  )
  let bound = @storage.GuardedMemoryStore::new(store, registration)
  let second = phase2_append_same_capability_intent_v3(
    fixture, store, bound, current, suffix,
  )
  let two_intents = fold_governed_recovery_v3(
    fixture.empty_effects,
    store.replay(fixture.registration.workflow()),
    governance,
  )
  (fixture, store, bound, two_intents, second)
}

///|
fn phase2_commit_legacy_observation_before_activation_v3(
  fixture : Phase1bPendingFixture,
  store : @storage.MemoryStore,
  bound : @storage.GuardedMemoryStore,
  current : CurrentGovernedRecoveryProjectionV3,
  intent : @effects.EffectIntent,
  suffix : String,
) -> CurrentGovernedRecoveryProjectionV3 raise {
  let evidence = [ for value in intent.evidence() => value ]
  let observation = @effects.DispatchObservation::new(
    "phase2-preactivation-observation-" + suffix,
    intent,
    phase1b_test_envelope(
      "phase2-preactivation-observation-envelope-" + suffix,
      "dispatch-observation",
      intent.governance().governed_subject(),
      @utf8.encode("phase2-preactivation-observation-" + suffix),
      evidence,
    ),
    11L,
    evidence,
  )
  let open = current.current.open_work_authority()
  let dispatch = current.current.guarded_dispatch_authorization(
    open,
    intent.intent_ref(),
  )
  let guarded = phase1b_legacy_guarded_observation_fixture_v2(
    current.current,
    dispatch,
    observation,
  )
  let request = prepare_guarded_dispatch_observation_v2(
    current.current,
    guarded,
    "phase2-preactivation-observation-event-" + suffix,
    "phase2-preactivation-observation-command-" + suffix,
  )
  let guarded = @storage.GuardedCommitRequest::new(request, [
    phase2_replay_head_guard(current.governance_replay),
  ])
  guard bound.guarded_commit(guarded) is @storage.GuardedCommitSucceeded(_) else {
    raise RecoveryViolation(field="phase2_preactivation_observation_commit")
  }
  fold_governed_recovery_v3(
    fixture.empty_effects,
    store.replay(fixture.registration.workflow()),
    current.governance_replay,
  )
}

///|
fn phase2_commit_legacy_receipt_before_activation_v3(
  fixture : Phase1bPendingFixture,
  store : @storage.MemoryStore,
  bound : @storage.GuardedMemoryStore,
  current : CurrentGovernedRecoveryProjectionV3,
  intent : @effects.EffectIntent,
  outcome : @effects.ExternalOutcome,
  suffix : String,
) -> CurrentGovernedRecoveryProjectionV3 raise {
  let evidence = [ for value in intent.evidence() => value ]
  let receipt = @effects.EffectReceipt::new(
    "phase2-preactivation-receipt-" + suffix,
    "1.0.0",
    intent,
    phase1b_test_envelope(
      "phase2-preactivation-receipt-envelope-" + suffix,
      "dispatcher-receipt",
      intent.governance().governed_subject(),
      @utf8.encode("phase2-preactivation-receipt-" + suffix),
      evidence,
    ),
    outcome,
    12L,
    evidence,
    observed_fencing=intent.fencing().unwrap(),
  )
  let authority = current.current.inflight_resolution_authority(
    intent.intent_ref(),
    "receipt.record",
    receipt.receipt_ref(),
  )
  let request = prepare_guarded_effect_receipt_v2(
    current.current,
    authority,
    "phase2-preactivation-receipt-event-" + suffix,
    "phase2-preactivation-receipt-command-" + suffix,
    receipt,
  )
  let guarded = @storage.GuardedCommitRequest::new(request, [
    phase2_replay_head_guard(current.governance_replay),
  ])
  guard bound.guarded_commit(guarded) is @storage.GuardedCommitSucceeded(_) else {
    raise RecoveryViolation(field="phase2_preactivation_receipt_commit")
  }
  fold_governed_recovery_v3(
    fixture.empty_effects,
    store.replay(fixture.registration.workflow()),
    current.governance_replay,
  )
}

///|
fn phase2_inject_recovery_activation_v3(
  fixture : Phase1bPendingFixture,
  bound : @storage.GuardedMemoryStore,
  current : CurrentGovernedRecoveryProjectionV3,
  suffix : String,
) -> Unit raise {
  let target = current.current.work.effects.strict_recovery_target_v3(
    fixture.intent.intent_ref(),
  )
  let profile = ProviderRecoveryProfileV3::new(
    "phase2-preactivation-profile-" + suffix,
    true,
    true,
    true,
    true,
  )
  let event_id = "phase2-preactivation-activation-event-" + suffix
  let command_id = "phase2-preactivation-activation-command-" + suffix
  let activation = make_recovery_protocol_activated_v3(
    "phase2-preactivation-activation-" + suffix,
    current.work_replay.workflow(),
    fixture.intent.intent_ref(),
    target.governed_subject(),
    target.capability_ref(),
    target.capability_kind(),
    profile,
    event_id,
    command_id,
    13L,
    current.current.work_revision,
    current.current.work_head_digest,
    current.current.work_replay_digest,
    current.current.root_binding.governance_stream_ref(),
    current.current.governance_revision,
    current.current.governance_head_digest,
    current.current.governance_replay_digest,
    [
      for value in target.permitted_evidence() => value
    ],
  )
  let event = recovery_activation_event_v3(current.current, activation)
  let request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    current.work_replay.workflow(),
    current.current.work_revision,
    command_id,
    [event],
    [],
  )
  let guarded = @storage.GuardedCommitRequest::new(request, [
    phase2_replay_head_guard(current.governance_replay),
  ])
  guard bound.guarded_commit(guarded) is @storage.GuardedCommitSucceeded(_) else {
    raise RecoveryViolation(field="phase2_preactivation_activation_injection")
  }
}

///|
fn phase2_assert_terminal_sibling_rejects_activation_v3(
  suffix : String,
  outcome : @effects.ExternalOutcome,
  expected_state : @effects.ReconciliationState,
) -> Unit raise {
  let (fixture, store, bound, two_intents, second) = phase2_preactivation_two_intent_fixture_v3(
    suffix,
  )
  let observed = phase2_commit_legacy_observation_before_activation_v3(
    fixture, store, bound, two_intents, second, suffix,
  )
  let settled = phase2_commit_legacy_receipt_before_activation_v3(
    fixture, store, bound, observed, second, outcome, suffix,
  )
  assert_true(
    settled.current.work.effects
    .strict_intent_state_v2(second.intent_ref())
    .state() ==
    expected_state,
  )
  let profile = ProviderRecoveryProfileV3::new(
    "phase2-preactivation-profile-" + suffix,
    true,
    true,
    true,
    true,
  )
  try
    activate_recovery_protocol_v3(
      bound,
      settled,
      fixture.intent.intent_ref(),
      profile,
      "phase2-preactivation-activation-" + suffix,
      "phase2-preactivation-activation-event-" + suffix,
      "phase2-preactivation-activation-command-" + suffix,
      13L,
    )
  catch {
    RecoveryViolation(field="recovery_activation_v3_dirty_capability") => ()
    error =>
      fail("unexpected dirty terminal activation error: \{to_repr(error)}")
  } noraise {
    _ => fail("terminal V2 sibling crossed the V3 activation boundary")
  }
}

///|
fn phase2_raw_legacy_fact_request_v3(
  current : CurrentGovernedClosedLoopProjectionV2,
  event_id : String,
  event_kind : String,
  command_idempotency_key : String,
  target_ref : @contracts.RecordRef,
  payload_bytes : Bytes,
  intent : @effects.EffectIntent,
  evidence : Array[@contracts.EvidenceRef],
) -> @storage.GuardedCommitRequest raise {
  let payload = @contracts.WireEnvelope::new(
    "closed-loop.effects",
    "1.0.0",
    event_id,
    event_kind,
    intent.governance().governed_subject(),
    phase1b_effect_schema_v22(event_kind),
    payload_bytes,
    "effects-protocol",
    "1.0.0",
    [],
    evidence,
    run_ref=current.root_binding.workflow,
    attempt_ref=intent.attempt_ref(),
    correlation_ref=current.root_binding.workflow.id(),
    causation_ref=intent.intent_ref().id(),
    idempotency_ref=target_ref.id(),
    previous_digest=current.work_head_digest,
  )
  let event = @storage.WorkflowEvent::new(
    "1.0.0",
    "1.0.0",
    current.root_binding.workflow,
    event_id,
    current.work_sequence + 1L,
    current.work_revision + 1L,
    target_ref.id(),
    payload,
    evidence,
    previous_event_digest=current.work_head_digest,
  )
  let request = @storage.CommitRequest::new(
    "1.0.0",
    "1.0.0",
    current.root_binding.workflow,
    current.work_revision,
    command_idempotency_key,
    [event],
    [],
  )
  @storage.GuardedCommitRequest::new(request, [
    @storage.WorkflowHeadGuard::new(
      current.root_binding.governance_stream_ref(),
      current.governance_revision,
      current.governance_head_digest,
      current.governance_replay_digest,
    ),
  ])
}

///|
test "Phase2 V2 dispatch is retired before provider entry" {
  let fixture = phase1b_pending_fixture("v2-retired-spy")
  let calls = Ref(0)
  let observation = @effects.DispatchObservation::new(
    "phase2-v2-retired-observation",
    fixture.intent,
    phase1b_test_envelope(
      "phase2-v2-retired-envelope",
      "dispatch-observation",
      fixture.intent.governance().governed_subject(),
      b"must-not-run",
      [
        for value in fixture.intent.evidence() => value
      ],
    ),
    11L,
    [
      for value in fixture.intent.evidence() => value
    ],
  )
  let open = fixture.current.open_work_authority()
  let authorization = fixture.current.guarded_dispatch_authorization(
    open,
    fixture.intent.intent_ref(),
  )
  try
    dispatch_guarded_effect_v2(
      Phase1bDispatchPort::{ observation, calls },
      fixture.current,
      authorization,
    )
  catch {
    RecoveryViolation(field="guarded_dispatch_v2_retired_phase2") => ()
    error => fail("unexpected V2 retirement error: \{to_repr(error)}")
  } noraise {
    _ => fail("retired V2 dispatch reached its provider")
  }
  assert_eq(calls.val, 0)
}

///|
test "Phase2 guarded dispatch publishes claim and start before one provider call" {
  let (fixture, store, bound, current, _, spy) = phase2_guarded_memory_fixture_v3(
    "guarded-success",
    Phase2ProviderSucceedsV3,
  )
  let result = dispatch_guarded_effect_v3(
    bound,
    current,
    spy,
    fixture.intent.intent_ref(),
    "phase2-guarded-success-claim",
    "phase2-guarded-success-claim-event",
    "phase2-guarded-success-command",
    "phase2-guarded-success-observation-event",
    11L,
    12L,
    13L,
  )
  assert_true(
    result.disposition() ==
    GuardedDispatchProviderObservedV3(@effects.RecoveryKnownSucceededV3),
  )
  assert_true(result.observation_persisted())
  assert_eq(spy.calls.val, 1)
  assert_true(spy.durable_at_entry.val)
  let replayed = fold_governed_recovery_v3(
    fixture.empty_effects,
    store.replay(fixture.registration.workflow()),
    store.replay(current.governance_replay.workflow()),
  )
  assert_true(
    replayed.state_for(fixture.intent.intent_ref()) ==
    @effects.RecoveryKnownSuccessV3,
  )
}

///|
test "Phase2 invalid observation metadata commits no claim and calls no provider" {
  let (fixture, store, bound, current, _, spy) = phase2_guarded_memory_fixture_v3(
    "guarded-invalid-metadata",
    Phase2ProviderSucceedsV3,
  )
  let initial_revision = store
    .replay(fixture.registration.workflow())
    .head()
    .revision()
  try
    dispatch_guarded_effect_v3(
      bound,
      current,
      spy,
      fixture.intent.intent_ref(),
      "phase2-invalid-empty-claim",
      "phase2-invalid-empty-claim-event",
      "phase2-invalid-empty-command",
      "",
      11L,
      12L,
      13L,
    )
  catch {
    MalformedInput(field="dispatch_observation_v3_event_id") => ()
    error => fail("unexpected empty event-id error: \{to_repr(error)}")
  } noraise {
    _ => fail("empty observation event id published a claim")
  }
  try
    dispatch_guarded_effect_v3(
      bound,
      current,
      spy,
      fixture.intent.intent_ref(),
      "phase2-invalid-negative-claim",
      "phase2-invalid-negative-claim-event",
      "phase2-invalid-negative-command",
      "phase2-invalid-negative-observation",
      11L,
      12L,
      -1L,
    )
  catch {
    MalformedInput(field="dispatch_observation_v3_bounds") => ()
    error =>
      fail("unexpected negative observation-time error: \{to_repr(error)}")
  } noraise {
    _ => fail("negative observation time published a claim")
  }
  try
    dispatch_guarded_effect_v3(
      bound,
      current,
      spy,
      fixture.intent.intent_ref(),
      "phase2-invalid-preclaim-claim",
      "phase2-invalid-preclaim-claim-event",
      "phase2-invalid-preclaim-command",
      "phase2-invalid-preclaim-observation",
      11L,
      12L,
      10L,
    )
  catch {
    MalformedInput(field="dispatch_observation_v3_bounds") => ()
    error =>
      fail("unexpected pre-claim observation-time error: \{to_repr(error)}")
  } noraise {
    _ => fail("pre-claim observation time published a claim")
  }
  assert_eq(spy.calls.val, 0)
  assert_eq(
    store.replay(fixture.registration.workflow()).head().revision(),
    initial_revision,
  )
}

///|
test "Phase2 provider evidence time mismatch persists unknown" {
  let (fixture, store, bound, current, _, spy) = phase2_guarded_memory_fixture_v3(
    "guarded-evidence-time-mismatch",
    Phase2ProviderEvidenceTimeMismatchV3,
  )
  let result = dispatch_guarded_effect_v3(
    bound,
    current,
    spy,
    fixture.intent.intent_ref(),
    "phase2-evidence-time-mismatch-claim",
    "phase2-evidence-time-mismatch-claim-event",
    "phase2-evidence-time-mismatch-command",
    "phase2-evidence-time-mismatch-observation",
    11L,
    12L,
    13L,
  )
  assert_true(
    result.disposition() ==
    GuardedDispatchProviderObservedV3(@effects.RecoveryStillUnknownV3),
  )
  assert_true(result.provider_evidence() is None)
  assert_true(result.observation_persisted())
  assert_eq(spy.calls.val, 1)
  let replayed = fold_governed_recovery_v3(
    fixture.empty_effects,
    store.replay(fixture.registration.workflow()),
    store.replay(current.governance_replay.workflow()),
  )
  assert_true(
    replayed.state_for(fixture.intent.intent_ref()) ==
    @effects.RecoveryUnknownRequiresReconciliationV3,
  )
}

///|
test "Phase2 exact dispatch retry is query-only and never calls provider twice" {
  let (fixture, _, bound, current, _, spy) = phase2_guarded_memory_fixture_v3(
    "guarded-retry",
    Phase2ProviderSucceedsV3,
  )
  let first_result = dispatch_guarded_effect_v3(
    bound,
    current,
    spy,
    fixture.intent.intent_ref(),
    "phase2-guarded-retry-claim",
    "phase2-guarded-retry-claim-event",
    "phase2-guarded-retry-command",
    "phase2-guarded-retry-observation-event",
    11L,
    12L,
    13L,
  )
  assert_true(first_result.observation_persisted())
  let retry_result = dispatch_guarded_effect_v3(
    bound,
    current,
    spy,
    fixture.intent.intent_ref(),
    "phase2-guarded-retry-claim",
    "phase2-guarded-retry-claim-event",
    "phase2-guarded-retry-command",
    "phase2-guarded-retry-observation-event",
    11L,
    12L,
    13L,
  )
  assert_true(
    retry_result.disposition() == GuardedDispatchAlreadyCommittedQueryOnlyV3,
  )
  assert_eq(spy.calls.val, 1)
}

///|
test "Phase2 competing dispatch claim loses without a second provider call" {
  let (fixture, _, bound, current, _, spy) = phase2_guarded_memory_fixture_v3(
    "guarded-race",
    Phase2ProviderUnknownV3,
  )
  ignore(
    dispatch_guarded_effect_v3(
      bound,
      current,
      spy,
      fixture.intent.intent_ref(),
      "phase2-guarded-race-first-claim",
      "phase2-guarded-race-first-event",
      "phase2-guarded-race-first-command",
      "phase2-guarded-race-first-observation",
      11L,
      12L,
      13L,
    ),
  )
  let losing = dispatch_guarded_effect_v3(
    bound,
    current,
    spy,
    fixture.intent.intent_ref(),
    "phase2-guarded-race-second-claim",
    "phase2-guarded-race-second-event",
    "phase2-guarded-race-second-command",
    "phase2-guarded-race-second-observation",
    11L,
    12L,
    13L,
  )
  assert_true(losing.disposition() == GuardedDispatchRaceLostNoCallV3)
  assert_eq(spy.calls.val, 1)
}

///|
test "Phase2 malformed known provider evidence degrades to durable unknown" {
  let (fixture, store, bound, current, _, spy) = phase2_guarded_memory_fixture_v3(
    "guarded-malformed",
    Phase2ProviderMalformedSuccessV3,
  )
  let result = dispatch_guarded_effect_v3(
    bound,
    current,
    spy,
    fixture.intent.intent_ref(),
    "phase2-guarded-malformed-claim",
    "phase2-guarded-malformed-event",
    "phase2-guarded-malformed-command",
    "phase2-guarded-malformed-observation",
    11L,
    12L,
    13L,
  )
  assert_true(
    result.disposition() ==
    GuardedDispatchProviderObservedV3(@effects.RecoveryStillUnknownV3),
  )
  assert_true(result.provider_evidence() is None)
  let replayed = fold_governed_recovery_v3(
    fixture.empty_effects,
    store.replay(fixture.registration.workflow()),
    store.replay(current.governance_replay.workflow()),
  )
  assert_true(
    replayed.state_for(fixture.intent.intent_ref()) ==
    @effects.RecoveryUnknownRequiresReconciliationV3,
  )
}

///|
test "Phase2 provider throw becomes durable unknown without a second create" {
  let (fixture, store, bound, current, _, spy) = phase2_guarded_memory_fixture_v3(
    "guarded-throw",
    Phase2ProviderThrowsV3,
  )
  let result = dispatch_guarded_effect_v3(
    bound,
    current,
    spy,
    fixture.intent.intent_ref(),
    "phase2-guarded-throw-claim",
    "phase2-guarded-throw-event",
    "phase2-guarded-throw-command",
    "phase2-guarded-throw-observation",
    11L,
    12L,
    13L,
  )
  assert_true(
    result.disposition() ==
    GuardedDispatchProviderObservedV3(@effects.RecoveryStillUnknownV3),
  )
  assert_true(result.observation_persisted())
  assert_eq(spy.calls.val, 1)
  let replayed = fold_governed_recovery_v3(
    fixture.empty_effects,
    store.replay(fixture.registration.workflow()),
    store.replay(current.governance_replay.workflow()),
  )
  assert_true(
    replayed.state_for(fixture.intent.intent_ref()) ==
    @effects.RecoveryUnknownRequiresReconciliationV3,
  )
}

///|
test "Phase2 known failure and authoritative not-applied remain distinct" {
  for
    item in [
      (
        "guarded-known-failure",
        Phase2ProviderFailsV3,
        @effects.RecoveryKnownFailedV3,
        @effects.RecoveryKnownFailureV3,
      ),
      (
        "guarded-not-applied",
        Phase2ProviderNotAppliedV3,
        @effects.RecoveryStillUnknownV3,
        @effects.RecoveryUnknownRequiresReconciliationV3,
      ),
    ] {
    let (suffix, behavior, expected_outcome, expected_state) = item
    let (fixture, store, bound, current, _, spy) = phase2_guarded_memory_fixture_v3(
      suffix, behavior,
    )
    let result = dispatch_guarded_effect_v3(
      bound,
      current,
      spy,
      fixture.intent.intent_ref(),
      "phase2-" + suffix + "-claim",
      "phase2-" + suffix + "-claim-event",
      "phase2-" + suffix + "-command",
      "phase2-" + suffix + "-observation",
      11L,
      12L,
      13L,
    )
    assert_true(
      result.disposition() ==
      GuardedDispatchProviderObservedV3(expected_outcome),
    )
    assert_true(result.observation_persisted())
    let replayed = fold_governed_recovery_v3(
      fixture.empty_effects,
      store.replay(fixture.registration.workflow()),
      store.replay(current.governance_replay.workflow()),
    )
    assert_true(
      replayed.state_for(fixture.intent.intent_ref()) == expected_state,
    )
  }
}

///|
test "Phase2 strict replay rejects confirmed-not-applied in Slice 4" {
  let (fixture, store, bound, current, _, _) = phase2_guarded_memory_fixture_v3(
    "confirmed-not-applied-replay",
    Phase2ProviderNotAppliedV3,
  )
  let evidence = [
    for value in fixture.registration.schedule().evidence() => value
  ]
  let candidate = current.prepare_dispatch_claim_v3(
    fixture.intent.intent_ref(),
    "phase2-confirmed-not-applied-claim",
    "phase2-confirmed-not-applied-claim-event",
    "phase2-confirmed-not-applied-command",
    11L,
    12L,
    evidence,
  )
  guard commit_dispatch_claim_v3(bound, candidate)
    is DispatchClaimFreshlyCommittedV3(_) else {
    fail("confirmed-not-applied fixture claim did not commit")
  }
  let claimed_work = store.replay(fixture.registration.workflow())
  let claimed_governance = store.replay(current.governance_replay.workflow())
  let claimed = fold_governed_recovery_v3(
    fixture.empty_effects,
    claimed_work,
    claimed_governance,
  )
  if claimed.claims.length() != 1 || claimed.invocation_starts.length() != 1 {
    fail("confirmed-not-applied fixture claim/start missing")
  }
  let claim = claimed.claims[0]
  let started = claimed.invocation_starts[0]
  guard claimed_work.head().last_event_digest() is Some(work_head) else {
    fail("confirmed-not-applied fixture work head missing")
  }
  let provider_evidence = ProviderCreateEvidenceV3::new(
    "phase2-confirmed-not-applied-provider",
    "phase2-confirmed-not-applied-provider-event",
    ProviderTombstoneNotAppliedEvidenceV3,
    @contracts.sha256_digest(b"phase2-confirmed-not-applied-body"),
    claim.external_idempotency_key,
    claim.fencing_token,
    13L,
  )
  let observation = make_dispatch_observation_record_v3(
    claim,
    started,
    @effects.RecoveryConfirmedNotAppliedV3,
    Some(provider_evidence),
    "phase2-confirmed-not-applied-observation",
    13L,
    claimed_work.head().revision(),
    work_head,
    claimed_work.replay_digest(),
    claimed_governance,
  )
  let event = dispatch_observation_event_v3(observation)
  let request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    fixture.registration.workflow(),
    claimed_work.head().revision(),
    observation.command_idempotency_key,
    [event],
    [],
  )
  let guarded = @storage.GuardedCommitRequest::new(request, [
    phase2_replay_head_guard(claimed_governance),
  ])
  guard bound.guarded_commit(guarded) is @storage.GuardedCommitSucceeded(_) else {
    fail("confirmed-not-applied fixture observation did not commit")
  }
  try
    fold_governed_recovery_v3(
      fixture.empty_effects,
      store.replay(fixture.registration.workflow()),
      claimed_governance,
    )
  catch {
    ReplayBindingViolation(field="dispatch_observation_v3_not_applied_proof") =>
      ()
    error =>
      fail("unexpected confirmed-not-applied replay error: \{to_repr(error)}")
  } noraise {
    _ => fail("Slice 4 replay accepted confirmed-not-applied")
  }
}

///|
test "Phase2 observation uses fresh work head after pending cancellation" {
  let (fixture, store, bound, current, _, spy) = phase2_guarded_memory_fixture_v3(
    "observation-after-cancellation",
    Phase2ProviderSucceedsV3,
    cancel_before_return=true,
  )
  let result = dispatch_guarded_effect_v3(
    bound,
    current,
    spy,
    fixture.intent.intent_ref(),
    "phase2-observation-after-cancellation-claim",
    "phase2-observation-after-cancellation-claim-event",
    "phase2-observation-after-cancellation-command",
    "phase2-observation-after-cancellation-event",
    11L,
    12L,
    13L,
  )
  assert_true(result.observation_persisted())
  let replayed = fold_governed_recovery_v3(
    fixture.empty_effects,
    store.replay(fixture.registration.workflow()),
    store.replay(current.governance_replay.workflow()),
  )
  if replayed.current.work.cancellation is None {
    let kinds = [
      for event in store.replay(fixture.registration.workflow()).events() => {
        event.payload().envelope_kind()
      }
    ]
    fail(
      "pending cancellation missing from fresh-head replay: " +
      "\{to_repr(kinds)}; committed=\{spy.cancellation_committed.val}; error=\{spy.cancellation_error.val}",
    )
  }
  assert_true(
    replayed.state_for(fixture.intent.intent_ref()) ==
    @effects.RecoveryKnownSuccessV3,
  )
}

///|
test "Phase2 activated capability rejects a provider profile fork" {
  let (fixture, _, bound, current, _, _) = phase2_guarded_memory_fixture_v3(
    "profile-fork",
    Phase2ProviderUnknownV3,
  )
  let fork = ProviderRecoveryProfileV3::new(
    "phase2-test-profile-profile-fork-substituted", true, true, true, true,
  )
  try
    activate_recovery_protocol_v3(
      bound,
      current,
      fixture.intent.intent_ref(),
      fork,
      "phase2-profile-fork-activation",
      "phase2-profile-fork-event",
      "phase2-profile-fork-command",
      11L,
    )
  catch {
    RecoveryViolation(field="recovery_activation_v3_profile_fork") => ()
    error => fail("unexpected profile-fork error: \{to_repr(error)}")
  } noraise {
    _ => fail("activated capability accepted a provider profile fork")
  }
}

///|
test "Phase2 ownership survives and rejects every post-activation legacy fact" {
  let (fixture, store, bound, current, _, _) = phase2_guarded_memory_fixture_v3(
    "legacy-transition-exploit",
    Phase2ProviderUnknownV3,
  )
  let evidence = [ for value in fixture.intent.evidence() => value ]
  let observation = @effects.DispatchObservation::new(
    "phase2-legacy-exploit-observation",
    fixture.intent,
    phase1b_test_envelope(
      "phase2-legacy-exploit-observation-envelope",
      "dispatch-observation",
      fixture.intent.governance().governed_subject(),
      b"legacy-observation",
      evidence,
    ),
    11L,
    evidence,
  )
  let old_open = fixture.current.open_work_authority()
  let old_authorization = fixture.current.guarded_dispatch_authorization(
    old_open,
    fixture.intent.intent_ref(),
  )
  let legacy_observation = phase1b_legacy_guarded_observation_fixture_v2(
    fixture.current,
    old_authorization,
    observation,
  )
  try
    prepare_guarded_dispatch_observation_v2(
      current.current,
      legacy_observation,
      "phase2-legacy-exploit-public-event",
      "phase2-legacy-exploit-public-command",
    )
  catch {
    RecoveryViolation(field="legacy_effect_transition_retired_phase2") => ()
    error => fail("unexpected public legacy mutation error: \{to_repr(error)}")
  } noraise {
    _ =>
      fail("public V2 observation mutation remained available after activation")
  }
  try
    current.current.inflight_resolution_authority(
      fixture.intent.intent_ref(),
      "dispatch.observe",
      observation.observation_ref(),
    )
  catch {
    RecoveryViolation(field="legacy_effect_transition_retired_phase2") => ()
    error => fail("unexpected in-flight authority error: \{to_repr(error)}")
  } noraise {
    _ => fail("V3-owned intent minted a legacy in-flight authority")
  }

  let raw_observation = phase2_raw_legacy_fact_request_v3(
    current.current,
    "phase2-legacy-exploit-raw-observation-event",
    "effect.dispatch.observed.v1",
    "phase2-legacy-exploit-raw-observation-command",
    observation.observation_ref(),
    observation.canonical_bytes(),
    fixture.intent,
    evidence,
  )
  try store.commit(raw_observation.mutation()) catch {
    @storage.GuardedCommitRequired(_) => ()
    error => fail("unexpected raw host rejection: \{to_repr(error)}")
  } noraise {
    _ => fail("registered workflow accepted an unguarded legacy write")
  }
  guard bound.guarded_commit(raw_observation)
    is @storage.GuardedCommitSucceeded(_) else {
    fail("test exploit could not inject guarded legacy observation")
  }
  let observed_work = store.replay(fixture.registration.workflow())
  let strict_observed = @effects.fold_committed_effects_bytes(
    fixture.empty_effects,
    observed_work,
  )
  let observed_catalog = strict_observed.strict_recovery_intent_catalog_v3()
  assert_true(
    observed_catalog.any(identity => {
      identity.intent_ref() == fixture.intent.intent_ref() &&
      identity.capability_ref() == fixture.intent.capability_ref() &&
      identity.capability_kind() == fixture.intent.capability_kind()
    }),
  )
  try
    strict_observed.strict_recovery_target_v3(fixture.intent.intent_ref())
  catch {
    @effects.InvalidState(field="intent_not_dispatch_eligible") => ()
    error => fail("unexpected post-observation target error: \{to_repr(error)}")
  } noraise {
    _ => fail("legacy observation preserved V3 dispatch eligibility")
  }
  try
    fold_governed_recovery_v3(
      fixture.empty_effects,
      observed_work,
      store.replay(current.governance_replay.workflow()),
    )
  catch {
    RecoveryViolation(field="legacy_effect_transition_retired_phase2") => ()
    error => fail("unexpected V3 replay rejection: \{to_repr(error)}")
  } noraise {
    _ => fail("V3 replay accepted a post-activation legacy observation")
  }

  let observed_v2 = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    observed_work,
    store.replay(current.governance_replay.workflow()),
  )
  let receipt = @effects.EffectReceipt::new(
    "phase2-legacy-exploit-receipt",
    "1.0.0",
    fixture.intent,
    phase1b_test_envelope(
      "phase2-legacy-exploit-receipt-envelope",
      "effect-receipt",
      fixture.intent.governance().governed_subject(),
      b"legacy-receipt",
      evidence,
    ),
    @effects.Succeeded,
    12L,
    evidence,
    observed_fencing?=fixture.intent.fencing(),
  )
  let raw_receipt = phase2_raw_legacy_fact_request_v3(
    observed_v2,
    "phase2-legacy-exploit-raw-receipt-event",
    "effect.receipt.recorded.v1",
    "phase2-legacy-exploit-raw-receipt-command",
    receipt.receipt_ref(),
    receipt.canonical_bytes(),
    fixture.intent,
    evidence,
  )
  guard bound.guarded_commit(raw_receipt) is @storage.GuardedCommitSucceeded(_) else {
    fail("test exploit could not inject guarded legacy receipt")
  }
  let receipted_work = store.replay(fixture.registration.workflow())
  let strict_receipted = @effects.fold_committed_effects_bytes(
    fixture.empty_effects,
    receipted_work,
  )
  assert_true(
    strict_receipted
    .strict_recovery_intent_catalog_v3()
    .any(identity => identity.intent_ref() == fixture.intent.intent_ref()),
  )
  try
    fold_governed_recovery_v3(
      fixture.empty_effects,
      receipted_work,
      store.replay(current.governance_replay.workflow()),
    )
  catch {
    RecoveryViolation(field="legacy_effect_transition_retired_phase2") => ()
    error => fail("unexpected V3 terminal-source rejection: \{to_repr(error)}")
  } noraise {
    _ => fail("legacy receipt became a V3 terminal source")
  }
}

///|
test "Phase2 activated stream rejects legacy reconciliation and retry protocol" {
  let (_, _, _, current, _, _) = phase2_guarded_memory_fixture_v3(
    "legacy-protocol-gate",
    Phase2ProviderUnknownV3,
  )
  try current.current.require_legacy_effect_protocol_v2() catch {
    RecoveryViolation(field="legacy_effect_protocol_retired_phase2") => ()
    error => fail("unexpected legacy protocol gate error: \{to_repr(error)}")
  } noraise {
    _ => fail("activated stream retained legacy reconciliation/retry protocol")
  }
}

///|
test "Phase2 terminal remains closed until strict V3 settlement exists" {
  let (fixture, store, bound, current, _, spy) = phase2_guarded_memory_fixture_v3(
    "terminal-settlement-gate",
    Phase2ProviderSucceedsV3,
  )
  ignore(
    dispatch_guarded_effect_v3(
      bound,
      current,
      spy,
      fixture.intent.intent_ref(),
      "phase2-terminal-settlement-claim",
      "phase2-terminal-settlement-claim-event",
      "phase2-terminal-settlement-command",
      "phase2-terminal-settlement-observation",
      11L,
      12L,
      13L,
    ),
  )
  let replayed = fold_governed_recovery_v3(
    fixture.empty_effects,
    store.replay(fixture.registration.workflow()),
    store.replay(current.governance_replay.workflow()),
  )
  assert_true(
    replayed.state_for(fixture.intent.intent_ref()) ==
    @effects.RecoveryKnownSuccessV3,
  )
  try replayed.require_work_terminal_ready_v3() catch {
    RecoveryViolation(field="work_terminal_requires_v3_settlement") => ()
    error => fail("unexpected V3 settlement gate error: \{to_repr(error)}")
  } noraise {
    _ => fail("known V3 outcome terminalized through a legacy source")
  }
  assert_true(
    recovery_state_blocks_work_terminal_v3(@effects.RecoveryExhaustedV3),
  )
}

///|
test "Phase2 activation owns every eligible intent sharing its capability" {
  let (fixture, store, bound, current, _, _) = phase2_guarded_memory_fixture_v3(
    "shared-capability",
    Phase2ProviderSucceedsV3,
  )
  let second = phase2_append_same_capability_intent_v3(
    fixture, store, bound, current, "shared-capability",
  )
  let two_intents = fold_governed_recovery_v3(
    fixture.empty_effects,
    store.replay(fixture.registration.workflow()),
    store.replay(current.governance_replay.workflow()),
  )
  let profile = ProviderRecoveryProfileV3::new(
    "phase2-test-profile-shared-capability", true, true, true, true,
  )
  let spy = Phase2GuardedProviderSpyV3::{
    profile,
    store,
    empty_effects: fixture.empty_effects,
    work: fixture.registration.workflow(),
    governance: current.governance_replay.workflow(),
    behavior: Phase2ProviderSucceedsV3,
    observed_at: 13L,
    cancellation_before_return: None,
    cancellation_committed: Ref(false),
    cancellation_error: Ref(""),
    calls: Ref(0),
    durable_at_entry: Ref(false),
  }
  ignore(
    dispatch_guarded_effect_v3(
      bound,
      two_intents,
      spy,
      fixture.intent.intent_ref(),
      "phase2-shared-capability-claim",
      "phase2-shared-capability-claim-event",
      "phase2-shared-capability-dispatch-command",
      "phase2-shared-capability-observation",
      11L,
      12L,
      13L,
    ),
  )
  let replayed = fold_governed_recovery_v3(
    fixture.empty_effects,
    store.replay(fixture.registration.workflow()),
    store.replay(current.governance_replay.workflow()),
  )
  assert_true(
    replayed.state_for(fixture.intent.intent_ref()) ==
    @effects.RecoveryKnownSuccessV3,
  )
  assert_true(
    replayed.state_for(second.intent_ref()) ==
    @effects.RecoveryDispatchEligibleV3,
  )
  assert_eq(replayed.v3_owned_intent_refs().length(), 2)
  try replayed.require_work_terminal_ready_v3() catch {
    RecoveryViolation(field="work_terminal_requires_recovery_v3") => ()
    error =>
      fail("unexpected shared-capability terminal error: \{to_repr(error)}")
  } noraise {
    _ => fail("second shared-capability intent bypassed the terminal gate")
  }
  let second_evidence = [ for value in second.evidence() => value ]
  let legacy_second = @effects.DispatchObservation::new(
    "phase2-shared-capability-legacy-observation",
    second,
    phase1b_test_envelope(
      "phase2-shared-capability-legacy-envelope",
      "dispatch-observation",
      second.governance().governed_subject(),
      b"shared-capability-legacy-observation",
      second_evidence,
    ),
    14L,
    second_evidence,
  )
  let raw_second = phase2_raw_legacy_fact_request_v3(
    replayed.current,
    "phase2-shared-capability-legacy-event",
    "effect.dispatch.observed.v1",
    "phase2-shared-capability-legacy-command",
    legacy_second.observation_ref(),
    legacy_second.canonical_bytes(),
    second,
    second_evidence,
  )
  guard bound.guarded_commit(raw_second) is @storage.GuardedCommitSucceeded(_) else {
    fail("test exploit could not transition shared capability through V2")
  }
  let transitioned_work = store.replay(fixture.registration.workflow())
  let strict_transitioned = @effects.fold_committed_effects_bytes(
    fixture.empty_effects,
    transitioned_work,
  )
  assert_eq(strict_transitioned.strict_recovery_intent_catalog_v3().length(), 2)
  try strict_transitioned.strict_recovery_target_v3(second.intent_ref()) catch {
    @effects.InvalidState(field="intent_not_dispatch_eligible") => ()
    error => fail("unexpected shared-capability state error: \{to_repr(error)}")
  } noraise {
    _ => fail("legacy transition left shared intent dispatch eligible")
  }
  try
    fold_governed_recovery_v3(
      fixture.empty_effects,
      transitioned_work,
      store.replay(current.governance_replay.workflow()),
    )
  catch {
    RecoveryViolation(field="legacy_effect_transition_retired_phase2") => ()
    error =>
      fail("unexpected shared-capability replay error: \{to_repr(error)}")
  } noraise {
    _ => fail("shared-capability ownership vanished after V2 state transition")
  }
}

///|
test "Phase2 activation rejects a pending same-capability V2 intent without mutation" {
  let (fixture, store, bound, two_intents, second) = phase2_preactivation_two_intent_fixture_v3(
    "dirty-pending",
  )
  let observed = phase2_commit_legacy_observation_before_activation_v3(
    fixture, store, bound, two_intents, second, "dirty-pending",
  )
  assert_true(
    observed.current.work.effects
    .strict_intent_state_v2(second.intent_ref())
    .state() ==
    @effects.DispatchObservationPending,
  )
  let before = store.replay(fixture.registration.workflow())
  let profile = ProviderRecoveryProfileV3::new(
    "phase2-preactivation-profile-dirty-pending", true, true, true, true,
  )
  try
    activate_recovery_protocol_v3(
      bound,
      observed,
      fixture.intent.intent_ref(),
      profile,
      "phase2-preactivation-activation-dirty-pending",
      "phase2-preactivation-activation-event-dirty-pending",
      "phase2-preactivation-activation-command-dirty-pending",
      13L,
    )
  catch {
    RecoveryViolation(field="recovery_activation_v3_dirty_capability") => ()
    error => fail("unexpected dirty activation error: \{to_repr(error)}")
  } noraise {
    _ => fail("pending V2 sibling crossed the V3 activation boundary")
  }
  let after = store.replay(fixture.registration.workflow())
  assert_eq(after.head().revision(), before.head().revision())
  assert_true(
    after.head().last_event_digest() == before.head().last_event_digest(),
  )
  assert_true(after.replay_digest() == before.replay_digest())
  assert_eq(after.events().length(), before.events().length())

  // A rejected activation publishes nothing and therefore cannot retire the
  // sibling's ordinary preactivation V2 resolution path.
  let evidence = [ for value in second.evidence() => value ]
  let receipt = @effects.EffectReceipt::new(
    "phase2-preactivation-still-v2-receipt",
    "1.0.0",
    second,
    phase1b_test_envelope(
      "phase2-preactivation-still-v2-receipt-envelope",
      "dispatcher-receipt",
      second.governance().governed_subject(),
      b"phase2-preactivation-still-v2-receipt",
      evidence,
    ),
    @effects.Succeeded,
    14L,
    evidence,
    observed_fencing=second.fencing().unwrap(),
  )
  let authority = observed.current.inflight_resolution_authority(
    second.intent_ref(),
    "receipt.record",
    receipt.receipt_ref(),
  )
  let prepared = prepare_guarded_effect_receipt_v2(
    observed.current,
    authority,
    "phase2-preactivation-still-v2-receipt-event",
    "phase2-preactivation-still-v2-receipt-command",
    receipt,
  )
  assert_eq(prepared.events().length(), 1)
  assert_eq(prepared.intents().length(), 0)
}

///|
test "Phase2 strict replay rejects an injected dirty capability activation" {
  let (fixture, store, bound, two_intents, second) = phase2_preactivation_two_intent_fixture_v3(
    "dirty-injected",
  )
  let observed = phase2_commit_legacy_observation_before_activation_v3(
    fixture, store, bound, two_intents, second, "dirty-injected",
  )
  phase2_inject_recovery_activation_v3(
    fixture, bound, observed, "dirty-injected",
  )
  try
    fold_governed_recovery_v3(
      fixture.empty_effects,
      store.replay(fixture.registration.workflow()),
      observed.governance_replay,
    )
  catch {
    ReplayBindingViolation(field="recovery_activation_v3_dirty_capability") =>
      ()
    error => fail("unexpected injected activation error: \{to_repr(error)}")
  } noraise {
    _ => fail("strict replay accepted an injected dirty capability activation")
  }
}

///|
test "Phase2 activation rejects known V2 outcomes on the same capability" {
  phase2_assert_terminal_sibling_rejects_activation_v3(
    "dirty-known-success",
    @effects.Succeeded,
    @effects.KnownSuccess,
  )
  phase2_assert_terminal_sibling_rejects_activation_v3(
    "dirty-known-failure",
    @effects.Failed,
    @effects.KnownFailure,
  )
}

///|
test "Phase2 clean capability activation owns its cohort and future intents" {
  let (fixture, store, bound, two_intents, second) = phase2_preactivation_two_intent_fixture_v3(
    "clean-boundary",
  )
  let profile = ProviderRecoveryProfileV3::new(
    "phase2-preactivation-profile-clean-boundary", true, true, true, true,
  )
  guard activate_recovery_protocol_v3(
      bound,
      two_intents,
      fixture.intent.intent_ref(),
      profile,
      "phase2-preactivation-activation-clean-boundary",
      "phase2-preactivation-activation-event-clean-boundary",
      "phase2-preactivation-activation-command-clean-boundary",
      13L,
    )
    is RecoveryProtocolActivationFreshV3 else {
    fail("clean same-capability cohort did not activate")
  }
  let activated = fold_governed_recovery_v3(
    fixture.empty_effects,
    store.replay(fixture.registration.workflow()),
    two_intents.governance_replay,
  )
  assert_eq(activated.v3_owned_intent_refs().length(), 2)
  assert_true(
    activated
    .v3_owned_intent_refs()
    .any(value => value == fixture.intent.intent_ref()),
  )
  assert_true(
    activated.v3_owned_intent_refs().any(value => value == second.intent_ref()),
  )
  let future = phase2_append_same_capability_intent_v3(
    fixture, store, bound, activated, "clean-boundary-future",
  )
  let replayed = fold_governed_recovery_v3(
    fixture.empty_effects,
    store.replay(fixture.registration.workflow()),
    two_intents.governance_replay,
  )
  assert_eq(replayed.v3_owned_intent_refs().length(), 3)
  assert_true(
    replayed.v3_owned_intent_refs().any(value => value == future.intent_ref()),
  )
  assert_true(
    replayed.state_for(second.intent_ref()) ==
    @effects.RecoveryDispatchEligibleV3,
  )
  assert_true(
    replayed.state_for(future.intent_ref()) ==
    @effects.RecoveryDispatchEligibleV3,
  )
}
