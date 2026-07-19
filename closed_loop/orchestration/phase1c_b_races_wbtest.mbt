///|
fn phase1c_b_terminal_loss(
  outcome : WorkTerminalOutcomeV2,
) -> LifecycleRaceLossReasonV2 {
  match outcome {
    SucceededV2 => LostToSucceededTerminalV2
    FailedNonRetryableV2 => LostToFailedNonRetryableTerminalV2
    FailedRetryExhaustedV2 => LostToFailedRetryExhaustedTerminalV2
    FailedCancellationStoppedRetryV2 =>
      LostToFailedCancellationStoppedRetryTerminalV2
    CancelledBeforeEffectIntentV2 => LostToCancelledBeforeEffectIntentTerminalV2
    CancelledAfterReconciledNotAppliedV2 =>
      LostToCancelledAfterReconciledNotAppliedTerminalV2
  }
}

///|
fn phase1c_b_category_for_request(
  request : @storage.CommitRequest,
) -> LifecycleCandidateCategoryV2 raise {
  let kind = classify_lifecycle_events_v2(request.events())
  public_lifecycle_category_v2(kind).unwrap()
}

///|
fn phase1c_b_combined_memory_store(
  work : @storage.ReplayResult,
  governance : @storage.ReplayResult,
) -> @storage.MemoryStore raise {
  let store = phase1b_clone_replay_to_memory(work)
  phase1b_append_replay_to_memory(store, governance)
  store
}

///|
fn phase1c_b_bound_memory_store(
  store : @storage.MemoryStore,
  candidate : LifecycleCommitCandidateV2,
) -> @storage.GuardedMemoryStore raise {
  let guards = [
    for head_guard in candidate.guarded_request.guards() => {
      head_guard.workflow()
    }
  ]
  let receipt = store.activate_guarded_workflow(
    candidate.request.workflow(),
    guards,
  )
  @storage.GuardedMemoryStore::new(store, receipt)
}

///|
fn phase1c_b_commit_memory(
  store : @storage.MemoryStore,
  candidate : LifecycleCommitCandidateV2,
) -> LifecycleCommitOutcomeV2 raise {
  commit_lifecycle_candidate_v2(
    phase1c_b_bound_memory_store(store, candidate),
    candidate,
  )
}

///|
fn phase1c_b_guarded_test_request(
  current : CurrentGovernedClosedLoopProjectionV2,
  request : @storage.CommitRequest,
) -> @storage.GuardedCommitRequest raise {
  guarded_lifecycle_commit_request_v22(current, request)
}

///|
fn phase1c_b_append_governance_advance(
  store : @storage.MemoryStore,
  governance : @storage.ReplayResult,
  suffix : String,
) -> @storage.ReplayResult raise {
  let source = governance.events().last().unwrap()
  let next_sequence = governance.head().sequence() + 1L
  let event = phase1b_clone_governance_event(
    source,
    "phase1c-b-governance-advance-event-" + suffix,
    "phase1c-b-governance-advance-event-key-" + suffix,
    next_sequence,
    Some(source),
  )
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        governance.record_version().text(),
        governance.schema_version().text(),
        governance.workflow(),
        governance.head().revision(),
        "phase1c-b-governance-advance-command-" + suffix,
        [event],
        [],
      ),
    ),
  )
  store.replay(governance.workflow())
}

///|
fn phase1c_b_require_governance_advance_stale(
  label : String,
  work : @storage.ReplayResult,
  governance : @storage.ReplayResult,
  candidate : LifecycleCommitCandidateV2,
) -> Unit raise {
  let store = phase1c_b_combined_memory_store(work, governance)
  let before = store.replay(work.workflow())
  let advanced = phase1c_b_append_governance_advance(store, governance, label)
  guard phase1c_b_commit_memory(store, candidate)
    is LifecycleStaleGovernanceV2(stale) else {
    fail("governance-only advance did not stale candidate: " + label)
  }
  stale.validate_current(advanced)
  assert_eq(stale.actual_revision(), governance.head().revision() + 1L)
  assert_true(stale.actual_replay_digest() == advanced.replay_digest())
  let after = store.replay(work.workflow())
  assert_true(before.replay_digest() == after.replay_digest())
  assert_true(before.head() == after.head())
}

///|
priv struct Phase1cBCancellation {
  prepared : PreparedCancellationV2
  governance_replay : @storage.ReplayResult
  current : CurrentGovernedClosedLoopProjectionV2
}

///|
fn phase1c_b_prepare_cancellation(
  current : CurrentGovernedClosedLoopProjectionV2,
  empty_effects : @effects.EffectsProjection,
  work_replay : @storage.ReplayResult,
  registration : ScheduleRegisteredV2,
  governed_subject : @contracts.RecordRef,
  suffix : String,
) -> Phase1cBCancellation raise {
  let root = fold_initial_work_receipt_v22(empty_effects, work_replay)
  let evidence = [ for value in registration.schedule().evidence() => value ]
  let proposal = CancellationProposalV2::new(
    "phase1c-b-proposal-" + suffix,
    root,
    current.work,
    governed_subject,
    phase1a_wb_ref(
      "reason",
      "phase1c-b-reason-" + suffix,
      @utf8.encode("phase1c-b-reason-" + suffix),
    ),
    10L,
    evidence,
    phase1a_wb_ref(
      "causation",
      "phase1c-b-causation-" + suffix,
      @utf8.encode("phase1c-b-causation-" + suffix),
    ),
    "phase1c-b-proposal-event-key-" + suffix,
    "phase1c-b-proposal-command-key-" + suffix,
  )
  let chain = phase1b_governance_chain(
    phase1a_wb_policy(),
    root.governance_stream_ref(),
    proposal,
    evidence,
    "phase1c-b-" + suffix,
    expires_at=Some(100L),
  )
  let governance_replay = chain.store.replay(root.governance_stream_ref())
  let governed = fold_governed_closed_loop_v2(
    empty_effects, work_replay, governance_replay,
  )
  let receipt = governed.committed_cancellation_governance_receipt(proposal)
  let authorization = CancellationAuthorizationV2::from_committed_governance(
    "phase1c-b-authorization-" + suffix,
    receipt,
    proposal,
    governed,
  )
  let request = CancellationRequestV2::new(
    "phase1c-b-request-" + suffix,
    proposal,
    authorization,
  )
  {
    prepared: prepare_cancellation_v2(governed, request),
    governance_replay,
    current: governed,
  }
}

///|
priv struct Phase1cBAtomicRetry {
  outcome : Phase1b3COutcomeFixture
  policy : RetryPolicyV2
  guarded_request : GuardedRetryScheduleRequestV2
  retry_commit : GuardedAtomicRetryV2
  candidate : LifecycleCommitCandidateV2
}

///|
fn phase1c_b_atomic_retry(suffix : String) -> Phase1cBAtomicRetry raise {
  let policy = phase1b3_c_policy("phase1c-b-" + suffix, 3L, 2L, [
    "terminal_failed",
  ])
  let outcome = phase1b3_c_known_failure_fixture("phase1c-b-" + suffix, policy)
  let current = outcome.current
  let open = current.open_work_authority()
  let evidence = [flow7_v2_evidence()]
  let requested_work = phase1b_test_envelope(
    "phase1c-b-retry-work-" + suffix,
    "requested-work",
    outcome.fixture.intent.governance().governed_subject(),
    @utf8.encode("phase1c-b-retry-work-" + suffix),
    evidence,
  )
  let requested_ref = @contracts.RecordRef::new(
    "requested-work",
    requested_work.envelope_id(),
    "1.0.0",
    requested_work.envelope_digest().text(),
  )
  let guarded_request = prepare_guarded_retry_schedule_request_v2(
    current,
    open,
    outcome.retry_receipt,
    policy,
    outcome.fixture.intent.governance(),
    "phase1c-b-retry-request-" + suffix,
    "phase1c-b-retry-attempt-" + suffix,
    "phase1c-b-retry-attempt-key-" + suffix,
    requested_work,
    "attempt",
    "1.0.0",
    "effect",
    "1.0.0",
    @contracts.sha256_digest(
      @utf8.encode("phase1c-b-retry-attempt-key-" + suffix + "-artifact"),
    ),
    "phase1c-b-retry-schedule-" + suffix,
    "phase1c-b-retry-schedule-key-" + suffix,
    40L,
    40L,
    40L,
    "phase1c-b-retry-command-" + suffix,
  )
  let timing = RetryTimingV2::compute(policy, outcome.retry_receipt)
  let admission = flow7_aggregate_admission(
    "phase1c-b-retry-admission-" + suffix,
    outcome.fixture.registration.workflow(),
    current.work.prefix_event().unwrap(),
    timing.due_at(),
    40L,
    outcome.fixture.intent.governance().policy_ref(),
    flow7_aggregate_planned(
      outcome.fixture.registration.workflow(),
      outcome.fixture.intent.governance().governed_subject(),
      requested_ref,
      requested_work.envelope_digest(),
      2L,
      "phase1c-b-retry-attempt-key-" + suffix,
      guarded_request.request().request_ref(),
    ),
    evidence[0],
    lease_epoch=2L,
    fencing_token=2L,
  )
  let retry_commit = prepare_guarded_atomic_retry_v2(
    current,
    open,
    guarded_request,
    outcome.retry_receipt,
    policy,
    admission,
    outcome.fixture.intent.governance(),
    "phase1c-b-retry-plan-" + suffix,
    "phase1c-b-retry-attempt-" + suffix,
    "phase1c-b-retry-attempt-event-" + suffix,
    "phase1c-b-retry-attempt-key-" + suffix,
    requested_work,
    evidence,
    outcome.retry_receipt.source_observed_at(),
    "phase1c-b-retry-schedule-" + suffix,
    "phase1c-b-retry-schedule-key-" + suffix,
    40L,
    "phase1c-b-retry-schedule-event-" + suffix,
    "phase1c-b-retry-registration-" + suffix,
    "phase1c-b-retry-command-" + suffix,
  )
  let candidate = prepare_lifecycle_atomic_retry_candidate_v2(
    current,
    open,
    guarded_request,
    outcome.retry_receipt,
    policy,
    admission,
    outcome.fixture.intent.governance(),
    "phase1c-b-retry-plan-" + suffix,
    "phase1c-b-retry-attempt-" + suffix,
    "phase1c-b-retry-attempt-event-" + suffix,
    "phase1c-b-retry-attempt-key-" + suffix,
    requested_work,
    evidence,
    outcome.retry_receipt.source_observed_at(),
    "phase1c-b-retry-schedule-" + suffix,
    "phase1c-b-retry-schedule-key-" + suffix,
    40L,
    "phase1c-b-retry-schedule-event-" + suffix,
    "phase1c-b-retry-registration-" + suffix,
    "phase1c-b-retry-command-" + suffix,
  )
  { outcome, policy, guarded_request, retry_commit, candidate }
}

///|
fn phase1c_b_tamper_current_replay_digest(
  current : CurrentGovernedClosedLoopProjectionV2,
) -> CurrentGovernedClosedLoopProjectionV2 {
  {
    cancellation_authoritative: current.cancellation_authoritative,
    governance: current.governance,
    governance_events: current.governance_events,
    governance_head_digest: current.governance_head_digest,
    governance_policy: current.governance_policy,
    governance_replay_digest: current.governance_replay_digest,
    governance_revision: current.governance_revision,
    governance_sequence: current.governance_sequence,
    governance_state_digest: current.governance_state_digest,
    phase2_recovery_active: current.phase2_recovery_active,
    phase2_recovery_activations: current.phase2_recovery_activations,
    root_binding: current.root_binding,
    work: current.work,
    work_effects_state_digest: current.work_effects_state_digest,
    work_head_digest: current.work_head_digest,
    work_orchestration_state_digest: current.work_orchestration_state_digest,
    work_replay_digest: @contracts.sha256_digest(b"phase1c-b-tampered-replay"),
    work_revision: current.work_revision,
    work_sequence: current.work_sequence,
  }
}

///|
test "FLOW-7 Phase1C-B retry preparation is pure and classifies only exact staleness" {
  let retry = try phase1c_b_atomic_retry("retry-currentness") catch {
    error => fail("retry fixture failed: \{to_repr(error)}")
  } noraise {
    value => value
  }
  let open = retry.outcome.current.open_work_authority()
  let prepared = retry.guarded_request.retry_preparation_currentness(
    retry.outcome.current,
    open,
  )
  assert_true(
    prepared.validate_current(retry.outcome.current) ==
    RetryPreparationCurrentV2,
  )
  assert_true(!prepared.canonical_bytes().is_empty())
  assert_true(
    prepared.digest() == @contracts.sha256_digest(prepared.canonical_bytes()),
  )

  let wrong_open : OpenWorkAuthorityV2 = {
    authority_ref: open.authority_ref,
    canonical: open.canonical,
    digest: open.digest,
    governance_head_digest: open.governance_head_digest,
    governance_revision: open.governance_revision,
    work_head_digest: open.work_head_digest,
    work_replay_digest: open.work_replay_digest,
    work_revision: open.work_revision,
    workflow: phase1a_wb_ref(
      "workflow", "phase1c-b-retry-wrong-workflow", b"phase1c-b-retry-wrong-workflow",
    ),
  }
  let wrong_prepared : RetryPreparationCurrentnessV2 = {
    request_ref: prepared.request_ref,
    open: wrong_open,
    authorization: prepared.authorization,
    work_revision: prepared.work_revision,
    work_head_digest: prepared.work_head_digest,
    canonical: prepared.canonical,
    digest: prepared.digest,
  }
  try ignore(wrong_prepared.validate_current(retry.outcome.current)) catch {
    WorkflowMismatch(field="retry_preparation_currentness_workflow") => ()
    error => fail("unexpected retry workflow error: \{to_repr(error)}")
  } noraise {
    _ => fail("retry preparation accepted a different workflow")
  }

  let corrupt = phase1c_b_tamper_current_replay_digest(retry.outcome.current)
  try ignore(prepared.validate_current(corrupt)) catch {
    CancellationPrecedenceViolation(field="open_work_authority_not_current") =>
      ()
    error => fail("unexpected retry corruption error: \{to_repr(error)}")
  } noraise {
    _ => fail("retry preparation downgraded replay corruption to staleness")
  }

  let terminal_policy = phase1b3_c_policy(
    "phase1c-b-retry-currentness-terminal",
    3L,
    2L,
    [],
  )
  let terminal_outcome = phase1b3_c_known_failure_fixture(
    "phase1c-b-retry-currentness-terminal", terminal_policy,
  )
  let terminal_store = phase1b_clone_replay_to_memory(
    terminal_outcome.fixture.work_store.replay(
      terminal_outcome.fixture.registration.workflow(),
    ),
  )
  let terminal = prepare_failed_work_terminal_v2(
    terminal_outcome.current,
    terminal_outcome.source,
  )
  ignore(terminal_store.commit(terminal.commit_request()))
  let terminal_current = fold_governed_closed_loop_v2(
    terminal_outcome.fixture.empty_effects,
    terminal_store.replay(terminal_outcome.fixture.registration.workflow()),
    terminal_outcome.governance_replay,
  )
  assert_true(
    prepared.validate_current(terminal_current) ==
    RetryPreparationStaleAfterTerminalV2,
  )

  let cancellation = try
    phase1c_b_prepare_cancellation(
      retry.outcome.current,
      retry.outcome.fixture.empty_effects,
      retry.outcome.fixture.work_store.replay(
        retry.outcome.fixture.registration.workflow(),
      ),
      retry.outcome.fixture.registration,
      retry.outcome.fixture.intent.governance().governed_subject(),
      "retry-currentness",
    )
  catch {
    error => fail("retry cancellation fixture failed: \{to_repr(error)}")
  } noraise {
    value => value
  }
  let cancellation_store = phase1b_clone_replay_to_memory(
    retry.outcome.fixture.work_store.replay(
      retry.outcome.fixture.registration.workflow(),
    ),
  )
  ignore(cancellation_store.commit(cancellation.prepared.commit_request()))
  let cancelled_current = fold_governed_closed_loop_v2(
    retry.outcome.fixture.empty_effects,
    cancellation_store.replay(retry.outcome.fixture.registration.workflow()),
    cancellation.governance_replay,
  )
  assert_true(
    prepared.validate_current(cancelled_current) ==
    RetryPreparationStaleAfterCancellationV2,
  )

  let advanced_store = phase1b_clone_replay_to_memory(
    retry.outcome.fixture.work_store.replay(
      retry.outcome.fixture.registration.workflow(),
    ),
  )
  let advanced_current = try {
    ignore(advanced_store.commit(retry.retry_commit.request()))
    fold_governed_closed_loop_v2(
      retry.outcome.fixture.empty_effects,
      advanced_store.replay(retry.outcome.fixture.registration.workflow()),
      retry.outcome.governance_replay,
    )
  } catch {
    error => fail("retry durable advance failed: \{to_repr(error)}")
  } noraise {
    value => value
  }
  assert_true(
    prepared.validate_current(advanced_current) ==
    RetryPreparationStaleAfterDurableAdvanceV2,
  )
  try
    ignore(
      prepare_guarded_atomic_retry_v2(
        advanced_current,
        advanced_current.open_work_authority(),
        retry.guarded_request,
        retry.outcome.retry_receipt,
        retry.policy,
        retry.retry_commit.registration().schedule().admission(),
        retry.outcome.fixture.intent.governance(),
        "phase1c-b-stale-plan",
        retry.retry_commit.attempt().attempt_ref().id(),
        "phase1c-b-stale-attempt-event",
        retry.retry_commit.attempt().idempotency_key(),
        retry.retry_commit.attempt().requested_work(),
        [
          for value in retry.retry_commit.attempt().evidence() => value
        ],
        retry.outcome.retry_receipt.source_observed_at(),
        retry.retry_commit.registration().schedule().schedule_ref().id(),
        retry.retry_commit.registration().schedule().idempotency_key(),
        retry.retry_commit.registration().schedule().deadline().unwrap(),
        "phase1c-b-stale-schedule-event",
        retry.retry_commit.registration().record_ref().id(),
        retry.retry_commit.request().command_idempotency_key(),
      ),
    )
  catch {
    CancellationPrecedenceViolation(field="open_work_authority_scope") => ()
    error => fail("unexpected stale atomic retry error: \{to_repr(error)}")
  } noraise {
    _ => fail("stale retry preparation became atomic authority")
  }
}

///|
priv struct Phase1cBReconciliation {
  fixture : Phase1bPendingFixture
  governance_replay : @storage.ReplayResult
  request_prefix : @storage.ReplayResult
  request_candidate : LifecycleCommitCandidateV2
  resolution_prefix : @storage.ReplayResult
  resolution_candidate : LifecycleCommitCandidateV2
}

///|
fn phase1c_b_reconciliation(suffix : String) -> Phase1cBReconciliation raise {
  let policy = phase1b3_c_policy("phase1c-b-reconciliation-" + suffix, 3L, 2L, [
    "terminal_failed", "reconciled_not_applied",
  ])
  let fixture = phase1b_pending_fixture(
    "phase1c-b-reconciliation-" + suffix,
    retry_policy=policy,
  )
  let governance_replay = fixture.governance.store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  let lease_settled = phase1b3_c_settle_root_lease(
    fixture,
    governance_replay,
    "phase1c-b-reconciliation-" + suffix,
  )
  let observed = phase1b3_c_observe_intent(
    lease_settled,
    fixture.work_store,
    fixture.empty_effects,
    fixture.registration.workflow(),
    fixture.intent,
    governance_replay,
    "phase1c-b-reconciliation-" + suffix,
  )
  let evidence = [ for value in fixture.intent.evidence() => value ]
  let unknown_receipt = @effects.EffectReceipt::new(
    "phase1c-b-unknown-receipt-" + suffix,
    "1.0.0",
    fixture.intent,
    phase1b_test_envelope(
      "phase1c-b-unknown-envelope-" + suffix,
      "dispatcher-receipt",
      fixture.intent.governance().governed_subject(),
      @utf8.encode("phase1c-b-unknown-" + suffix),
      evidence,
    ),
    @effects.Unknown,
    30L,
    evidence,
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  let receipt_authority = observed.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "receipt.record",
    unknown_receipt.receipt_ref(),
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_effect_receipt_v2(
        observed,
        receipt_authority,
        "phase1c-b-unknown-event-" + suffix,
        "phase1c-b-unknown-command-" + suffix,
        unknown_receipt,
      ),
    ),
  )
  let request_prefix = fixture.work_store.replay(
    fixture.registration.workflow(),
  )
  let unknown = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    request_prefix,
    governance_replay,
  )
  let request = @effects.ReconciliationRequest::new(
    "phase1c-b-reconciliation-request-" + suffix,
    fixture.intent,
    unknown_receipt,
    31L,
    evidence,
  )
  let request_authority = unknown.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "reconciliation.request",
    request.request_ref(),
  )
  let request_candidate = prepare_lifecycle_reconciliation_request_candidate_v2(
    unknown,
    request_authority,
    "phase1c-b-reconciliation-request-event-" + suffix,
    "phase1c-b-reconciliation-request-command-" + suffix,
    request,
  )
  ignore(fixture.work_store.commit(request_candidate.request))
  let resolution_prefix = fixture.work_store.replay(
    fixture.registration.workflow(),
  )
  let requested = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    resolution_prefix,
    governance_replay,
  )
  let resolution = @effects.ReconciliationRecord::new(
    "phase1c-b-reconciliation-resolution-" + suffix,
    fixture.intent,
    request,
    @effects.ReconciledNotApplied,
    phase1b_test_envelope(
      "phase1c-b-reconciliation-resolution-envelope-" + suffix,
      "reconciliation-observation",
      fixture.intent.governance().governed_subject(),
      @utf8.encode("phase1c-b-reconciliation-resolution-" + suffix),
      evidence,
    ),
    32L,
    evidence,
  )
  let resolution_authority = requested.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "reconciliation.resolve",
    resolution.reconciliation_ref(),
  )
  let resolution_candidate = prepare_lifecycle_reconciliation_resolution_candidate_v2(
    requested,
    resolution_authority,
    "phase1c-b-reconciliation-resolution-event-" + suffix,
    "phase1c-b-reconciliation-resolution-command-" + suffix,
    resolution,
  )
  {
    fixture,
    governance_replay,
    request_prefix,
    request_candidate,
    resolution_prefix,
    resolution_candidate,
  }
}

///|
fn phase1c_b_require_candidate_cancellation_race(
  label : String,
  empty_effects : @effects.EffectsProjection,
  prefix : @storage.ReplayResult,
  registration : ScheduleRegisteredV2,
  governed_subject : @contracts.RecordRef,
  current : CurrentGovernedClosedLoopProjectionV2,
  candidate_governance_replay : @storage.ReplayResult,
  candidate : LifecycleCommitCandidateV2,
) -> Unit raise {
  let cancellation = phase1c_b_prepare_cancellation(
    current, empty_effects, prefix, registration, governed_subject, label,
  )
  let cancellation_candidate = lifecycle_candidate_from_prepared_cancellation_v22(
    cancellation.prepared,
    cancellation.current,
  )
  assert_eq(
    candidate.request.expected_revision(),
    cancellation_candidate.request.expected_revision(),
  )
  let mut saw_candidate_first = false
  let mut saw_cancellation_first = false
  for seed in [3L, 7L, 19L, 31L, 73L, 211L] {
    let candidate_first = @decision.recorded_order_key(seed, 0) <
      @decision.recorded_order_key(seed, 1)
    if candidate_first {
      saw_candidate_first = true
    } else {
      saw_cancellation_first = true
    }
    let actual_governance_replay = if candidate_first {
      candidate_governance_replay
    } else {
      cancellation.governance_replay
    }
    let store = phase1c_b_combined_memory_store(
      prefix, actual_governance_replay,
    )
    let winner = if candidate_first {
      phase1c_b_commit_memory(store, candidate)
    } else {
      phase1c_b_commit_memory(store, cancellation_candidate)
    }
    guard winner is LifecycleCommittedV2(committed) else {
      fail("candidate/cancellation winner missing: " + label)
    }
    let loser = if candidate_first {
      phase1c_b_commit_memory(store, cancellation_candidate)
    } else {
      phase1c_b_commit_memory(store, candidate)
    }
    guard loser is LifecycleStaleGovernanceV2(stale) else {
      fail("alternate-governance loser was not stale: " + label)
    }
    stale.validate_current(actual_governance_replay)
    assert_true(stale.expected_replay_digest() != stale.actual_replay_digest())
    let replay = store.replay(registration.workflow())
    committed.validate_replay_binding(replay)
    let contested = replay
      .committed_batches()
      .filter(boundary => {
        boundary.expected_revision() == candidate.request.expected_revision()
      })
    assert_eq(contested.length(), 1)
    if !candidate_first {
      let cancelled = fold_governed_closed_loop_v2(
        empty_effects,
        replay,
        cancellation.governance_replay,
      )
      try ignore(cancelled.open_work_authority()) catch {
        CancellationPrecedenceViolation(field="open_work_authority_not_current") =>
          ()
        error =>
          fail(
            "unexpected cancellation authority error: \{label}:\{to_repr(error)}",
          )
      } noraise {
        _ =>
          fail(
            "losing candidate retained authority after cancellation: " + label,
          )
      }
    }
  }
  assert_true(saw_candidate_first)
  assert_true(saw_cancellation_first)
}

///|
test "FLOW-7 Phase1C-B reconciliation request and resolution race cancellation" {
  let fixture = phase1c_b_reconciliation("races")
  let request_current = fold_governed_closed_loop_v2(
    fixture.fixture.empty_effects,
    fixture.request_prefix,
    fixture.governance_replay,
  )
  phase1c_b_require_candidate_cancellation_race(
    "reconciliation-request",
    fixture.fixture.empty_effects,
    fixture.request_prefix,
    fixture.fixture.registration,
    fixture.fixture.intent.governance().governed_subject(),
    request_current,
    fixture.governance_replay,
    fixture.request_candidate,
  )
  let resolution_current = fold_governed_closed_loop_v2(
    fixture.fixture.empty_effects,
    fixture.resolution_prefix,
    fixture.governance_replay,
  )
  phase1c_b_require_candidate_cancellation_race(
    "reconciliation-resolution",
    fixture.fixture.empty_effects,
    fixture.resolution_prefix,
    fixture.fixture.registration,
    fixture.fixture.intent.governance().governed_subject(),
    resolution_current,
    fixture.governance_replay,
    fixture.resolution_candidate,
  )
}

///|
test "FLOW-7 Phase1C-B atomic retry commit races cancellation in both orders" {
  let retry = phase1c_b_atomic_retry("atomic-race")
  let prefix = retry.outcome.fixture.work_store.replay(
    retry.outcome.fixture.registration.workflow(),
  )
  phase1c_b_require_candidate_cancellation_race(
    "atomic-retry",
    retry.outcome.fixture.empty_effects,
    prefix,
    retry.outcome.fixture.registration,
    retry.outcome.fixture.intent.governance().governed_subject(),
    retry.outcome.current,
    retry.outcome.fixture.governance.store.replay(
      retry.outcome.current.root_binding.governance_stream_ref(),
    ),
    retry.candidate,
  )
}

///|
priv struct Phase1cBLeaseLifecycle {
  fixture : Phase1bFixture
  governance_replay : @storage.ReplayResult
  expiry_prefix : @storage.ReplayResult
  expiry_current : CurrentGovernedClosedLoopProjectionV2
  expiry_candidate : LifecycleCommitCandidateV2
  reclaim_prefix : @storage.ReplayResult
  reclaim_current : CurrentGovernedClosedLoopProjectionV2
  reclaim_candidate : LifecycleCommitCandidateV2
}

///|
fn phase1c_b_lease_lifecycle(suffix : String) -> Phase1cBLeaseLifecycle raise {
  let fixture = phase1b_fixture(
    suffix="phase1c-b-lease-life-" + suffix,
    expires_at=Some(100L),
  )
  let governance_replay = fixture.governance.store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  let (claim_candidate, _) = phase1c_b_lease_claim_candidate(
    fixture,
    "lease-life-" + suffix,
  )
  ignore(fixture.work_store.commit(claim_candidate.request))
  let expiry_prefix = fixture.work_store.replay(fixture.registration.workflow())
  let expiry_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    expiry_prefix,
    governance_replay,
  )
  guard expiry_current.committed_lease_authority_receipt_v2()
    is Some(lease_receipt) else {
    fail("lease lifecycle authority receipt missing")
  }
  let expiry = LeaseExpiryV2::new(
    "phase1c-b-expiry-" + suffix,
    fixture.registration,
    lease_receipt,
    flow7_lifecycle_active_authorization(
      "phase1c-b-expiry-" + suffix,
      expiry_current.work.orchestration(),
      fixture.registration,
      lease_receipt,
      ExpireLeaseV2,
      None,
      lease_receipt.expires_at(),
    ),
  )
  let expiry_authorization = expiry_current.authorize_lease_settlement_v2(
    "lease.expire",
    expiry.record_ref(),
  )
  let expiry_candidate = prepare_lifecycle_lease_expiry_candidate_v2(
    expiry_current,
    expiry_authorization,
    "phase1c-b-expiry-event-" + suffix,
    expiry.idempotency_key(),
    "phase1c-b-expiry-command-" + suffix,
    expiry,
  )
  let reclaim_store = phase1b_clone_replay_to_memory(expiry_prefix)
  let release = LeaseReleaseV2::new(
    "phase1c-b-release-for-reclaim-" + suffix,
    fixture.registration,
    lease_receipt,
    flow7_lifecycle_active_authorization(
      "phase1c-b-release-for-reclaim-" + suffix,
      expiry_current.work.orchestration(),
      fixture.registration,
      lease_receipt,
      ReleaseLeaseV2,
      None,
      12L,
    ),
  )
  let release_authorization = expiry_current.authorize_lease_settlement_v2(
    "lease.release",
    release.record_ref(),
  )
  ignore(
    reclaim_store.commit(
      prepare_guarded_lease_released_v2(
        expiry_current,
        release_authorization,
        "phase1c-b-release-for-reclaim-event-" + suffix,
        release.idempotency_key(),
        "phase1c-b-release-for-reclaim-command-" + suffix,
        release,
      ),
    ),
  )
  let reclaim_prefix = reclaim_store.replay(fixture.registration.workflow())
  let reclaim_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    reclaim_prefix,
    governance_replay,
  )
  guard reclaim_current.work.orchestration().committed_lease_terminal_receipt()
    is Some(terminal_receipt) else {
    fail("lease lifecycle terminal receipt missing")
  }
  let owner = phase1a_wb_ref(
    "owner",
    "phase1c-b-reclaim-owner-" + suffix,
    @utf8.encode("phase1c-b-reclaim-owner-" + suffix),
  )
  let reclaim = LeaseReclaimV2::new(
    "phase1c-b-reclaim-" + suffix,
    fixture.registration,
    terminal_receipt,
    flow7_lifecycle_terminal_authorization(
      "phase1c-b-reclaim-" + suffix,
      reclaim_current.work.orchestration(),
      fixture.registration,
      terminal_receipt,
      owner,
      5L,
      reclaim_current.work.orchestration().epoch_floor() + 1L,
      reclaim_current.work.orchestration().fencing_floor() + 1L,
      13L,
    ),
  )
  let open = reclaim_current.open_work_authority()
  let reclaim_authorization = reclaim_current.authorize_open_work_operation(
    open,
    "lease.reclaim",
    reclaim.record_ref(),
  )
  let reclaim_candidate = prepare_lifecycle_lease_reclaim_candidate_v2(
    reclaim_current,
    open,
    reclaim_authorization,
    "phase1c-b-reclaim-event-" + suffix,
    reclaim.idempotency_key(),
    "phase1c-b-reclaim-command-" + suffix,
    reclaim,
  )
  {
    fixture,
    governance_replay,
    expiry_prefix,
    expiry_current,
    expiry_candidate,
    reclaim_prefix,
    reclaim_current,
    reclaim_candidate,
  }
}

///|
test "FLOW-7 Phase1C-B lease expiry and reclaim race cancellation" {
  let lease = try phase1c_b_lease_lifecycle("races") catch {
    error => fail("lease lifecycle fixture failed: \{to_repr(error)}")
  } noraise {
    value => value
  }
  let subject = lease.fixture.registration
    .schedule()
    .admission()
    .governance()
    .governed_subject()
  phase1c_b_require_candidate_cancellation_race(
    "lease-expiry",
    lease.fixture.empty_effects,
    lease.expiry_prefix,
    lease.fixture.registration,
    subject,
    lease.expiry_current,
    lease.governance_replay,
    lease.expiry_candidate,
  )
  phase1c_b_require_candidate_cancellation_race(
    "lease-reclaim",
    lease.fixture.empty_effects,
    lease.reclaim_prefix,
    lease.fixture.registration,
    subject,
    lease.reclaim_current,
    lease.governance_replay,
    lease.reclaim_candidate,
  )
}

///|
test "FLOW-7 Phase1C-B stale workers observe one durable lease claim" {
  let fixture = phase1b_fixture(suffix="phase1c-b-stale-workers")
  let (first, first_owner) = phase1c_b_lease_claim_candidate(
    fixture, "stale-worker-a",
  )
  let (second, second_owner) = phase1c_b_lease_claim_candidate(
    fixture, "stale-worker-b",
  )
  let prefix = fixture.work_store.replay(fixture.registration.workflow())
  let governance_replay = fixture.governance.store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  let mut saw_first = false
  let mut saw_second = false
  for seed in [3L, 7L, 19L, 31L, 73L, 211L] {
    let first_wins = @decision.recorded_order_key(seed, 0) <
      @decision.recorded_order_key(seed, 1)
    if first_wins {
      saw_first = true
    } else {
      saw_second = true
    }
    let store = phase1c_b_combined_memory_store(prefix, governance_replay)
    let winner = if first_wins {
      phase1c_b_commit_memory(store, first)
    } else {
      phase1c_b_commit_memory(store, second)
    }
    guard winner is LifecycleCommittedV2(_) else {
      fail("stale-worker winner missing")
    }
    let loser = if first_wins {
      phase1c_b_commit_memory(store, second)
    } else {
      phase1c_b_commit_memory(store, first)
    }
    guard loser is LifecycleLostV2(loss) else {
      fail("stale-worker loss receipt missing")
    }
    assert_true(loss.reason() == LostToLeaseClaimV2)
    let replay = store.replay(fixture.registration.workflow())
    loss.validate_replay_binding(replay)
    let current = fold_governed_closed_loop_v2(
      fixture.empty_effects,
      replay,
      fixture.governance.store.replay(
        fixture.current.root_binding.governance_stream_ref(),
      ),
    )
    guard current.committed_lease_authority_receipt_v2() is Some(receipt) else {
      fail("stale-worker winning lease receipt missing")
    }
    let winning_owner = if first_wins { first_owner } else { second_owner }
    let losing_owner = if first_wins { second_owner } else { first_owner }
    assert_true(receipt.owner() == winning_owner)
    assert_true(receipt.owner() != losing_owner)
  }
  assert_true(saw_first)
  assert_true(saw_second)
}

///|
test "FLOW-7 Phase1C-B distinct safe terminal candidates have one durable terminal" {
  let fixture = phase1b_fixture(
    suffix="phase1c-b-safe-terminal-candidates",
    expires_at=Some(100L),
  )
  let first_prepared = prepare_cancellation_v2(fixture.current, fixture.request)
  let prefix = fixture.work_store.replay(fixture.registration.workflow())
  let second = phase1c_b_prepare_cancellation(
    fixture.current,
    fixture.empty_effects,
    prefix,
    fixture.registration,
    fixture.registration.schedule().admission().governance().governed_subject(),
    "safe-terminal-second",
  )
  assert_true(
    first_prepared.terminal_outcome() == Some(CancelledBeforeEffectIntentV2),
  )
  assert_true(
    second.prepared.terminal_outcome() == Some(CancelledBeforeEffectIntentV2),
  )
  let first = lifecycle_candidate_from_prepared_cancellation_v22(
    first_prepared,
    fixture.current,
  )
  let second_candidate = lifecycle_candidate_from_prepared_cancellation_v22(
    second.prepared,
    second.current,
  )
  assert_true(first.digest() != second_candidate.digest())
  let mut saw_first = false
  let mut saw_second = false
  for seed in [3L, 7L, 19L, 31L, 73L, 211L] {
    let first_wins = @decision.recorded_order_key(seed, 0) <
      @decision.recorded_order_key(seed, 1)
    if first_wins {
      saw_first = true
    } else {
      saw_second = true
    }
    let actual_governance_replay = if first_wins {
      fixture.governance.store.replay(
        fixture.current.root_binding.governance_stream_ref(),
      )
    } else {
      second.governance_replay
    }
    let store = phase1c_b_combined_memory_store(
      prefix, actual_governance_replay,
    )
    let winner = if first_wins {
      phase1c_b_commit_memory(store, first)
    } else {
      phase1c_b_commit_memory(store, second_candidate)
    }
    guard winner is LifecycleCommittedV2(_) else {
      fail("safe terminal winner missing")
    }
    let loser = if first_wins {
      phase1c_b_commit_memory(store, second_candidate)
    } else {
      phase1c_b_commit_memory(store, first)
    }
    guard loser is LifecycleStaleGovernanceV2(stale) else {
      fail("alternate-governance safe terminal loser was not stale")
    }
    stale.validate_current(actual_governance_replay)
    let replay = store.replay(fixture.registration.workflow())
    assert_eq(
      replay
      .events()
      .filter(event => {
        event.payload().envelope_kind() == work_terminal_event_kind_v22
      })
      .length(),
      1,
    )
    assert_eq(
      replay
      .events()
      .filter(event => {
        event.payload().envelope_kind() == cancellation_requested_event_kind_v22
      })
      .length(),
      1,
    )
    let current = fold_governed_closed_loop_v2(
      fixture.empty_effects,
      replay,
      actual_governance_replay,
    )
    guard current.committed_work_terminal_receipt() is Some(receipt) else {
      fail("safe terminal receipt missing")
    }
    assert_true(receipt.outcome() == CancelledBeforeEffectIntentV2)
  }
  assert_true(saw_first)
  assert_true(saw_second)
}

///|
test "FLOW-7 Phase1C-B loss receipt is stable after later legal append" {
  let fixture = phase1b_fixture(
    suffix="phase1c-b-loss-stability",
    expires_at=Some(100L),
  )
  let cancellation = prepare_lifecycle_cancellation_candidate_v2(
    fixture.current,
    fixture.request,
  )
  let (claim, _) = phase1c_b_lease_claim_candidate(fixture, "loss-stability")
  let store = phase1c_b_combined_memory_store(
    fixture.work_store.replay(fixture.registration.workflow()),
    fixture.governance.store.replay(
      fixture.current.root_binding.governance_stream_ref(),
    ),
  )
  let bound = phase1c_b_bound_memory_store(store, claim)
  guard commit_lifecycle_candidate_v2(bound, claim) is LifecycleCommittedV2(_) else {
    fail("loss stability claim did not commit")
  }
  guard commit_lifecycle_candidate_v2(bound, cancellation)
    is LifecycleLostV2(first_loss) else {
    fail("loss stability first loss missing")
  }
  let claimed = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    store.replay(fixture.registration.workflow()),
    fixture.governance.store.replay(
      fixture.current.root_binding.governance_stream_ref(),
    ),
  )
  guard claimed.committed_lease_authority_receipt_v2() is Some(lease_receipt) else {
    fail("loss stability lease receipt missing")
  }
  let release = LeaseReleaseV2::new(
    "phase1c-b-loss-stability-release",
    fixture.registration,
    lease_receipt,
    flow7_lifecycle_active_authorization(
      "phase1c-b-loss-stability-release",
      claimed.work.orchestration(),
      fixture.registration,
      lease_receipt,
      ReleaseLeaseV2,
      None,
      12L,
    ),
  )
  let authorization = claimed.authorize_lease_settlement_v2(
    "lease.release",
    release.record_ref(),
  )
  let release_request = prepare_guarded_lease_released_v2(
    claimed,
    authorization,
    "phase1c-b-loss-stability-release-event",
    release.idempotency_key(),
    "phase1c-b-loss-stability-release-command",
    release,
  )
  guard bound.guarded_commit(
      phase1c_b_guarded_test_request(claimed, release_request),
    )
    is @storage.GuardedCommitSucceeded(_) else {
    fail("loss stability guarded release did not commit")
  }
  let later_replay = store.replay(fixture.registration.workflow())
  first_loss.validate_replay_binding(later_replay)
  try first_loss.validate_current(later_replay) catch {
    RecoveryViolation(field="lifecycle_race_receipt_not_current") => ()
    error => fail("unexpected loss currentness error: \{to_repr(error)}")
  } noraise {
    _ => fail("historical loss receipt remained diagnostically current")
  }
  guard commit_lifecycle_candidate_v2(bound, cancellation)
    is LifecycleLostV2(duplicate_loss) else {
    fail("loss stability duplicate loss missing")
  }
  assert_true(first_loss.canonical_bytes() == duplicate_loss.canonical_bytes())
  assert_true(first_loss.digest() == duplicate_loss.digest())
  assert_true(first_loss.record_ref() == duplicate_loss.record_ref())
}

///|
fn phase1c_b_lease_claim_candidate(
  fixture : Phase1bFixture,
  suffix : String,
) -> (LifecycleCommitCandidateV2, @contracts.RecordRef) raise {
  let schedule = fixture.registration.schedule()
  let evidence = [ for value in schedule.evidence() => value ]
  let owner = phase1a_wb_ref(
    "owner",
    "phase1c-b-lease-owner-" + suffix,
    @utf8.encode("phase1c-b-lease-owner-" + suffix),
  )
  let claim = LeaseClaimV2::new(
    "phase1c-b-lease-claim-" + suffix,
    schedule,
    schedule.admission(),
    schedule.workflow(),
    owner,
    10L,
    fixture.current.work.orchestration().epoch_floor(),
    fixture.current.work.orchestration().fencing_floor(),
    1L,
    1L,
    "phase1c-b-lease-claim-key-" + suffix,
    evidence,
    fixture.current.work.prefix_event().unwrap().event_ref(),
  )
  let claimed = LeaseClaimedV2::new(
    "phase1c-b-lease-claimed-" + suffix,
    fixture.registration,
    claim,
  )
  let open = fixture.current.open_work_authority()
  let authorization = fixture.current.authorize_open_work_operation(
    open,
    "lease.claim",
    claimed.record_ref(),
  )
  (
    prepare_lifecycle_lease_claim_candidate_v2(
      fixture.current,
      open,
      authorization,
      "phase1c-b-lease-event-" + suffix,
      claim.idempotency_key(),
      "phase1c-b-lease-command-" + suffix,
      claimed,
    ),
    owner,
  )
}

///|
test "FLOW-7 Phase1C-B cancellation and lease claim race in both seeded orders" {
  let fixture = phase1b_fixture(suffix="phase1c-b-cancel-lease")
  let prepared_cancellation = prepare_cancellation_v2(
    fixture.current,
    fixture.request,
  )
  assert_true(
    prepared_cancellation.terminal_outcome() ==
    Some(CancelledBeforeEffectIntentV2),
  )
  let cancellation = lifecycle_candidate_from_prepared_cancellation_v22(
    prepared_cancellation,
    fixture.current,
  )
  let (claim, claim_owner) = phase1c_b_lease_claim_candidate(
    fixture, "cancel-lease",
  )
  assert_eq(
    cancellation.request.expected_revision(),
    claim.request.expected_revision(),
  )
  let prefix = fixture.work_store.replay(fixture.registration.workflow())
  let governance_replay = fixture.governance.store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  let mut saw_cancellation_first = false
  let mut saw_claim_first = false
  for seed in [3L, 7L, 19L, 31L, 73L, 211L] {
    let cancellation_first = @decision.recorded_order_key(seed, 0) <
      @decision.recorded_order_key(seed, 1)
    if cancellation_first {
      saw_cancellation_first = true
    } else {
      saw_claim_first = true
    }
    let store = phase1c_b_combined_memory_store(prefix, governance_replay)
    let winner = if cancellation_first {
      phase1c_b_commit_memory(store, cancellation)
    } else {
      phase1c_b_commit_memory(store, claim)
    }
    guard winner is LifecycleCommittedV2(committed) else {
      fail("seeded cancellation/claim winner missing")
    }
    committed.validate_replay_binding(
      store.replay(fixture.registration.workflow()),
    )
    let loser = if cancellation_first {
      phase1c_b_commit_memory(store, claim)
    } else {
      phase1c_b_commit_memory(store, cancellation)
    }
    guard loser is LifecycleLostV2(loss) else {
      fail("seeded cancellation/claim loser missing")
    }
    let expected_reason = if cancellation_first {
      LostToCancellationRequestV2
    } else {
      LostToLeaseClaimV2
    }
    assert_true(loss.reason() == expected_reason)
    let replay = store.replay(fixture.registration.workflow())
    loss.validate_replay_binding(replay)
    loss.validate_current(replay)
    let current = fold_governed_closed_loop_v2(
      fixture.empty_effects,
      replay,
      fixture.governance.store.replay(
        fixture.current.root_binding.governance_stream_ref(),
      ),
    )
    if cancellation_first {
      assert_true(current.committed_lease_authority_receipt_v2() is None)
      try ignore(current.open_work_authority()) catch {
        CancellationPrecedenceViolation(field="open_work_authority_not_current") =>
          ()
        error =>
          fail(
            "unexpected cancellation-winner authority error: \{to_repr(error)}",
          )
      } noraise {
        _ => fail("lease loser retained post-cancellation authority")
      }
    } else {
      guard current.committed_lease_authority_receipt_v2() is Some(receipt) else {
        fail("lease winner receipt missing")
      }
      assert_true(receipt.owner() == claim_owner)
      assert_true(current.work.cancellation is None)
    }
  }
  assert_true(saw_cancellation_first)
  assert_true(saw_claim_first)
}

///|
fn phase1c_b_require_terminal_cancel_order(
  label : String,
  terminal_first : Bool,
) -> Unit raise {
  let terminal = phase1b3_de_terminal_fixture(label)
  let cancellation = phase1b3_de_cancellation_candidate(
    terminal,
    "phase1c-b-\{label}-\{terminal_first}",
  )
  let terminal_category = phase1c_b_category_for_request(
    terminal.terminal_request,
  )
  let terminal_candidate = seal_lifecycle_candidate_v2(
    terminal_category,
    phase1c_b_guarded_test_request(
      fold_governed_closed_loop_v2(
        terminal.empty_effects,
        cancellation.prefix_replay,
        terminal.governance_replay,
      ),
      terminal.terminal_request,
    ),
  )
  let cancellation_current = fold_governed_closed_loop_v2(
    terminal.empty_effects,
    cancellation.prefix_replay,
    cancellation.governance_replay,
  )
  let cancellation_candidate = seal_lifecycle_candidate_v2(
    CancellationRequestCandidateV2,
    phase1c_b_guarded_test_request(cancellation_current, cancellation.request),
  )
  let actual_governance_replay = if terminal_first {
    terminal.governance_replay
  } else {
    cancellation.governance_replay
  }
  let store = phase1c_b_combined_memory_store(
    cancellation.prefix_replay,
    actual_governance_replay,
  )
  let winner = if terminal_first {
    phase1c_b_commit_memory(store, terminal_candidate)
  } else {
    phase1c_b_commit_memory(store, cancellation_candidate)
  }
  guard winner is LifecycleCommittedV2(_) else {
    fail("first candidate did not win: " + label)
  }
  let loser = if terminal_first {
    phase1c_b_commit_memory(store, cancellation_candidate)
  } else {
    phase1c_b_commit_memory(store, terminal_candidate)
  }
  guard loser is LifecycleStaleGovernanceV2(stale) else {
    fail("alternate-governance terminal loser was not stale: " + label)
  }
  stale.validate_current(actual_governance_replay)
  let replay = store.replay(terminal.workflow)
  let current = if terminal_first {
    assert_true(
      replay.replay_digest() ==
      terminal.work_store.replay(terminal.workflow).replay_digest(),
    )
    terminal.terminal_current
  } else {
    fold_governed_closed_loop_v2(
      terminal.empty_effects,
      replay,
      cancellation.governance_replay,
    )
  }
  try ignore(current.open_work_authority()) catch {
    CancellationPrecedenceViolation(field="open_work_authority_not_current") =>
      ()
    error => fail("unexpected post-race authority error: \{to_repr(error)}")
  } noraise {
    _ => fail("losing path minted later authority: " + label)
  }
}

///|
test "FLOW-7 Phase1C-B independent effect terminal outcomes race cancellation in both orders" {
  let labels = ["succeeded", "failed-nonretryable", "failed-exhausted"]
  for label in labels {
    for terminal_first in [true, false] {
      try phase1c_b_require_terminal_cancel_order(label, terminal_first) catch {
        error =>
          fail(
            "terminal/cancellation race failed: \{label}:terminal_first=\{terminal_first}:\{to_repr(error)}",
          )
      } noraise {
        _ => ()
      }
    }
  }
}

///|
test "FLOW-7 Phase1C-B cancellation-dependent terminals cannot mint open authority" {
  let cases = [
    (
      "cancelled-not-applied",
      CancelledAfterReconciledNotAppliedTerminalCandidateV2,
    ),
    (
      "failed-cancellation-stopped",
      FailedCancellationStoppedRetryTerminalCandidateV2,
    ),
  ]
  for pair in cases {
    let (label, expected_category) = pair
    let terminal = phase1b3_de_terminal_fixture(label)
    let replay = terminal.work_store.replay(terminal.workflow)
    let cancellations = replay
      .events()
      .filter(event => {
        event.payload().envelope_kind() == cancellation_requested_event_kind_v22
      })
    assert_eq(cancellations.length(), 1)
    assert_true(
      cancellations[0].revision() <
      terminal.terminal_request.expected_revision() + 1L,
    )
    let candidate = seal_lifecycle_candidate_v2(
      expected_category,
      phase1c_b_guarded_test_request(
        fold_governed_closed_loop_v2(
          terminal.empty_effects,
          terminal.work_store
          .replay(terminal.workflow)
          .verified_prefix(terminal.terminal_request.expected_revision()),
          terminal.governance_replay,
        ),
        terminal.terminal_request,
      ),
    )
    let combined = phase1c_b_combined_memory_store(
      terminal.work_store.replay(terminal.workflow),
      terminal.governance_replay,
    )
    guard phase1c_b_commit_memory(combined, candidate)
      is LifecycleCommittedV2(receipt) else {
      fail("cancellation-dependent terminal duplicate missing: " + label)
    }
    assert_true(receipt.category() == expected_category)
    receipt.validate_replay_binding(replay)
    try ignore(terminal.terminal_current.open_work_authority()) catch {
      CancellationPrecedenceViolation(field="open_work_authority_not_current") =>
        ()
      error =>
        fail(
          "unexpected cancellation-dependent authority error: \{label}:\{to_repr(error)}",
        )
    } noraise {
      _ =>
        fail("cancellation-dependent terminal minted open authority: " + label)
    }
  }
}

///|
test "FLOW-7 Phase1C-B two cancellations from one head have one typed winner" {
  let terminal = phase1b3_de_terminal_fixture("succeeded")
  let first = phase1b3_de_cancellation_candidate(terminal, "phase1c-b-cancel-a")
  let second = phase1b3_de_cancellation_candidate(
    terminal, "phase1c-b-cancel-b",
  )
  assert_eq(
    first.request.expected_revision(),
    second.request.expected_revision(),
  )
  let a = seal_lifecycle_candidate_v2(
    CancellationRequestCandidateV2,
    phase1c_b_guarded_test_request(
      fold_governed_closed_loop_v2(
        terminal.empty_effects,
        first.prefix_replay,
        first.governance_replay,
      ),
      first.request,
    ),
  )
  let b = seal_lifecycle_candidate_v2(
    CancellationRequestCandidateV2,
    phase1c_b_guarded_test_request(
      fold_governed_closed_loop_v2(
        terminal.empty_effects,
        second.prefix_replay,
        second.governance_replay,
      ),
      second.request,
    ),
  )
  for seed in [7L, 19L, 73L, 211L] {
    let a_first = @decision.recorded_order_key(seed, 0) <
      @decision.recorded_order_key(seed, 1)
    let actual_governance = if a_first {
      first.governance_replay
    } else {
      second.governance_replay
    }
    let store = phase1c_b_combined_memory_store(
      first.prefix_replay,
      actual_governance,
    )
    let winner = if a_first {
      phase1c_b_commit_memory(store, a)
    } else {
      phase1c_b_commit_memory(store, b)
    }
    guard winner is LifecycleCommittedV2(_) else {
      fail("seeded cancellation winner missing")
    }
    let loser = if a_first {
      phase1c_b_commit_memory(store, b)
    } else {
      phase1c_b_commit_memory(store, a)
    }
    guard loser is LifecycleStaleGovernanceV2(receipt) else {
      fail("seeded cancellation stale-governance loser missing")
    }
    receipt.validate_current(actual_governance)
    assert_true(
      receipt.expected_replay_digest() != receipt.actual_replay_digest(),
    )
    let first_work_replay = store.replay(terminal.workflow)
    let restored = phase1c_b_combined_memory_store(
      first_work_replay, actual_governance,
    )
    let second_work_replay = restored.replay(terminal.workflow)
    assert_true(
      first_work_replay.replay_digest() == second_work_replay.replay_digest(),
    )
  }
}

///|
test "FLOW-7 Phase1C-B cancellation factory rejects an alternate-governance request at the same work head" {
  let fixture = phase1b_fixture(
    suffix="phase1c-b-cancellation-provenance",
    expires_at=Some(100L),
  )
  let work = fixture.work_store.replay(fixture.registration.workflow())
  let alternate = phase1c_b_prepare_cancellation(
    fixture.current,
    fixture.empty_effects,
    work,
    fixture.registration,
    fixture.registration.schedule().admission().governance().governed_subject(),
    "cancellation-provenance-alternate",
  )
  assert_eq(alternate.current.work_revision, fixture.current.work_revision)
  assert_true(
    alternate.current.work_head_digest == fixture.current.work_head_digest,
  )
  assert_true(
    alternate.current.governance_replay_digest !=
    fixture.current.governance_replay_digest,
  )
  let before = work.replay_digest()
  try
    ignore(
      prepare_lifecycle_cancellation_candidate_v2(
        alternate.current,
        fixture.request,
      ),
    )
  catch {
    ReplayBindingViolation(..) | CancellationPrecedenceViolation(..) => ()
    error => fail("unexpected cancellation provenance error: \{to_repr(error)}")
  } noraise {
    _ => fail("alternate-governance cancellation request was resealed")
  }
  assert_true(
    fixture.work_store.replay(fixture.registration.workflow()).replay_digest() ==
    before,
  )
}

///|
test "FLOW-7 Phase1C-B duplicate terminal derivations are identical and changed body conflicts" {
  let policy = phase1b3_c_policy("phase1c-b-terminal-derivation", 1L, 0L, [])
  let failed = phase1b3_c_known_failure_fixture(
    "phase1c-b-terminal-derivation", policy,
  )
  let by_source = prepare_failed_work_terminal_v2(failed.current, failed.source)
  let by_receipt = prepare_retry_proven_failure_work_terminal_v2(
    failed.current,
    failed.retry_receipt,
  )
  let a = lifecycle_candidate_from_prepared_terminal_v22(
    by_source,
    failed.current,
  )
  let b = lifecycle_candidate_from_prepared_terminal_v22(
    by_receipt,
    failed.current,
  )
  assert_true(a.canonical_bytes() == b.canonical_bytes())
  let store = phase1c_b_combined_memory_store(
    failed.fixture.work_store.replay(failed.fixture.registration.workflow()),
    failed.fixture.governance.store.replay(
      failed.current.root_binding.governance_stream_ref(),
    ),
  )
  let first = phase1c_b_commit_memory(store, a)
  let duplicate = phase1c_b_commit_memory(store, b)
  guard first is LifecycleCommittedV2(_) && duplicate is LifecycleCommittedV2(_) else {
    fail("exact terminal duplicate was not idempotent")
  }
  let request = by_source.commit_request()
  let event = request.events()[0]
  let changed_payload = phase1b_append_byte(event.payload().payload(), b'X')
  let changed_event = phase1b3_de_replace_terminal_payload(
    event,
    phase1b_readdress(event.payload().subject(), changed_payload),
    changed_payload,
  )
  let changed = @storage.CommitRequest::new(
    request.record_version().text(),
    request.schema_version().text(),
    request.workflow(),
    request.expected_revision(),
    request.command_idempotency_key(),
    [changed_event],
    [],
  )
  try ignore(store.commit(changed)) catch {
    @storage.GuardedCommitRequired(key~, ..) =>
      assert_eq(key, request.command_idempotency_key())
    error => fail("unexpected changed-body error: \{to_repr(error)}")
  } noraise {
    _ => fail("changed-body terminal duplicate survived")
  }
}

///|
test "FLOW-7 Phase1C-B committed receipt stays identical after later legal terminal" {
  let terminal = phase1b3_de_terminal_fixture("succeeded")
  let cancellation = phase1b3_de_cancellation_candidate(
    terminal, "phase1c-b-stable-duplicate",
  )
  let candidate = seal_lifecycle_candidate_v2(
    CancellationRequestCandidateV2,
    phase1c_b_guarded_test_request(
      fold_governed_closed_loop_v2(
        terminal.empty_effects,
        cancellation.prefix_replay,
        cancellation.governance_replay,
      ),
      cancellation.request,
    ),
  )
  let store = phase1c_b_combined_memory_store(
    cancellation.prefix_replay,
    cancellation.governance_replay,
  )
  let bound = phase1c_b_bound_memory_store(store, candidate)
  guard commit_lifecycle_candidate_v2(bound, candidate)
    is LifecycleCommittedV2(first) else {
    fail("cancellation did not commit")
  }
  let cancelled = fold_governed_closed_loop_v2(
    terminal.empty_effects,
    store.replay(terminal.workflow),
    cancellation.governance_replay,
  )
  let original_terminal = decode_work_terminal_record_v22(
    terminal.terminal_request.events()[0].payload().subject(),
    terminal.terminal_request.events()[0].payload().payload(),
  )
  let source = cancelled.work.effects
    .committed_effect_terminal_source_v2(
      original_terminal.source_intent_ref.unwrap(),
    )
    .unwrap()
  let later = prepare_succeeded_work_terminal_v2(cancelled, source)
  guard bound.guarded_commit(
      phase1c_b_guarded_test_request(cancelled, later.commit_request()),
    )
    is @storage.GuardedCommitSucceeded(_) else {
    fail("later guarded terminal did not commit")
  }
  guard commit_lifecycle_candidate_v2(bound, candidate)
    is LifecycleCommittedV2(duplicate) else {
    fail("later exact duplicate did not remain committed")
  }
  assert_true(first.canonical_bytes() == duplicate.canonical_bytes())
  assert_true(first.digest() == duplicate.digest())
  first.validate_replay_binding(store.replay(terminal.workflow))
}

///|
test "FLOW-7 Phase1C-B governance-only advance stales every authority candidate family" {
  let claim_fixture = phase1b_fixture(
    suffix="phase1c-b-governance-advance-claim",
    expires_at=Some(100L),
  )
  let claim_work = claim_fixture.work_store.replay(
    claim_fixture.registration.workflow(),
  )
  let claim_governance = claim_fixture.governance.store.replay(
    claim_fixture.current.root_binding.governance_stream_ref(),
  )
  let (claim, _) = phase1c_b_lease_claim_candidate(
    claim_fixture, "governance-advance-claim",
  )
  phase1c_b_require_governance_advance_stale(
    "claim", claim_work, claim_governance, claim,
  )
  phase1c_b_require_governance_advance_stale(
    "cancellation",
    claim_work,
    claim_governance,
    prepare_lifecycle_cancellation_candidate_v2(
      claim_fixture.current,
      claim_fixture.request,
    ),
  )

  let reconciliation = phase1c_b_reconciliation("governance-advance")
  phase1c_b_require_governance_advance_stale(
    "reconciliation-request",
    reconciliation.request_prefix,
    reconciliation.governance_replay,
    reconciliation.request_candidate,
  )
  phase1c_b_require_governance_advance_stale(
    "reconciliation-resolution",
    reconciliation.resolution_prefix,
    reconciliation.governance_replay,
    reconciliation.resolution_candidate,
  )

  let retry = phase1c_b_atomic_retry("governance-advance")
  phase1c_b_require_governance_advance_stale(
    "retry",
    retry.outcome.fixture.work_store.replay(
      retry.outcome.fixture.registration.workflow(),
    ),
    retry.outcome.governance_replay,
    retry.candidate,
  )

  let lease = phase1c_b_lease_lifecycle("governance-advance")
  phase1c_b_require_governance_advance_stale(
    "lease-expiry",
    lease.expiry_prefix,
    lease.governance_replay,
    lease.expiry_candidate,
  )
  phase1c_b_require_governance_advance_stale(
    "lease-reclaim",
    lease.reclaim_prefix,
    lease.governance_replay,
    lease.reclaim_candidate,
  )

  for
    label in [
      "succeeded", "failed-nonretryable", "failed-exhausted", "cancelled-not-applied",
      "failed-cancellation-stopped",
    ] {
    let terminal = phase1b3_de_terminal_fixture(label)
    let prefix = terminal.work_store
      .replay(terminal.workflow)
      .verified_prefix(terminal.terminal_request.expected_revision())
    let candidate = seal_lifecycle_candidate_v2(
      phase1c_b_category_for_request(terminal.terminal_request),
      phase1c_b_guarded_test_request(
        fold_governed_closed_loop_v2(
          terminal.empty_effects,
          prefix,
          terminal.governance_replay,
        ),
        terminal.terminal_request,
      ),
    )
    phase1c_b_require_governance_advance_stale(
      "terminal-" + label,
      prefix,
      terminal.governance_replay,
      candidate,
    )
  }
}

///|
