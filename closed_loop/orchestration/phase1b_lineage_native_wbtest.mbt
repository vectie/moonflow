///|
#borrow(status)
extern "c" fn phase1b_lineage_native_temporary_root(status : Ref[Int]) -> Bytes = "moonflow_storage_native_temporary_root"

///|
extern "c" fn phase1b_lineage_native_unique_suffix() -> Bytes = "moonflow_storage_native_unique_suffix"

///|
fn phase1b_lineage_native_root() -> String {
  let status = Ref(0)
  let bytes = phase1b_lineage_native_temporary_root(status)
  if status.val != 0 {
    abort("temporary root unavailable")
  }
  try! @utf8.decode(bytes)
}

///|
fn phase1b_lineage_native_relative() -> String {
  try! @utf8.decode(phase1b_lineage_native_unique_suffix())
}

///|
fn phase1b_lineage_copy_replay(
  replay : @storage.ReplayResult,
  destination : @storage.FileSystemStore,
) -> Unit raise {
  let mut event_offset = 0
  let mut intent_offset = 0
  for boundary in replay.committed_batches() {
    let batch_events = [
      for
        index in event_offset..<(event_offset + boundary.event_refs().length()) => {
        replay.events()[index]
      }
    ]
    let batch_intents = [
      for
        index in intent_offset..<(intent_offset +
        boundary.intent_refs().length()) => replay.intents()[index]
    ]
    let committed = destination.commit(
      @storage.CommitRequest::new(
        replay.record_version().text(),
        replay.schema_version().text(),
        replay.workflow(),
        boundary.expected_revision(),
        boundary.command_idempotency_key(),
        batch_events,
        batch_intents,
      ),
    )
    assert_true(committed.batch_digest() == boundary.batch_digest())
    event_offset += boundary.event_refs().length()
    intent_offset += boundary.intent_refs().length()
  }
  assert_eq(event_offset, replay.events().length())
  assert_eq(intent_offset, replay.intents().length())
  assert_true(
    destination.replay(replay.workflow()).replay_digest() ==
    replay.replay_digest(),
  )
}

///|
test "FLOW-7 Phase1B filesystem restart preserves retry lineage before and after matching intent" {
  let root = phase1b_lineage_native_root()
  let relative = phase1b_lineage_native_relative()
  let suffix = "phase1b-native-lineage"
  let ready = flow7_retry_ready_fixture(suffix, false)
  let prepared = flow7_prepare_ready_retry(ready, suffix)
  ignore(ready.fixture.store.commit(prepared.request()))
  let retry_gap_replay = ready.fixture.store.replay(ready.fixture.workflow)
  let retry_gap_oracle = phase1b_lineage_proposal_from_replay(
    ready,
    retry_gap_replay,
    suffix + "-gap",
  )
  let writer = @storage.FileSystemStore::open(root, relative)
  phase1b_lineage_copy_replay(retry_gap_replay, writer)
  let retry_gap_restart = @storage.FileSystemStore::open(root, relative)
  let retry_gap_restarted_replay = retry_gap_restart.replay(
    ready.fixture.workflow,
  )
  let retry_gap_recovered = phase1b_lineage_proposal_from_replay(
    ready,
    retry_gap_restarted_replay,
    suffix + "-gap",
  )
  assert_true(retry_gap_recovered.record_ref() == retry_gap_oracle.record_ref())
  assert_true(retry_gap_recovered.digest() == retry_gap_oracle.digest())
  assert_true(
    retry_gap_recovered.canonical_bytes() == retry_gap_oracle.canonical_bytes(),
  )
  assert_true(
    retry_gap_recovered.source_attempt_ref() ==
    Some(prepared.attempt().attempt_ref()),
  )
  assert_true(
    retry_gap_recovered.source_attempt_ref().unwrap().digest() ==
    prepared.attempt().attempt_ref().digest(),
  )
  assert_true(retry_gap_recovered.source_intent_ref() is None)
  retry_gap_recovered.validate_current(
    phase1b_lineage_current_from_replay(ready, retry_gap_restarted_replay),
  )
  let committed_intent = phase1b_prepare_matching_retry_intent(
    ready, prepared, suffix,
  )
  let retry_intent = committed_intent.effect_intent()
  ignore(ready.fixture.store.commit(committed_intent.commit_request()))
  let after_intent_oracle = phase1b_lineage_proposal(
    ready,
    suffix + "-after-intent",
  )
  ignore(retry_gap_restart.commit(committed_intent.commit_request()))
  let after_intent_restart = @storage.FileSystemStore::open(root, relative)
  let after_intent_replay = after_intent_restart.replay(ready.fixture.workflow)
  let after_intent_recovered = phase1b_lineage_proposal_from_replay(
    ready,
    after_intent_replay,
    suffix + "-after-intent",
  )
  assert_true(
    after_intent_recovered.record_ref() == after_intent_oracle.record_ref(),
  )
  assert_true(after_intent_recovered.digest() == after_intent_oracle.digest())
  assert_true(
    after_intent_recovered.canonical_bytes() ==
    after_intent_oracle.canonical_bytes(),
  )
  assert_true(
    after_intent_recovered.source_attempt_ref() ==
    Some(prepared.attempt().attempt_ref()),
  )
  assert_true(
    after_intent_recovered.source_attempt_ref().unwrap().digest() ==
    prepared.attempt().attempt_ref().digest(),
  )
  assert_true(
    after_intent_recovered.source_intent_ref() ==
    Some(retry_intent.intent_ref()),
  )
  assert_true(
    after_intent_recovered.source_intent_ref().unwrap().digest() ==
    retry_intent.intent_ref().digest(),
  )
  let after_current = phase1b_lineage_current_from_replay(
    ready, after_intent_replay,
  )
  after_intent_recovered.validate_current(after_current)
  try retry_gap_recovered.validate_current(after_current) catch {
    OrchestrationError::ReplayBindingViolation(
      field="cancellation_source_lineage"
    ) => ()
    _ => fail("unexpected restarted retry-gap lineage rejection")
  } noraise {
    _ => fail("accepted retry-gap lineage after matching intent was committed")
  }
}
