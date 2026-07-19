///|
fn registry_wb_ref(kind : String, id : String) -> @contracts.RecordRef {
  wb_ref(kind, id, @utf8.encode("registry-wb:" + id))
}

///|
fn registry_wb_event(
  workflow : @contracts.RecordRef,
  id : String,
  revision : Int64,
  previous : @contracts.ContentDigest?,
) -> WorkflowEvent {
  let envelope = try! @contracts.WireEnvelope::new(
    "neutral.storage",
    "1.0.0",
    "registry-wb-envelope-" + id,
    "opaque-value",
    registry_wb_ref("subject", id),
    try! @contracts.SchemaRef::new(
      "neutral.storage",
      "1.0.0",
      "opaque-value",
      "1.0.0",
      @contracts.sha256_digest(b"registry-wb-schema").text(),
    ),
    @utf8.encode(id),
    "registry-wb",
    "1.0.0",
    [],
    [],
    run_ref=workflow,
  )
  match previous {
    None =>
      try! WorkflowEvent::new(
        "1.0.0",
        "1.0.0",
        workflow,
        id,
        revision,
        revision,
        "registry-wb-event-key-" + id,
        envelope,
        [],
      )
    Some(digest) =>
      try! WorkflowEvent::new(
        "1.0.0",
        "1.0.0",
        workflow,
        id,
        revision,
        revision,
        "registry-wb-event-key-" + id,
        envelope,
        [],
        previous_event_digest=digest,
      )
  }
}

///|
fn registry_wb_request(
  workflow : @contracts.RecordRef,
  command : String,
  expected : Int64,
  event : WorkflowEvent,
) -> CommitRequest {
  try! CommitRequest::new(
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
fn registry_wb_guard(replay : ReplayResult) -> WorkflowHeadGuard {
  try! WorkflowHeadGuard::new(
    replay.workflow(),
    replay.head().revision(),
    replay.head().last_event_digest(),
    replay.replay_digest(),
  )
}

///|
test "FLOW-4A existing MemoryStore migrates at exact activation prefix and rejects fork" {
  let store = MemoryStore::new()
  let work = registry_wb_ref("workflow", "registry-wb-migration-work")
  let governance = registry_wb_ref(
    "workflow", "registry-wb-migration-governance",
  )
  let original = registry_wb_request(
    work,
    "registry-wb-migration-command",
    0L,
    registry_wb_event(work, "registry-wb-migration-original", 1L, None),
  )
  ignore(store.commit(original))
  let activation = store.activate_guarded_workflow(work, [governance])
  assert_eq(activation.activation_revision(), 1L)
  try ignore(store.commit(original)) catch {
    GuardedCommitRequired(key="registry-wb-migration-command", ..) => ()
    error => fail("unexpected migrated raw retry error: \{to_repr(error)}")
  } noraise {
    _ => fail("post-activation exact raw retry bypassed registry")
  }
  let alternate = registry_wb_request(
    work,
    "registry-wb-migration-fork-command",
    0L,
    registry_wb_event(work, "registry-wb-migration-fork", 1L, None),
  )
  store.batches.clear()
  store.batches.push(encode_batch(make_stored_batch(alternate, 1L, 0L)))
  try store.activate_guarded_workflow(work, [governance]) catch {
    GuardedBindingFork(workflow_id="registry-wb-migration-work") => ()
    error => fail("unexpected same-revision fork error: \{to_repr(error)}")
  } noraise {
    _ => fail("same-revision alternate activation fork was accepted")
  }
  try GuardedMemoryStore::new(store, activation) catch {
    GuardedBindingFork(workflow_id="registry-wb-migration-work") => ()
    error => fail("unexpected forked receipt error: \{to_repr(error)}")
  } noraise {
    _ => fail("forked backing constructed an official capability")
  }
}

///|
test "FLOW-4A MemoryStore registry fails closed on missing marker and guard reorder" {
  let store = MemoryStore::new()
  let work = registry_wb_ref("workflow", "registry-wb-order-work")
  let first_guard = registry_wb_ref("workflow", "registry-wb-order-guard-a")
  let second_guard = registry_wb_ref("workflow", "registry-wb-order-guard-b")
  let activation = store.activate_guarded_workflow(work, [
    first_guard, second_guard,
  ])
  let mutation = registry_wb_request(
    work,
    "registry-wb-order-command",
    0L,
    registry_wb_event(work, "registry-wb-order-event", 1L, None),
  )
  let reordered = try! GuardedCommitRequest::new(mutation, [
    registry_wb_guard(store.replay(second_guard)),
    registry_wb_guard(store.replay(first_guard)),
  ])
  let bound = try! GuardedMemoryStore::new(store, activation)
  try bound.guarded_commit(reordered) catch {
    GuardedBindingConflict(field="guard_set", ..) => ()
    error => fail("unexpected reordered guard error: \{to_repr(error)}")
  } noraise {
    _ => fail("reordered authoritative guards were accepted")
  }
  let missing = try! GuardedCommitRequest::new(mutation, [
    registry_wb_guard(store.replay(first_guard)),
  ])
  try bound.guarded_commit(missing) catch {
    GuardedBindingConflict(field="guard_set", ..) => ()
    error => fail("unexpected missing guard error: \{to_repr(error)}")
  } noraise {
    _ => fail("missing authoritative guard was accepted")
  }
  store.registry_markers.clear()
  let marker = guarded_binding_marker_name(activation.binding)
  try ignore(store.commit(mutation)) catch {
    GuardedRegistryMissing(name~) => assert_eq(name, marker)
    error => fail("unexpected missing memory marker error: \{to_repr(error)}")
  } noraise {
    _ => fail("missing memory marker reopened raw mutation")
  }
  try GuardedMemoryStore::new(store, activation) catch {
    GuardedRegistryMissing(name~) => assert_eq(name, marker)
    error =>
      fail("unexpected missing memory capability error: \{to_repr(error)}")
  } noraise {
    _ => fail("missing memory marker constructed official capability")
  }
}
