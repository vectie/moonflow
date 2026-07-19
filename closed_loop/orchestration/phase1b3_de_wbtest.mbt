///|
priv struct Phase1b3DETerminalFixture {
  label : String
  work_store : @storage.MemoryStore
  empty_effects : @effects.EffectsProjection
  governance_replay : @storage.ReplayResult
  workflow : @contracts.RecordRef
  registration : ScheduleRegisteredV2
  governed_subject : @contracts.RecordRef
  terminal_request : @storage.CommitRequest
  terminal_current : CurrentGovernedClosedLoopProjectionV2
  terminal_receipt : CommittedWorkTerminalReceiptV2
  outcome : WorkTerminalOutcomeV2
}

///|
priv struct Phase1b3DECancellationCandidate {
  prefix_replay : @storage.ReplayResult
  governance_replay : @storage.ReplayResult
  request : @storage.CommitRequest
}

///|
fn phase1b3_de_commit_terminal(
  label : String,
  work_store : @storage.MemoryStore,
  empty_effects : @effects.EffectsProjection,
  governance_replay : @storage.ReplayResult,
  workflow : @contracts.RecordRef,
  registration : ScheduleRegisteredV2,
  governed_subject : @contracts.RecordRef,
  prepared : PreparedWorkTerminalV2,
  outcome : WorkTerminalOutcomeV2,
) -> Phase1b3DETerminalFixture raise {
  assert_true(prepared.outcome() == outcome)
  let request = prepared.commit_request()
  assert_eq(request.events().length(), 1)
  assert_eq(request.intents().length(), 0)
  ignore(work_store.commit(request))
  let current = fold_governed_closed_loop_v2(
    empty_effects,
    work_store.replay(workflow),
    governance_replay,
  )
  guard current.committed_work_terminal_receipt() is Some(receipt) else {
    fail("terminal receipt missing: " + label)
  }
  assert_true(receipt.outcome() == outcome)
  receipt.validate_current(current)
  {
    label,
    work_store,
    empty_effects,
    governance_replay,
    workflow,
    registration,
    governed_subject,
    terminal_request: request,
    terminal_current: current,
    terminal_receipt: receipt,
    outcome,
  }
}

///|
fn phase1b3_de_success_fixture(
  suffix : String,
) -> Phase1b3DETerminalFixture raise {
  let fixture = phase1b_pending_fixture(suffix)
  let governance_replay = fixture.governance.store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  let observed = phase1b3_c_observe_intent(
    fixture.current,
    fixture.work_store,
    fixture.empty_effects,
    fixture.registration.workflow(),
    fixture.intent,
    governance_replay,
    suffix,
  )
  let evidence = [ for value in fixture.intent.evidence() => value ]
  let receipt = @effects.EffectReceipt::new(
    "phase1b3-de-success-receipt-" + suffix,
    "1.0.0",
    fixture.intent,
    phase1b_test_envelope(
      "phase1b3-de-success-receipt-envelope-" + suffix,
      "dispatcher-receipt",
      fixture.intent.governance().governed_subject(),
      @utf8.encode("phase1b3-de-success-" + suffix),
      evidence,
    ),
    @effects.Succeeded,
    12L,
    evidence,
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  let authority = observed.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "receipt.record",
    receipt.receipt_ref(),
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_effect_receipt_v2(
        observed,
        authority,
        "phase1b3-de-success-receipt-event-" + suffix,
        "phase1b3-de-success-receipt-command-" + suffix,
        receipt,
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
    fail("success source missing: " + suffix)
  }
  phase1b3_de_commit_terminal(
    "succeeded",
    fixture.work_store,
    fixture.empty_effects,
    governance_replay,
    fixture.registration.workflow(),
    fixture.registration,
    fixture.intent.governance().governed_subject(),
    prepare_succeeded_work_terminal_v2(current, source),
    SucceededV2,
  )
}

///|
fn phase1b3_de_safe_fixture(suffix : String) -> Phase1b3DETerminalFixture raise {
  let fixture = phase1b_fixture(suffix~)
  let governance_replay = fixture.governance.store.replay(
    fixture.receipt.governance_stream_ref,
  )
  let prepared = prepare_cancellation_v2(fixture.current, fixture.request)
  assert_true(
    prepared.terminal_outcome() == Some(CancelledBeforeEffectIntentV2),
  )
  let request = prepared.commit_request()
  assert_eq(request.events().length(), 2)
  assert_eq(request.intents().length(), 0)
  ignore(fixture.work_store.commit(request))
  let current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard current.committed_work_terminal_receipt() is Some(receipt) else {
    fail("safe terminal receipt missing")
  }
  receipt.validate_current(current)
  {
    label: "cancelled-before-effect-intent",
    work_store: fixture.work_store,
    empty_effects: fixture.empty_effects,
    governance_replay,
    workflow: fixture.registration.workflow(),
    registration: fixture.registration,
    governed_subject: fixture.registration
    .schedule()
    .admission()
    .governance()
    .governed_subject(),
    terminal_request: request,
    terminal_current: current,
    terminal_receipt: receipt,
    outcome: CancelledBeforeEffectIntentV2,
  }
}

///|
fn phase1b3_de_terminal_fixture(
  label : String,
) -> Phase1b3DETerminalFixture raise {
  if label == "safe" {
    return phase1b3_de_safe_fixture("phase1b3-de-safe")
  }
  if label == "succeeded" {
    return phase1b3_de_success_fixture("phase1b3-de-succeeded")
  }
  if label == "cancelled-not-applied" {
    let policy = phase1b3_c_policy(
      "phase1b3-de-cancelled-not-applied",
      3L,
      2L,
      ["terminal_failed", "reconciled_not_applied"],
    )
    let resolved = phase1b3_c_reconciled_fixture(
      "phase1b3-de-cancelled-not-applied", policy, true,
    )
    let cancelled = phase1b3_c_cancel_reconciled_not_applied(
      resolved, "phase1b3-de-cancelled-not-applied",
    )
    return phase1b3_de_commit_terminal(
      label,
      cancelled.fixture.work_store,
      cancelled.fixture.empty_effects,
      cancelled.governance_replay,
      cancelled.fixture.registration.workflow(),
      cancelled.fixture.registration,
      cancelled.fixture.intent.governance().governed_subject(),
      prepare_cancelled_after_reconciled_not_applied_work_terminal_v2(
        cancelled.current,
        cancelled.source,
      ),
      CancelledAfterReconciledNotAppliedV2,
    )
  }
  if label == "failed-nonretryable" {
    let policy = phase1b3_c_policy("phase1b3-de-failed-nonretryable", 3L, 2L, [])
    let failed = phase1b3_c_known_failure_fixture(
      "phase1b3-de-failed-nonretryable", policy,
    )
    return phase1b3_de_commit_terminal(
      label,
      failed.fixture.work_store,
      failed.fixture.empty_effects,
      failed.governance_replay,
      failed.fixture.registration.workflow(),
      failed.fixture.registration,
      failed.fixture.intent.governance().governed_subject(),
      prepare_failed_work_terminal_v2(failed.current, failed.source),
      FailedNonRetryableV2,
    )
  }
  if label == "failed-exhausted" {
    let policy = phase1b3_c_policy("phase1b3-de-failed-exhausted", 1L, 0L, [
      "terminal_failed",
    ])
    let failed = phase1b3_c_known_failure_fixture(
      "phase1b3-de-failed-exhausted", policy,
    )
    return phase1b3_de_commit_terminal(
      label,
      failed.fixture.work_store,
      failed.fixture.empty_effects,
      failed.governance_replay,
      failed.fixture.registration.workflow(),
      failed.fixture.registration,
      failed.fixture.intent.governance().governed_subject(),
      prepare_retry_exhausted_work_terminal_v2(
        failed.current,
        failed.retry_receipt,
      ),
      FailedRetryExhaustedV2,
    )
  }
  if label == "failed-cancellation-stopped" {
    let policy = phase1b3_c_policy(
      "phase1b3-de-failed-cancellation-stopped",
      3L,
      2L,
      ["terminal_failed"],
    )
    let failed = phase1b3_c_known_failure_fixture(
      "phase1b3-de-failed-cancellation-stopped", policy,
    )
    let cancelled = phase1b3_c_cancel_reconciled_not_applied(
      failed, "phase1b3-de-failed-cancellation-stopped",
    )
    return phase1b3_de_commit_terminal(
      label,
      cancelled.fixture.work_store,
      cancelled.fixture.empty_effects,
      cancelled.governance_replay,
      cancelled.fixture.registration.workflow(),
      cancelled.fixture.registration,
      cancelled.fixture.intent.governance().governed_subject(),
      prepare_failed_work_terminal_v2(cancelled.current, cancelled.source),
      FailedCancellationStoppedRetryV2,
    )
  }
  fail("unknown terminal fixture: " + label)
}

///|
fn phase1b3_de_require_memory_consistency(
  terminal : Phase1b3DETerminalFixture,
) -> Unit raise {
  let replay = terminal.work_store.replay(terminal.workflow)
  let matching = replay
    .committed_batches()
    .filter(boundary => {
      boundary.command_idempotency_key() ==
      terminal.terminal_request.command_idempotency_key()
    })
  assert_eq(matching.length(), 1)
  let boundary = matching[0]
  assert_eq(
    boundary.expected_revision(),
    terminal.terminal_request.expected_revision(),
  )
  assert_eq(
    boundary.event_refs().length(),
    terminal.terminal_request.events().length(),
  )
  for index, event_ref in boundary.event_refs() {
    assert_true(
      event_ref == terminal.terminal_request.events()[index].event_ref(),
    )
  }
  assert_eq(boundary.intent_refs().length(), 0)
  assert_eq(terminal.terminal_request.intents().length(), 0)
  let first = terminal.work_store.commit(terminal.terminal_request)
  let duplicate = terminal.work_store.commit(terminal.terminal_request)
  assert_eq(first.workflow_revision(), duplicate.workflow_revision())
  let before_conflicts = terminal.work_store.replay(terminal.workflow)
  let changed_same_key = @storage.CommitRequest::new(
    terminal.terminal_request.record_version().text(),
    terminal.terminal_request.schema_version().text(),
    terminal.workflow,
    terminal.terminal_request.expected_revision() + 1L,
    terminal.terminal_request.command_idempotency_key(),
    [
      for event in terminal.terminal_request.events() => event
    ],
    [],
  )
  try terminal.work_store.commit(changed_same_key) catch {
    @storage.IdempotencyConflict(key~) =>
      assert_eq(key, terminal.terminal_request.command_idempotency_key())
    error => fail("unexpected changed-body conflict: \{to_repr(error)}")
  } noraise {
    _ => fail("same command key accepted changed body: " + terminal.label)
  }
  let stale = @storage.CommitRequest::new(
    terminal.terminal_request.record_version().text(),
    terminal.terminal_request.schema_version().text(),
    terminal.workflow,
    terminal.terminal_request.expected_revision(),
    terminal.terminal_request.command_idempotency_key() + ":stale",
    [
      for event in terminal.terminal_request.events() => event
    ],
    [],
  )
  try terminal.work_store.commit(stale) catch {
    @storage.OptimisticRevisionConflict(..) => ()
    error => fail("unexpected stale-head conflict: \{to_repr(error)}")
  } noraise {
    _ => fail("stale terminal head committed: " + terminal.label)
  }
  let after_conflicts = terminal.work_store.replay(terminal.workflow)
  assert_true(
    after_conflicts.replay_digest() == before_conflicts.replay_digest(),
  )
  let restarted_store = phase1b_clone_replay_to_memory(after_conflicts)
  let restarted_replay = restarted_store.replay(terminal.workflow)
  let restarted = fold_governed_closed_loop_v2(
    terminal.empty_effects,
    restarted_replay,
    terminal.governance_replay,
  )
  guard restarted.committed_work_terminal_receipt() is Some(receipt) else {
    fail("memory restart lost terminal: " + terminal.label)
  }
  receipt.validate_current(restarted)
  assert_true(restarted_replay.replay_digest() == replay.replay_digest())
  assert_true(
    restarted.work.effects.state_digest() ==
    terminal.terminal_current.work.effects.state_digest(),
  )
  assert_true(
    restarted.work.orchestration.state_digest() ==
    terminal.terminal_current.work.orchestration.state_digest(),
  )
  assert_true(receipt.record_ref() == terminal.terminal_receipt.record_ref())
  assert_true(receipt.digest() == terminal.terminal_receipt.digest())
  assert_true(
    receipt.canonical_bytes() == terminal.terminal_receipt.canonical_bytes(),
  )
}

///|
fn phase1b3_de_require_late_kind_rejected(
  terminal : Phase1b3DETerminalFixture,
  kind : String,
  index : Int,
) -> Unit raise {
  let store = phase1b_clone_replay_to_memory(
    terminal.work_store.replay(terminal.workflow),
  )
  let current = terminal.terminal_current
  let late_event = prepare_phase1b_work_event_v22(
    terminal.workflow,
    current.work_sequence + 1L,
    current.work_revision + 1L,
    current.work_head_digest,
    "phase1b3-de-late-\{terminal.label}-\{index}",
    kind,
    terminal.terminal_receipt.record_ref(),
    @utf8.encode("late:" + kind),
    terminal.governed_subject,
    [],
    terminal.terminal_receipt.record_ref(),
    "phase1b3-de-late-key-\{terminal.label}-\{index}",
  )
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        terminal.workflow,
        current.work_revision,
        "phase1b3-de-late-command-\{terminal.label}-\{index}",
        [late_event],
        [],
      ),
    ),
  )
  try
    ignore(
      fold_governed_closed_loop_v2(
        terminal.empty_effects,
        store.replay(terminal.workflow),
        terminal.governance_replay,
      ),
    )
  catch {
    CancellationPrecedenceViolation(field="late_event_after_work_terminal") =>
      ()
    error =>
      fail(
        "unexpected late-event rejection: \{terminal.label}:\{kind}:\{to_repr(error)}",
      )
  } noraise {
    _ => fail("late event survived terminal: \{terminal.label}:\{kind}")
  }
}

///|
fn phase1b3_de_cancellation_candidate(
  terminal : Phase1b3DETerminalFixture,
  suffix : String,
) -> Phase1b3DECancellationCandidate raise {
  let prefix_replay = terminal.work_store
    .replay(terminal.workflow)
    .verified_prefix(terminal.terminal_request.expected_revision())
  let root = fold_initial_work_receipt_v22(
    terminal.empty_effects,
    prefix_replay,
  )
  let prefix_current = fold_governed_closed_loop_v2(
    terminal.empty_effects,
    prefix_replay,
    terminal.governance_replay,
  )
  let evidence = [
    for value in terminal.registration.schedule().evidence() => value
  ]
  let proposal = CancellationProposalV2::new(
    "phase1b3-de-race-proposal-" + suffix,
    root,
    prefix_current.work,
    terminal.governed_subject,
    phase1a_wb_ref(
      "reason",
      "phase1b3-de-race-reason-" + suffix,
      @utf8.encode("phase1b3-de-race-reason-" + suffix),
    ),
    10L,
    evidence,
    phase1a_wb_ref(
      "causation",
      "phase1b3-de-race-causation-" + suffix,
      @utf8.encode("phase1b3-de-race-causation-" + suffix),
    ),
    "phase1b3-de-race-proposal-event-key-" + suffix,
    "phase1b3-de-race-proposal-command-key-" + suffix,
  )
  let chain = phase1b_governance_chain(
    phase1a_wb_policy(),
    root.governance_stream_ref(),
    proposal,
    evidence,
    "phase1b3-de-race-" + suffix,
  )
  let governance_replay = chain.store.replay(root.governance_stream_ref())
  let governed = fold_governed_closed_loop_v2(
    terminal.empty_effects,
    prefix_replay,
    governance_replay,
  )
  let governance_receipt = governed.committed_cancellation_governance_receipt(
    proposal,
  )
  let authorization = CancellationAuthorizationV2::from_committed_governance(
    "phase1b3-de-race-authorization-" + suffix,
    governance_receipt,
    proposal,
    governed,
  )
  let request = CancellationRequestV2::new(
    "phase1b3-de-race-request-" + suffix,
    proposal,
    authorization,
  )
  let prepared = prepare_cancellation_v2(governed, request)
  assert_true(prepared.terminal_outcome() is None)
  { prefix_replay, governance_replay, request: prepared.commit_request() }
}

///|
fn phase1b3_de_require_terminal_cancellation_race(
  terminal : Phase1b3DETerminalFixture,
  suffix : String,
) -> Unit raise {
  let cancellation = phase1b3_de_cancellation_candidate(terminal, suffix)
  assert_eq(
    cancellation.request.expected_revision(),
    terminal.terminal_request.expected_revision(),
  )
  let terminal_wins = phase1b_clone_replay_to_memory(cancellation.prefix_replay)
  ignore(terminal_wins.commit(terminal.terminal_request))
  try terminal_wins.commit(cancellation.request) catch {
    @storage.OptimisticRevisionConflict(expected~, actual~, ..) => {
      assert_eq(expected, terminal.terminal_request.expected_revision())
      assert_eq(
        actual,
        terminal.terminal_request.expected_revision() +
        Int64::from_int(terminal.terminal_request.events().length()),
      )
    }
    error => fail("unexpected terminal-winner race error: \{to_repr(error)}")
  } noraise {
    _ => fail("stale cancellation survived terminal winner: " + suffix)
  }
  let terminal_current = fold_governed_closed_loop_v2(
    terminal.empty_effects,
    terminal_wins.replay(terminal.workflow),
    terminal.governance_replay,
  )
  guard terminal_current.committed_work_terminal_receipt() is Some(receipt) else {
    fail("terminal winner receipt missing: " + suffix)
  }
  assert_true(receipt.outcome() == terminal.outcome)
  let cancellation_wins = phase1b_clone_replay_to_memory(
    cancellation.prefix_replay,
  )
  ignore(cancellation_wins.commit(cancellation.request))
  try cancellation_wins.commit(terminal.terminal_request) catch {
    @storage.OptimisticRevisionConflict(expected~, actual~, ..) => {
      assert_eq(expected, terminal.terminal_request.expected_revision())
      assert_eq(actual, terminal.terminal_request.expected_revision() + 1L)
    }
    error =>
      fail("unexpected cancellation-winner race error: \{to_repr(error)}")
  } noraise {
    _ => fail("stale terminal survived cancellation winner: " + suffix)
  }
  let cancellation_current = fold_governed_closed_loop_v2(
    terminal.empty_effects,
    cancellation_wins.replay(terminal.workflow),
    cancellation.governance_replay,
  )
  assert_true(cancellation_current.work.cancellation is Some(_))
  assert_true(cancellation_current.committed_work_terminal_receipt() is None)
}

///|
fn phase1b3_de_replace_terminal_payload(
  event : @storage.WorkflowEvent,
  subject : @contracts.RecordRef,
  payload_bytes : Bytes,
) -> @storage.WorkflowEvent raise {
  let payload = event.payload()
  let changed = @contracts.WireEnvelope::new(
    payload.contract_id(),
    payload.contract_version().text(),
    payload.envelope_id(),
    payload.envelope_kind(),
    subject,
    payload.schema(),
    payload_bytes,
    payload.producer_id(),
    payload.producer_version().text(),
    [
      for value in payload.artifacts() => value
    ],
    [
      for value in payload.evidence() => value
    ],
    run_ref?=payload.run_ref(),
    stage_ref?=payload.stage_ref(),
    attempt_ref?=payload.attempt_ref(),
    correlation_ref?=payload.correlation_ref(),
    causation_ref?=payload.causation_ref(),
    idempotency_ref?=payload.idempotency_ref(),
    previous_digest?=payload.previous_digest(),
    extensions=[ for value in payload.extensions() => value ],
  )
  @storage.WorkflowEvent::new(
    event.record_version().text(),
    event.schema_version().text(),
    event.workflow(),
    event.event_ref().id(),
    event.sequence(),
    event.revision(),
    event.idempotency_key(),
    changed,
    [
      for value in event.evidence() => value
    ],
    previous_event_digest?=event.previous_event_digest(),
  )
}

///|
fn phase1b3_de_readdress_event(
  event : @storage.WorkflowEvent,
  sequence : Int64,
  revision : Int64,
  previous_digest : @contracts.ContentDigest,
) -> @storage.WorkflowEvent raise {
  let payload = event.payload()
  let changed = @contracts.WireEnvelope::new(
    payload.contract_id(),
    payload.contract_version().text(),
    payload.envelope_id(),
    payload.envelope_kind(),
    payload.subject(),
    payload.schema(),
    payload.payload(),
    payload.producer_id(),
    payload.producer_version().text(),
    [
      for value in payload.artifacts() => value
    ],
    [
      for value in payload.evidence() => value
    ],
    run_ref?=payload.run_ref(),
    stage_ref?=payload.stage_ref(),
    attempt_ref?=payload.attempt_ref(),
    correlation_ref?=payload.correlation_ref(),
    causation_ref?=payload.causation_ref(),
    idempotency_ref?=payload.idempotency_ref(),
    previous_digest~,
    extensions=[ for value in payload.extensions() => value ],
  )
  @storage.WorkflowEvent::new(
    event.record_version().text(),
    event.schema_version().text(),
    event.workflow(),
    event.event_ref().id(),
    sequence,
    revision,
    event.idempotency_key(),
    changed,
    [
      for value in event.evidence() => value
    ],
    previous_event_digest=previous_digest,
  )
}

///|
fn phase1b3_de_require_terminal_replay_rejected(
  terminal : Phase1b3DETerminalFixture,
  event : @storage.WorkflowEvent,
  intents : Array[@storage.OutboxIntent],
  suffix : String,
  expected_kind : String,
  expected_field : String,
) -> Unit raise {
  let prefix = terminal.work_store
    .replay(terminal.workflow)
    .verified_prefix(terminal.terminal_request.expected_revision())
  let store = phase1b_clone_replay_to_memory(prefix)
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        terminal.workflow,
        terminal.terminal_request.expected_revision(),
        terminal.terminal_request.command_idempotency_key(),
        [event],
        intents,
      ),
    ),
  )
  try
    ignore(
      fold_governed_closed_loop_v2(
        terminal.empty_effects,
        store.replay(terminal.workflow),
        terminal.governance_replay,
      ),
    )
  catch {
    MalformedInput(field~) => {
      assert_eq(expected_kind, "MalformedInput")
      assert_eq(field, expected_field)
    }
    ReplayBindingViolation(field~) => {
      assert_eq(expected_kind, "ReplayBindingViolation")
      assert_eq(field, expected_field)
    }
    error =>
      fail("unexpected terminal tamper error: \{suffix}:\{to_repr(error)}")
  } noraise {
    _ => fail("canonical terminal tamper survived: " + suffix)
  }
}

///|
test "FLOW-7 Phase1B.3-D/E terminal outcomes are exact final and memory-stable" {
  let labels = [
    "safe", "succeeded", "cancelled-not-applied", "failed-nonretryable", "failed-exhausted",
    "failed-cancellation-stopped",
  ]
  let late_kinds = [
    "schedule.registered.v2", "retry.policy.bound.v2", "cancellation.governance.bound.v2",
    "EvidenceAttached", "AuthorityRequested", "AuthorityGranted", "AuthorityDenied",
    "AuthorityExpired", "ReviewRequested", "ReviewDecisionRecorded", "ReviewReceiptBound",
    "lifecycle.transitioned.v2", "lease.claimed.v2", "lease.renewed.v2", "lease.released.v2",
    "lease.expired.v2", "lease.reclaimed.v2", "attempt.registered.v1", "effect.intent.requested.v1",
    "effect.dispatch.observed.v1", "effect.receipt.recorded.v1", "effect.outcome.unknown.v1",
    "effect.reconciliation.requested.v1", "effect.reconciliation.resolved.v1", "schedule.retry.requested.v2",
    "work.cancellation.requested.v2", "work.terminal.v2",
  ]
  for label in labels {
    let terminal = phase1b3_de_terminal_fixture(label)
    phase1b3_de_require_memory_consistency(terminal)
    for index, kind in late_kinds {
      phase1b3_de_require_late_kind_rejected(terminal, kind, index)
    }
  }
}

///|
test "FLOW-7 Phase1B.3-D terminal races have one CAS winner" {
  phase1b3_de_require_terminal_cancellation_race(
    phase1b3_de_terminal_fixture("succeeded"),
    "success-cancellation",
  )
  phase1b3_de_require_terminal_cancellation_race(
    phase1b3_de_terminal_fixture("failed-nonretryable"),
    "failure-cancellation",
  )
}

///|
test "FLOW-7 Phase1B.3-E canonical wrappers composites and batches reject tamper" {
  let terminal = phase1b3_de_terminal_fixture("failed-nonretryable")
  let event = terminal.terminal_request.events()[0]
  let changed_bytes = phase1b_append_byte(event.payload().payload(), b'X')
  let changed_bytes_event = phase1b3_de_replace_terminal_payload(
    event,
    phase1b_readdress(event.payload().subject(), changed_bytes),
    changed_bytes,
  )
  phase1b3_de_require_terminal_replay_rejected(
    terminal,
    changed_bytes_event,
    [],
    "terminal-bytes",
    "MalformedInput",
    "trailing_bytes",
  )
  let wrong_subject_event = phase1b3_de_replace_terminal_payload(
    event,
    phase1a_wb_ref(
      "wrong-terminal", "phase1b3-de-wrong-terminal-subject", b"wrong-terminal-subject",
    ),
    event.payload().payload(),
  )
  phase1b3_de_require_terminal_replay_rejected(
    terminal,
    wrong_subject_event,
    [],
    "wrapper-subject",
    "ReplayBindingViolation",
    "work_record_byte_binding",
  )
  let unexpected_outbox = @storage.OutboxIntent::new(
    "1.0.0",
    "1.0.0",
    "phase1b3-de-terminal-outbox",
    terminal.workflow,
    event.event_ref(),
    "phase1b3-de-terminal-outbox-key",
    event.payload(),
    [],
  )
  phase1b3_de_require_terminal_replay_rejected(
    terminal,
    event,
    [unexpected_outbox],
    "terminal-outbox",
    "ReplayBindingViolation",
    "aggregate_outbox_consumption",
  )
  let safe = phase1b_fixture(suffix="phase1b3-de-canonical-safe")
  let prepared = prepare_cancellation_v2(safe.current, safe.request)
  let cancellation_event = prepared.commit_request().events()[0]
  let terminal_event = prepared.commit_request().events()[1]
  let safe_prefix = safe.work_store.replay(safe.registration.workflow())
  let omission = @storage.CommitRequest::new(
    "1.0.0",
    "1.0.0",
    safe.registration.workflow(),
    prepared.commit_request().expected_revision(),
    prepared.commit_request().command_idempotency_key(),
    [cancellation_event],
    [],
  )
  let omission_store = phase1b_clone_replay_to_memory(safe_prefix)
  ignore(omission_store.commit(omission))
  try
    ignore(
      fold_governed_closed_loop_v2(
        safe.empty_effects,
        omission_store.replay(safe.registration.workflow()),
        safe.governance.store.replay(safe.receipt.governance_stream_ref),
      ),
    )
  catch {
    ReplayBindingViolation(field="work_batch_boundary_shape") => ()
    error => fail("unexpected safe omission error: \{to_repr(error)}")
  } noraise {
    _ => fail("safe composite omission survived replay")
  }
  let prefix_head = safe_prefix.head()
  let reordered_terminal = phase1b3_de_readdress_event(
    terminal_event,
    prefix_head.sequence() + 1L,
    prefix_head.revision() + 1L,
    prefix_head.last_event_digest().unwrap(),
  )
  let reordered_cancellation = phase1b3_de_readdress_event(
    cancellation_event,
    prefix_head.sequence() + 2L,
    prefix_head.revision() + 2L,
    reordered_terminal.event_ref().digest(),
  )
  let reordered_store = phase1b_clone_replay_to_memory(safe_prefix)
  ignore(
    reordered_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        safe.registration.workflow(),
        prepared.commit_request().expected_revision(),
        prepared.commit_request().command_idempotency_key(),
        [reordered_terminal, reordered_cancellation],
        [],
      ),
    ),
  )
  try
    ignore(
      fold_governed_closed_loop_v2(
        safe.empty_effects,
        reordered_store.replay(safe.registration.workflow()),
        safe.governance.store.replay(safe.receipt.governance_stream_ref),
      ),
    )
  catch {
    CancellationPrecedenceViolation(field="late_event_after_work_terminal") =>
      ()
    error => fail("unexpected persisted reorder error: \{to_repr(error)}")
  } noraise {
    _ => fail("persisted safe composite reorder survived replay")
  }
  let malformed_bytes = phase1b_append_byte(
    terminal_event.payload().payload(),
    b'X',
  )
  let malformed_terminal = phase1b3_de_readdress_event(
    phase1b3_de_replace_terminal_payload(
      terminal_event,
      phase1b_readdress(terminal_event.payload().subject(), malformed_bytes),
      malformed_bytes,
    ),
    prefix_head.sequence() + 1L,
    prefix_head.revision() + 1L,
    prefix_head.last_event_digest().unwrap(),
  )
  let suffix = prepare_phase1b_work_event_v22(
    safe.registration.workflow(),
    prefix_head.sequence() + 2L,
    prefix_head.revision() + 2L,
    malformed_terminal.event_ref().digest(),
    "phase1b3-de-malformed-terminal-suffix",
    "effect.outcome.unknown.v1",
    safe.registration.record_ref(),
    b"malformed-terminal-suffix",
    safe.registration.schedule().admission().governance().governed_subject(),
    [],
    safe.registration.record_ref(),
    "phase1b3-de-malformed-terminal-suffix-key",
  )
  let malformed_suffix_store = phase1b_clone_replay_to_memory(safe_prefix)
  ignore(
    malformed_suffix_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        safe.registration.workflow(),
        prepared.commit_request().expected_revision(),
        "phase1b3-de-malformed-terminal-suffix-command",
        [malformed_terminal, suffix],
        [],
      ),
    ),
  )
  try
    ignore(
      fold_governed_closed_loop_v2(
        safe.empty_effects,
        malformed_suffix_store.replay(safe.registration.workflow()),
        safe.governance.store.replay(safe.receipt.governance_stream_ref),
      ),
    )
  catch {
    CancellationPrecedenceViolation(field="late_event_after_work_terminal") =>
      ()
    error =>
      fail("unexpected malformed-terminal suffix error: \{to_repr(error)}")
  } noraise {
    _ => fail("malformed terminal marker allowed a suffix")
  }
}
