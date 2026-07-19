///|
priv struct Phase1b3COutcomeFixture {
  fixture : Phase1bPendingFixture
  governance_replay : @storage.ReplayResult
  current : CurrentGovernedClosedLoopProjectionV2
  source : @effects.CommittedEffectTerminalSourceV2
  retry_receipt : @effects.CommittedRetryEligibilityReceiptV2
}

///|
fn phase1b3_c_policy(
  suffix : String,
  maximum_attempt_count : Int64,
  maximum_retry_count : Int64,
  retryable_failure_classes : Array[String],
) -> RetryPolicyV2 raise OrchestrationError {
  RetryPolicyV2::new(
    "phase1b3-c-policy-" + suffix,
    "2.0.0",
    maximum_attempt_count,
    maximum_retry_count,
    1L,
    1000L,
    1L,
    1L,
    0L,
    @contracts.sha256_digest(@utf8.encode("phase1b3-c-seed-" + suffix)),
    retryable_failure_classes,
  )
}

///|
fn phase1b3_c_observe_intent(
  current : CurrentGovernedClosedLoopProjectionV2,
  store : @storage.MemoryStore,
  empty_effects : @effects.EffectsProjection,
  workflow : @contracts.RecordRef,
  intent : @effects.EffectIntent,
  governance_replay : @storage.ReplayResult,
  suffix : String,
) -> CurrentGovernedClosedLoopProjectionV2 raise {
  let evidence = [ for value in intent.evidence() => value ]
  let observation = @effects.DispatchObservation::new(
    "phase1b3-c-observation-" + suffix,
    intent,
    phase1b_test_envelope(
      "phase1b3-c-observation-envelope-" + suffix,
      "dispatch-observation",
      intent.governance().governed_subject(),
      @utf8.encode("phase1b3-c-observation-" + suffix),
      evidence,
    ),
    11L,
    evidence,
  )
  let open = current.open_work_authority()
  let dispatch = current.guarded_dispatch_authorization(
    open,
    intent.intent_ref(),
  )
  let guarded = phase1b_legacy_guarded_observation_fixture_v2(
    current, dispatch, observation,
  )
  ignore(
    store.commit(
      prepare_guarded_dispatch_observation_v2(
        current,
        guarded,
        "phase1b3-c-observation-event-" + suffix,
        "phase1b3-c-observation-command-" + suffix,
      ),
    ),
  )
  fold_governed_closed_loop_v2(
    empty_effects,
    store.replay(workflow),
    governance_replay,
  )
}

///|
fn phase1b3_c_settle_root_lease(
  fixture : Phase1bPendingFixture,
  governance_replay : @storage.ReplayResult,
  suffix : String,
) -> CurrentGovernedClosedLoopProjectionV2 raise {
  let schedule = fixture.registration.schedule()
  let evidence = [ for value in schedule.evidence() => value ]
  let schedule_event = fixture.work_store
    .replay(fixture.registration.workflow())
    .events()[0]
  let claim = LeaseClaimV2::new(
    "phase1b3-c-claim-" + suffix,
    schedule,
    schedule.admission(),
    fixture.registration.workflow(),
    phase1a_wb_ref(
      "owner",
      "phase1b3-c-owner-" + suffix,
      @utf8.encode("phase1b3-c-owner-" + suffix),
    ),
    10L,
    0L,
    0L,
    1L,
    1L,
    "phase1b3-c-claim-key-" + suffix,
    evidence,
    schedule_event.event_ref(),
  )
  let claimed = LeaseClaimedV2::new(
    "phase1b3-c-claimed-" + suffix,
    fixture.registration,
    claim,
  )
  let open = fixture.current.open_work_authority()
  let claim_authorization = fixture.current.authorize_open_work_operation(
    open,
    "lease.claim",
    claimed.record_ref(),
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_lease_claimed_v2(
        fixture.current,
        open,
        claim_authorization,
        "phase1b3-c-claim-event-" + suffix,
        claim.idempotency_key(),
        "phase1b3-c-claim-command-" + suffix,
        claimed,
      ),
    ),
  )
  let claimed_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard claimed_current.committed_lease_authority_receipt_v2()
    is Some(lease_receipt) else {
    fail("claimed lease receipt missing: " + suffix)
  }
  let release = LeaseReleaseV2::new(
    "phase1b3-c-release-" + suffix,
    fixture.registration,
    lease_receipt,
    flow7_lifecycle_active_authorization(
      "phase1b3-c-release-" + suffix,
      claimed_current.work.orchestration(),
      fixture.registration,
      lease_receipt,
      ReleaseLeaseV2,
      None,
      12L,
    ),
  )
  let release_authorization = claimed_current.authorize_lease_settlement_v2(
    "lease.release",
    release.record_ref(),
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_lease_released_v2(
        claimed_current,
        release_authorization,
        "phase1b3-c-release-event-" + suffix,
        release.idempotency_key(),
        "phase1b3-c-release-command-" + suffix,
        release,
      ),
    ),
  )
  fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
}

///|
fn phase1b3_c_known_failure_fixture(
  suffix : String,
  retry_policy : RetryPolicyV2,
) -> Phase1b3COutcomeFixture raise {
  let fixture = phase1b_pending_fixture(suffix, retry_policy~)
  let governance_replay = fixture.governance.store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  let lease_settled = phase1b3_c_settle_root_lease(
    fixture, governance_replay, suffix,
  )
  let observed = phase1b3_c_observe_intent(
    lease_settled,
    fixture.work_store,
    fixture.empty_effects,
    fixture.registration.workflow(),
    fixture.intent,
    governance_replay,
    suffix,
  )
  let evidence = [ for value in fixture.intent.evidence() => value ]
  let failed_receipt = @effects.EffectReceipt::new(
    "phase1b3-c-failed-receipt-" + suffix,
    "1.0.0",
    fixture.intent,
    phase1b_test_envelope(
      "phase1b3-c-failed-receipt-envelope-" + suffix,
      "dispatcher-receipt",
      fixture.intent.governance().governed_subject(),
      @utf8.encode("phase1b3-c-failed-receipt-" + suffix),
      evidence,
    ),
    @effects.Failed,
    12L,
    evidence,
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  let authority = observed.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "receipt.record",
    failed_receipt.receipt_ref(),
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_effect_receipt_v2(
        observed,
        authority,
        "phase1b3-c-failed-receipt-event-" + suffix,
        "phase1b3-c-failed-receipt-command-" + suffix,
        failed_receipt,
      ),
    ),
  )
  let current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard current.work.effects.committed_effect_terminal_source_v2(
      fixture.intent.intent_ref(),
    )
    is Some(source) else {
    fail("known failure source missing: " + suffix)
  }
  guard current.work.effects.committed_retry_eligibility_receipt(
      fixture.intent.intent_ref(),
    )
    is Some(retry_receipt) else {
    fail("known failure retry receipt missing: " + suffix)
  }
  { fixture, governance_replay, current, source, retry_receipt }
}

///|
fn phase1b3_c_reconciled_fixture(
  suffix : String,
  retry_policy : RetryPolicyV2,
  not_applied : Bool,
) -> Phase1b3COutcomeFixture raise {
  let fixture = phase1b_pending_fixture(suffix, retry_policy~)
  let governance_replay = fixture.governance.store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  let lease_settled = phase1b3_c_settle_root_lease(
    fixture, governance_replay, suffix,
  )
  let observed = phase1b3_c_observe_intent(
    lease_settled,
    fixture.work_store,
    fixture.empty_effects,
    fixture.registration.workflow(),
    fixture.intent,
    governance_replay,
    suffix,
  )
  let evidence = [ for value in fixture.intent.evidence() => value ]
  let unknown_receipt = @effects.EffectReceipt::new(
    "phase1b3-c-unknown-receipt-" + suffix,
    "1.0.0",
    fixture.intent,
    phase1b_test_envelope(
      "phase1b3-c-unknown-receipt-envelope-" + suffix,
      "dispatcher-receipt",
      fixture.intent.governance().governed_subject(),
      @utf8.encode("phase1b3-c-unknown-receipt-" + suffix),
      evidence,
    ),
    @effects.Unknown,
    12L,
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
        "phase1b3-c-unknown-receipt-event-" + suffix,
        "phase1b3-c-unknown-receipt-command-" + suffix,
        unknown_receipt,
      ),
    ),
  )
  let unknown = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  assert_true(
    unknown.work.effects.committed_effect_terminal_source_v2(
      fixture.intent.intent_ref(),
    )
    is None,
  )
  assert_true(
    unknown.work.effects.committed_retry_eligibility_receipt(
      fixture.intent.intent_ref(),
    )
    is None,
  )
  let request = @effects.ReconciliationRequest::new(
    "phase1b3-c-reconciliation-request-" + suffix,
    fixture.intent,
    unknown_receipt,
    13L,
    evidence,
  )
  let request_authority = unknown.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "reconciliation.request",
    request.request_ref(),
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_reconciliation_request_v2(
        unknown,
        request_authority,
        "phase1b3-c-reconciliation-request-event-" + suffix,
        "phase1b3-c-reconciliation-request-command-" + suffix,
        request,
      ),
    ),
  )
  let requested = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  assert_true(
    requested.work.effects.committed_effect_terminal_source_v2(
      fixture.intent.intent_ref(),
    )
    is None,
  )
  assert_true(
    requested.work.effects.committed_retry_eligibility_receipt(
      fixture.intent.intent_ref(),
    )
    is None,
  )
  let outcome = if not_applied {
    @effects.ReconciledNotApplied
  } else {
    @effects.ReconciledFailed
  }
  let resolution = @effects.ReconciliationRecord::new(
    "phase1b3-c-reconciliation-resolution-" + suffix,
    fixture.intent,
    request,
    outcome,
    phase1b_test_envelope(
      "phase1b3-c-reconciliation-resolution-envelope-" + suffix,
      "reconciliation-observation",
      fixture.intent.governance().governed_subject(),
      @utf8.encode("phase1b3-c-reconciliation-resolution-" + suffix),
      evidence,
    ),
    14L,
    evidence,
  )
  let resolution_authority = requested.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "reconciliation.resolve",
    resolution.reconciliation_ref(),
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_reconciliation_resolution_v2(
        requested,
        resolution_authority,
        "phase1b3-c-reconciliation-resolution-event-" + suffix,
        "phase1b3-c-reconciliation-resolution-command-" + suffix,
        resolution,
      ),
    ),
  )
  let current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard current.work.effects.committed_effect_terminal_source_v2(
      fixture.intent.intent_ref(),
    )
    is Some(source) else {
    fail("reconciled source missing: " + suffix)
  }
  guard current.work.effects.committed_retry_eligibility_receipt(
      fixture.intent.intent_ref(),
    )
    is Some(retry_receipt) else {
    fail("reconciled retry receipt missing: " + suffix)
  }
  { fixture, governance_replay, current, source, retry_receipt }
}

///|
fn phase1b3_c_cancel_reconciled_not_applied(
  resolved : Phase1b3COutcomeFixture,
  suffix : String,
) -> Phase1b3COutcomeFixture raise {
  let work_replay = resolved.fixture.work_store.replay(
    resolved.fixture.registration.workflow(),
  )
  let root = fold_initial_work_receipt_v22(
    resolved.fixture.empty_effects,
    work_replay,
  )
  let evidence = [
    for value in resolved.fixture.registration.schedule().evidence() => value
  ]
  let proposal = CancellationProposalV2::new(
    "phase1b3-c-cancel-proposal-" + suffix,
    root,
    resolved.current.work,
    resolved.fixture.intent.governance().governed_subject(),
    phase1a_wb_ref(
      "reason",
      "phase1b3-c-cancel-reason-" + suffix,
      @utf8.encode("phase1b3-c-cancel-reason-" + suffix),
    ),
    10L,
    evidence,
    phase1a_wb_ref(
      "causation",
      "phase1b3-c-cancel-causation-" + suffix,
      @utf8.encode("phase1b3-c-cancel-causation-" + suffix),
    ),
    "phase1b3-c-cancel-proposal-event-key-" + suffix,
    "phase1b3-c-cancel-proposal-command-key-" + suffix,
  )
  let chain = phase1b_governance_chain(
    phase1a_wb_policy(),
    root.governance_stream_ref(),
    proposal,
    evidence,
    "phase1b3-c-cancel-" + suffix,
  )
  let governance_replay = chain.store.replay(root.governance_stream_ref())
  let governed = fold_governed_closed_loop_v2(
    resolved.fixture.empty_effects,
    work_replay,
    governance_replay,
  )
  let receipt = governed.committed_cancellation_governance_receipt(proposal)
  let authorization = CancellationAuthorizationV2::from_committed_governance(
    "phase1b3-c-cancel-authorization-" + suffix,
    receipt,
    proposal,
    governed,
  )
  let request = CancellationRequestV2::new(
    "phase1b3-c-cancel-request-" + suffix,
    proposal,
    authorization,
  )
  let prepared = prepare_cancellation_v2(governed, request)
  assert_true(prepared.terminal_outcome() is None)
  ignore(resolved.fixture.work_store.commit(prepared.commit_request()))
  let current = fold_governed_closed_loop_v2(
    resolved.fixture.empty_effects,
    resolved.fixture.work_store.replay(resolved.fixture.registration.workflow()),
    governance_replay,
  )
  guard current.work.effects.committed_effect_terminal_source_v2(
      resolved.fixture.intent.intent_ref(),
    )
    is Some(source) else {
    fail("cancelled not-applied source missing")
  }
  guard current.work.effects.committed_retry_eligibility_receipt(
      resolved.fixture.intent.intent_ref(),
    )
    is Some(retry_receipt) else {
    fail("cancelled not-applied retry receipt missing")
  }
  {
    fixture: resolved.fixture,
    governance_replay,
    current,
    source,
    retry_receipt,
  }
}

///|
fn phase1b3_c_commit_and_require_terminal(
  outcome_fixture : Phase1b3COutcomeFixture,
  prepared : PreparedWorkTerminalV2,
  expected : WorkTerminalOutcomeV2,
) -> CommittedWorkTerminalReceiptV2 raise {
  assert_true(prepared.outcome() == expected)
  assert_eq(prepared.commit_request().events().length(), 1)
  assert_eq(prepared.commit_request().intents().length(), 0)
  ignore(outcome_fixture.fixture.work_store.commit(prepared.commit_request()))
  let current = fold_governed_closed_loop_v2(
    outcome_fixture.fixture.empty_effects,
    outcome_fixture.fixture.work_store.replay(
      outcome_fixture.fixture.registration.workflow(),
    ),
    outcome_fixture.governance_replay,
  )
  guard current.committed_work_terminal_receipt() is Some(receipt) else {
    fail("terminal receipt missing")
  }
  assert_true(receipt.outcome() == expected)
  receipt.validate_current(current)
  receipt
}

///|
fn phase1b3_c_commit_cancelled_not_applied(
  policy : RetryPolicyV2,
  suffix : String,
) -> Unit raise {
  let resolved = phase1b3_c_reconciled_fixture(suffix, policy, true)
  let cancelled = phase1b3_c_cancel_reconciled_not_applied(resolved, suffix)
  let prepared = prepare_cancelled_after_reconciled_not_applied_work_terminal_v2(
    cancelled.current,
    cancelled.source,
  )
  assert_true(prepared.outcome() == CancelledAfterReconciledNotAppliedV2)
  ignore(cancelled.fixture.work_store.commit(prepared.commit_request()))
  let terminal = fold_governed_closed_loop_v2(
    cancelled.fixture.empty_effects,
    cancelled.fixture.work_store.replay(
      cancelled.fixture.registration.workflow(),
    ),
    cancelled.governance_replay,
  )
  guard terminal.committed_work_terminal_receipt() is Some(receipt) else {
    fail("cancelled not-applied terminal receipt missing: " + suffix)
  }
  assert_true(receipt.outcome() == CancelledAfterReconciledNotAppliedV2)
  receipt.validate_current(terminal)
}

///|
fn phase1b3_c_reseal_terminal(
  terminal : WorkTerminalRecordV2,
  retry_policy_ref : @contracts.RecordRef?,
  retry_policy_bytes : Bytes?,
  attempt_count : Int64?,
  retry_count : Int64?,
  source_proof_ref : @contracts.RecordRef,
  source_proof_bytes : Bytes,
) -> WorkTerminalRecordV2 raise OrchestrationError {
  seal_work_terminal_v22({
    terminal_id: terminal.terminal_ref.id(),
    outcome: terminal.outcome,
    lineage_digest: terminal.lineage_digest,
    root_registration_ref: terminal.root_registration_ref,
    root_attempt_ref: terminal.root_attempt_ref,
    root_attempt_digest: terminal.root_attempt_digest,
    root_intent_ref: terminal.root_intent_ref,
    root_intent_digest: terminal.root_intent_digest,
    source_attempt_ref: terminal.source_attempt_ref,
    source_intent_ref: terminal.source_intent_ref,
    source_proof_ref,
    source_proof_bytes,
    source_event_ref: terminal.source_event_ref,
    source_event_bytes: terminal.source_event_bytes,
    cancellation_request_ref: terminal.cancellation_request_ref,
    cancellation_request_bytes: terminal.cancellation_request_bytes,
    retry_policy_ref,
    retry_policy_bytes,
    attempt_count,
    retry_count,
    workflow: terminal.workflow,
    governed_subject: terminal.governed_subject,
    effects_prefix_state_digest: terminal.effects_prefix_state_digest,
    effects_prefix_replay_digest: terminal.effects_prefix_replay_digest,
    orchestration_prefix_state_digest: terminal.orchestration_prefix_state_digest,
    orchestration_prefix_replay_digest: terminal.orchestration_prefix_replay_digest,
    prefix_event_ref: terminal.prefix_event_ref,
    prefix_sequence: terminal.prefix_sequence,
    prefix_revision: terminal.prefix_revision,
    prefix_replay_digest: terminal.prefix_replay_digest,
    terminal_logical_instant: terminal.terminal_logical_instant,
    evidence: terminal.evidence,
    causation: terminal.causation,
    event_idempotency_key: terminal.event_idempotency_key,
    command_idempotency_key: terminal.command_idempotency_key,
    previous_digest: terminal.previous_digest,
  })
}

///|
fn phase1b3_c_require_forged_terminal_rejected(
  outcome_fixture : Phase1b3COutcomeFixture,
  forged : WorkTerminalRecordV2,
  suffix : String,
) -> Unit raise {
  let store = phase1b_clone_replay_to_memory(
    outcome_fixture.fixture.work_store.replay(
      outcome_fixture.fixture.registration.workflow(),
    ),
  )
  let current = outcome_fixture.current
  let event = prepare_phase1b_work_event_v22(
    outcome_fixture.fixture.registration.workflow(),
    current.work_sequence + 1L,
    current.work_revision + 1L,
    current.work_head_digest,
    "phase1b3-c-forged-terminal-event-" + suffix,
    work_terminal_event_kind_v22,
    forged.terminal_ref,
    forged.canonical,
    forged.governed_subject,
    [
      for value in forged.evidence => value
    ],
    forged.causation,
    forged.event_idempotency_key,
  )
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        outcome_fixture.fixture.registration.workflow(),
        current.work_revision,
        forged.command_idempotency_key,
        [event],
        [],
      ),
    ),
  )
  try
    ignore(
      fold_governed_closed_loop_v2(
        outcome_fixture.fixture.empty_effects,
        store.replay(outcome_fixture.fixture.registration.workflow()),
        outcome_fixture.governance_replay,
      ),
    )
  catch {
    ReplayBindingViolation(field="work_terminal_source") => ()
    PolicyMismatch(field="work_terminal_root_policy_binding") => ()
    RetryBoundViolation(field="work_terminal_failure_counter") => ()
    CancellationPrecedenceViolation(field="work_terminal_outcome_conflict") =>
      ()
    error => fail("unexpected forged terminal rejection: \{to_repr(error)}")
  } noraise {
    _ => fail("forged terminal replay was accepted: " + suffix)
  }
}

///|
test "FLOW-7 Phase1B.3-C actual excluded failure is nonretryable end to end" {
  let policy = phase1b3_c_policy("known-excluded", 3L, 2L, [])
  let failed = phase1b3_c_known_failure_fixture("known-excluded", policy)
  assert_true(failed.source.state() == @effects.KnownFailure)
  assert_eq(failed.retry_receipt.cause_key(), "terminal_failed")
  let by_source = prepare_failed_work_terminal_v2(failed.current, failed.source)
  let by_receipt = prepare_retry_proven_failure_work_terminal_v2(
    failed.current,
    failed.retry_receipt,
  )
  assert_true(by_source.outcome() == FailedNonRetryableV2)
  assert_true(by_receipt.outcome() == FailedNonRetryableV2)
  assert_true(
    by_source.commit_request().canonical_bytes() ==
    by_receipt.commit_request().canonical_bytes(),
  )
  let receipt = phase1b3_c_commit_and_require_terminal(
    failed,
    by_source,
    FailedNonRetryableV2,
  )
  let terminal_current = try! fold_governed_closed_loop_v2(
    failed.fixture.empty_effects,
    failed.fixture.work_store.replay(failed.fixture.registration.workflow()),
    failed.governance_replay,
  )
  assert_true(
    receipt.canonical_bytes() ==
    terminal_current
    .committed_work_terminal_receipt()
    .unwrap()
    .canonical_bytes(),
  )
  try
    ignore(
      prepare_retry_proven_failure_work_terminal_v2(
        terminal_current,
        failed.retry_receipt,
      ),
    )
  catch {
    ReplayBindingViolation(field="work_terminal_source") => ()
    error => fail("unexpected stale retry receipt error: \{to_repr(error)}")
  } noraise {
    _ => fail("stale retry receipt survived terminal append")
  }
}

///|
test "FLOW-7 Phase1B.3-C reconciled failure receipt classifies excluded and exhausted" {
  let excluded_policy = phase1b3_c_policy("reconciled-excluded", 3L, 2L, [])
  let excluded = phase1b3_c_reconciled_fixture(
    "reconciled-excluded", excluded_policy, false,
  )
  assert_true(excluded.source.state() == @effects.ReconciledFailureState)
  assert_eq(excluded.retry_receipt.cause_key(), "terminal_failed")
  let excluded_by_source = prepare_failed_work_terminal_v2(
    excluded.current,
    excluded.source,
  )
  let excluded_by_receipt = prepare_retry_proven_failure_work_terminal_v2(
    excluded.current,
    excluded.retry_receipt,
  )
  assert_true(
    excluded_by_source.commit_request().canonical_bytes() ==
    excluded_by_receipt.commit_request().canonical_bytes(),
  )
  phase1b3_c_commit_and_require_terminal(
    excluded,
    excluded_by_receipt,
    FailedNonRetryableV2,
  )
  |> ignore
  let exhausted_policy = phase1b3_c_policy("reconciled-attempt-bound", 1L, 0L, [
    "terminal_failed",
  ])
  let exhausted = phase1b3_c_reconciled_fixture(
    "reconciled-attempt-bound", exhausted_policy, false,
  )
  assert_eq(exhausted.retry_receipt.attempt_count(), 1L)
  assert_eq(exhausted.retry_receipt.retry_count(), 0L)
  phase1b3_c_commit_and_require_terminal(
    exhausted,
    prepare_retry_exhausted_work_terminal_v2(
      exhausted.current,
      exhausted.retry_receipt,
    ),
    FailedRetryExhaustedV2,
  )
  |> ignore
}

///|
test "FLOW-7 Phase1B.3-C not-applied totality excludes or remains retry-only" {
  let excluded_policy = phase1b3_c_policy("not-applied-excluded", 3L, 2L, [
    "terminal_failed",
  ])
  let excluded = phase1b3_c_reconciled_fixture(
    "not-applied-excluded", excluded_policy, true,
  )
  assert_true(
    excluded.source.state() == @effects.ReconciledNotAppliedRetryEligible,
  )
  assert_eq(excluded.retry_receipt.cause_key(), "reconciled_not_applied")
  phase1b3_c_commit_and_require_terminal(
    excluded,
    prepare_retry_proven_failure_work_terminal_v2(
      excluded.current,
      excluded.retry_receipt,
    ),
    FailedNonRetryableV2,
  )
  |> ignore
  let permitted_policy = phase1b3_c_policy("not-applied-under-bound", 3L, 2L, [
    "terminal_failed", "reconciled_not_applied",
  ])
  let permitted = phase1b3_c_reconciled_fixture(
    "not-applied-under-bound", permitted_policy, true,
  )
  assert_true(permitted.current.committed_work_terminal_receipt() is None)
  assert_true(permitted_policy.allows(permitted.retry_receipt))
  for use_source in [true, false] {
    try {
      if use_source {
        ignore(
          prepare_failed_work_terminal_v2(permitted.current, permitted.source),
        )
      } else {
        ignore(
          prepare_retry_proven_failure_work_terminal_v2(
            permitted.current,
            permitted.retry_receipt,
          ),
        )
      }
    } catch {
      CancellationPrecedenceViolation(field="work_terminal_retry_still_open") =>
        ()
      error =>
        fail("unexpected under-bound not-applied error: \{to_repr(error)}")
    } noraise {
      _ => fail("under-bound not-applied terminalized")
    }
  }
  let open = permitted.current.open_work_authority()
  let retry_work = phase1b_test_envelope(
    "phase1b3-c-under-bound-retry-work",
    "requested-work",
    permitted.fixture.intent.governance().governed_subject(),
    b"phase1b3-c-under-bound-retry-work",
    [
      for value in permitted.fixture.intent.evidence() => value
    ],
  )
  ignore(
    prepare_guarded_retry_schedule_request_v2(
      permitted.current,
      open,
      permitted.retry_receipt,
      permitted_policy,
      permitted.fixture.intent.governance(),
      "phase1b3-c-under-bound-retry-request",
      "phase1b3-c-under-bound-retry-attempt",
      "phase1b3-c-under-bound-retry-attempt-key",
      retry_work,
      "attempt",
      "1.0.0",
      "effect",
      "1.0.0",
      @contracts.sha256_digest(b"phase1b3-c-under-bound-artifact"),
      "phase1b3-c-under-bound-retry-schedule",
      "phase1b3-c-under-bound-retry-schedule-key",
      18L,
      18L,
      18L,
      "phase1b3-c-under-bound-retry-command",
    ),
  )
}

///|
test "FLOW-7 Phase1B.3-C exact retry bound is distinct on valid child lineage" {
  let policy = phase1b3_c_policy("retry-bound-lineage", 3L, 1L, [
    "terminal_failed",
  ])
  let root_failed = phase1b3_c_known_failure_fixture(
    "retry-bound-lineage", policy,
  )
  assert_eq(root_failed.retry_receipt.attempt_count(), 1L)
  assert_eq(root_failed.retry_receipt.retry_count(), 0L)
  assert_true(policy.allows(root_failed.retry_receipt))
  let current = root_failed.current
  let open = current.open_work_authority()
  let evidence = [flow7_v2_evidence()]
  let requested_work = phase1b_test_envelope(
    "phase1b3-c-retry-requested-work",
    "requested-work",
    root_failed.fixture.intent.governance().governed_subject(),
    b"phase1b3-c-retry-requested-work",
    evidence,
  )
  let requested_ref = @contracts.RecordRef::new(
    "requested-work",
    requested_work.envelope_id(),
    "1.0.0",
    requested_work.envelope_digest().text(),
  )
  let alternate_policy = phase1b3_c_policy(
    "retry-bound-lineage-substituted",
    4L,
    2L,
    ["terminal_failed"],
  )
  try
    ignore(
      prepare_guarded_retry_schedule_request_v2(
        current,
        open,
        root_failed.retry_receipt,
        alternate_policy,
        root_failed.fixture.intent.governance(),
        "phase1b3-c-substituted-retry-request",
        "phase1b3-c-substituted-retry-attempt",
        "phase1b3-c-substituted-retry-attempt-key",
        requested_work,
        "attempt",
        "1.0.0",
        "effect",
        "1.0.0",
        @contracts.sha256_digest(b"phase1b3-c-substituted-artifact"),
        "phase1b3-c-substituted-retry-schedule",
        "phase1b3-c-substituted-retry-schedule-key",
        18L,
        18L,
        18L,
        "phase1b3-c-substituted-retry-command",
      ),
    )
  catch {
    PolicyMismatch(field="root_retry_policy_binding") => ()
    error =>
      fail("unexpected substituted retry request error: \{to_repr(error)}")
  } noraise {
    _ => fail("guarded retry request accepted a substituted root policy")
  }
  let same_id_different_policy = RetryPolicyV2::new(
    policy.policy_ref().id(),
    "2.0.0",
    3L,
    1L,
    1L,
    1000L,
    1L,
    1L,
    0L,
    @contracts.sha256_digest(b"phase1b3-c-same-id-different-policy"),
    ["terminal_failed"],
  )
  assert_true(
    same_id_different_policy.policy_ref().id() == policy.policy_ref().id(),
  )
  assert_true(same_id_different_policy.digest() != policy.digest())
  try
    ignore(
      prepare_guarded_retry_schedule_request_v2(
        current,
        open,
        root_failed.retry_receipt,
        same_id_different_policy,
        root_failed.fixture.intent.governance(),
        "phase1b3-c-same-id-retry-request",
        "phase1b3-c-same-id-retry-attempt",
        "phase1b3-c-same-id-retry-attempt-key",
        requested_work,
        "attempt",
        "1.0.0",
        "effect",
        "1.0.0",
        @contracts.sha256_digest(b"phase1b3-c-same-id-retry-artifact"),
        "phase1b3-c-same-id-retry-schedule",
        "phase1b3-c-same-id-retry-schedule-key",
        18L,
        18L,
        18L,
        "phase1b3-c-same-id-retry-command",
      ),
    )
  catch {
    PolicyMismatch(field="root_retry_policy_binding") => ()
    error => fail("unexpected same-id retry policy error: \{to_repr(error)}")
  } noraise {
    _ => fail("guarded retry request accepted same-id different policy bytes")
  }
  let guarded_request = prepare_guarded_retry_schedule_request_v2(
    current,
    open,
    root_failed.retry_receipt,
    policy,
    root_failed.fixture.intent.governance(),
    "phase1b3-c-retry-request",
    "phase1b3-c-retry-attempt",
    "phase1b3-c-retry-attempt-key",
    requested_work,
    "attempt",
    "1.0.0",
    "effect",
    "1.0.0",
    @contracts.sha256_digest(b"phase1b3-c-retry-attempt-key-artifact"),
    "phase1b3-c-retry-schedule",
    "phase1b3-c-retry-schedule-key",
    18L,
    18L,
    18L,
    "phase1b3-c-retry-command",
  )
  let timing = RetryTimingV2::compute(policy, root_failed.retry_receipt)
  let admission = flow7_aggregate_admission(
    "phase1b3-c-retry-admission",
    root_failed.fixture.registration.workflow(),
    current.work.prefix_event().unwrap(),
    timing.due_at(),
    18L,
    root_failed.fixture.intent.governance().policy_ref(),
    flow7_aggregate_planned(
      root_failed.fixture.registration.workflow(),
      root_failed.fixture.intent.governance().governed_subject(),
      requested_ref,
      requested_work.envelope_digest(),
      2L,
      "phase1b3-c-retry-attempt-key",
      guarded_request.request().request_ref(),
    ),
    evidence[0],
    lease_epoch=2L,
    fencing_token=2L,
  )
  try
    ignore(
      prepare_guarded_atomic_retry_v2(
        current,
        open,
        guarded_request,
        root_failed.retry_receipt,
        alternate_policy,
        admission,
        root_failed.fixture.intent.governance(),
        "phase1b3-c-substituted-atomic-plan",
        "phase1b3-c-retry-attempt",
        "phase1b3-c-substituted-atomic-attempt-event",
        "phase1b3-c-retry-attempt-key",
        requested_work,
        evidence,
        root_failed.retry_receipt.source_observed_at(),
        "phase1b3-c-retry-schedule",
        "phase1b3-c-retry-schedule-key",
        18L,
        "phase1b3-c-substituted-atomic-schedule-event",
        "phase1b3-c-substituted-atomic-registration",
        "phase1b3-c-retry-command",
      ),
    )
  catch {
    PolicyMismatch(field="root_retry_policy_binding") => ()
    error =>
      fail("unexpected substituted atomic retry error: \{to_repr(error)}")
  } noraise {
    _ => fail("guarded atomic retry accepted a substituted root policy")
  }
  let raw_request = prepare_retry_schedule_request_v2(
    current.work,
    root_failed.retry_receipt,
    alternate_policy,
    root_failed.fixture.intent.governance(),
    "phase1b3-c-raw-substituted-request",
    "phase1b3-c-raw-substituted-attempt",
    "phase1b3-c-raw-substituted-attempt-key",
    requested_work,
    "attempt",
    "1.0.0",
    "effect",
    "1.0.0",
    @contracts.sha256_digest(b"phase1b3-c-raw-substituted-attempt-key-artifact"),
    "phase1b3-c-raw-substituted-schedule",
    "phase1b3-c-raw-substituted-schedule-key",
    18L,
    18L,
    18L,
    "phase1b3-c-raw-substituted-command",
  )
  let raw_admission = flow7_aggregate_admission(
    "phase1b3-c-raw-substituted-admission",
    root_failed.fixture.registration.workflow(),
    current.work.prefix_event().unwrap(),
    RetryTimingV2::compute(alternate_policy, root_failed.retry_receipt).due_at(),
    18L,
    root_failed.fixture.intent.governance().policy_ref(),
    flow7_aggregate_planned(
      root_failed.fixture.registration.workflow(),
      root_failed.fixture.intent.governance().governed_subject(),
      requested_ref,
      requested_work.envelope_digest(),
      2L,
      "phase1b3-c-raw-substituted-attempt-key",
      raw_request.request_ref(),
    ),
    evidence[0],
  )
  let raw_retry = prepare_atomic_retry_v2(
    current.work,
    root_failed.retry_receipt,
    alternate_policy,
    raw_request,
    raw_admission,
    root_failed.fixture.intent.governance(),
    "phase1b3-c-raw-substituted-plan",
    "phase1b3-c-raw-substituted-attempt",
    "phase1b3-c-raw-substituted-attempt-event",
    "phase1b3-c-raw-substituted-attempt-key",
    requested_work,
    evidence,
    root_failed.retry_receipt.source_observed_at(),
    "phase1b3-c-raw-substituted-schedule",
    "phase1b3-c-raw-substituted-schedule-key",
    18L,
    "phase1b3-c-raw-substituted-schedule-event",
    "phase1b3-c-raw-substituted-registration",
    "phase1b3-c-raw-substituted-command",
  )
  let raw_store = phase1b_clone_replay_to_memory(
    root_failed.fixture.work_store.replay(
      root_failed.fixture.registration.workflow(),
    ),
  )
  ignore(raw_store.commit(raw_retry.request()))
  let raw_replay = raw_store.replay(root_failed.fixture.registration.workflow())
  let raw_closed = fold_closed_loop_v2(
    root_failed.fixture.empty_effects,
    raw_replay,
  )
  guard raw_closed.orchestration().schedules.last() is Some(raw_registration) &&
    raw_registration.schedule().retry_plan() is Some(raw_plan) else {
    fail("raw substituted retry schedule or plan missing")
  }
  assert_true(raw_plan.policy_ref() == alternate_policy.policy_ref())
  assert_true(raw_plan.policy_bytes() == alternate_policy.canonical_bytes())
  let raw_root = fold_initial_work_receipt_v22(
    root_failed.fixture.empty_effects,
    raw_replay,
  )
  assert_true(raw_root.retry_policy.retry_policy_ref == policy.policy_ref())
  assert_true(
    raw_root.retry_policy.retry_policy_bytes == policy.canonical_bytes(),
  )
  try
    ignore(
      fold_governed_closed_loop_v2(
        root_failed.fixture.empty_effects,
        raw_replay,
        root_failed.governance_replay,
      ),
    )
  catch {
    PolicyMismatch(field="root_retry_policy_binding") => ()
    error =>
      fail("unexpected substituted retry replay error: \{to_repr(error)}")
  } noraise {
    _ => fail("governed replay accepted a substituted retry plan policy")
  }
  let retry = try
    prepare_guarded_atomic_retry_v2(
      current,
      open,
      guarded_request,
      root_failed.retry_receipt,
      policy,
      admission,
      root_failed.fixture.intent.governance(),
      "phase1b3-c-retry-plan",
      "phase1b3-c-retry-attempt",
      "phase1b3-c-retry-attempt-event",
      "phase1b3-c-retry-attempt-key",
      requested_work,
      evidence,
      root_failed.retry_receipt.source_observed_at(),
      "phase1b3-c-retry-schedule",
      "phase1b3-c-retry-schedule-key",
      18L,
      "phase1b3-c-retry-schedule-event",
      "phase1b3-c-retry-registration",
      "phase1b3-c-retry-command",
    )
  catch {
    EffectProofMismatch(field~) => fail("retry atomic proof: " + field)
    error => fail("retry atomic: \{to_repr(error)}")
  } noraise {
    value => value
  }
  ignore(root_failed.fixture.work_store.commit(retry.request()))
  let retry_current = fold_governed_closed_loop_v2(
    root_failed.fixture.empty_effects,
    root_failed.fixture.work_store.replay(
      root_failed.fixture.registration.workflow(),
    ),
    root_failed.governance_replay,
  )
  let effect_request = phase1b_test_envelope(
    "phase1b3-c-retry-effect-request",
    "effect-request",
    root_failed.fixture.intent.governance().governed_subject(),
    b"phase1b3-c-retry-effect-request",
    evidence,
  )
  let retry_intent = @effects.EffectIntent::new(
    "phase1b3-c-retry-intent",
    "1.0.0",
    retry.attempt(),
    root_failed.fixture.intent.governance(),
    effect_request,
    evidence,
    "phase1b3-c-retry-external-key",
    phase1a_wb_ref(
      "capability", "phase1b3-c-retry-capability", b"phase1b3-c-retry-capability",
    ),
    "phase1b3-c-retry-capability-token",
    14L,
    retry.attempt().attempt_ref(),
    retry_current.work_head_digest,
    true,
    fencing=@effects.FencingBinding::new(
      root_failed.fixture.intent.fencing().unwrap().fence_ref(),
      2L,
      11L,
    ),
  )
  let retry_open = retry_current.open_work_authority()
  let intent_authorization = retry_current.authorize_open_work_operation(
    retry_open,
    "effect.intent.commit",
    retry_intent.intent_ref(),
  )
  ignore(
    root_failed.fixture.work_store.commit(
      prepare_guarded_effect_intent_v2(
        retry_current, retry_open, intent_authorization, "phase1b3-c-retry-intent-event",
        "phase1b3-c-retry-outbox", "phase1b3-c-retry-intent-command", retry_intent,
      ),
    ),
  )
  let intent_current = fold_governed_closed_loop_v2(
    root_failed.fixture.empty_effects,
    root_failed.fixture.work_store.replay(
      root_failed.fixture.registration.workflow(),
    ),
    root_failed.governance_replay,
  )
  let observed = phase1b3_c_observe_intent(
    intent_current,
    root_failed.fixture.work_store,
    root_failed.fixture.empty_effects,
    root_failed.fixture.registration.workflow(),
    retry_intent,
    root_failed.governance_replay,
    "retry-bound-child",
  )
  let failed_receipt = @effects.EffectReceipt::new(
    "phase1b3-c-retry-failed-receipt",
    "1.0.0",
    retry_intent,
    phase1b_test_envelope(
      "phase1b3-c-retry-failed-receipt-envelope",
      "dispatcher-receipt",
      retry_intent.governance().governed_subject(),
      b"phase1b3-c-retry-failed-receipt",
      evidence,
    ),
    @effects.Failed,
    16L,
    evidence,
    observed_fencing=retry_intent.fencing().unwrap(),
  )
  let receipt_authority = observed.inflight_resolution_authority(
    retry_intent.intent_ref(),
    "receipt.record",
    failed_receipt.receipt_ref(),
  )
  ignore(
    root_failed.fixture.work_store.commit(
      prepare_guarded_effect_receipt_v2(
        observed, receipt_authority, "phase1b3-c-retry-failed-receipt-event", "phase1b3-c-retry-failed-receipt-command",
        failed_receipt,
      ),
    ),
  )
  let failed = fold_governed_closed_loop_v2(
    root_failed.fixture.empty_effects,
    root_failed.fixture.work_store.replay(
      root_failed.fixture.registration.workflow(),
    ),
    root_failed.governance_replay,
  )
  guard failed.work.effects.committed_retry_eligibility_receipt(
      retry_intent.intent_ref(),
    )
    is Some(retry_receipt) else {
    fail("child retry receipt missing")
  }
  assert_eq(retry_receipt.attempt_count(), 2L)
  assert_eq(retry_receipt.retry_count(), 1L)
  assert_true(retry_receipt.attempt_count() < policy.maximum_attempt_count())
  assert_true(retry_receipt.retry_count() == policy.maximum_retry_count())
  assert_true(!policy.allows(retry_receipt))
  let multi_store = phase1b_clone_replay_to_memory(
    root_failed.fixture.work_store.replay(
      root_failed.fixture.registration.workflow(),
    ),
  )
  let multi_base = fold_governed_closed_loop_v2(
    root_failed.fixture.empty_effects,
    multi_store.replay(root_failed.fixture.registration.workflow()),
    root_failed.governance_replay,
  )
  let child_registration = retry.registration()
  let child_schedule = child_registration.schedule()
  guard multi_store
    .replay(root_failed.fixture.registration.workflow())
    .events()
    .filter(event => {
      event.payload().envelope_kind() == schedule_registered_event_kind_v2
    })
    .last()
    is Some(child_schedule_event) else {
    fail("valid first-child schedule event missing")
  }
  let child_claim = LeaseClaimV2::new(
    "phase1b3-c-multi-child-claim",
    child_schedule,
    child_schedule.admission(),
    root_failed.fixture.registration.workflow(),
    phase1a_wb_ref(
      "owner", "phase1b3-c-multi-child-owner", b"phase1b3-c-multi-child-owner",
    ),
    1L,
    multi_base.work.orchestration().epoch_floor(),
    multi_base.work.orchestration().fencing_floor(),
    2L,
    2L,
    "phase1b3-c-multi-child-claim-key",
    evidence,
    child_schedule_event.event_ref(),
  )
  let child_claimed = LeaseClaimedV2::new(
    "phase1b3-c-multi-child-claimed", child_registration, child_claim,
  )
  let multi_open = multi_base.open_work_authority()
  let child_claim_authorization = multi_base.authorize_open_work_operation(
    multi_open,
    "lease.claim",
    child_claimed.record_ref(),
  )
  ignore(
    multi_store.commit(
      prepare_guarded_lease_claimed_v2(
        multi_base,
        multi_open,
        child_claim_authorization,
        "phase1b3-c-multi-child-claim-event",
        child_claim.idempotency_key(),
        "phase1b3-c-multi-child-claim-command",
        child_claimed,
      ),
    ),
  )
  let multi_claimed = fold_governed_closed_loop_v2(
    root_failed.fixture.empty_effects,
    multi_store.replay(root_failed.fixture.registration.workflow()),
    root_failed.governance_replay,
  )
  guard multi_claimed.committed_lease_authority_receipt_v2()
    is Some(child_lease_receipt) else {
    fail("valid first-child lease receipt missing")
  }
  let child_release = LeaseReleaseV2::new(
    "phase1b3-c-multi-child-release",
    child_registration,
    child_lease_receipt,
    flow7_lifecycle_active_authorization(
      "phase1b3-c-multi-child-release",
      multi_claimed.work.orchestration(),
      child_registration,
      child_lease_receipt,
      ReleaseLeaseV2,
      None,
      child_schedule.admission().eligibility().clock(),
    ),
  )
  let child_release_authorization = multi_claimed.authorize_lease_settlement_v2(
    "lease.release",
    child_release.record_ref(),
  )
  ignore(
    multi_store.commit(
      prepare_guarded_lease_released_v2(
        multi_claimed,
        child_release_authorization,
        "phase1b3-c-multi-child-release-event",
        child_release.idempotency_key(),
        "phase1b3-c-multi-child-release-command",
        child_release,
      ),
    ),
  )
  let multi_current = fold_governed_closed_loop_v2(
    root_failed.fixture.empty_effects,
    multi_store.replay(root_failed.fixture.registration.workflow()),
    root_failed.governance_replay,
  )
  guard multi_current.work.effects.committed_retry_eligibility_receipt(
      retry_intent.intent_ref(),
    )
    is Some(multi_receipt) else {
    fail("valid first-child current retry receipt missing")
  }
  multi_receipt.validate_current(multi_current.work.effects)
  let multi_requested_work = phase1b_test_envelope(
    "phase1b3-c-multi-foreign-requested-work",
    "requested-work",
    retry_intent.governance().governed_subject(),
    b"phase1b3-c-multi-foreign-requested-work",
    evidence,
  )
  let multi_requested_ref = @contracts.RecordRef::new(
    "requested-work",
    multi_requested_work.envelope_id(),
    "1.0.0",
    multi_requested_work.envelope_digest().text(),
  )
  let multi_request = prepare_retry_schedule_request_v2(
    multi_current.work,
    multi_receipt,
    alternate_policy,
    retry_intent.governance(),
    "phase1b3-c-multi-foreign-request",
    "phase1b3-c-multi-foreign-attempt",
    "phase1b3-c-multi-foreign-attempt-key",
    multi_requested_work,
    "attempt",
    "1.0.0",
    "effect",
    "1.0.0",
    @contracts.sha256_digest(b"phase1b3-c-multi-foreign-attempt-key-artifact"),
    "phase1b3-c-multi-foreign-schedule",
    "phase1b3-c-multi-foreign-schedule-key",
    18L,
    18L,
    18L,
    "phase1b3-c-multi-foreign-command",
  )
  let multi_timing = RetryTimingV2::compute(alternate_policy, multi_receipt)
  let multi_admission = flow7_aggregate_admission(
    "phase1b3-c-multi-foreign-admission",
    root_failed.fixture.registration.workflow(),
    multi_current.work.prefix_event().unwrap(),
    multi_timing.due_at(),
    18L,
    retry_intent.governance().policy_ref(),
    flow7_aggregate_planned(
      root_failed.fixture.registration.workflow(),
      retry_intent.governance().governed_subject(),
      multi_requested_ref,
      multi_requested_work.envelope_digest(),
      3L,
      "phase1b3-c-multi-foreign-attempt-key",
      multi_request.request_ref(),
    ),
    evidence[0],
    lease_epoch=3L,
    fencing_token=3L,
  )
  let multi_retry = prepare_atomic_retry_v2(
    multi_current.work,
    multi_receipt,
    alternate_policy,
    multi_request,
    multi_admission,
    retry_intent.governance(),
    "phase1b3-c-multi-foreign-plan",
    "phase1b3-c-multi-foreign-attempt",
    "phase1b3-c-multi-foreign-attempt-event",
    "phase1b3-c-multi-foreign-attempt-key",
    multi_requested_work,
    evidence,
    multi_receipt.source_observed_at(),
    "phase1b3-c-multi-foreign-schedule",
    "phase1b3-c-multi-foreign-schedule-key",
    18L,
    "phase1b3-c-multi-foreign-schedule-event",
    "phase1b3-c-multi-foreign-registration",
    "phase1b3-c-multi-foreign-command",
  )
  ignore(multi_store.commit(multi_retry.request()))
  try
    ignore(
      fold_governed_closed_loop_v2(
        root_failed.fixture.empty_effects,
        multi_store.replay(root_failed.fixture.registration.workflow()),
        root_failed.governance_replay,
      ),
    )
  catch {
    PolicyMismatch(field="root_retry_policy_binding") => ()
    error => fail("unexpected multi-generation policy error: \{to_repr(error)}")
  } noraise {
    _ => fail("governed replay accepted a later foreign retry plan")
  }
  let prepared = prepare_retry_exhausted_work_terminal_v2(failed, retry_receipt)
  assert_true(prepared.outcome() == FailedRetryExhaustedV2)
  ignore(root_failed.fixture.work_store.commit(prepared.commit_request()))
  let terminal = fold_governed_closed_loop_v2(
    root_failed.fixture.empty_effects,
    root_failed.fixture.work_store.replay(
      root_failed.fixture.registration.workflow(),
    ),
    root_failed.governance_replay,
  )
  guard terminal.committed_work_terminal_receipt() is Some(receipt) else {
    fail("retry-bound terminal receipt missing")
  }
  assert_true(receipt.outcome() == FailedRetryExhaustedV2)
  receipt.validate_current(terminal)
}

///|
test "FLOW-7 Phase1B.3-C stale mismatch policy counter and source proofs deny terminalization" {
  let policy_a = phase1b3_c_policy("negative-a", 3L, 2L, [])
  let policy_b = phase1b3_c_policy("negative-b", 3L, 2L, [])
  let left = phase1b3_c_known_failure_fixture("negative-a", policy_a)
  let right = phase1b3_c_known_failure_fixture("negative-b", policy_b)
  try
    ignore(
      prepare_retry_proven_failure_work_terminal_v2(
        left.current,
        right.retry_receipt,
      ),
    )
  catch {
    ReplayBindingViolation(field="work_terminal_source") => ()
    error => fail("unexpected mismatched receipt error: \{to_repr(error)}")
  } noraise {
    _ => fail("mismatched source and retry receipt terminalized")
  }
  let prepared = prepare_failed_work_terminal_v2(left.current, left.source)
  let event = prepared.commit_request().events()[0]
  let original = decode_work_terminal_record_v22(
    event.payload().subject(),
    event.payload().payload(),
  )
  let substituted_policy = RetryPolicyV2::new(
    policy_a.policy_ref().id(),
    "2.0.0",
    3L,
    2L,
    2L,
    1000L,
    1L,
    1L,
    0L,
    @contracts.sha256_digest(b"phase1b3-c-substituted-policy-seed"),
    [],
  )
  phase1b3_c_require_forged_terminal_rejected(
    left,
    phase1b3_c_reseal_terminal(
      original,
      Some(substituted_policy.policy_ref()),
      Some(substituted_policy.canonical_bytes()),
      original.attempt_count,
      original.retry_count,
      original.source_proof_ref,
      original.source_proof_bytes,
    ),
    "substituted-policy",
  )
  phase1b3_c_require_forged_terminal_rejected(
    left,
    phase1b3_c_reseal_terminal(
      original,
      original.retry_policy_ref,
      original.retry_policy_bytes,
      Some(policy_a.maximum_attempt_count() + 1L),
      original.retry_count,
      original.source_proof_ref,
      original.source_proof_bytes,
    ),
    "substituted-counter",
  )
  phase1b3_c_require_forged_terminal_rejected(
    left,
    phase1b3_c_reseal_terminal(
      original,
      original.retry_policy_ref,
      original.retry_policy_bytes,
      original.attempt_count,
      original.retry_count,
      right.source.receipt_ref(),
      right.source.canonical_bytes(),
    ),
    "substituted-source",
  )
}

///|
test "FLOW-7 Phase1B.3-C cancellation not-applied over-bound and forged replay reject" {
  phase1b3_c_commit_cancelled_not_applied(
    phase1b3_c_policy("cancel-excluded-not-applied", 3L, 2L, []),
    "cancel-excluded-not-applied",
  )
  phase1b3_c_commit_cancelled_not_applied(
    phase1b3_c_policy("cancel-exact-not-applied", 1L, 0L, [
      "reconciled_not_applied",
    ]),
    "cancel-exact-not-applied",
  )
  let policy = phase1b3_c_policy("cancel-not-applied", 3L, 2L, [
    "terminal_failed", "reconciled_not_applied",
  ])
  let resolved = phase1b3_c_reconciled_fixture(
    "cancel-not-applied", policy, true,
  )
  let cancelled = try
    phase1b3_c_cancel_reconciled_not_applied(resolved, "cancel-not-applied")
  catch {
    ClockRegression(previous~, incoming~) =>
      fail("cancel not-applied clock: \{previous}/\{incoming}")
    error => fail("cancel not-applied fixture: \{to_repr(error)}")
  } noraise {
    value => value
  }
  for
    counts in [
      (policy.maximum_attempt_count() + 1L, 0L),
      (1L, policy.maximum_retry_count() + 1L),
    ] {
    try
      require_work_terminal_counter_bounds_v22(policy, counts.0, counts.1)
    catch {
      RetryBoundViolation(field="work_terminal_failure_counter") => ()
      error =>
        fail("unexpected cancellation over-bound error: \{to_repr(error)}")
    } noraise {
      _ => fail("cancellation not-applied accepted over-bound counters")
    }
  }
  let prepared = prepare_cancelled_after_reconciled_not_applied_work_terminal_v2(
    cancelled.current,
    cancelled.source,
  )
  assert_true(prepared.outcome() == CancelledAfterReconciledNotAppliedV2)
  let event = prepared.commit_request().events()[0]
  let terminal = decode_work_terminal_record_v22(
    event.payload().subject(),
    event.payload().payload(),
  )
  try
    ignore(
      phase1b3_c_reseal_terminal(
        terminal,
        Some(policy.policy_ref()),
        Some(policy.canonical_bytes()),
        Some(policy.maximum_attempt_count() + 1L),
        Some(0L),
        terminal.source_proof_ref,
        terminal.source_proof_bytes,
      ),
    )
  catch {
    ReplayBindingViolation(field="work_terminal_option_shape") => ()
    error =>
      fail("unexpected cancellation counter shape error: \{to_repr(error)}")
  } noraise {
    _ => fail("cancellation terminal carried failure counters")
  }
  let (_, retry_option_offset) = phase1b_terminal_option_offsets(
    terminal.canonical,
  )
  let forged_bytes = phase1b_replace_int64_marker(
    terminal.canonical,
    retry_option_offset,
    2,
  )
  let forged_ref = phase1b_readdress(terminal.terminal_ref, forged_bytes)
  let store = phase1b_clone_replay_to_memory(
    cancelled.fixture.work_store.replay(
      cancelled.fixture.registration.workflow(),
    ),
  )
  let forged_event = prepare_phase1b_work_event_v22(
    cancelled.fixture.registration.workflow(),
    cancelled.current.work_sequence + 1L,
    cancelled.current.work_revision + 1L,
    cancelled.current.work_head_digest,
    "phase1b3-c-forged-cancel-terminal-event",
    work_terminal_event_kind_v22,
    forged_ref,
    forged_bytes,
    terminal.governed_subject,
    [
      for value in terminal.evidence => value
    ],
    terminal.causation,
    terminal.event_idempotency_key,
  )
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        cancelled.fixture.registration.workflow(),
        cancelled.current.work_revision,
        terminal.command_idempotency_key,
        [forged_event],
        [],
      ),
    ),
  )
  try
    ignore(
      fold_governed_closed_loop_v2(
        cancelled.fixture.empty_effects,
        store.replay(cancelled.fixture.registration.workflow()),
        cancelled.governance_replay,
      ),
    )
  catch {
    MalformedInput(field="work_terminal_v22_retry_policy_option") => ()
    error =>
      fail("unexpected forged cancellation replay error: \{to_repr(error)}")
  } noraise {
    _ => fail("forged cancellation counter option replayed")
  }
}
