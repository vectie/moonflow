///|
fn complete_native_fixture() -> (
  ReviewedChain,
  @governance.ReviewReceipt,
  Array[@storage.WorkflowEvent],
  Array[@storage.OutboxIntent],
) raise {
  let chain = reviewed_chain(Approved)
  let (receipt, receipt_event, _) = bind_reviewed_chain(chain)
  let events = [ for event in chain.events => event ]
  events.push(receipt_event)
  let authority_work = fixture_envelope(
    "native-authority-request-work",
    "opaque-requested-work",
    chain.workflow,
    b"native-authority-request-work",
    evidence=chain.evidence,
  )
  let review_work = fixture_envelope(
    "native-review-request-work",
    "opaque-requested-work",
    chain.workflow,
    b"native-review-request-work",
    evidence=chain.evidence,
  )
  let intents = [
    try! @governance.prepare_request_intent(
      events[1],
      "native-authority-request-intent",
      "native-authority-request-intent-key",
      authority_work,
      chain.evidence,
    ),
    try! @governance.prepare_request_intent(
      events[3],
      "native-review-request-intent",
      "native-review-request-intent-key",
      review_work,
      chain.evidence,
    ),
  ]
  (chain, receipt, events, intents)
}

///|
test "FLOW-5A filesystem and memory restart with canonical equality" {
  let (chain, receipt, events, intents) = complete_native_fixture()
  let empty = @governance.GovernanceProjection::new(
    chain.policy,
    chain.workflow,
  )
  let request = try! @governance.prepare_governance_commit(
    empty, "native-complete-command-v1", events, intents,
  )
  let memory = @storage.MemoryStore::new()
  let filesystem = try! @storage.FileSystemStore::open(
    "/private/tmp", "moonflow-flow5a-governance-v1/canonical-equality",
  )
  let memory_result = memory.commit(request)
  let filesystem_result = filesystem.commit(request)
  assert_true(memory_result == filesystem_result)
  let restarted = try! @storage.FileSystemStore::open(
    "/private/tmp", "moonflow-flow5a-governance-v1/canonical-equality",
  )
  let memory_replay = memory.replay(chain.workflow)
  let filesystem_replay = restarted.replay(chain.workflow)
  assert_true(
    memory_replay.replay_digest() == filesystem_replay.replay_digest(),
  )
  assert_eq(filesystem_replay.events().length(), 6)
  assert_eq(filesystem_replay.intents().length(), 2)
  let memory_projection = try! @governance.fold_replay(
    chain.policy,
    memory_replay,
  )
  let filesystem_projection = try! @governance.fold_replay(
    chain.policy,
    filesystem_replay,
  )
  assert_true(
    memory_projection.canonical_bytes() ==
    filesystem_projection.canonical_bytes(),
  )
  assert_true(
    memory_projection.state_digest() == filesystem_projection.state_digest(),
  )
  guard filesystem_projection.receipt() is Some(restarted_receipt) else {
    fail("missing filesystem receipt")
  }
  assert_true(restarted_receipt.canonical_bytes() == receipt.canonical_bytes())
}

///|
test "FLOW-5A filesystem restart after every transition is authoritative" {
  let (chain, receipt, events, _) = complete_native_fixture()
  let existing = try! @storage.FileSystemStore::open(
    "/private/tmp", "moonflow-flow5a-governance-v1/restart-each",
  )
  let mut projection = try! @governance.fold_replay(
    chain.policy,
    existing.replay(chain.workflow),
  )
  for index in projection.revision().to_int()..<events.length() {
    let event = events[index]
    let filesystem = try! @storage.FileSystemStore::open(
      "/private/tmp", "moonflow-flow5a-governance-v1/restart-each",
    )
    let request = try! @governance.prepare_governance_commit(
      projection,
      "native-transition-command-\{index}",
      [event],
      [],
    )
    ignore(filesystem.commit(request))
    let restarted = try! @storage.FileSystemStore::open(
      "/private/tmp", "moonflow-flow5a-governance-v1/restart-each",
    )
    projection = try! @governance.fold_replay(
      chain.policy,
      restarted.replay(chain.workflow),
    )
    assert_eq(projection.revision(), Int64::from_int(index + 1))
  }
  guard projection.receipt() is Some(restarted_receipt) else {
    fail("missing restart-each receipt")
  }
  assert_true(restarted_receipt.binding_digest() == receipt.binding_digest())
}
