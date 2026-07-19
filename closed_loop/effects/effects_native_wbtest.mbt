///|
#borrow(status)
extern "c" fn effects_native_temporary_root(status : Ref[Int]) -> Bytes = "moonflow_storage_native_temporary_root"

///|
extern "c" fn effects_native_unique_suffix() -> Bytes = "moonflow_storage_native_unique_suffix"

///|
fn effects_native_fixture_root() -> String {
  let status = Ref(0)
  let bytes = effects_native_temporary_root(status)
  if status.val != 0 {
    abort("temporary root unavailable")
  }
  try! @utf8.decode(bytes)
}

///|
fn effects_native_fixture_relative() -> String {
  try! @utf8.decode(effects_native_unique_suffix())
}

///|
test "FLOW-6A native filesystem restart matches memory eligibility and registry" {
  let fixture = durable_intent("native-parity")
  let root = effects_native_fixture_root()
  let relative = effects_native_fixture_relative()
  let filesystem = try! @storage.FileSystemStore::open(root, relative)
  assert_eq(filesystem.head(fixture.accepted.workflow).event_count(), 0L)
  for request in fixture.requests {
    ignore(filesystem.commit(request))
  }
  let restarted = try! @storage.FileSystemStore::open(root, relative)
  let replay = restarted.replay(fixture.accepted.workflow)
  let projection = fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    replay,
    ReplayCatalog::new([fixture.attempt], [fixture.intent], [], [], [], []),
  )
  assert_eq(projection.dispatch_eligible_intents().length(), 1)
  assert_true(
    projection.canonical_bytes() == fixture.projection.canonical_bytes(),
  )
  assert_true(
    projection.registry().canonical_bytes() ==
    fixture.projection.registry().canonical_bytes(),
  )
  assert_true(
    replay.replay_digest() ==
    fixture.store.replay(fixture.accepted.workflow).replay_digest(),
  )
}

///|
struct EffectsNativeRetryOracle {
  workflow : @contracts.RecordRef
  policy_ref : @contracts.RecordRef
  source_intent_ref : @contracts.RecordRef
  receipt_canonical : Bytes
  receipt_ref : @contracts.RecordRef
  receipt_digest : @contracts.ContentDigest
}

///|
fn effects_write_fresh_retry_history(
  root : String,
  relative : String,
) -> EffectsNativeRetryOracle raise {
  let fixture = durable_intent("native-retry-receipt-v2")
  let observation = make_observation(
    fixture, "native-retry-receipt-v2-observation",
  )
  let observation_request = prepare_dispatch_observation_commit(
    fixture.projection,
    "native-retry-receipt-v2-observation-event",
    "native-retry-receipt-v2-observation-command",
    observation,
  )
  ignore(fixture.store.commit(observation_request))
  let pending = fold_authoritative_replay(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
    ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [observation],
      [],
      [],
      [],
    ),
  )
  let failed = make_receipt(fixture, "native-retry-receipt-v2-failed", Failed)
  let receipt_request = prepare_effect_receipt_commit(
    pending, "native-retry-receipt-v2-failed-event", "native-retry-receipt-v2-failed-command",
    failed,
  )
  ignore(fixture.store.commit(receipt_request))
  let expected_projection = fold_committed_effects_bytes(
    EffectsProjection::new(
      fixture.accepted.workflow,
      fixture.accepted.policy.policy_ref(),
    ),
    fixture.store.replay(fixture.accepted.workflow),
  )
  guard expected_projection.committed_retry_eligibility_receipt(
      fixture.intent.intent_ref(),
    )
    is Some(expected) else {
    fail("expected writer retry receipt")
  }
  let writer = @storage.FileSystemStore::open(root, relative)
  assert_eq(writer.head(fixture.accepted.workflow).event_count(), 0L)
  for request in fixture.requests {
    ignore(writer.commit(request))
  }
  ignore(writer.commit(observation_request))
  ignore(writer.commit(receipt_request))
  {
    workflow: fixture.accepted.workflow,
    policy_ref: fixture.accepted.policy.policy_ref(),
    source_intent_ref: fixture.intent.intent_ref(),
    receipt_canonical: expected.canonical_bytes(),
    receipt_ref: expected.receipt_ref(),
    receipt_digest: expected.digest(),
  }
}

///|
test "FLOW-6 V2 retry receipt is byte-identical after filesystem restart" {
  let root = effects_native_fixture_root()
  let relative = effects_native_fixture_relative()
  // The helper owns and drops every fixture/catalog/domain object, both
  // in-memory projections, prepared requests, and the filesystem writer.
  let oracle = effects_write_fresh_retry_history(root, relative)
  let restarted = try! @storage.FileSystemStore::open(root, relative)
  let recovered_projection = fold_committed_effects_bytes(
    EffectsProjection::new(oracle.workflow, oracle.policy_ref),
    restarted.replay(oracle.workflow),
  )
  guard recovered_projection.committed_retry_eligibility_receipt(
      oracle.source_intent_ref,
    )
    is Some(recovered) else {
    fail("expected restarted retry receipt")
  }
  assert_true(recovered.canonical_bytes() == oracle.receipt_canonical)
  assert_true(recovered.receipt_ref() == oracle.receipt_ref)
  assert_true(recovered.digest() == oracle.receipt_digest)
  recovered.validate_current(recovered_projection)
}
