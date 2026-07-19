///|
test "FLOW-7 Phase1A V2.2 initial admission commits exact binding batch" {
  let (admission_fixture, evidence, _, _, _, _) = flow7_durable_fixture()
  let schedule = flow7_v2_schedule_intent(admission_fixture.admission, evidence)
  let registration = ScheduleRegisteredV2::new(
    "phase1a-v22-registration", schedule,
  )
  let store = @storage.MemoryStore::new()
  let empty_replay = store.replay(schedule.workflow())
  let governance_policy = flow7_v2_governance_policy()
  let empty_effects = @effects.EffectsProjection::new(
    schedule.workflow(),
    governance_policy.policy_ref(),
  )
  let empty = fold_empty_closed_loop_v22(empty_effects, empty_replay)
  let governance_stream = flow7_v2_ref(
    "governance-stream", "phase1a-governance", b"phase1a-governance",
  )
  try
    authorize_initial_work_v22(
      "phase1a-cutoff-too-early",
      empty,
      registration,
      flow7_v2_retry_policy(),
      governance_policy,
      governance_stream,
      9L,
      "phase1a-cutoff-e1",
      "phase1a-cutoff-r2",
      "phase1a-cutoff-e2",
      "phase1a-cutoff-e2-key",
      "phase1a-cutoff-r3",
      "phase1a-cutoff-e3",
      "phase1a-cutoff-e3-key",
      "phase1a-cutoff-command",
    )
  catch {
    MalformedInput(field="cancellation_governance_valid_until_inclusive") => ()
    _ => fail("unexpected early governance cutoff error")
  } noraise {
    _ => fail("accepted governance cutoff before admission clock")
  }
  let unrelated_policy = @governance.GovernancePolicy::new(
    "phase1a-unrelated-policy",
    "1.0.0",
    "1.0.0",
    "1.0.0",
    ["authority"],
    ["reviewer"],
    1,
    1,
    [@governance.Approved],
  )
  try
    authorize_initial_work_v22(
      "phase1a-policy-mismatch",
      empty,
      registration,
      flow7_v2_retry_policy(),
      unrelated_policy,
      governance_stream,
      20L,
      "phase1a-policy-e1",
      "phase1a-policy-r2",
      "phase1a-policy-e2",
      "phase1a-policy-e2-key",
      "phase1a-policy-r3",
      "phase1a-policy-e3",
      "phase1a-policy-e3-key",
      "phase1a-policy-command",
    )
  catch {
    PolicyMismatch(field="initial_work_governance_policy") => ()
    _ => fail("unexpected governance-policy mismatch error")
  } noraise {
    _ => fail("accepted governance policy unrelated to admission")
  }
  let authorization = authorize_initial_work_v22(
    "phase1a-initial-authorization",
    empty,
    registration,
    flow7_v2_retry_policy(),
    governance_policy,
    governance_stream,
    20L,
    "phase1a-e1",
    "phase1a-r2",
    "phase1a-e2",
    "phase1a-e2-key",
    "phase1a-r3",
    "phase1a-e3",
    "phase1a-e3-key",
    "phase1a-initial-command",
  )
  let request = prepare_initial_work_v22(authorization, registration)
  assert_eq(request.events().length(), 3)
  assert_eq(request.intents().length(), 0)
  assert_eq(request.expected_revision(), 0L)
  assert_eq(
    request.events()[0].payload().envelope_kind(),
    "schedule.registered.v2",
  )
  assert_eq(
    request.events()[1].payload().envelope_kind(),
    "retry.policy.bound.v2",
  )
  assert_eq(
    request.events()[2].payload().envelope_kind(),
    "cancellation.governance.bound.v2",
  )
  let torn_store = @storage.MemoryStore::new()
  let torn = @storage.CommitRequest::new(
    "1.0.0",
    "1.0.0",
    schedule.workflow(),
    0L,
    "phase1a-torn-command",
    [request.events()[0], request.events()[1]],
    [],
  )
  ignore(torn_store.commit(torn))
  let torn_replay = torn_store.replay(schedule.workflow())
  try fold_initial_work_receipt_v22(empty_effects, torn_replay) catch {
    PolicyMismatch(field="root_cancellation_governance_binding_missing") => ()
    _ => fail("unexpected torn initial batch error")
  } noraise {
    _ => fail("expected torn initial batch replay rejection")
  }
  let missing_store = @storage.MemoryStore::new()
  let missing = @storage.CommitRequest::new(
    "1.0.0",
    "1.0.0",
    schedule.workflow(),
    0L,
    "phase1a-missing-command",
    [request.events()[0]],
    [],
  )
  ignore(missing_store.commit(missing))
  let missing_replay = missing_store.replay(schedule.workflow())
  try fold_initial_work_receipt_v22(empty_effects, missing_replay) catch {
    PolicyMismatch(field="root_retry_policy_binding_missing") => ()
    _ => fail("unexpected missing initial binding error")
  } noraise {
    _ => fail("expected missing initial binding replay rejection")
  }
  ignore(commit_orchestration_v2(store, request))
  let replay = store.replay(schedule.workflow())
  let receipt = fold_initial_work_receipt_v22(empty_effects, replay) catch {
    ReplayBindingViolation(field~) => fail(field)
    PolicyMismatch(field~) => fail(field)
    _ => fail("unexpected initial work receipt failure")
  }
  assert_true(
    receipt.retry_policy_ref() == flow7_v2_retry_policy().policy_ref(),
  )
  assert_eq(receipt.valid_until_inclusive(), 20L)
  assert_true(receipt.governance_policy_ref() == governance_policy.policy_ref())
  receipt.validate_current(empty_effects, replay)
  let root_head = replay.events()[2]
  let governance_fixture = orchestration_fixture_with_governance_version(
    "phase1a-later-effect",
    true,
    workflow_override=schedule.workflow(),
    policy_override=governance_policy,
    authority_kind="authority",
    reviewer_kind="reviewer",
  ) catch {
    @effects.EffectsError::GovernanceViolation(field~) => fail(field)
    @effects.EffectsError::IdentityMismatch(field~) => fail(field)
    _ => fail("unexpected governance fixture failure")
  }
  let governance_source = governance_fixture.store.replay(schedule.workflow())
  let governance_events : Array[@storage.WorkflowEvent] = []
  let mut governance_previous = root_head.event_ref().digest()
  for index = 0; index < 6; index = index + 1 {
    let cloned = flow7_clone_event_position(
      governance_source.events()[index],
      governance_source.events()[index].event_ref().id(),
      governance_source.events()[index].idempotency_key(),
      4L + index.to_int64(),
      4L + index.to_int64(),
      Some(governance_previous),
    )
    governance_events.push(cloned)
    governance_previous = cloned.event_ref().digest()
  }
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        schedule.workflow(),
        3L,
        "phase1a-later-governance-command",
        governance_events,
        [],
      ),
    ) catch {
      @storage.StorageError::IdentityConflict(kind=_, id=_, version=_) =>
        fail("governance identity conflict")
      _ => fail("unexpected governance tail storage rejection")
    },
  )
  let governed_replay = store.replay(schedule.workflow())
  let base_effects = @effects.fold_committed_effects_bytes(
    empty_effects, governed_replay,
  ) catch {
    @effects.EffectsError::GovernanceViolation(field~) => fail(field)
    @effects.EffectsError::IdentityMismatch(field~) => fail(field)
    _ => fail("unexpected governed-prefix effects fold failure")
  }
  let effect_causal_event = governance_events[5]
  let governed_subject = governance_fixture.governance.governed_subject()
  let later_attempt = @effects.AttemptRegistration::new(
    "phase1a-later-attempt",
    "1.0.0",
    schedule.workflow(),
    effect_causal_event,
    1L,
    fixture_envelope(
      "phase1a-later-requested",
      "requested-work",
      governed_subject,
      b"phase1a-later-work",
      evidence=governance_fixture.evidence,
    ),
    governance_fixture.evidence,
    governance_fixture.governance,
    60L,
    "phase1a-later-attempt-key",
    effect_causal_event.event_ref().digest(),
  ) catch {
    @effects.EffectsError::GovernanceViolation(field~) => fail(field)
    @effects.EffectsError::IdentityMismatch(field~) => fail(field)
    _ => fail("unexpected later attempt construction failure")
  }
  let later_attempt_event = fixture_prepare_attempt_registration_event(
    base_effects, "phase1a-later-attempt-event", later_attempt,
  )
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        schedule.workflow(),
        9L,
        "phase1a-later-attempt-command",
        [later_attempt_event],
        [],
      ),
    ),
  )
  let after_attempt = @effects.fold_authoritative_replay(
    empty_effects,
    store.replay(schedule.workflow()),
    @effects.ReplayCatalog::new([later_attempt], [], [], [], [], []),
  )
  assert_eq(after_attempt.attempts().length(), 1)
  assert_true(
    after_attempt.attempts()[0].attempt_ref() == later_attempt.attempt_ref(),
  )
  let later_intent = @effects.EffectIntent::new(
    "phase1a-later-intent",
    "1.0.0",
    later_attempt,
    governance_fixture.governance,
    fixture_envelope(
      "phase1a-later-effect-request",
      "effect-request",
      governed_subject,
      b"phase1a-later-effect",
      evidence=governance_fixture.evidence,
    ),
    governance_fixture.evidence,
    "phase1a-later-external-key",
    fixture_ref("capability", "phase1a-later-capability"),
    "opaque-capability",
    70L,
    later_attempt.attempt_ref(),
    after_attempt.last_event_digest().unwrap(),
    true,
    fencing=@effects.FencingBinding::new(
      fixture_ref("fence", "phase1a-later-fence"),
      1L,
      10L,
    ),
  ) catch {
    @effects.EffectsError::GovernanceViolation(field~) => fail(field)
    @effects.EffectsError::IdentityMismatch(field~) => fail(field)
    _ => fail("unexpected later intent construction failure")
  }
  let later_prepared = fixture_prepare_effect_commit(
    after_attempt, "phase1a-later-intent-event", "phase1a-later-outbox", "phase1a-later-intent-command",
    later_intent,
  ) catch {
    @effects.EffectsError::GovernanceViolation(field~) => fail(field)
    @effects.EffectsError::IdentityMismatch(field~) => fail(field)
    @effects.EffectsError::DigestMismatch(field~) => fail(field)
    @effects.EffectsError::OrderingViolation(field~) => fail(field)
    @effects.EffectsError::OutboxAtomicityViolation(field~) => fail(field)
    @effects.EffectsError::IdempotencyConflict(key~) => fail(key)
    _ => fail("unexpected later intent prepare failure")
  }
  ignore(store.commit(later_prepared.commit_request()))
  let later_replay = store.replay(schedule.workflow())
  assert_eq(later_replay.intents().length(), 1)
  let later_receipt = fold_initial_work_receipt_v22(empty_effects, later_replay)
  assert_eq(later_receipt.current_revision(), 11L)
  later_receipt.validate_current(empty_effects, later_replay)
}

///|
test "FLOW-7 Phase1A checked authorization time boundaries" {
  let (zero_observed, zero_inclusive, zero_exclusive) = cancellation_authorization_times_v22(
    0L,
    0L,
    0L,
    0L,
    0L,
    0L,
    0L,
    None,
  )
  assert_eq(zero_observed, 0L)
  assert_eq(zero_inclusive, 0L)
  assert_eq(zero_exclusive, 1L)
  let (observed, inclusive, exclusive) = cancellation_authorization_times_v22(
    1L,
    2L,
    3L,
    4L,
    5L,
    6L,
    100L,
    None,
  )
  assert_eq(observed, 6L)
  assert_eq(inclusive, 100L)
  assert_eq(exclusive, 101L)
  let (_, present, present_exclusive) = cancellation_authorization_times_v22(
    1L,
    2L,
    3L,
    4L,
    5L,
    6L,
    100L,
    Some(80L),
  )
  assert_eq(present, 79L)
  assert_eq(present_exclusive, 80L)
  assert_eq(checked_exclusive_deadline_v22(253402300799998L), 253402300799999L)
  let (at_deadline, effective_inclusive, effective_exclusive) = cancellation_authorization_times_v22(
    6L,
    6L,
    6L,
    6L,
    6L,
    6L,
    6L,
    None,
  )
  assert_eq(at_deadline, effective_inclusive)
  assert_eq(effective_exclusive, 7L)
  try
    cancellation_authorization_times_v22(6L, 6L, 6L, 6L, 6L, 6L, 100L, Some(6L))
  catch {
    AuthorityExpired(expires_at=6L, observed_at=6L) => ()
    _ => fail("unexpected derived-exclusive expiry error")
  } noraise {
    _ => fail("accepted authorization at derived exclusive deadline")
  }
  try
    cancellation_authorization_times_v22(-1L, 0L, 0L, 0L, 0L, 0L, 0L, None)
  catch {
    MalformedInput(field="cancellation_authorization_time_v22") => ()
    _ => fail("unexpected negative UTC error")
  } noraise {
    _ => fail("accepted negative UTC milliseconds")
  }
  try
    cancellation_authorization_times_v22(
      253402300799999L,
      253402300799999L,
      253402300799999L,
      253402300799999L,
      253402300799999L,
      253402300799999L,
      253402300799998L,
      None,
    )
  catch {
    AuthorityExpired(expires_at=253402300799999L, observed_at=253402300799999L) =>
      ()
    _ => fail("unexpected maximum UTC boundary error")
  } noraise {
    _ => fail("maximum UTC millisecond bypassed convertible governance cutoff")
  }
  try
    cancellation_authorization_times_v22(
      253402300800000L,
      253402300800000L,
      253402300800000L,
      253402300800000L,
      253402300800000L,
      253402300800000L,
      253402300799998L,
      None,
    )
  catch {
    MalformedInput(field="cancellation_authorization_time_v22") => ()
    _ => fail("unexpected UTC upper-plus-one error")
  } noraise {
    _ => fail("accepted UTC upper-plus-one")
  }
  for invalid_request_expiry in [-1L, 0L, 253402300800000L] {
    try
      cancellation_authorization_times_v22(
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        10L,
        Some(invalid_request_expiry),
      )
    catch {
      MalformedInput(field="request_deadline_exclusive_v22") => ()
      _ => fail("unexpected optional request-expiry boundary error")
    } noraise {
      _ => fail("accepted invalid optional request expiry")
    }
  }
  try
    cancellation_authorization_times_v22(
      0L,
      0L,
      0L,
      0L,
      0L,
      0L,
      253402300800000L,
      None,
    )
  catch {
    MalformedInput(field="governance_valid_until_inclusive_v22") => ()
    _ => fail("unexpected governance cutoff upper-plus-one error")
  } noraise {
    _ => fail("accepted governance cutoff upper-plus-one")
  }
  try
    cancellation_authorization_times_v22(1L, 3L, 2L, 4L, 5L, 6L, 100L, None)
  catch {
    ClockRegression(previous=3L, incoming=2L) => ()
    _ => fail("expected committed governance time regression rejection")
  } noraise {
    _ => fail("expected committed governance time regression rejection")
  }
  try checked_exclusive_deadline_v22(253402300799999L) catch {
    ArithmeticOverflow(field="exclusive_deadline_v22") => ()
    _ => fail("expected checked exclusive-deadline overflow rejection")
  } noraise {
    _ => fail("expected checked exclusive-deadline overflow rejection")
  }
}
