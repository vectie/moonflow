///|
fn flow7_aggregate_admission_at_position(
  prefix : String,
  workflow : @contracts.RecordRef,
  position : @effects_authorization.ReplayPosition,
  clock : Int64,
  deadline : Int64,
  policy : @contracts.RecordRef,
  planned : @effects_authorization.PlannedEffectTuple,
  evidence : @contracts.EvidenceRef,
  lease_epoch? : Int64 = 1L,
  fencing_token? : Int64 = 1L,
) -> AdmissionV2 raise OrchestrationError {
  if planned.workflow() != workflow {
    raise WorkflowMismatch(field="aggregate_fixture_workflow")
  }
  let producer_ref = flow7_v2_ref(
    "producer",
    prefix + "-producer",
    @utf8.encode(prefix + "-producer"),
  )
  let producer = @effects_authorization.ProducerDescriptor::new(
    "fixture.aggregate",
    "1.0.0",
    producer_ref,
    producer_ref.digest(),
  ).unwrap()
  let decision = flow7_v2_ref(
    "decision",
    prefix + "-decision",
    @utf8.encode(prefix + "-decision"),
  )
  let governance = @effects_authorization.AuthorizationGovernanceBinding::new(
    decision,
    decision.digest(),
    policy,
    policy.digest(),
    planned.subject(),
    0L,
    deadline,
  ).unwrap()
  let eligibility = @effects_authorization.EligibilityBinding::new(
    clock, position,
  ).unwrap()
  let evidence_binding = @effects_authorization.EvidenceBinding::new(
    evidence.record(),
    evidence.observed_digest(),
  ).unwrap()
  let capability_ref = flow7_v2_ref(
    "capability",
    prefix + "-capability",
    @utf8.encode(prefix + "-capability"),
  )
  let capability = @effects_authorization.CapabilityBinding::new(
    capability_ref,
    capability_ref.digest(),
  ).unwrap()
  let fencing_ref = flow7_v2_ref(
    "fencing",
    prefix + "-fencing",
    @utf8.encode(prefix + "-fencing"),
  )
  let fencing = @effects_authorization.FencingBinding::new(
    fencing_ref, lease_epoch, fencing_token,
  ).unwrap()
  let controls = @effects_authorization.AuthorizationControls::new(
    Some(capability),
    [evidence_binding],
    Some(fencing),
    Some(clock),
    deadline,
  ).unwrap()
  let authorization = @effects_authorization.PreDispatchAuthorization::new(
    prefix + "-authorization",
    producer,
    governance,
    eligibility,
    planned,
    controls,
  ).unwrap()
  let e0 = flow7_v2_envelope(
    prefix + "-authorization-event",
    @effects_authorization.AuthorizationEventKindV2::pre_dispatch_authorization_committed(),
    authorization.record_ref(),
    authorization.canonical_bytes(),
    0L,
    @effects_authorization.authorization_event_genesis_digest_v2,
  )
  let p0 = @effects_authorization.ReplayPosition::new(
    e0.event_ref(),
    0L,
    0L,
    e0.event_digest(),
  ).unwrap()
  let auth_link = @effects_authorization.AuthorizationLink::new(
    authorization.record_ref(),
    authorization.record_digest(),
    p0,
  ).unwrap()
  let attempt = @effects_authorization.AuthorizedAttemptRegistration::new(
    prefix + "-attempt",
    auth_link,
    producer,
    governance,
    eligibility,
    planned,
    controls,
  ).unwrap()
  let e1 = flow7_v2_envelope(
    prefix + "-attempt-event",
    @effects_authorization.AuthorizationEventKindV2::authorized_attempt_registration_committed(),
    attempt.record_ref(),
    attempt.canonical_bytes(),
    1L,
    e0.event_digest(),
  )
  let p1 = @effects_authorization.ReplayPosition::new(
    e1.event_ref(),
    1L,
    1L,
    e1.event_digest(),
  ).unwrap()
  let attempt_link = @effects_authorization.AttemptLink::new(
    attempt.record_ref(),
    attempt.record_digest(),
    p1,
  ).unwrap()
  let intent = @effects_authorization.AuthorizedEffectIntent::new(
    prefix + "-intent",
    auth_link,
    attempt_link,
    producer,
    governance,
    eligibility,
    planned,
    controls,
  ).unwrap()
  let e2 = flow7_v2_envelope(
    prefix + "-intent-event",
    @effects_authorization.AuthorizationEventKindV2::authorized_effect_intent_committed(),
    intent.record_ref(),
    intent.canonical_bytes(),
    2L,
    e1.event_digest(),
  )
  let store = @effects_authorization.AuthorizationEventStoreV2::new()
  ignore(store.append(e0).unwrap())
  ignore(store.append(e1).unwrap())
  ignore(store.append(e2).unwrap())
  let commit = @effects_authorization.derive_eligible_authorization_proof_commit_v2(
    store,
    prefix + "-proof",
    prefix + "-proof-event",
  ).unwrap()
  AdmissionV2::decode(prefix + "-proof", commit.proof().canonical_bytes())
}

///|
fn flow7_aggregate_admission(
  prefix : String,
  workflow : @contracts.RecordRef,
  head : @storage.WorkflowEvent,
  clock : Int64,
  deadline : Int64,
  policy : @contracts.RecordRef,
  planned : @effects_authorization.PlannedEffectTuple,
  evidence : @contracts.EvidenceRef,
  lease_epoch? : Int64 = 1L,
  fencing_token? : Int64 = 1L,
) -> AdmissionV2 raise OrchestrationError {
  let position = @effects_authorization.ReplayPosition::new(
    head.event_ref(),
    head.sequence(),
    head.revision(),
    head.event_ref().digest(),
  ).unwrap()
  flow7_aggregate_admission_at_position(
    prefix,
    workflow,
    position,
    clock,
    deadline,
    policy,
    planned,
    evidence,
    lease_epoch~,
    fencing_token~,
  )
}

///|
fn flow7_aggregate_genesis_admission(
  prefix : String,
  workflow : @contracts.RecordRef,
  clock : Int64,
  deadline : Int64,
  policy : @contracts.RecordRef,
  planned : @effects_authorization.PlannedEffectTuple,
  evidence : @contracts.EvidenceRef,
) -> AdmissionV2 raise OrchestrationError {
  flow7_aggregate_admission_at_position(
    prefix,
    workflow,
    orchestration_genesis_position_v2(workflow),
    clock,
    deadline,
    policy,
    planned,
    evidence,
  )
}

///|
fn flow7_aggregate_planned(
  workflow : @contracts.RecordRef,
  subject : @contracts.RecordRef,
  requested : @contracts.RecordRef,
  requested_digest : @contracts.ContentDigest,
  ordinal : Int64,
  key : String,
  effect_request_ref : @contracts.RecordRef,
) -> @effects_authorization.PlannedEffectTuple {
  @effects_authorization.PlannedEffectTuple::new(
    workflow,
    subject,
    "attempt",
    "1.0.0",
    "effect",
    "1.0.0",
    ordinal,
    key,
    requested,
    requested_digest,
    effect_request_ref,
    effect_request_ref.digest(),
    @contracts.sha256_digest(@utf8.encode(key + "-artifact")),
  ).unwrap()
}

///|
priv struct Flow7RootBoundFixture {
  fixture : OrchestrationFixture
  empty_effects : @effects.EffectsProjection
  schedule : ScheduleIntentV2
  registration : ScheduleRegisteredV2
  schedule_event : @storage.WorkflowEvent
}

///|
fn flow7_root_bound_strict_fixture(
  suffix : String,
) -> Flow7RootBoundFixture raise {
  let policy = flow7_v2_governance_policy()
  let workflow = flow7_v2_ref(
    "workflow",
    suffix + "-root-workflow",
    @utf8.encode(suffix + "-root-workflow"),
  )
  let subject = fixture_ref("subject", "governed-" + suffix)
  let evidence = flow7_v2_evidence()
  let requested = flow7_v2_ref(
    "requested-work",
    suffix + "-root-requested",
    @utf8.encode(suffix + "-root-requested"),
  )
  let effect = flow7_v2_ref(
    "effect-request",
    suffix + "-root-effect",
    @utf8.encode(suffix + "-root-effect"),
  )
  let admission = flow7_aggregate_genesis_admission(
    suffix + "-root",
    workflow,
    10L,
    1000L,
    policy.policy_ref(),
    flow7_aggregate_planned(
      workflow,
      subject,
      requested,
      requested.digest(),
      1L,
      suffix + "-root-key",
      effect,
    ),
    evidence,
  )
  let schedule = ScheduleIntentV2::new(
    suffix + "-root-schedule",
    "2.0.0",
    admission,
    workflow,
    10L,
    Some(1000L),
    [evidence],
    flow7_v2_ref(
      "causation",
      suffix + "-root-schedule",
      @utf8.encode(suffix + "-root-schedule"),
    ),
    suffix + "-root-schedule-key",
  )
  let registration = ScheduleRegisteredV2::new(
    suffix + "-root-registration",
    schedule,
  )
  let fixture = orchestration_fixture_with_governance_version(
    suffix,
    true,
    workflow_override=workflow,
    policy_override=policy,
    authority_kind="authority",
    reviewer_kind="reviewer",
    root_registration=registration,
  )
  let empty_effects = @effects.EffectsProjection::new(
    workflow,
    policy.policy_ref(),
  )
  let schedule_event = fixture.store.replay(workflow).events()[0]
  if schedule_event.payload().envelope_kind() != "schedule.registered.v2" ||
    schedule_event.payload().subject() != registration.record_ref() {
    raise OrchestrationError::ReplayBindingViolation(
      field="fixture_root_schedule_event",
    )
  }
  { fixture, empty_effects, schedule, registration, schedule_event }
}

///|
fn flow7_assert_retry_planned_mutation_rejected(
  suffix : String,
  expected_field : String,
  aggregate : ClosedLoopProjectionV2,
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
  policy : RetryPolicyV2,
  request : @retry_authority.RetryScheduleRequestV2,
  governance : @effects.GovernanceBinding,
  requested_work : @contracts.WireEnvelope,
  evidence : @contracts.EvidenceRef,
  planned : @effects_authorization.PlannedEffectTuple,
) -> Unit raise {
  let admission = flow7_aggregate_admission(
    suffix,
    request.workflow(),
    aggregate.prefix_event().unwrap(),
    request.due_at(),
    1000L,
    governance.policy_ref(),
    planned,
    evidence,
  )
  try
    prepare_atomic_retry_v2(
      aggregate,
      receipt,
      policy,
      request,
      admission,
      governance,
      suffix + "-plan",
      request.child_attempt_id(),
      suffix + "-attempt-event",
      request.child_attempt_idempotency_key(),
      requested_work,
      [evidence],
      receipt.source_observed_at(),
      request.schedule_id(),
      request.schedule_idempotency_key(),
      request.requested_schedule_deadline(),
      suffix + "-schedule-event",
      suffix + "-registration",
      request.command_idempotency_key(),
    )
  catch {
    OrchestrationError::EffectProofMismatch(field~) =>
      assert_eq(field, expected_field)
    _ => fail("unexpected planned-tuple mutation rejection: " + suffix)
  } noraise {
    _ => fail("accepted mutated planned tuple: " + suffix)
  }
}

///|
fn flow7_replay_with_extra_outbox(
  replay : @storage.ReplayResult,
) -> @storage.ReplayResult raise {
  let store = @storage.MemoryStore::new()
  let mut injected = false
  for batch in replay.committed_batches() {
    let events : Array[@storage.WorkflowEvent] = []
    for event_ref in batch.event_refs() {
      let index = replay
        .events()
        .search_by(event => event.event_ref() == event_ref)
        .unwrap()
      events.push(replay.events()[index])
    }
    let intents : Array[@storage.OutboxIntent] = []
    for intent_ref in batch.intent_refs() {
      let index = replay
        .intents()
        .search_by(intent => intent.intent_ref() == intent_ref)
        .unwrap()
      intents.push(replay.intents()[index])
    }
    if !injected && !intents.is_empty() {
      let original = intents[0]
      intents.push(
        @storage.OutboxIntent::new(
          "1.0.0",
          "1.0.0",
          "aggregate-corrupt-extra-outbox",
          replay.workflow(),
          original.causative_event(),
          "aggregate-corrupt-extra-outbox-key",
          original.payload(),
          [
            for value in original.evidence() => value
          ],
        ),
      )
      injected = true
    }
    ignore(
      store.commit(
        @storage.CommitRequest::new(
          "1.0.0",
          "1.0.0",
          replay.workflow(),
          batch.expected_revision(),
          batch.command_idempotency_key(),
          events,
          intents,
        ),
      ),
    )
  }
  if !injected {
    raise OrchestrationError::ReplayBindingViolation(
      field="aggregate_extra_outbox_fixture",
    )
  }
  store.replay(replay.workflow())
}

///|
fn flow7_replay_with_split_outbox(
  replay : @storage.ReplayResult,
) -> @storage.ReplayResult raise {
  let store = @storage.MemoryStore::new()
  let mut held : @storage.OutboxIntent? = None
  let mut split = false
  for batch in replay.committed_batches() {
    let events : Array[@storage.WorkflowEvent] = []
    for event_ref in batch.event_refs() {
      let index = replay
        .events()
        .search_by(event => event.event_ref() == event_ref)
        .unwrap()
      events.push(replay.events()[index])
    }
    let intents : Array[@storage.OutboxIntent] = []
    for intent_ref in batch.intent_refs() {
      let index = replay
        .intents()
        .search_by(intent => intent.intent_ref() == intent_ref)
        .unwrap()
      if !split && held is None {
        held = Some(replay.intents()[index])
        split = true
      } else {
        intents.push(replay.intents()[index])
      }
    }
    if split && held is Some(value) && batch.intent_refs().is_empty() {
      intents.push(value)
      held = None
    }
    ignore(
      store.commit(
        @storage.CommitRequest::new(
          "1.0.0",
          "1.0.0",
          replay.workflow(),
          batch.expected_revision(),
          batch.command_idempotency_key(),
          events,
          intents,
        ),
      ),
    )
  }
  if held is Some(value) {
    let head = store.replay(replay.workflow()).events().last().unwrap()
    let dummy_subject = flow7_v2_ref(
      "schedule-registration-v2", "aggregate-split-outbox-dummy-subject", b"aggregate-split-outbox-dummy-subject",
    )
    let dummy = flow7_durable_test_event(
      "aggregate-split-outbox-dummy-event",
      "aggregate-split-outbox-dummy-key",
      replay.workflow(),
      "schedule.registered.v2",
      dummy_subject,
      b"aggregate-split-outbox-dummy-payload",
      [],
      head.event_ref(),
      head.sequence() + 1L,
      head.revision() + 1L,
      Some(head.event_ref().digest()),
    )
    ignore(
      store.commit(
        @storage.CommitRequest::new(
          "1.0.0",
          "1.0.0",
          replay.workflow(),
          head.revision(),
          "aggregate-split-outbox-dummy-command",
          [dummy],
          [value],
        ),
      ),
    )
    held = None
  }
  if !split || held is Some(_) {
    raise OrchestrationError::ReplayBindingViolation(
      field="aggregate_split_outbox_fixture",
    )
  }
  store.replay(replay.workflow())
}

///|
struct Flow7RetryReadyFixture {
  fixture : OrchestrationFixture
  empty_effects : @effects.EffectsProjection
  aggregate : ClosedLoopProjectionV2
  receipt : @effects.CommittedRetryEligibilityReceiptV2
  observation : @effects.DispatchObservation
  effect_receipt : @effects.EffectReceipt
}

///|
fn flow7_retry_ready_fixture(
  suffix : String,
  reconciled_not_applied : Bool,
) -> Flow7RetryReadyFixture raise {
  let root = flow7_root_bound_strict_fixture(suffix)
  let fixture = root.fixture
  let empty_effects = root.empty_effects
  let evidence = flow7_v2_evidence()
  let initial_admission = root.schedule.admission()
  let schedule = root.schedule
  let registration = root.registration
  let schedule_event = root.schedule_event
  let scheduled = fold_closed_loop_v2(
    empty_effects,
    fixture.store.replay(fixture.workflow),
  )
  let claim = LeaseClaimV2::new(
    suffix + "-claim",
    schedule,
    initial_admission,
    fixture.workflow,
    flow7_v2_ref("owner", suffix + "-owner", @utf8.encode(suffix + "-owner")),
    10L,
    0L,
    0L,
    1L,
    1L,
    suffix + "-claim-key",
    [evidence],
    schedule_event.event_ref(),
  )
  let claimed = LeaseClaimedV2::new(suffix + "-claimed", registration, claim)
  ignore(
    fixture.store.commit(
      prepare_lease_claimed_v2(
        scheduled.orchestration(),
        suffix + "-claim-event",
        claim.idempotency_key(),
        suffix + "-claim-command",
        claimed,
      ),
    ),
  )
  let claimed_aggregate = fold_closed_loop_v2(
    empty_effects,
    fixture.store.replay(fixture.workflow),
  )
  let lease_receipt = claimed_aggregate
    .orchestration()
    .committed_lease_authority_receipt()
    .unwrap()
  let release = LeaseReleaseV2::new(
    suffix + "-release",
    registration,
    lease_receipt,
    flow7_lifecycle_active_authorization(
      suffix + "-release",
      claimed_aggregate.orchestration(),
      registration,
      lease_receipt,
      ReleaseLeaseV2,
      None,
      12L,
    ),
  )
  ignore(
    fixture.store.commit(
      prepare_lease_released_v2(
        claimed_aggregate.orchestration(),
        suffix + "-release-event",
        release.idempotency_key(),
        suffix + "-release-command",
        release,
      ),
    ),
  )
  let released_effects = @effects.fold_authoritative_replay(
    empty_effects,
    fixture.store.replay(fixture.workflow),
    @effects.ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [],
      [],
      [],
      [],
    ),
  )
  let observation = @effects.DispatchObservation::new(
    suffix + "-observation",
    fixture.intent,
    fixture_envelope(
      suffix + "-observation-envelope",
      "dispatch-observation",
      fixture.intent.governance().governed_subject(),
      @utf8.encode(suffix + "-observation"),
    ),
    71L,
    [],
  )
  ignore(
    fixture.store.commit(
      fixture_prepare_dispatch_observation_commit(
        released_effects,
        suffix + "-observation-event",
        suffix + "-observation-command",
        observation,
      ),
    ),
  )
  let observed_effects = @effects.fold_authoritative_replay(
    empty_effects,
    fixture.store.replay(fixture.workflow),
    @effects.ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [observation],
      [],
      [],
      [],
    ),
  )
  let outcome : @effects.ExternalOutcome = if reconciled_not_applied {
    @effects.Unknown
  } else {
    @effects.Failed
  }
  let effect_receipt = @effects.EffectReceipt::new(
    suffix + "-effect-receipt",
    "1.0.0",
    fixture.intent,
    fixture_envelope(
      suffix + "-effect-receipt-envelope",
      "dispatcher-receipt",
      fixture.intent.governance().governed_subject(),
      @utf8.encode(suffix + "-effect-receipt"),
    ),
    outcome,
    72L,
    [],
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  ignore(
    fixture.store.commit(
      fixture_prepare_effect_receipt_commit(
        observed_effects,
        suffix + "-effect-receipt-event",
        suffix + "-effect-receipt-command",
        effect_receipt,
      ),
    ),
  )
  let after_receipt = @effects.fold_authoritative_replay(
    empty_effects,
    fixture.store.replay(fixture.workflow),
    @effects.ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [observation],
      [effect_receipt],
      [],
      [],
    ),
  )
  if !reconciled_not_applied {
    let aggregate = fold_closed_loop_v2(
      empty_effects,
      fixture.store.replay(fixture.workflow),
    )
    let receipt = aggregate
      .effects()
      .committed_retry_eligibility_receipt(fixture.intent.intent_ref())
      .unwrap()
    return {
      fixture,
      empty_effects,
      aggregate,
      receipt,
      observation,
      effect_receipt,
    }
  }
  let reconciliation_request = @effects.ReconciliationRequest::new(
    suffix + "-reconciliation-request",
    fixture.intent,
    effect_receipt,
    73L,
    [evidence],
  )
  ignore(
    fixture.store.commit(
      fixture_prepare_reconciliation_request_commit(
        after_receipt,
        suffix + "-reconciliation-request-event",
        suffix + "-reconciliation-request-command",
        reconciliation_request,
      ),
    ),
  )
  let during_reconciliation = @effects.fold_authoritative_replay(
    empty_effects,
    fixture.store.replay(fixture.workflow),
    @effects.ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [observation],
      [effect_receipt],
      [reconciliation_request],
      [],
    ),
  )
  let resolution = @effects.ReconciliationRecord::new(
    suffix + "-reconciliation-resolution",
    fixture.intent,
    reconciliation_request,
    ReconciledNotApplied,
    fixture_envelope(
      suffix + "-reconciliation-observation",
      "reconciliation-observation",
      fixture.intent.governance().governed_subject(),
      @utf8.encode(suffix + "-reconciliation-observation"),
      evidence=[evidence],
    ),
    74L,
    [evidence],
  )
  ignore(
    fixture.store.commit(
      fixture_prepare_reconciliation_resolution_commit(
        during_reconciliation,
        suffix + "-reconciliation-resolution-event",
        suffix + "-reconciliation-resolution-command",
        resolution,
      ),
    ),
  )
  let aggregate = fold_closed_loop_v2(
    empty_effects,
    fixture.store.replay(fixture.workflow),
  )
  let receipt = aggregate
    .effects()
    .committed_retry_eligibility_receipt(fixture.intent.intent_ref())
    .unwrap()
  { fixture, empty_effects, aggregate, receipt, observation, effect_receipt }
}

///|
fn flow7_prepare_ready_retry(
  ready : Flow7RetryReadyFixture,
  suffix : String,
) -> PreparedAtomicRetryV2 raise {
  let policy = flow7_v2_retry_policy()
  let timing = RetryTimingV2::compute(policy, ready.receipt)
  let evidence = flow7_v2_evidence()
  let requested_work = fixture_envelope(
    suffix + "-retry-work",
    "requested-work",
    ready.fixture.intent.governance().governed_subject(),
    @utf8.encode(suffix + "-retry-work"),
    evidence=[evidence],
  )
  let requested_ref = @contracts.RecordRef::new(
    "requested-work",
    requested_work.envelope_id(),
    "1.0.0",
    requested_work.envelope_digest().text(),
  )
  let retry_request = prepare_retry_schedule_request_v2(
    ready.aggregate,
    ready.receipt,
    policy,
    ready.fixture.intent.governance(),
    suffix + "-retry-request",
    suffix + "-retry-attempt",
    suffix + "-retry-attempt-key",
    requested_work,
    "attempt",
    "1.0.0",
    "effect",
    "1.0.0",
    @contracts.sha256_digest(
      @utf8.encode(suffix + "-retry-attempt-key-artifact"),
    ),
    suffix + "-retry-schedule",
    suffix + "-retry-schedule-key",
    1000L,
    1000L,
    1000L,
    suffix + "-retry-command",
  )
  let admission = flow7_aggregate_admission(
    suffix + "-retry",
    ready.fixture.workflow,
    ready.aggregate.prefix_event().unwrap(),
    timing.due_at(),
    1000L,
    ready.fixture.intent.governance().policy_ref(),
    flow7_aggregate_planned(
      ready.fixture.workflow,
      ready.fixture.intent.governance().governed_subject(),
      requested_ref,
      requested_work.envelope_digest(),
      ready.receipt.attempt_count() + 1L,
      suffix + "-retry-attempt-key",
      retry_request.request_ref(),
    ),
    evidence,
  )
  prepare_atomic_retry_v2(
    ready.aggregate,
    ready.receipt,
    policy,
    retry_request,
    admission,
    ready.fixture.intent.governance(),
    suffix + "-retry-plan",
    suffix + "-retry-attempt",
    suffix + "-retry-attempt-event",
    suffix + "-retry-attempt-key",
    requested_work,
    [evidence],
    ready.receipt.source_observed_at(),
    suffix + "-retry-schedule",
    suffix + "-retry-schedule-key",
    1000L,
    suffix + "-retry-schedule-event",
    suffix + "-retry-registration",
    suffix + "-retry-command",
  )
}

///|
test "FLOW-7 aggregate schedules a reconciled-not-applied retry and exhaustion emits no request" {
  let reconciled = flow7_retry_ready_fixture("aggregate-reconciled-happy", true)
  assert_eq(reconciled.receipt.cause_key(), "reconciled_not_applied")
  let prepared = try
    flow7_prepare_ready_retry(reconciled, "aggregate-reconciled-happy")
  catch {
    OrchestrationError::RetryBoundViolation(field~) =>
      fail("unexpected reconciled retry bound: " + field)
    _ => fail("unexpected reconciled retry preparation error")
  } noraise {
    value => value
  }
  let before = reconciled.fixture.store
    .head(reconciled.fixture.workflow)
    .revision()
  ignore(reconciled.fixture.store.commit(prepared.request()))
  assert_eq(
    reconciled.fixture.store.head(reconciled.fixture.workflow).revision(),
    before + 2L,
  )
  let replayed = fold_closed_loop_v2(
    reconciled.empty_effects,
    reconciled.fixture.store.replay(reconciled.fixture.workflow),
  )
  assert_eq(replayed.orchestration().schedule_count(), 2)
  assert_true(
    replayed
    .effects()
    .committed_retry_plan(prepared.attempt().attempt_ref())
    .unwrap()
    .canonical_bytes() ==
    prepared.plan().canonical_bytes(),
  )

  let exhausted = flow7_retry_ready_fixture("aggregate-retry-exhausted", false)
  let exhausted_policy = RetryPolicyV2::new(
    "aggregate-exhausted-policy",
    "2.0.0",
    exhausted.receipt.attempt_count(),
    exhausted.receipt.retry_count(),
    10L,
    1000L,
    2L,
    1L,
    31L,
    @contracts.sha256_digest(b"aggregate-exhausted-seed"),
    ["terminal_failed", "reconciled_not_applied"],
  )
  let exhausted_work = fixture_envelope(
    "aggregate-exhausted-work",
    "requested-work",
    exhausted.fixture.intent.governance().governed_subject(),
    b"aggregate-exhausted-work",
    evidence=exhausted.fixture.evidence,
  )
  let exhausted_before = exhausted.fixture.store
    .head(exhausted.fixture.workflow)
    .revision()
  try
    prepare_retry_schedule_request_v2(
      exhausted.aggregate,
      exhausted.receipt,
      exhausted_policy,
      exhausted.fixture.intent.governance(),
      "aggregate-exhausted-request",
      "aggregate-exhausted-attempt",
      "aggregate-exhausted-attempt-key",
      exhausted_work,
      "attempt",
      "1.0.0",
      "effect",
      "1.0.0",
      @contracts.sha256_digest(b"aggregate-exhausted-artifact"),
      "aggregate-exhausted-schedule",
      "aggregate-exhausted-schedule-key",
      1000L,
      1000L,
      1000L,
      "aggregate-exhausted-command",
    )
  catch {
    OrchestrationError::RetryBoundViolation(field="retry_counters") => ()
    _ => fail("unexpected retry exhaustion error")
  } noraise {
    _ => fail("retry exhaustion emitted a schedule request")
  }
  assert_eq(
    exhausted.fixture.store.head(exhausted.fixture.workflow).revision(),
    exhausted_before,
  )
}

///|
test "FLOW-7 aggregate rejects unconsumed governance events and outbox records" {
  let legacy_fixture = orchestration_fixture("aggregate-legacy-governance-v1")
  let legacy_empty = @effects.EffectsProjection::new(
    legacy_fixture.workflow,
    legacy_fixture.policy.policy_ref(),
  )
  try
    fold_closed_loop_v2(
      legacy_empty,
      legacy_fixture.store.replay(legacy_fixture.workflow),
    )
  catch {
    OrchestrationError::ReplayBindingViolation(
      field="aggregate_governance_v2_required"
    ) => ()
    _ => fail("unexpected structural-only governance V1 rejection")
  } noraise {
    _ => fail("aggregate accepted structural-only governance V1")
  }
  let outbox_fixture = orchestration_fixture_strict("aggregate-extra-outbox")
  let outbox_empty = @effects.EffectsProjection::new(
    outbox_fixture.workflow,
    outbox_fixture.policy.policy_ref(),
  )
  let outbox_replay = outbox_fixture.store.replay(outbox_fixture.workflow)
  ignore(fold_closed_loop_v2(outbox_empty, outbox_replay))
  let corrupt_outbox_replay = flow7_replay_with_extra_outbox(outbox_replay)
  try fold_closed_loop_v2(outbox_empty, corrupt_outbox_replay) catch {
    OrchestrationError::ReplayBindingViolation(field="aggregate_effects_replay") =>
      ()
    _ => fail("unexpected extra-outbox rejection")
  } noraise {
    _ => fail("accepted unmatched extra outbox record")
  }
  let split_fixture = orchestration_fixture_strict("aggregate-split-outbox")
  let split_empty = @effects.EffectsProjection::new(
    split_fixture.workflow,
    split_fixture.policy.policy_ref(),
  )
  let split_replay = flow7_replay_with_split_outbox(
    split_fixture.store.replay(split_fixture.workflow),
  )
  try fold_closed_loop_v2(split_empty, split_replay) catch {
    OrchestrationError::ReplayBindingViolation(field="aggregate_effects_replay") =>
      ()
    _ => fail("unexpected split-outbox rejection")
  } noraise {
    _ => fail("accepted effect event and outbox split across commits")
  }

  let governance_fixture = orchestration_fixture_strict(
    "aggregate-extra-governance",
  )
  let governance_empty = @effects.EffectsProjection::new(
    governance_fixture.workflow,
    governance_fixture.policy.policy_ref(),
  )
  ignore(
    fold_closed_loop_v2(
      governance_empty,
      governance_fixture.store.replay(governance_fixture.workflow),
    ),
  )
  let head = governance_fixture.store
    .replay(governance_fixture.workflow)
    .events()
    .last()
    .unwrap()
  let corrupt_subject = flow7_v2_ref(
    "governance-authority-request", "aggregate-corrupt-governance-subject", b"aggregate-corrupt-governance-subject",
  )
  let corrupt_event = flow7_durable_test_event(
    "aggregate-corrupt-governance-event",
    "aggregate-corrupt-governance-key",
    governance_fixture.workflow,
    "AuthorityRequested",
    corrupt_subject,
    b"aggregate-corrupt-governance-payload",
    governance_fixture.evidence,
    head.event_ref(),
    head.sequence() + 1L,
    head.revision() + 1L,
    Some(head.event_ref().digest()),
  )
  ignore(
    governance_fixture.store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        governance_fixture.workflow,
        head.revision(),
        "aggregate-corrupt-governance-command",
        [corrupt_event],
        [],
      ),
    ),
  )
  try
    fold_closed_loop_v2(
      governance_empty,
      governance_fixture.store.replay(governance_fixture.workflow),
    )
  catch {
    OrchestrationError::ReplayBindingViolation(
      field="aggregate_event_consumption"
    ) => ()
    _ => fail("unexpected extra-governance rejection")
  } noraise {
    _ => fail("accepted unconsumed extra governance event")
  }
}

///|
test "FLOW-7 aggregate atomic retry commits one restart-safe pair" {
  let root = flow7_root_bound_strict_fixture("aggregate-atomic-happy")
  let fixture = root.fixture
  let empty_effects = root.empty_effects
  let aggregate_evidence = flow7_v2_evidence()
  let initial_admission = root.schedule.admission()
  let schedule = root.schedule
  let registration = root.registration
  let schedule_event = root.schedule_event
  let public_projection = fold_orchestration_v2(
    fixture.store.replay(fixture.workflow),
  )
  assert_eq(public_projection.schedule_count(), 1)
  let scheduled = fold_closed_loop_v2(
    empty_effects,
    fixture.store.replay(fixture.workflow),
  )
  let claim = LeaseClaimV2::new(
    "aggregate-claim",
    schedule,
    initial_admission,
    fixture.workflow,
    flow7_v2_ref("owner", "aggregate-owner", b"aggregate-owner"),
    10L,
    0L,
    0L,
    1L,
    1L,
    "aggregate-claim-key",
    [aggregate_evidence],
    schedule_event.event_ref(),
  )
  let claimed = LeaseClaimedV2::new("aggregate-claimed", registration, claim)
  ignore(
    fixture.store.commit(
      prepare_lease_claimed_v2(
        scheduled.orchestration(),
        "aggregate-claim-event",
        claim.idempotency_key(),
        "aggregate-claim-command",
        claimed,
      ),
    ),
  )
  let claimed_aggregate = fold_closed_loop_v2(
    empty_effects,
    fixture.store.replay(fixture.workflow),
  )
  let lease_receipt = claimed_aggregate
    .orchestration()
    .committed_lease_authority_receipt()
    .unwrap()
  let release = LeaseReleaseV2::new(
    "aggregate-release",
    registration,
    lease_receipt,
    flow7_lifecycle_active_authorization(
      "aggregate-release",
      claimed_aggregate.orchestration(),
      registration,
      lease_receipt,
      ReleaseLeaseV2,
      None,
      12L,
    ),
  )
  ignore(
    fixture.store.commit(
      prepare_lease_released_v2(
        claimed_aggregate.orchestration(),
        "aggregate-release-event",
        release.idempotency_key(),
        "aggregate-release-command",
        release,
      ),
    ),
  )
  let released = fold_closed_loop_v2(
    empty_effects,
    fixture.store.replay(fixture.workflow),
  )
  assert_true(released.orchestration().has_terminal_lease())
  let released_effects = @effects.fold_authoritative_replay(
    empty_effects,
    fixture.store.replay(fixture.workflow),
    @effects.ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [],
      [],
      [],
      [],
    ),
  )
  let observation = @effects.DispatchObservation::new(
    "aggregate-observation",
    fixture.intent,
    fixture_envelope(
      "aggregate-observation-envelope",
      "dispatch-observation",
      fixture.intent.governance().governed_subject(),
      b"aggregate-observation",
    ),
    71L,
    [],
  )
  ignore(
    fixture.store.commit(
      fixture_prepare_dispatch_observation_commit(
        released_effects, "aggregate-observation-event", "aggregate-observation-command",
        observation,
      ),
    ),
  )
  let observed = fold_closed_loop_v2(
    empty_effects,
    fixture.store.replay(fixture.workflow),
  )
  ignore(observed)
  let observed_effects = @effects.fold_authoritative_replay(
    empty_effects,
    fixture.store.replay(fixture.workflow),
    @effects.ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [observation],
      [],
      [],
      [],
    ),
  )
  let failed = @effects.EffectReceipt::new(
    "aggregate-failed-receipt",
    "1.0.0",
    fixture.intent,
    fixture_envelope(
      "aggregate-failed-envelope",
      "dispatcher-receipt",
      fixture.intent.governance().governed_subject(),
      b"aggregate-failed",
    ),
    Failed,
    72L,
    [],
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  ignore(
    fixture.store.commit(
      fixture_prepare_effect_receipt_commit(
        observed_effects, "aggregate-failed-event", "aggregate-failed-command", failed,
      ),
    ),
  )
  let eligible = fold_closed_loop_v2(
    empty_effects,
    fixture.store.replay(fixture.workflow),
  )
  let receipt = eligible
    .effects()
    .committed_retry_eligibility_receipt(fixture.intent.intent_ref())
    .unwrap()
  let policy = flow7_v2_retry_policy()
  let timing = RetryTimingV2::compute(policy, receipt)
  let requested_work = fixture_envelope(
    "aggregate-retry-work",
    "requested-work",
    fixture.intent.governance().governed_subject(),
    b"aggregate-retry-work",
    evidence=[aggregate_evidence],
  )
  let requested_ref = try! @contracts.RecordRef::new(
    "requested-work",
    requested_work.envelope_id(),
    "1.0.0",
    requested_work.envelope_digest().text(),
  )
  let retry_request = prepare_retry_schedule_request_v2(
    eligible,
    receipt,
    policy,
    fixture.intent.governance(),
    "aggregate-retry-request",
    "aggregate-retry-attempt",
    "aggregate-retry-attempt-key",
    requested_work,
    "attempt",
    "1.0.0",
    "effect",
    "1.0.0",
    @contracts.sha256_digest(b"aggregate-retry-attempt-key-artifact"),
    "aggregate-retry-schedule",
    "aggregate-retry-schedule-key",
    1000L,
    1000L,
    1000L,
    "aggregate-retry-command",
  )
  let retry_planned = flow7_aggregate_planned(
    fixture.workflow,
    fixture.intent.governance().governed_subject(),
    requested_ref,
    requested_work.envelope_digest(),
    receipt.attempt_count() + 1L,
    "aggregate-retry-attempt-key",
    retry_request.request_ref(),
  )
  let admission = flow7_aggregate_admission(
    "aggregate-retry",
    fixture.workflow,
    eligible.prefix_event().unwrap(),
    timing.due_at(),
    1000L,
    fixture.intent.governance().policy_ref(),
    retry_planned,
    aggregate_evidence,
  )
  let planned_mutations = [
    @effects_authorization.PlannedEffectTuple::new(
      retry_planned.workflow(),
      retry_planned.subject(),
      "attempt-mutated",
      retry_planned.logical_attempt_version(),
      retry_planned.logical_effect_id(),
      retry_planned.logical_effect_version(),
      retry_planned.next_ordinal(),
      retry_planned.external_idempotency(),
      retry_planned.requested_work_ref(),
      retry_planned.requested_work_digest(),
      retry_planned.effect_request_ref(),
      retry_planned.effect_request_digest(),
      retry_planned.artifact_digest(),
    ).unwrap(),
    @effects_authorization.PlannedEffectTuple::new(
      retry_planned.workflow(),
      retry_planned.subject(),
      retry_planned.logical_attempt_id(),
      "2.0.0",
      retry_planned.logical_effect_id(),
      retry_planned.logical_effect_version(),
      retry_planned.next_ordinal(),
      retry_planned.external_idempotency(),
      retry_planned.requested_work_ref(),
      retry_planned.requested_work_digest(),
      retry_planned.effect_request_ref(),
      retry_planned.effect_request_digest(),
      retry_planned.artifact_digest(),
    ).unwrap(),
    @effects_authorization.PlannedEffectTuple::new(
      retry_planned.workflow(),
      retry_planned.subject(),
      retry_planned.logical_attempt_id(),
      retry_planned.logical_attempt_version(),
      "effect-mutated",
      retry_planned.logical_effect_version(),
      retry_planned.next_ordinal(),
      retry_planned.external_idempotency(),
      retry_planned.requested_work_ref(),
      retry_planned.requested_work_digest(),
      retry_planned.effect_request_ref(),
      retry_planned.effect_request_digest(),
      retry_planned.artifact_digest(),
    ).unwrap(),
    @effects_authorization.PlannedEffectTuple::new(
      retry_planned.workflow(),
      retry_planned.subject(),
      retry_planned.logical_attempt_id(),
      retry_planned.logical_attempt_version(),
      retry_planned.logical_effect_id(),
      "2.0.0",
      retry_planned.next_ordinal(),
      retry_planned.external_idempotency(),
      retry_planned.requested_work_ref(),
      retry_planned.requested_work_digest(),
      retry_planned.effect_request_ref(),
      retry_planned.effect_request_digest(),
      retry_planned.artifact_digest(),
    ).unwrap(),
    @effects_authorization.PlannedEffectTuple::new(
      retry_planned.workflow(),
      retry_planned.subject(),
      retry_planned.logical_attempt_id(),
      retry_planned.logical_attempt_version(),
      retry_planned.logical_effect_id(),
      retry_planned.logical_effect_version(),
      retry_planned.next_ordinal(),
      "external-idempotency-mutated",
      retry_planned.requested_work_ref(),
      retry_planned.requested_work_digest(),
      retry_planned.effect_request_ref(),
      retry_planned.effect_request_digest(),
      retry_planned.artifact_digest(),
    ).unwrap(),
    @effects_authorization.PlannedEffectTuple::new(
      retry_planned.workflow(),
      retry_planned.subject(),
      retry_planned.logical_attempt_id(),
      retry_planned.logical_attempt_version(),
      retry_planned.logical_effect_id(),
      retry_planned.logical_effect_version(),
      retry_planned.next_ordinal(),
      retry_planned.external_idempotency(),
      retry_planned.requested_work_ref(),
      retry_planned.requested_work_digest(),
      retry_planned.effect_request_ref(),
      retry_planned.effect_request_digest(),
      @contracts.sha256_digest(b"artifact-mutated"),
    ).unwrap(),
  ]
  for index, mutation in planned_mutations {
    flow7_assert_retry_planned_mutation_rejected(
      "aggregate-planned-mutation-" + index.to_string(),
      if index == 4 {
        "retry_prepare_planned_work"
      } else {
        "retry_prepare_request"
      },
      eligible,
      receipt,
      policy,
      retry_request,
      fixture.intent.governance(),
      requested_work,
      aggregate_evidence,
      mutation,
    )
  }
  let prepared = prepare_atomic_retry_v2(
    eligible,
    receipt,
    policy,
    retry_request,
    admission,
    fixture.intent.governance(),
    "aggregate-retry-plan",
    "aggregate-retry-attempt",
    "aggregate-retry-attempt-event",
    "aggregate-retry-attempt-key",
    requested_work,
    [aggregate_evidence],
    receipt.source_observed_at(),
    "aggregate-retry-schedule",
    "aggregate-retry-schedule-key",
    1000L,
    "aggregate-retry-schedule-event",
    "aggregate-retry-registration",
    "aggregate-retry-command",
  )
  try
    @effects.AttemptRegistration::new(
      "aggregate-substituted-attempt-id",
      "1.0.0",
      fixture.workflow,
      eligible.prefix_event().unwrap(),
      receipt.attempt_count() + 1L,
      requested_work,
      [aggregate_evidence],
      fixture.intent.governance(),
      receipt.source_observed_at(),
      "aggregate-retry-attempt-key",
      eligible.prefix_event().unwrap().event_ref().digest(),
      retry_of_intent_ref=receipt.source_intent_ref(),
      retry_eligibility_receipt=receipt,
      retry_plan=prepared.plan(),
    )
  catch {
    @effects.EffectsError::RetryEligibilityViolation(
      field="retry_attempt_plan_binding"
    ) => ()
    _ => fail("unexpected attempt identity substitution rejection")
  } noraise {
    _ => fail("accepted attempt identity substitution under frozen plan")
  }
  try
    ScheduleIntentV2::new(
      "aggregate-substituted-schedule-id",
      "2.0.0",
      admission,
      fixture.workflow,
      timing.due_at(),
      Some(prepared.plan().admission_deadline()),
      [aggregate_evidence],
      prepared.request().events()[0].event_ref(),
      "aggregate-retry-schedule-key",
      previous_digest=prepared.request().events()[0].event_ref().digest(),
      retry_policy=policy,
      retry_plan=prepared.plan(),
      retry_attempt_ref=prepared.attempt().attempt_ref(),
      retry_attempt_event_ref=prepared.request().events()[0].event_ref(),
    )
  catch {
    OrchestrationError::ScheduleStateViolation(
      field="retry_schedule_plan_binding"
    ) => ()
    _ => fail("unexpected schedule identity substitution rejection")
  } noraise {
    _ => fail("accepted schedule identity substitution under frozen plan")
  }
  let altered_same_command = prepare_atomic_retry_v2(
    eligible,
    receipt,
    policy,
    retry_request,
    admission,
    fixture.intent.governance(),
    "aggregate-altered-plan",
    "aggregate-retry-attempt",
    "aggregate-altered-attempt-event",
    "aggregate-retry-attempt-key",
    requested_work,
    [aggregate_evidence],
    receipt.source_observed_at(),
    "aggregate-retry-schedule",
    "aggregate-retry-schedule-key",
    1000L,
    "aggregate-altered-schedule-event",
    "aggregate-altered-registration",
    "aggregate-retry-command",
  )
  let changed_policy = RetryPolicyV2::new(
    "aggregate-changed-retry-policy",
    "2.0.0",
    5L,
    4L,
    11L,
    1000L,
    2L,
    1L,
    31L,
    @contracts.sha256_digest(b"aggregate-changed-retry-seed"),
    ["terminal_failed", "reconciled_not_applied"],
  )
  try
    prepare_atomic_retry_v2(
      eligible,
      receipt,
      changed_policy,
      retry_request,
      admission,
      fixture.intent.governance(),
      "aggregate-changed-policy-plan",
      "aggregate-retry-attempt",
      "aggregate-changed-policy-attempt-event",
      "aggregate-retry-attempt-key",
      requested_work,
      [aggregate_evidence],
      receipt.source_observed_at(),
      "aggregate-retry-schedule",
      "aggregate-retry-schedule-key",
      1000L,
      "aggregate-changed-policy-schedule-event",
      "aggregate-changed-policy-registration",
      "aggregate-retry-command",
    )
  catch {
    OrchestrationError::EffectProofMismatch(field="retry_prepare_request") => ()
    _ => fail("unexpected changed-policy rejection")
  } noraise {
    _ => fail("accepted changed retry policy and due under frozen request")
  }
  try
    prepare_atomic_retry_v2(
      eligible,
      receipt,
      policy,
      retry_request,
      admission,
      fixture.intent.governance(),
      "aggregate-changed-schedule-plan",
      "aggregate-retry-attempt",
      "aggregate-changed-schedule-attempt-event",
      "aggregate-retry-attempt-key",
      requested_work,
      [aggregate_evidence],
      receipt.source_observed_at(),
      "aggregate-changed-schedule",
      "aggregate-retry-schedule-key",
      1000L,
      "aggregate-changed-schedule-event",
      "aggregate-changed-schedule-registration",
      "aggregate-retry-command",
    )
  catch {
    OrchestrationError::EffectProofMismatch(field="retry_prepare_request") => ()
    _ => fail("unexpected changed-schedule-id rejection")
  } noraise {
    _ => fail("accepted changed schedule identity under frozen request")
  }
  try
    prepare_atomic_retry_v2(
      eligible,
      receipt,
      policy,
      retry_request,
      admission,
      fixture.intent.governance(),
      "aggregate-changed-schedule-key-plan",
      "aggregate-retry-attempt",
      "aggregate-changed-key-attempt-event",
      "aggregate-retry-attempt-key",
      requested_work,
      [aggregate_evidence],
      receipt.source_observed_at(),
      "aggregate-retry-schedule",
      "aggregate-changed-schedule-key",
      1000L,
      "aggregate-changed-key-schedule-event",
      "aggregate-changed-key-registration",
      "aggregate-retry-command",
    )
  catch {
    OrchestrationError::EffectProofMismatch(field="retry_prepare_request") => ()
    _ => fail("unexpected changed-schedule-key rejection")
  } noraise {
    _ => fail("accepted changed schedule key under frozen request")
  }
  try
    prepare_atomic_retry_v2(
      eligible,
      receipt,
      policy,
      retry_request,
      admission,
      fixture.intent.governance(),
      "aggregate-changed-deadline-plan",
      "aggregate-retry-attempt",
      "aggregate-changed-deadline-attempt-event",
      "aggregate-retry-attempt-key",
      requested_work,
      [aggregate_evidence],
      receipt.source_observed_at(),
      "aggregate-retry-schedule",
      "aggregate-retry-schedule-key",
      999L,
      "aggregate-changed-deadline-schedule-event",
      "aggregate-changed-deadline-registration",
      "aggregate-retry-command",
    )
  catch {
    OrchestrationError::EffectProofMismatch(field="retry_prepare_request") => ()
    _ => fail("unexpected changed-deadline rejection")
  } noraise {
    _ => fail("accepted changed schedule deadline under frozen request")
  }
  try
    prepare_atomic_retry_v2(
      eligible,
      receipt,
      policy,
      retry_request,
      admission,
      fixture.intent.governance(),
      "aggregate-changed-command-plan",
      "aggregate-retry-attempt",
      "aggregate-changed-command-attempt-event",
      "aggregate-retry-attempt-key",
      requested_work,
      [aggregate_evidence],
      receipt.source_observed_at(),
      "aggregate-retry-schedule",
      "aggregate-retry-schedule-key",
      1000L,
      "aggregate-changed-command-schedule-event",
      "aggregate-changed-command-registration",
      "aggregate-changed-command",
    )
  catch {
    OrchestrationError::EffectProofMismatch(field="retry_prepare_request") => ()
    _ => fail("unexpected changed-command rejection")
  } noraise {
    _ => fail("accepted changed atomic command key under frozen request")
  }
  try
    prepare_atomic_retry_v2(
      eligible,
      receipt,
      policy,
      retry_request,
      admission,
      fixture.intent.governance(),
      "aggregate-expired-plan",
      "aggregate-retry-attempt",
      "aggregate-expired-attempt-event",
      "aggregate-retry-attempt-key",
      requested_work,
      [aggregate_evidence],
      receipt.source_observed_at(),
      "aggregate-retry-schedule",
      "aggregate-retry-schedule-key",
      timing.due_at() - 1L,
      "aggregate-expired-schedule-event",
      "aggregate-expired-registration",
      "aggregate-expired-command",
    )
  catch {
    OrchestrationError::AuthorityExpired(expires_at~, observed_at~) => {
      assert_eq(expires_at, timing.due_at() - 1L)
      assert_eq(observed_at, timing.due_at())
    }
    _ => fail("unexpected expired-deadline rejection")
  } noraise {
    _ => fail("accepted retry deadline before policy due time")
  }
  let substituted_work = fixture_envelope(
    "aggregate-substituted-work",
    "requested-work",
    fixture.intent.governance().governed_subject(),
    b"aggregate-substituted-work",
    evidence=[aggregate_evidence],
  )
  try
    prepare_atomic_retry_v2(
      eligible,
      receipt,
      policy,
      retry_request,
      admission,
      fixture.intent.governance(),
      "aggregate-substituted-plan",
      "aggregate-retry-attempt",
      "aggregate-substituted-attempt-event",
      "aggregate-retry-attempt-key",
      substituted_work,
      [aggregate_evidence],
      receipt.source_observed_at(),
      "aggregate-retry-schedule",
      "aggregate-retry-schedule-key",
      1000L,
      "aggregate-substituted-schedule-event",
      "aggregate-substituted-registration",
      "aggregate-substituted-command",
    )
  catch {
    OrchestrationError::EffectProofMismatch(field="retry_prepare_request") => ()
    _ => fail("unexpected substituted-work rejection")
  } noraise {
    _ => fail("accepted substituted retry requested work")
  }
  let request = prepared.request()
  assert_eq(request.events().length(), 2)
  assert_true(request.intents().is_empty())
  let before = fixture.store.head(fixture.workflow).revision()
  ignore(fixture.store.commit(request))
  assert_eq(fixture.store.head(fixture.workflow).revision(), before + 2L)
  try fixture.store.commit(altered_same_command.request()) catch {
    @storage.IdempotencyConflict(key="aggregate-retry-command") => ()
    _ => fail("expected changed body under same command key to conflict")
  } noraise {
    _ => fail("accepted altered retry body under committed command key")
  }
  ignore(fixture.store.commit(request))
  assert_eq(fixture.store.head(fixture.workflow).revision(), before + 2L)
  let restarted = try
    fold_closed_loop_v2(empty_effects, fixture.store.replay(fixture.workflow))
  catch {
    OrchestrationError::ReplayBindingViolation(field~) =>
      fail("unexpected aggregate replay rejection: " + field)
    _ => fail("unexpected aggregate replay rejection")
  } noraise {
    value => value
  }
  assert_eq(restarted.orchestration().schedule_count(), 2)
  assert_true(
    restarted
    .orchestration()
    .committed_schedule_registration()
    .unwrap()
    .record_ref() ==
    prepared.registration().record_ref(),
  )
  assert_true(!restarted.orchestration().has_terminal_lease())
  let replayed_plan = restarted
    .effects()
    .committed_retry_plan(prepared.attempt().attempt_ref())
    .unwrap()
  assert_true(
    replayed_plan.canonical_bytes() == prepared.plan().canonical_bytes(),
  )
  let batch = fixture.store
    .replay(fixture.workflow)
    .committed_batches()
    .last()
    .unwrap()
  assert_eq(batch.event_refs().length(), 2)
  assert_true(batch.intent_refs().is_empty())
  assert_true(batch.event_refs()[0] == request.events()[0].event_ref())
  assert_true(batch.event_refs()[1] == request.events()[1].event_ref())
}

///|
fn flow7_retry_request_deadline_variant(
  base : @retry_authority.RetryScheduleRequestV2,
  suffix : String,
  source_schedule_deadline : Int64?,
  admission_governance_deadline : Int64,
  admission_controls_deadline : Int64,
  requested_schedule_deadline : Int64,
  governance_deadline : Int64?,
) -> @retry_authority.RetryScheduleRequestV2 raise {
  @retry_authority.RetryScheduleRequestV2::new(
    "deadline-variant-" + suffix,
    base.workflow(),
    base.receipt_ref(),
    base.receipt_digest(),
    base.receipt_bytes(),
    base.policy_ref(),
    base.policy_digest(),
    base.policy_bytes(),
    base.timing_digest(),
    base.timing_bytes(),
    base.due_at(),
    base.attempt_count(),
    base.retry_count(),
    base.retry_ordinal(),
    base.cause_key(),
    base.requested_work_ref(),
    base.requested_work_digest(),
    base.logical_attempt_id(),
    base.logical_attempt_version(),
    base.logical_effect_id(),
    base.logical_effect_version(),
    base.artifact_digest(),
    base.child_attempt_id(),
    base.child_attempt_ordinal(),
    base.child_attempt_idempotency_key(),
    base.schedule_id(),
    base.schedule_idempotency_key(),
    source_schedule_deadline,
    admission_governance_deadline,
    admission_controls_deadline,
    requested_schedule_deadline,
    governance_deadline,
    base.prefix_head_ref(),
    base.prefix_head_digest(),
    base.prefix_sequence(),
    base.prefix_revision(),
    base.prefix_replay_digest(),
    base.command_idempotency_key(),
  )
}

///|
fn flow7_unique_bytes_offset(bytes : Bytes, needle : Bytes) -> Int raise {
  let mut found = -1
  let mut matches = 0
  for start = 0; start + needle.length() <= bytes.length(); start = start + 1 {
    let mut same = true
    for offset = 0; offset < needle.length(); offset = offset + 1 {
      if bytes[start + offset] != needle[offset] {
        same = false
      }
    }
    if same {
      found = start
      matches += 1
    }
  }
  assert_eq(matches, 1)
  found
}

///|
test "FLOW-7 retry request binds each deadline source into the effective minimum" {
  let ready = flow7_retry_ready_fixture("aggregate-deadline-matrix", false)
  let prepared = flow7_prepare_ready_retry(ready, "aggregate-deadline-matrix")
  let plan = prepared.plan()
  let base = @retry_authority.RetryScheduleRequestV2::decode(
    plan.request_ref(),
    plan.request_bytes(),
  )
  let due = base.due_at()
  let source = flow7_retry_request_deadline_variant(
    base,
    "source",
    Some(due + 20L),
    due + 30L,
    due + 40L,
    due + 50L,
    Some(due + 100L),
  )
  assert_eq(source.effective_deadline(), due + 20L)
  let admission_governance = flow7_retry_request_deadline_variant(
    base,
    "admission-governance",
    Some(due + 50L),
    due + 20L,
    due + 40L,
    due + 30L,
    Some(due + 100L),
  )
  assert_eq(admission_governance.effective_deadline(), due + 20L)
  let admission_controls = flow7_retry_request_deadline_variant(
    base,
    "admission-controls",
    Some(due + 50L),
    due + 40L,
    due + 20L,
    due + 30L,
    Some(due + 100L),
  )
  assert_eq(admission_controls.effective_deadline(), due + 20L)
  let requested = flow7_retry_request_deadline_variant(
    base,
    "requested",
    Some(due + 50L),
    due + 40L,
    due + 30L,
    due + 20L,
    Some(due + 100L),
  )
  assert_eq(requested.effective_deadline(), due + 20L)
  let governance = flow7_retry_request_deadline_variant(
    base,
    "governance",
    Some(due + 50L),
    due + 40L,
    due + 30L,
    due + 25L,
    Some(due + 21L),
  )
  assert_eq(governance.effective_deadline(), due + 20L)
}

///|
test "FLOW-7 retry request rejects an effective-minimum byte substitution" {
  let ready = flow7_retry_ready_fixture(
    "aggregate-effective-deadline-tamper", false,
  )
  let prepared = flow7_prepare_ready_retry(
    ready, "aggregate-effective-deadline-tamper",
  )
  let plan = prepared.plan()
  let base = @retry_authority.RetryScheduleRequestV2::decode(
    plan.request_ref(),
    plan.request_bytes(),
  )
  let due = base.due_at()
  let request = flow7_retry_request_deadline_variant(
    base,
    "effective-tamper",
    Some(due + 50L),
    due + 40L,
    due + 30L,
    due + 25L,
    Some(due + 21L),
  )
  let effective = request.effective_deadline()
  let needle = Bytes::from_array([0, 0, 0, 0, 0, 0, 0, effective.to_byte()])
  let changed = request.canonical_bytes().to_array()
  let offset = flow7_unique_bytes_offset(request.canonical_bytes(), needle)
  changed[offset + 7] = (changed[offset + 7].to_int() ^ 1).to_byte()
  let forged = Bytes::from_array(changed)
  let forged_ref = @contracts.RecordRef::new(
    request.request_ref().kind(),
    request.request_ref().id(),
    request.request_ref().version().text(),
    @contracts.sha256_digest(forged).text(),
  )
  try
    @retry_authority.RetryScheduleRequestV2::decode(forged_ref, forged)
  catch {
    @retry_authority.RetryAuthorityError::BoundViolation(
      field="effective_deadline"
    ) => ()
    _ => fail("unexpected effective-minimum substitution rejection")
  } noraise {
    _ => fail("accepted substituted effective minimum")
  }
}

///|
fn flow7_clone_event_position(
  event : @storage.WorkflowEvent,
  event_id : String,
  event_key : String,
  sequence : Int64,
  revision : Int64,
  previous_event_digest : @contracts.ContentDigest?,
) -> @storage.WorkflowEvent raise {
  let original = event.payload()
  let run_ref = original.run_ref()
  let stage_ref = original.stage_ref()
  let attempt_ref = original.attempt_ref()
  let correlation_ref = original.correlation_ref()
  let causation_ref = original.causation_ref()
  let idempotency_ref = Some(event_key)
  let previous_digest = previous_event_digest
  let envelope = @contracts.WireEnvelope::new(
    original.contract_id(),
    original.contract_version().text(),
    event_id,
    original.envelope_kind(),
    original.subject(),
    original.schema(),
    original.payload(),
    original.producer_id(),
    original.producer_version().text(),
    [
      for artifact in original.artifacts() => artifact
    ],
    [
      for evidence in original.evidence() => evidence
    ],
    run_ref?,
    stage_ref?,
    attempt_ref?,
    correlation_ref?,
    causation_ref?,
    idempotency_ref?,
    previous_digest?,
    extensions=[ for extension in original.extensions() => extension ],
  )
  @storage.WorkflowEvent::new(
    event.record_version().text(),
    event.schema_version().text(),
    event.workflow(),
    event_id,
    sequence,
    revision,
    event_key,
    envelope,
    [
      for evidence in event.evidence() => evidence
    ],
    previous_event_digest?,
  )
}

///|
fn flow7_replay_with_tail(
  prefix : @storage.ReplayResult,
  command_idempotency_key : String,
  events : Array[@storage.WorkflowEvent],
  intents? : Array[@storage.OutboxIntent] = [],
) -> @storage.ReplayResult raise {
  let store = @storage.MemoryStore::new()
  for batch in prefix.committed_batches() {
    let copied_events : Array[@storage.WorkflowEvent] = []
    for event_ref in batch.event_refs() {
      let index = prefix
        .events()
        .search_by(event => event.event_ref() == event_ref)
        .unwrap()
      copied_events.push(prefix.events()[index])
    }
    let copied_intents : Array[@storage.OutboxIntent] = []
    for intent_ref in batch.intent_refs() {
      let index = prefix
        .intents()
        .search_by(intent => intent.intent_ref() == intent_ref)
        .unwrap()
      copied_intents.push(prefix.intents()[index])
    }
    ignore(
      store.commit(
        @storage.CommitRequest::new(
          "1.0.0",
          "1.0.0",
          prefix.workflow(),
          batch.expected_revision(),
          batch.command_idempotency_key(),
          copied_events,
          copied_intents,
        ),
      ),
    )
  }
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        prefix.workflow(),
        prefix.head().revision(),
        command_idempotency_key,
        events,
        intents,
      ),
    ),
  )
  store.replay(prefix.workflow())
}

///|
fn flow7_assert_aggregate_replay_field(
  empty_effects : @effects.EffectsProjection,
  replay : @storage.ReplayResult,
  expected_field : String,
) -> Unit raise {
  try fold_closed_loop_v2(empty_effects, replay) catch {
    OrchestrationError::ReplayBindingViolation(field~) =>
      assert_eq(field, expected_field)
    _ => fail("unexpected retry-tail structural rejection")
  } noraise {
    _ => fail("accepted malformed retry tail")
  }
}

///|
test "FLOW-7 aggregate rejects every malformed retry-pair boundary" {
  let ready = flow7_retry_ready_fixture("aggregate-structural-matrix", false)
  let prepared = flow7_prepare_ready_retry(ready, "aggregate-structural-matrix")
  let prefix = ready.fixture.store.replay(ready.fixture.workflow)
  let prefix_head = prefix.events().last().unwrap()
  let request = prepared.request()
  let attempt = request.events()[0]
  let schedule = request.events()[1]

  flow7_assert_aggregate_replay_field(
    ready.empty_effects,
    flow7_replay_with_tail(prefix, "aggregate-structural-attempt-only", [
      attempt,
    ]),
    "retry_attempt_without_schedule",
  )

  let schedule_only = flow7_clone_event_position(
    schedule,
    "aggregate-structural-schedule-only-event",
    "aggregate-structural-schedule-only-key",
    prefix_head.sequence() + 1L,
    prefix_head.revision() + 1L,
    Some(prefix_head.event_ref().digest()),
  )
  flow7_assert_aggregate_replay_field(
    ready.empty_effects,
    flow7_replay_with_tail(prefix, "aggregate-structural-schedule-only", [
      schedule_only,
    ]),
    "retry_schedule_not_adjacent_attempt",
  )

  let reordered_schedule = flow7_clone_event_position(
    schedule,
    "aggregate-structural-reordered-schedule-event",
    "aggregate-structural-reordered-schedule-key",
    prefix_head.sequence() + 1L,
    prefix_head.revision() + 1L,
    Some(prefix_head.event_ref().digest()),
  )
  let reordered_attempt = flow7_clone_event_position(
    attempt,
    "aggregate-structural-reordered-attempt-event",
    "aggregate-structural-reordered-attempt-key",
    prefix_head.sequence() + 2L,
    prefix_head.revision() + 2L,
    Some(reordered_schedule.event_ref().digest()),
  )
  flow7_assert_aggregate_replay_field(
    ready.empty_effects,
    flow7_replay_with_tail(prefix, "aggregate-structural-reordered", [
      reordered_schedule, reordered_attempt,
    ]),
    "aggregate_effects_replay",
  )

  let substituted_attempt = flow7_clone_event_position(
    attempt,
    "aggregate-structural-substituted-attempt-event",
    "aggregate-structural-substituted-attempt-key",
    attempt.sequence(),
    attempt.revision(),
    attempt.previous_event_digest(),
  )
  let substituted_schedule = flow7_clone_event_position(
    schedule,
    "aggregate-structural-substituted-schedule-event",
    "aggregate-structural-substituted-schedule-key",
    schedule.sequence(),
    schedule.revision(),
    Some(substituted_attempt.event_ref().digest()),
  )
  flow7_assert_aggregate_replay_field(
    ready.empty_effects,
    flow7_replay_with_tail(
      prefix,
      "aggregate-structural-substituted-event-ref",
      [substituted_attempt, substituted_schedule],
    ),
    "aggregate_effects_replay",
  )

  let initial_schedule = prefix
    .events()
    .filter(event => event.payload().envelope_kind() == "schedule.registered.v2")[0]
  let inserted = flow7_clone_event_position(
    initial_schedule,
    "aggregate-structural-inserted-event",
    "aggregate-structural-inserted-key",
    attempt.sequence() + 1L,
    attempt.revision() + 1L,
    Some(attempt.event_ref().digest()),
  )
  let delayed_schedule = flow7_clone_event_position(
    schedule,
    "aggregate-structural-delayed-schedule-event",
    "aggregate-structural-delayed-schedule-key",
    attempt.sequence() + 2L,
    attempt.revision() + 2L,
    Some(inserted.event_ref().digest()),
  )
  flow7_assert_aggregate_replay_field(
    ready.empty_effects,
    flow7_replay_with_tail(prefix, "aggregate-structural-inserted", [
      attempt, inserted, delayed_schedule,
    ]),
    "retry_schedule_plan_missing",
  )

  flow7_assert_aggregate_replay_field(
    ready.empty_effects,
    flow7_replay_with_tail(prefix, "aggregate-structural-wrong-batch-command", [
      attempt, schedule,
    ]),
    "retry_atomic_batch_boundary",
  )
}
