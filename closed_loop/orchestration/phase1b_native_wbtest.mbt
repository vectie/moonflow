///|
#borrow(status)
extern "c" fn phase1b_native_temporary_root(status : Ref[Int]) -> Bytes = "moonflow_storage_native_temporary_root"

///|
extern "c" fn phase1b_native_unique_suffix() -> Bytes = "moonflow_storage_native_unique_suffix"

///|
fn phase1b_native_fixture_root() -> String {
  let status = Ref(0)
  let bytes = phase1b_native_temporary_root(status)
  if status.val != 0 {
    abort("temporary root unavailable")
  }
  try! @utf8.decode(bytes)
}

///|
fn phase1b_native_fixture_relative() -> String {
  try! @utf8.decode(phase1b_native_unique_suffix())
}

///|
struct Phase1bNativeRestartOracle {
  workflow : @contracts.RecordRef
  policy_ref : @contracts.RecordRef
  governance_stream : @contracts.RecordRef
  work_replay_digest : @contracts.ContentDigest
  governance_replay_digest : @contracts.ContentDigest
  proposal_ref : @contracts.RecordRef
  proposal_canonical : Bytes
  receipt_ref : @contracts.RecordRef
  receipt_canonical : Bytes
  authorization_ref : @contracts.RecordRef
  authorization_canonical : Bytes
  request_ref : @contracts.RecordRef
  request_canonical : Bytes
}

///|
fn phase1b_copy_single_batch_to_filesystem(
  replay : @storage.ReplayResult,
  destination : @storage.FileSystemStore,
) -> Unit raise {
  assert_eq(replay.committed_batches().length(), 1)
  let boundary = replay.committed_batches()[0]
  ignore(
    destination.commit(
      @storage.CommitRequest::new(
        replay.record_version().text(),
        replay.schema_version().text(),
        replay.workflow(),
        boundary.expected_revision(),
        boundary.command_idempotency_key(),
        [
          for event in replay.events() => event
        ],
        [
          for intent in replay.intents() => intent
        ],
      ),
    ),
  )
  let copied = destination.replay(replay.workflow())
  assert_true(copied.replay_digest() == replay.replay_digest())
  assert_true(
    copied.committed_batches()[0].batch_digest() == boundary.batch_digest(),
  )
}

///|
fn phase1b_copy_replay_to_filesystem(
  replay : @storage.ReplayResult,
  destination : @storage.FileSystemStore,
) -> Unit raise {
  for boundary in replay.committed_batches() {
    let events : Array[@storage.WorkflowEvent] = []
    for event_ref in boundary.event_refs() {
      guard replay.events().search_by(event => event.event_ref() == event_ref)
        is Some(index) else {
        fail("filesystem replay event missing")
      }
      events.push(replay.events()[index])
    }
    let intents : Array[@storage.OutboxIntent] = []
    for intent_ref in boundary.intent_refs() {
      guard replay
        .intents()
        .search_by(intent => intent.intent_ref() == intent_ref)
        is Some(index) else {
        fail("filesystem replay intent missing")
      }
      intents.push(replay.intents()[index])
    }
    ignore(
      destination.commit(
        @storage.CommitRequest::new(
          replay.record_version().text(),
          replay.schema_version().text(),
          replay.workflow(),
          boundary.expected_revision(),
          boundary.command_idempotency_key(),
          events,
          intents,
        ),
      ),
    )
  }
  assert_true(
    destination.replay(replay.workflow()).replay_digest() ==
    replay.replay_digest(),
  )
}

///|
fn phase1b_write_restart_histories(
  root : String,
  work_relative : String,
  governance_relative : String,
) -> Phase1bNativeRestartOracle raise {
  let fixture = phase1b_fixture(suffix="native-restart")
  let work_replay = fixture.work_store.replay(fixture.registration.workflow())
  let governance_replay = fixture.governance.store.replay(
    fixture.receipt.governance_stream_ref,
  )
  let work_writer = @storage.FileSystemStore::open(root, work_relative)
  let governance_writer = @storage.FileSystemStore::open(
    root, governance_relative,
  )
  phase1b_copy_single_batch_to_filesystem(work_replay, work_writer)
  phase1b_copy_single_batch_to_filesystem(governance_replay, governance_writer)
  {
    workflow: fixture.registration.workflow(),
    policy_ref: phase1a_wb_policy().policy_ref(),
    governance_stream: fixture.receipt.governance_stream_ref,
    work_replay_digest: work_replay.replay_digest(),
    governance_replay_digest: governance_replay.replay_digest(),
    proposal_ref: fixture.proposal.record_ref(),
    proposal_canonical: fixture.proposal.canonical_bytes(),
    receipt_ref: fixture.receipt.record_ref(),
    receipt_canonical: fixture.receipt.canonical_bytes(),
    authorization_ref: fixture.authorization.record_ref(),
    authorization_canonical: fixture.authorization.canonical_bytes(),
    request_ref: fixture.request.record_ref(),
    request_canonical: fixture.request.canonical_bytes(),
  }
}

///|
test "FLOW-7 Phase1B filesystem restart reproduces proposal receipt authorization and request" {
  let root = phase1b_native_fixture_root()
  let work_relative = phase1b_native_fixture_relative()
  let governance_relative = phase1b_native_fixture_relative()
  // The writer helper drops the in-memory fixture and both writer instances.
  // Recovery gets only durable histories and immutable canonical oracle values.
  let oracle = phase1b_write_restart_histories(
    root, work_relative, governance_relative,
  )
  let work_restart = @storage.FileSystemStore::open(root, work_relative)
  let governance_restart = @storage.FileSystemStore::open(
    root, governance_relative,
  )
  let work_replay = work_restart.replay(oracle.workflow)
  let governance_replay = governance_restart.replay(oracle.governance_stream)
  assert_true(work_replay.replay_digest() == oracle.work_replay_digest)
  assert_true(
    governance_replay.replay_digest() == oracle.governance_replay_digest,
  )
  let effects = @effects.EffectsProjection::new(
    oracle.workflow,
    oracle.policy_ref,
  )
  let current = fold_governed_closed_loop_v2(
    effects, work_replay, governance_replay,
  )
  let proposal = decode_cancellation_proposal_v22_strict(
    oracle.proposal_ref,
    oracle.proposal_canonical,
  )
  let receipt = current.committed_cancellation_governance_receipt(proposal)
  let authorization = CancellationAuthorizationV2::from_committed_governance(
    oracle.authorization_ref.id(),
    receipt,
    proposal,
    current,
  )
  let request = CancellationRequestV2::new(
    oracle.request_ref.id(),
    proposal,
    authorization,
  )
  assert_true(receipt.record_ref() == oracle.receipt_ref)
  assert_true(receipt.canonical_bytes() == oracle.receipt_canonical)
  assert_true(authorization.record_ref() == oracle.authorization_ref)
  assert_true(authorization.canonical_bytes() == oracle.authorization_canonical)
  assert_true(request.record_ref() == oracle.request_ref)
  assert_true(request.canonical_bytes() == oracle.request_canonical)
  let prepared = prepare_cancellation_v2(current, request)
  let first_commit = work_restart.commit(prepared.commit_request())
  let duplicate_commit = work_restart.commit(prepared.commit_request())
  assert_eq(
    first_commit.workflow_revision(),
    duplicate_commit.workflow_revision(),
  )
  let first_replay = work_restart.replay(oracle.workflow)
  let first_cancelled = fold_governed_closed_loop_v2(
    effects, first_replay, governance_replay,
  )
  guard first_cancelled.committed_work_terminal_receipt()
    is Some(first_terminal) else {
    fail("filesystem cancellation terminal missing before restart")
  }
  let restarted_again = @storage.FileSystemStore::open(root, work_relative)
  let second_replay = restarted_again.replay(oracle.workflow)
  let second_cancelled = fold_governed_closed_loop_v2(
    effects, second_replay, governance_replay,
  )
  guard second_cancelled.committed_work_terminal_receipt()
    is Some(second_terminal) else {
    fail("filesystem cancellation terminal missing after restart")
  }
  assert_true(first_replay.replay_digest() == second_replay.replay_digest())
  assert_true(first_terminal.record_ref() == second_terminal.record_ref())
  assert_true(first_terminal.digest() == second_terminal.digest())
  assert_true(
    first_terminal.canonical_bytes() == second_terminal.canonical_bytes(),
  )
}

///|
test "FLOW-7 Phase1B.2 filesystem pending cancellation restart is byte exact" {
  let fixture = phase1b_pending_fixture("native-pending")
  let root = phase1b_native_fixture_root()
  let work_relative = phase1b_native_fixture_relative()
  let governance_relative = phase1b_native_fixture_relative()
  let workflow = fixture.registration.workflow()
  let governance_stream = fixture.current.root_binding.governance_stream_ref()
  let proposal_ref = fixture.request.proposal.record_ref()
  let proposal_bytes = fixture.request.proposal.canonical_bytes()
  let authorization_id = fixture.request.authorization.record_ref().id()
  let request_id = fixture.request.record_ref().id()
  let intent_ref = fixture.intent.intent_ref()
  let work_before = fixture.work_store.replay(workflow)
  let governance_before = fixture.governance.store.replay(governance_stream)
  let work_writer = @storage.FileSystemStore::open(root, work_relative)
  let governance_writer = @storage.FileSystemStore::open(
    root, governance_relative,
  )
  phase1b_copy_replay_to_filesystem(work_before, work_writer)
  phase1b_copy_replay_to_filesystem(governance_before, governance_writer)
  let work_restart = @storage.FileSystemStore::open(root, work_relative)
  let governance_restart = @storage.FileSystemStore::open(
    root, governance_relative,
  )
  let empty_effects = @effects.EffectsProjection::new(
    workflow,
    phase1a_wb_policy().policy_ref(),
  )
  let recovered = fold_governed_closed_loop_v2(
    empty_effects,
    work_restart.replay(workflow),
    governance_restart.replay(governance_stream),
  )
  let proposal = decode_cancellation_proposal_v22_strict(
    proposal_ref, proposal_bytes,
  )
  let receipt = recovered.committed_cancellation_governance_receipt(proposal)
  let authorization = CancellationAuthorizationV2::from_committed_governance(
    authorization_id, receipt, proposal, recovered,
  )
  let request = CancellationRequestV2::new(request_id, proposal, authorization)
  let prepared = prepare_cancellation_v2(recovered, request)
  assert_true(prepared.terminal_outcome() is None)
  assert_eq(prepared.commit_request().events().length(), 1)
  assert_eq(prepared.commit_request().intents().length(), 0)
  let first = work_restart.commit(prepared.commit_request())
  let duplicate = work_restart.commit(prepared.commit_request())
  assert_eq(first.workflow_revision(), duplicate.workflow_revision())
  ignore(fixture.work_store.commit(prepared.commit_request()))
  let work_restart_again = @storage.FileSystemStore::open(root, work_relative)
  let recovered_pending = fold_governed_closed_loop_v2(
    empty_effects,
    work_restart_again.replay(workflow),
    governance_restart.replay(governance_stream),
  )
  let memory_pending = fold_governed_closed_loop_v2(
    empty_effects,
    fixture.work_store.replay(workflow),
    governance_before,
  )
  assert_true(recovered_pending.committed_work_terminal_receipt() is None)
  assert_true(memory_pending.committed_work_terminal_receipt() is None)
  assert_true(
    work_restart_again.replay(workflow).replay_digest() ==
    fixture.work_store.replay(workflow).replay_digest(),
  )
  assert_true(
    recovered_pending.work.effects.state_digest() ==
    memory_pending.work.effects.state_digest(),
  )
  assert_true(
    recovered_pending.work.orchestration.state_digest() ==
    memory_pending.work.orchestration.state_digest(),
  )
  let target = phase1a_wb_ref(
    "observation", "phase1b-native-pending-target", b"pending-target",
  )
  let inflight = recovered_pending.inflight_resolution_authority(
    intent_ref, "dispatch.observe", target,
  )
  inflight.validate_current(recovered_pending)
}
