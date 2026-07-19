///|
fn guarded_fixture_ref(kind : String, id : String) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(
    kind,
    id,
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode("guarded:" + id)).text(),
  )
}

///|
fn guarded_fixture_schema() -> @contracts.SchemaRef {
  try! @contracts.SchemaRef::new(
    "neutral.storage",
    "1.0.0",
    "guarded.fixture",
    "1.0.0",
    @contracts.sha256_digest(b"guarded-schema").text(),
  )
}

///|
fn guarded_fixture_envelope(
  workflow : @contracts.RecordRef,
  id : String,
) -> @contracts.WireEnvelope {
  try! @contracts.WireEnvelope::new(
    "neutral.storage",
    "1.0.0",
    id,
    "guarded.fixture",
    guarded_fixture_ref("subject", id),
    guarded_fixture_schema(),
    @utf8.encode(id),
    "guarded-test",
    "1.0.0",
    [],
    [],
    run_ref=workflow,
  )
}

///|
fn guarded_fixture_event(
  workflow : @contracts.RecordRef,
  id : String,
  revision : Int64,
  previous : @contracts.ContentDigest?,
) -> @storage.WorkflowEvent {
  match previous {
    None =>
      try! @storage.WorkflowEvent::new(
        "1.0.0",
        "1.0.0",
        workflow,
        id,
        revision,
        revision,
        "guarded-event-key-" + id,
        guarded_fixture_envelope(workflow, id),
        [],
      )
    Some(digest) =>
      try! @storage.WorkflowEvent::new(
        "1.0.0",
        "1.0.0",
        workflow,
        id,
        revision,
        revision,
        "guarded-event-key-" + id,
        guarded_fixture_envelope(workflow, id),
        [],
        previous_event_digest=digest,
      )
  }
}

///|
fn guarded_fixture_request(
  workflow : @contracts.RecordRef,
  command : String,
  expected : Int64,
  event : @storage.WorkflowEvent,
) -> @storage.CommitRequest {
  try! @storage.CommitRequest::new(
    "1.0.0",
    "1.0.0",
    workflow,
    expected,
    command,
    [event],
    [],
  )
}

///|
fn guarded_fixture_guard(
  replay : @storage.ReplayResult,
) -> @storage.WorkflowHeadGuard {
  try! @storage.WorkflowHeadGuard::new(
    replay.workflow(),
    replay.head().revision(),
    replay.head().last_event_digest(),
    replay.replay_digest(),
  )
}

///|
test "FLOW-4A guarded MemoryStore commits atomically and exact retry survives guard advance" {
  let store = @storage.MemoryStore::new()
  let second_handle = store
  let work = guarded_fixture_ref("workflow", "guarded-work-success")
  let governance = guarded_fixture_ref("workflow", "guarded-governance-success")
  let governance_first = guarded_fixture_event(
    governance,
    "guarded-governance-success-1",
    1L,
    None,
  )
  ignore(
    store.commit(
      guarded_fixture_request(
        governance, "guarded-governance-success-command-1", 0L, governance_first,
      ),
    ),
  )
  let guarded = try! @storage.GuardedCommitRequest::new(
    guarded_fixture_request(
      work,
      "guarded-work-success-command",
      0L,
      guarded_fixture_event(work, "guarded-work-success-1", 1L, None),
    ),
    [guarded_fixture_guard(store.replay(governance))],
  )
  guard store.guarded_commit(guarded)
    is @storage.GuardedCommitSucceeded(original) else {
    fail("guarded commit did not succeed")
  }
  let governance_second = guarded_fixture_event(
    governance,
    "guarded-governance-success-2",
    2L,
    Some(governance_first.event_ref().digest()),
  )
  ignore(
    second_handle.commit(
      guarded_fixture_request(
        governance, "guarded-governance-success-command-2", 1L, governance_second,
      ),
    ),
  )
  guard second_handle.guarded_commit(guarded)
    is @storage.GuardedCommitSucceeded(duplicate) else {
    fail("exact guarded retry was rejected after governance advance")
  }
  assert_true(original == duplicate)
  assert_eq(store.replay(work).events().length(), 1)
}

///|
test "FLOW-4A stale MemoryStore guard returns current non-mutating receipt" {
  let store = @storage.MemoryStore::new()
  let work = guarded_fixture_ref("workflow", "guarded-work-stale")
  let governance = guarded_fixture_ref("workflow", "guarded-governance-stale")
  let first = guarded_fixture_event(
    governance,
    "guarded-governance-stale-1",
    1L,
    None,
  )
  ignore(
    store.commit(
      guarded_fixture_request(
        governance, "guarded-governance-stale-command-1", 0L, first,
      ),
    ),
  )
  let expected = guarded_fixture_guard(store.replay(governance))
  let guarded = try! @storage.GuardedCommitRequest::new(
    guarded_fixture_request(
      work,
      "guarded-work-stale-command",
      0L,
      guarded_fixture_event(work, "guarded-work-stale-1", 1L, None),
    ),
    [expected],
  )
  let second = guarded_fixture_event(
    governance,
    "guarded-governance-stale-2",
    2L,
    Some(first.event_ref().digest()),
  )
  ignore(
    store.commit(
      guarded_fixture_request(
        governance, "guarded-governance-stale-command-2", 1L, second,
      ),
    ),
  )
  guard store.guarded_commit(guarded) is @storage.GuardedCommitRejected(receipt) else {
    fail("stale governance was not rejected")
  }
  assert_eq(store.replay(work).events().length(), 0)
  assert_eq(receipt.expected_revision(), 1L)
  assert_eq(receipt.actual_revision(), 2L)
  receipt.validate_current(store.replay(governance))
  let third = guarded_fixture_event(
    governance,
    "guarded-governance-stale-3",
    3L,
    Some(second.event_ref().digest()),
  )
  ignore(
    store.commit(
      guarded_fixture_request(
        governance, "guarded-governance-stale-command-3", 2L, third,
      ),
    ),
  )
  try receipt.validate_current(store.replay(governance)) catch {
    @storage.ValidationFailure(field="guard_conflict_receipt_not_current") => ()
    error => fail("unexpected stale receipt error: \{to_repr(error)}")
  } noraise {
    _ => fail("stale observation remained current after another advance")
  }
}

///|
test "FLOW-4A raw or changed guard set cannot claim guarded idempotency" {
  let raw_store = @storage.MemoryStore::new()
  let work = guarded_fixture_ref("workflow", "guarded-work-raw")
  let governance = guarded_fixture_ref("workflow", "guarded-governance-raw")
  let mutation = guarded_fixture_request(
    work,
    "guarded-work-raw-command",
    0L,
    guarded_fixture_event(work, "guarded-work-raw-1", 1L, None),
  )
  ignore(raw_store.commit(mutation))
  let raw_guarded = try! @storage.GuardedCommitRequest::new(mutation, [
    guarded_fixture_guard(raw_store.replay(governance)),
  ])
  try raw_store.guarded_commit(raw_guarded) catch {
    @storage.IdempotencyConflict(key="guarded-work-raw-command") => ()
    error => fail("unexpected raw/guarded conflict: \{to_repr(error)}")
  } noraise {
    _ => fail("raw commit was reclassified as guarded")
  }

  let guarded_store = @storage.MemoryStore::new()
  let exact = try! @storage.GuardedCommitRequest::new(mutation, [
    guarded_fixture_guard(guarded_store.replay(governance)),
  ])
  guard guarded_store.guarded_commit(exact)
    is @storage.GuardedCommitSucceeded(_) else {
    fail("initial guarded commit failed")
  }
  let alternate_governance = guarded_fixture_ref(
    "workflow", "guarded-governance-alternate",
  )
  let changed = try! @storage.GuardedCommitRequest::new(mutation, [
    guarded_fixture_guard(guarded_store.replay(alternate_governance)),
  ])
  try guarded_store.guarded_commit(changed) catch {
    @storage.IdempotencyConflict(key="guarded-work-raw-command") => ()
    error => fail("unexpected changed guard conflict: \{to_repr(error)}")
  } noraise {
    _ => fail("changed guard set reused guarded command identity")
  }
}

///|
test "FLOW-4A MemoryStore registry binds capability and blocks raw bypass" {
  let store = @storage.MemoryStore::new()
  let work = guarded_fixture_ref("workflow", "registry-memory-work")
  let governance = guarded_fixture_ref("workflow", "registry-memory-governance")
  let governance_first = guarded_fixture_event(
    governance,
    "registry-memory-governance-1",
    1L,
    None,
  )
  ignore(
    store.commit(
      guarded_fixture_request(
        governance, "registry-memory-governance-command-1", 0L, governance_first,
      ),
    ),
  )
  let mutation = guarded_fixture_request(
    work,
    "registry-memory-work-command",
    0L,
    guarded_fixture_event(work, "registry-memory-work-1", 1L, None),
  )
  let guarded = try! @storage.GuardedCommitRequest::new(mutation, [
    guarded_fixture_guard(store.replay(governance)),
  ])
  let activation = store.activate_guarded_workflow(work, [governance])
  try ignore(store.commit(mutation)) catch {
    @storage.GuardedCommitRequired(
      workflow_id="registry-memory-work",
      key="registry-memory-work-command",
      binding_digest~
    ) => assert_eq(binding_digest, activation.registry_digest().text())
    error => fail("unexpected raw registry rejection: \{to_repr(error)}")
  } noraise {
    _ => fail("registered MemoryStore accepted raw mutation")
  }
  let bound = @storage.GuardedMemoryStore::new(store, activation)
  guard bound.guarded_commit(guarded)
    is @storage.GuardedCommitSucceeded(original) else {
    fail("registry-bound MemoryStore did not commit")
  }
  let identical = store.activate_guarded_workflow(work, [governance])
  assert_true(identical.canonical_bytes() == activation.canonical_bytes())
  assert_eq(identical.activation_revision(), 0L)
  let governance_second = guarded_fixture_event(
    governance,
    "registry-memory-governance-2",
    2L,
    Some(governance_first.event_ref().digest()),
  )
  ignore(
    store.commit(
      guarded_fixture_request(
        governance, "registry-memory-governance-command-2", 1L, governance_second,
      ),
    ),
  )
  guard bound.guarded_commit(guarded)
    is @storage.GuardedCommitSucceeded(duplicate) else {
    fail("exact guarded retry failed after guard advance")
  }
  assert_true(original == duplicate)
  let shadow = guarded_fixture_ref("workflow", "registry-memory-shadow")
  let substituted = try! @storage.GuardedCommitRequest::new(mutation, [
    guarded_fixture_guard(store.replay(shadow)),
  ])
  try bound.guarded_commit(substituted) catch {
    @storage.GuardedBindingConflict(field="guard_set", ..) => ()
    error => fail("unexpected shadow-root rejection: \{to_repr(error)}")
  } noraise {
    _ => fail("shadow guard workflow substituted the registry binding")
  }
  try store.activate_guarded_workflow(work, [shadow]) catch {
    @storage.GuardedBindingConflict(field="binding_configuration", ..) => ()
    error => fail("unexpected changed binding rejection: \{to_repr(error)}")
  } noraise {
    _ => fail("active MemoryStore workflow was silently rebound")
  }
}

///|
test "FLOW-4A MemoryStore registry rejects stale authoritative guard" {
  let store = @storage.MemoryStore::new()
  let work = guarded_fixture_ref("workflow", "registry-memory-stale-work")
  let governance = guarded_fixture_ref(
    "workflow", "registry-memory-stale-governance",
  )
  let first = guarded_fixture_event(
    governance,
    "registry-memory-stale-governance-1",
    1L,
    None,
  )
  ignore(
    store.commit(
      guarded_fixture_request(
        governance, "registry-memory-stale-governance-command-1", 0L, first,
      ),
    ),
  )
  let mutation = guarded_fixture_request(
    work,
    "registry-memory-stale-work-command",
    0L,
    guarded_fixture_event(work, "registry-memory-stale-work-1", 1L, None),
  )
  let guarded = try! @storage.GuardedCommitRequest::new(mutation, [
    guarded_fixture_guard(store.replay(governance)),
  ])
  let activation = store.activate_guarded_workflow(work, [governance])
  let bound = @storage.GuardedMemoryStore::new(store, activation)
  let second = guarded_fixture_event(
    governance,
    "registry-memory-stale-governance-2",
    2L,
    Some(first.event_ref().digest()),
  )
  ignore(
    store.commit(
      guarded_fixture_request(
        governance, "registry-memory-stale-governance-command-2", 1L, second,
      ),
    ),
  )
  guard bound.guarded_commit(guarded) is @storage.GuardedCommitRejected(receipt) else {
    fail("stale registered guard was accepted")
  }
  assert_eq(receipt.expected_revision(), 1L)
  assert_eq(receipt.actual_revision(), 2L)
  assert_eq(store.replay(work).events().length(), 0)
}

///|
test "FLOW-4A registry-bound classified guarded commit distinguishes publication" {
  let store = @storage.MemoryStore::new()
  let work = guarded_fixture_ref("workflow", "classified-memory-work")
  let governance = guarded_fixture_ref(
    "workflow", "classified-memory-governance",
  )
  ignore(
    store.commit(
      guarded_fixture_request(
        governance,
        "classified-memory-governance-command",
        0L,
        guarded_fixture_event(
          governance,
          "classified-memory-governance-event",
          1L,
          None,
        ),
      ),
    ),
  )
  let guarded = try! @storage.GuardedCommitRequest::new(
    guarded_fixture_request(
      work,
      "classified-memory-work-command",
      0L,
      guarded_fixture_event(work, "classified-memory-work-event", 1L, None),
    ),
    [guarded_fixture_guard(store.replay(governance))],
  )
  let activation = store.activate_guarded_workflow(work, [governance])
  let bound = @storage.GuardedMemoryStore::new(store, activation)
  guard bound.classified_guarded_commit(guarded)
    is @storage.FreshlyApplied(first) else {
    fail("first classified commit was not fresh")
  }
  guard bound.classified_guarded_commit(guarded)
    is @storage.AlreadyCommitted(second) else {
    fail("exact classified retry was not already committed")
  }
  assert_true(first == second)
  let boundary = bound.replay(work).committed_batches()[0]
  assert_eq(boundary.guards().length(), 1)
  assert_true(
    boundary.guards()[0].canonical_bytes() ==
    guarded.guards()[0].canonical_bytes(),
  )
}
