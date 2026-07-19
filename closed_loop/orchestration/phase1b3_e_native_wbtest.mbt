///|
fn phase1b3_e_require_filesystem_parity(label : String) -> Unit raise {
  let terminal = phase1b3_de_terminal_fixture(label)
  let memory_work = terminal.work_store.replay(terminal.workflow)
  let memory_governance = terminal.governance_replay
  let root = phase1b_native_fixture_root()
  let work_relative = phase1b_native_fixture_relative()
  let governance_relative = phase1b_native_fixture_relative()
  let work_writer = @storage.FileSystemStore::open(root, work_relative)
  let governance_writer = @storage.FileSystemStore::open(
    root, governance_relative,
  )
  phase1b_copy_replay_to_filesystem(memory_work, work_writer)
  phase1b_copy_replay_to_filesystem(memory_governance, governance_writer)
  let work_restart = @storage.FileSystemStore::open(root, work_relative)
  let governance_restart = @storage.FileSystemStore::open(
    root, governance_relative,
  )
  let work_replay = work_restart.replay(terminal.workflow)
  let governance_replay = governance_restart.replay(
    memory_governance.workflow(),
  )
  assert_true(work_replay.replay_digest() == memory_work.replay_digest())
  assert_true(
    governance_replay.replay_digest() == memory_governance.replay_digest(),
  )
  let recovered = fold_governed_closed_loop_v2(
    terminal.empty_effects,
    work_replay,
    governance_replay,
  )
  guard recovered.committed_work_terminal_receipt() is Some(receipt) else {
    fail("filesystem restart lost terminal: " + label)
  }
  receipt.validate_current(recovered)
  assert_true(receipt.outcome() == terminal.outcome)
  assert_true(receipt.record_ref() == terminal.terminal_receipt.record_ref())
  assert_true(receipt.digest() == terminal.terminal_receipt.digest())
  assert_true(
    receipt.canonical_bytes() == terminal.terminal_receipt.canonical_bytes(),
  )
  assert_true(
    recovered.work.effects.state_digest() ==
    terminal.terminal_current.work.effects.state_digest(),
  )
  assert_true(
    recovered.work.orchestration.state_digest() ==
    terminal.terminal_current.work.orchestration.state_digest(),
  )
  let memory_boundaries = memory_work
    .committed_batches()
    .filter(boundary => {
      boundary.command_idempotency_key() ==
      terminal.terminal_request.command_idempotency_key()
    })
  let recovered_boundaries = work_replay
    .committed_batches()
    .filter(boundary => {
      boundary.command_idempotency_key() ==
      terminal.terminal_request.command_idempotency_key()
    })
  assert_eq(memory_boundaries.length(), 1)
  assert_eq(recovered_boundaries.length(), 1)
  let memory_boundary = memory_boundaries[0]
  let recovered_boundary = recovered_boundaries[0]
  assert_eq(
    recovered_boundary.expected_revision(),
    memory_boundary.expected_revision(),
  )
  assert_true(
    recovered_boundary.batch_digest() == memory_boundary.batch_digest(),
  )
  assert_true(recovered_boundary.event_refs() == memory_boundary.event_refs())
  assert_true(recovered_boundary.intent_refs().is_empty())
  let terminal_event_ref = terminal.terminal_request
    .events()
    .last()
    .unwrap()
    .event_ref()
  guard memory_work
    .events()
    .search_by(event => event.event_ref() == terminal_event_ref)
    is Some(memory_index) else {
    fail("memory terminal event missing: " + label)
  }
  guard work_replay
    .events()
    .search_by(event => event.event_ref() == terminal_event_ref)
    is Some(recovered_index) else {
    fail("filesystem terminal event missing: " + label)
  }
  assert_true(
    work_replay.events()[recovered_index].canonical_bytes() ==
    memory_work.events()[memory_index].canonical_bytes(),
  )
  let first = work_restart.commit(terminal.terminal_request)
  let duplicate = work_restart.commit(terminal.terminal_request)
  assert_eq(first.workflow_revision(), duplicate.workflow_revision())
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
  try work_restart.commit(changed_same_key) catch {
    @storage.IdempotencyConflict(key~) =>
      assert_eq(key, terminal.terminal_request.command_idempotency_key())
    error => fail("unexpected filesystem changed-body error: \{to_repr(error)}")
  } noraise {
    _ => fail("filesystem accepted changed body for same key: " + label)
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
  try work_restart.commit(stale) catch {
    @storage.OptimisticRevisionConflict(..) => ()
    error => fail("unexpected filesystem stale-head error: \{to_repr(error)}")
  } noraise {
    _ => fail("filesystem accepted stale terminal head: " + label)
  }
  assert_true(
    work_restart.replay(terminal.workflow).replay_digest() ==
    work_replay.replay_digest(),
  )
}

///|
test "FLOW-7 Phase1B.3-E filesystem restarts preserve all new terminal outcomes" {
  for
    label in [
      "succeeded", "cancelled-not-applied", "failed-nonretryable", "failed-exhausted",
      "failed-cancellation-stopped",
    ] {
    phase1b3_e_require_filesystem_parity(label)
  }
}

///|
fn phase1b3_e_batch_end_revision(
  replay : @storage.ReplayResult,
  command_key : String,
) -> Int64 raise {
  let matching = replay
    .committed_batches()
    .filter(boundary => boundary.command_idempotency_key() == command_key)
  assert_eq(matching.length(), 1)
  matching[0].expected_revision() +
  Int64::from_int(matching[0].event_refs().length())
}

///|
fn phase1b3_e_batch_event(
  replay : @storage.ReplayResult,
  command_key : String,
) -> @storage.WorkflowEvent raise {
  let matching = replay
    .committed_batches()
    .filter(boundary => boundary.command_idempotency_key() == command_key)
  assert_eq(matching.length(), 1)
  assert_eq(matching[0].event_refs().length(), 1)
  let event_ref = matching[0].event_refs()[0]
  guard replay.events().search_by(event => event.event_ref() == event_ref)
    is Some(index) else {
    fail("boundary event missing: " + command_key)
  }
  replay.events()[index]
}

///|
fn phase1b3_e_require_boundary_restart(
  label : String,
  replay : @storage.ReplayResult,
  revision : Int64,
  empty_effects : @effects.EffectsProjection,
  governance_replay : @storage.ReplayResult,
  intent_ref : @contracts.RecordRef,
  expect_source : Bool,
  expect_retry_receipt : Bool,
  expect_terminal : Bool,
  expected_source_event : @storage.WorkflowEvent?,
  authority_scope : String?,
  authority_target : @contracts.RecordRef?,
  expect_authority : Bool,
) -> Unit raise {
  let prefix = replay.verified_prefix(revision)
  let original = fold_governed_closed_loop_v2(
    empty_effects, prefix, governance_replay,
  )
  let memory_store = phase1b_clone_replay_to_memory(prefix)
  let memory_replay = memory_store.replay(prefix.workflow())
  let memory = fold_governed_closed_loop_v2(
    empty_effects, memory_replay, governance_replay,
  )
  assert_true(memory_replay.replay_digest() == prefix.replay_digest())
  assert_true(
    memory.work.effects.state_digest() == original.work.effects.state_digest(),
  )
  assert_true(
    memory.work.orchestration.state_digest() ==
    original.work.orchestration.state_digest(),
  )
  let root = phase1b_native_fixture_root()
  let work_relative = phase1b_native_fixture_relative()
  let governance_relative = phase1b_native_fixture_relative()
  let work_writer = @storage.FileSystemStore::open(root, work_relative)
  let governance_writer = @storage.FileSystemStore::open(
    root, governance_relative,
  )
  phase1b_copy_replay_to_filesystem(prefix, work_writer)
  phase1b_copy_replay_to_filesystem(governance_replay, governance_writer)
  let work_restart = @storage.FileSystemStore::open(root, work_relative)
  let governance_restart = @storage.FileSystemStore::open(
    root, governance_relative,
  )
  let filesystem_replay = work_restart.replay(prefix.workflow())
  let filesystem = fold_governed_closed_loop_v2(
    empty_effects,
    filesystem_replay,
    governance_restart.replay(governance_replay.workflow()),
  )
  assert_true(filesystem_replay.replay_digest() == prefix.replay_digest())
  assert_true(
    filesystem.work.effects.state_digest() ==
    original.work.effects.state_digest(),
  )
  assert_true(
    filesystem.work.orchestration.state_digest() ==
    original.work.orchestration.state_digest(),
  )
  let original_source = original.work.effects.committed_effect_terminal_source_v2(
    intent_ref,
  )
  let memory_source = memory.work.effects.committed_effect_terminal_source_v2(
    intent_ref,
  )
  let filesystem_source = filesystem.work.effects.committed_effect_terminal_source_v2(
    intent_ref,
  )
  assert_true((original_source is Some(_)) == expect_source)
  assert_true((memory_source is Some(_)) == expect_source)
  assert_true((filesystem_source is Some(_)) == expect_source)
  if expect_source {
    let original_value = original_source.unwrap()
    let memory_value = memory_source.unwrap()
    let filesystem_value = filesystem_source.unwrap()
    original_value.validate_current(original.work.effects)
    memory_value.validate_current(memory.work.effects)
    filesystem_value.validate_current(filesystem.work.effects)
    original_value.validate_current(memory.work.effects)
    original_value.validate_current(filesystem.work.effects)
    assert_true(original_value.receipt_ref() == memory_value.receipt_ref())
    assert_true(original_value.receipt_ref() == filesystem_value.receipt_ref())
    assert_true(original_value.digest() == memory_value.digest())
    assert_true(original_value.digest() == filesystem_value.digest())
    assert_true(
      original_value.canonical_bytes() == memory_value.canonical_bytes(),
    )
    assert_true(
      original_value.canonical_bytes() == filesystem_value.canonical_bytes(),
    )
    assert_true(
      original_value.source_record_ref() == memory_value.source_record_ref(),
    )
    assert_true(
      original_value.source_record_ref() == filesystem_value.source_record_ref(),
    )
    assert_true(
      original_value.source_record_bytes() == memory_value.source_record_bytes(),
    )
    assert_true(
      original_value.source_record_bytes() ==
      filesystem_value.source_record_bytes(),
    )
    assert_true(
      original_value.source_event_ref() == memory_value.source_event_ref(),
    )
    assert_true(
      original_value.source_event_ref() == filesystem_value.source_event_ref(),
    )
    assert_true(
      original_value.source_event_bytes() == memory_value.source_event_bytes(),
    )
    assert_true(
      original_value.source_event_bytes() ==
      filesystem_value.source_event_bytes(),
    )
    guard expected_source_event is Some(source_event) else {
      fail("expected source event missing: " + label)
    }
    assert_true(
      original_value.source_record_ref().id() == source_event.idempotency_key(),
    )
    assert_true(
      original_value.source_record_bytes() == source_event.payload().payload(),
    )
    assert_true(original_value.source_event_ref() == source_event.event_ref())
    assert_true(
      original_value.source_event_bytes() == source_event.canonical_bytes(),
    )
    assert_true(
      original_value.source_record_ref().digest() ==
      @contracts.sha256_digest(original_value.source_record_bytes()),
    )
  }
  let original_retry = original.work.effects.committed_retry_eligibility_receipt(
    intent_ref,
  )
  let memory_retry = memory.work.effects.committed_retry_eligibility_receipt(
    intent_ref,
  )
  let filesystem_retry = filesystem.work.effects.committed_retry_eligibility_receipt(
    intent_ref,
  )
  assert_true((original_retry is Some(_)) == expect_retry_receipt)
  assert_true((memory_retry is Some(_)) == expect_retry_receipt)
  assert_true((filesystem_retry is Some(_)) == expect_retry_receipt)
  if expect_retry_receipt {
    let original_value = original_retry.unwrap()
    let memory_value = memory_retry.unwrap()
    let filesystem_value = filesystem_retry.unwrap()
    original_value.validate_current(original.work.effects)
    memory_value.validate_current(memory.work.effects)
    filesystem_value.validate_current(filesystem.work.effects)
    original_value.validate_current(memory.work.effects)
    original_value.validate_current(filesystem.work.effects)
    assert_true(original_value.receipt_ref() == memory_value.receipt_ref())
    assert_true(original_value.receipt_ref() == filesystem_value.receipt_ref())
    assert_true(original_value.digest() == memory_value.digest())
    assert_true(original_value.digest() == filesystem_value.digest())
    assert_true(
      original_value.canonical_bytes() == memory_value.canonical_bytes(),
    )
    assert_true(
      original_value.canonical_bytes() == filesystem_value.canonical_bytes(),
    )
    assert_true(
      original_value.source_record_ref() == memory_value.source_record_ref(),
    )
    assert_true(
      original_value.source_record_ref() == filesystem_value.source_record_ref(),
    )
    assert_true(
      original_value.source_event_ref() == memory_value.source_event_ref(),
    )
    assert_true(
      original_value.source_event_ref() == filesystem_value.source_event_ref(),
    )
    assert_true(
      original_value.source_event_digest() == memory_value.source_event_digest(),
    )
    assert_true(
      original_value.source_event_digest() ==
      filesystem_value.source_event_digest(),
    )
    guard expected_source_event is Some(source_event) else {
      fail("retry source event missing: " + label)
    }
    assert_true(
      original_value.source_record_ref().id() == source_event.idempotency_key(),
    )
    assert_true(
      original_value.source_record_ref().digest() ==
      @contracts.sha256_digest(source_event.payload().payload()),
    )
    assert_true(original_value.source_event_ref() == source_event.event_ref())
    assert_true(
      original_value.source_event_digest() == source_event.event_ref().digest(),
    )
  }
  match (authority_scope, authority_target) {
    (Some(scope), Some(target)) =>
      if expect_authority {
        let original_authority = original.inflight_resolution_authority(
          intent_ref, scope, target,
        )
        let memory_authority = memory.inflight_resolution_authority(
          intent_ref, scope, target,
        )
        let filesystem_authority = filesystem.inflight_resolution_authority(
          intent_ref, scope, target,
        )
        original_authority.validate_current(original)
        memory_authority.validate_current(memory)
        filesystem_authority.validate_current(filesystem)
        original_authority.validate_current(memory)
        original_authority.validate_current(filesystem)
      } else {
        try
          original.inflight_resolution_authority(intent_ref, scope, target)
        catch {
          CancellationPrecedenceViolation(field="inflight_resolution_scope") =>
            ()
          error =>
            fail(
              "unexpected unavailable authority error: \{label}:\{to_repr(error)}",
            )
        } noraise {
          _ => fail("unexpected reconciliation authority: " + label)
        }
        try
          memory.inflight_resolution_authority(intent_ref, scope, target)
        catch {
          CancellationPrecedenceViolation(field="inflight_resolution_scope") =>
            ()
          error =>
            fail(
              "unexpected memory authority error: \{label}:\{to_repr(error)}",
            )
        } noraise {
          _ => fail("unexpected memory reconciliation authority: " + label)
        }
        try
          filesystem.inflight_resolution_authority(intent_ref, scope, target)
        catch {
          CancellationPrecedenceViolation(field="inflight_resolution_scope") =>
            ()
          error =>
            fail(
              "unexpected filesystem authority error: \{label}:\{to_repr(error)}",
            )
        } noraise {
          _ => fail("unexpected filesystem reconciliation authority: " + label)
        }
      }
    (None, None) => assert_false(expect_authority)
    _ => fail("partial reconciliation authority expectation: " + label)
  }
  assert_true(
    (original.committed_work_terminal_receipt() is Some(_)) == expect_terminal,
  )
  assert_true(
    (memory.committed_work_terminal_receipt() is Some(_)) == expect_terminal,
  )
  assert_true(
    (filesystem.committed_work_terminal_receipt() is Some(_)) == expect_terminal,
  )
  if expect_terminal {
    let original_receipt = original.committed_work_terminal_receipt().unwrap()
    let memory_receipt = memory.committed_work_terminal_receipt().unwrap()
    let filesystem_receipt = filesystem
      .committed_work_terminal_receipt()
      .unwrap()
    assert_true(
      original_receipt.canonical_bytes() == memory_receipt.canonical_bytes(),
    )
    assert_true(
      original_receipt.canonical_bytes() == filesystem_receipt.canonical_bytes(),
    )
  }
  ignore(label)
}

///|
test "FLOW-7 Phase1B.3-E restart boundaries preserve reconciliation authority" {
  let suffix = "phase1b3-e-boundaries"
  let policy = phase1b3_c_policy(suffix, 3L, 2L, [
    "terminal_failed", "reconciled_not_applied",
  ])
  let resolved = phase1b3_c_reconciled_fixture(suffix, policy, true)
  let cancelled = phase1b3_c_cancel_reconciled_not_applied(resolved, suffix)
  let prepared = prepare_cancelled_after_reconciled_not_applied_work_terminal_v2(
    cancelled.current,
    cancelled.source,
  )
  ignore(cancelled.fixture.work_store.commit(prepared.commit_request()))
  let replay = cancelled.fixture.work_store.replay(
    cancelled.fixture.registration.workflow(),
  )
  let unknown_revision = phase1b3_e_batch_end_revision(
    replay,
    "phase1b3-c-unknown-receipt-command-" + suffix,
  )
  let request_revision = phase1b3_e_batch_end_revision(
    replay,
    "phase1b3-c-reconciliation-request-command-" + suffix,
  )
  let resolution_revision = phase1b3_e_batch_end_revision(
    replay,
    "phase1b3-c-reconciliation-resolution-command-" + suffix,
  )
  let cancellation_revision = phase1b3_e_batch_end_revision(
    replay,
    "phase1b3-c-cancel-proposal-command-key-" + suffix,
  )
  let terminal_revision = replay.head().revision()
  let intent_ref = cancelled.fixture.intent.intent_ref()
  let request_event = phase1b3_e_batch_event(
    replay,
    "phase1b3-c-reconciliation-request-command-" + suffix,
  )
  let resolution_event = phase1b3_e_batch_event(
    replay,
    "phase1b3-c-reconciliation-resolution-command-" + suffix,
  )
  phase1b3_e_require_boundary_restart(
    "unknown",
    replay,
    unknown_revision,
    cancelled.fixture.empty_effects,
    cancelled.governance_replay,
    intent_ref,
    false,
    false,
    false,
    None,
    Some("reconciliation.request"),
    Some(request_event.payload().subject()),
    true,
  )
  phase1b3_e_require_boundary_restart(
    "request",
    replay,
    request_revision,
    cancelled.fixture.empty_effects,
    cancelled.governance_replay,
    intent_ref,
    false,
    false,
    false,
    None,
    Some("reconciliation.resolve"),
    Some(resolution_event.payload().subject()),
    true,
  )
  phase1b3_e_require_boundary_restart(
    "resolution",
    replay,
    resolution_revision,
    cancelled.fixture.empty_effects,
    cancelled.governance_replay,
    intent_ref,
    true,
    true,
    false,
    Some(resolution_event),
    Some("reconciliation.resolve"),
    Some(resolution_event.payload().subject()),
    false,
  )
  phase1b3_e_require_boundary_restart(
    "cancellation",
    replay,
    cancellation_revision,
    cancelled.fixture.empty_effects,
    cancelled.governance_replay,
    intent_ref,
    true,
    true,
    false,
    Some(resolution_event),
    None,
    None,
    false,
  )
  phase1b3_e_require_boundary_restart(
    "terminal",
    replay,
    terminal_revision,
    cancelled.fixture.empty_effects,
    cancelled.governance_replay,
    intent_ref,
    true,
    true,
    true,
    Some(resolution_event),
    Some("reconciliation.resolve"),
    Some(resolution_event.payload().subject()),
    false,
  )
}
