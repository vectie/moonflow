///|
fn fixture_ref(
  kind : String,
  id : String,
  seed : Bytes,
) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(
    kind,
    id,
    "1.0.0",
    @contracts.sha256_digest(seed).text(),
  )
}

///|
fn fixture_workflow() -> @contracts.RecordRef {
  fixture_ref("workflow", "workflow-1", b"workflow-1")
}

///|
test "empty replay digest helper matches MemoryStore replay" {
  let workflow = fixture_workflow()
  let replay = @storage.MemoryStore::new().replay(workflow)
  assert_true(@storage.empty_replay_digest(workflow) == replay.replay_digest())
}

///|
fn fixture_schema() -> @contracts.SchemaRef {
  try! @contracts.SchemaRef::new(
    "neutral.storage",
    "1.0.0",
    "opaque-value",
    "1.0.0",
    @contracts.sha256_digest(b"schema").text(),
  )
}

///|
fn fixture_envelope(id : String, payload : Bytes) -> @contracts.WireEnvelope {
  try! @contracts.WireEnvelope::new(
    "neutral.storage",
    "1.0.0",
    id,
    "opaque-value",
    fixture_ref("subject", id, @utf8.encode(id)),
    fixture_schema(),
    payload,
    "neutral-writer",
    "1.0.0",
    [],
    [],
    run_ref=fixture_workflow(),
  )
}

///|
fn fixture_evidence(id : String) -> @contracts.EvidenceRef {
  try! @contracts.EvidenceRef::new(
    fixture_ref("evidence", id, @utf8.encode(id)),
    fixture_ref("provenance", "source", b"source"),
    @contracts.sha256_digest(@utf8.encode(id)).text(),
  )
}

///|
fn fixture_event(
  id : String,
  sequence : Int64,
  revision : Int64,
  payload : Bytes,
  previous : @contracts.ContentDigest?,
  key? : String,
) -> @storage.WorkflowEvent {
  match previous {
    None =>
      try! @storage.WorkflowEvent::new(
        "1.0.0",
        "1.0.0",
        fixture_workflow(),
        id,
        sequence,
        revision,
        key.unwrap_or("event-key-\{id}"),
        fixture_envelope("envelope-\{id}", payload),
        [fixture_evidence("evidence-\{id}")],
      )
    Some(previous) =>
      try! @storage.WorkflowEvent::new(
        "1.0.0",
        "1.0.0",
        fixture_workflow(),
        id,
        sequence,
        revision,
        key.unwrap_or("event-key-\{id}"),
        fixture_envelope("envelope-\{id}", payload),
        [fixture_evidence("evidence-\{id}")],
        previous_event_digest=previous,
      )
  }
}

///|
fn fixture_intent(
  id : String,
  event : @storage.WorkflowEvent,
  key? : String,
) -> @storage.OutboxIntent {
  try! @storage.OutboxIntent::new(
    "1.0.0",
    "1.0.0",
    id,
    fixture_workflow(),
    event.event_ref(),
    key.unwrap_or("intent-key-\{id}"),
    fixture_envelope("intent-envelope-\{id}", @utf8.encode(id)),
    [fixture_evidence("intent-evidence-\{id}")],
  )
}

///|
fn fixture_request(
  command : String,
  expected : Int64,
  events : Array[@storage.WorkflowEvent],
  intents : Array[@storage.OutboxIntent],
) -> @storage.CommitRequest {
  try! @storage.CommitRequest::new(
    "1.0.0",
    "1.0.0",
    fixture_workflow(),
    expected,
    command,
    events,
    intents,
  )
}

///|
test "FLOW-4A first commit is atomically visible with its intent" {
  let store = @storage.MemoryStore::new()
  let event = fixture_event("event-1", 1L, 1L, b"one", None)
  let intent = fixture_intent("intent-1", event)
  let result = store.commit(fixture_request("command-1", 0L, [event], [intent]))
  assert_eq(result.first_sequence(), 1L)
  assert_eq(result.last_sequence(), 1L)
  assert_eq(result.event_count(), 1L)
  assert_eq(result.intent_count(), 1L)
  let replay = store.replay(fixture_workflow())
  assert_eq(replay.events().length(), 1)
  assert_eq(replay.intents().length(), 1)
  assert_eq(replay.head().revision(), 1L)
}

///|
test "FLOW-4A multi-event multi-intent commit is contiguous" {
  let store = @storage.MemoryStore::new()
  let first = fixture_event("event-1", 1L, 1L, b"one", None)
  let second = fixture_event(
    "event-2",
    2L,
    2L,
    b"two",
    Some(first.event_ref().digest()),
  )
  let result = store.commit(
    fixture_request("command-1", 0L, [first, second], [
      fixture_intent("intent-1", first),
      fixture_intent("intent-2", second),
    ]),
  )
  assert_eq(result.last_sequence(), 2L)
  assert_eq(result.workflow_revision(), 2L)
  assert_eq(result.event_count(), 2L)
  assert_eq(result.intent_count(), 2L)
}

///|
test "FLOW-4A exact command retry precedes stale revision and is stable" {
  let store = @storage.MemoryStore::new()
  let first = fixture_event("event-1", 1L, 1L, b"one", None)
  let request = fixture_request("command-1", 0L, [first], [])
  let original = store.commit(request)
  let second = fixture_event(
    "event-2",
    2L,
    2L,
    b"two",
    Some(first.event_ref().digest()),
  )
  ignore(store.commit(fixture_request("command-2", 1L, [second], [])))
  let duplicate = store.commit(request)
  assert_true(duplicate == original)
  assert_eq(store.head(fixture_workflow()).event_count(), 2L)
}

///|
test "FLOW-4A reused command key with changed canonical content conflicts" {
  let store = @storage.MemoryStore::new()
  let first = fixture_event("event-1", 1L, 1L, b"one", None)
  ignore(store.commit(fixture_request("command-1", 0L, [first], [])))
  let changed = fixture_event("event-x", 1L, 1L, b"changed", None)
  try store.commit(fixture_request("command-1", 0L, [changed], [])) catch {
    IdempotencyConflict(key~) => assert_eq(key, "command-1")
    _ => fail("unexpected command conflict")
  } noraise {
    _ => fail("expected command conflict")
  }
  assert_eq(store.head(fixture_workflow()).event_count(), 1L)
}

///|
test "FLOW-4A stale expected revision is an optimistic conflict" {
  let store = @storage.MemoryStore::new()
  let first = fixture_event("event-1", 1L, 1L, b"one", None)
  ignore(store.commit(fixture_request("command-1", 0L, [first], [])))
  let second = fixture_event(
    "event-2",
    2L,
    2L,
    b"two",
    Some(first.event_ref().digest()),
  )
  try store.commit(fixture_request("command-2", 0L, [second], [])) catch {
    OptimisticRevisionConflict(expected~, actual~, ..) => {
      assert_eq(expected, 0L)
      assert_eq(actual, 1L)
    }
    _ => fail("unexpected optimistic conflict")
  } noraise {
    _ => fail("expected optimistic conflict")
  }
}

///|
test "FLOW-4A event identity and record idempotency conflicts never overwrite" {
  let store = @storage.MemoryStore::new()
  let first = fixture_event("event-1", 1L, 1L, b"one", None)
  ignore(store.commit(fixture_request("command-1", 0L, [first], [])))
  let reused_identity = fixture_event(
    "event-1",
    2L,
    2L,
    b"changed",
    Some(first.event_ref().digest()),
  )
  try
    store.commit(fixture_request("command-2", 1L, [reused_identity], []))
  catch {
    IdentityConflict(id~, ..) => assert_eq(id, "event-1")
    _ => fail("unexpected identity conflict")
  } noraise {
    _ => fail("expected identity conflict")
  }
  let reused_key = fixture_event(
    "event-2",
    2L,
    2L,
    b"changed",
    Some(first.event_ref().digest()),
    key="event-key-event-1",
  )
  try store.commit(fixture_request("command-3", 1L, [reused_key], [])) catch {
    IdempotencyConflict(key~) => assert_eq(key, "event-key-event-1")
    _ => fail("unexpected record idempotency conflict")
  } noraise {
    _ => fail("expected record idempotency conflict")
  }
  assert_eq(store.events(fixture_workflow()).length(), 1)
}

///|
test "FLOW-4A intent identity and idempotency conflicts never overwrite" {
  let store = @storage.MemoryStore::new()
  let first = fixture_event("event-1", 1L, 1L, b"one", None)
  let first_intent = fixture_intent("intent-1", first)
  ignore(
    store.commit(fixture_request("command-1", 0L, [first], [first_intent])),
  )
  let second = fixture_event(
    "event-2",
    2L,
    2L,
    b"two",
    Some(first.event_ref().digest()),
  )
  let reused_identity = try! @storage.OutboxIntent::new(
    "1.0.0",
    "1.0.0",
    "intent-1",
    fixture_workflow(),
    second.event_ref(),
    "intent-key-changed",
    fixture_envelope("intent-envelope-changed", b"changed"),
    [],
  )
  try
    store.commit(fixture_request("command-2", 1L, [second], [reused_identity]))
  catch {
    IdentityConflict(id~, ..) => assert_eq(id, "intent-1")
    _ => fail("unexpected intent identity conflict")
  } noraise {
    _ => fail("expected intent identity conflict")
  }
  let reused_key = try! @storage.OutboxIntent::new(
    "1.0.0",
    "1.0.0",
    "intent-2",
    fixture_workflow(),
    second.event_ref(),
    "intent-key-intent-1",
    fixture_envelope("intent-envelope-2", b"changed"),
    [],
  )
  try
    store.commit(fixture_request("command-3", 1L, [second], [reused_key]))
  catch {
    IdempotencyConflict(key~) => assert_eq(key, "intent-key-intent-1")
    _ => fail("unexpected intent idempotency conflict")
  } noraise {
    _ => fail("expected intent idempotency conflict")
  }
  assert_eq(store.intents(fixture_workflow()).length(), 1)
}

///|
test "FLOW-4A sequence revision and previous digest gaps are typed" {
  let store = @storage.MemoryStore::new()
  let first = fixture_event("event-1", 1L, 1L, b"one", None)
  ignore(store.commit(fixture_request("command-1", 0L, [first], [])))
  let sequence_gap = fixture_event(
    "event-3",
    3L,
    2L,
    b"gap",
    Some(first.event_ref().digest()),
  )
  try store.commit(fixture_request("command-2", 1L, [sequence_gap], [])) catch {
    SequenceGap(expected~, actual~, ..) => {
      assert_eq(expected, 2L)
      assert_eq(actual, 3L)
    }
    _ => fail("unexpected sequence gap")
  } noraise {
    _ => fail("expected sequence gap")
  }
  let revision_gap = fixture_event(
    "event-2",
    2L,
    3L,
    b"gap",
    Some(first.event_ref().digest()),
  )
  try store.commit(fixture_request("command-3", 1L, [revision_gap], [])) catch {
    RevisionGap(expected~, actual~, ..) => {
      assert_eq(expected, 2L)
      assert_eq(actual, 3L)
    }
    _ => fail("unexpected revision gap")
  } noraise {
    _ => fail("expected revision gap")
  }
  let wrong_previous = fixture_event(
    "event-2",
    2L,
    2L,
    b"wrong",
    Some(@contracts.sha256_digest(b"wrong")),
  )
  try
    store.commit(fixture_request("command-4", 1L, [wrong_previous], []))
  catch {
    DigestMismatch(record_kind~, ..) =>
      assert_eq(record_kind, "workflow_event_chain")
    _ => fail("unexpected chain digest error")
  } noraise {
    _ => fail("expected chain digest error")
  }
}

///|
test "FLOW-4A causative event must be exact and visible atomically" {
  let store = @storage.MemoryStore::new()
  let first = fixture_event("event-1", 1L, 1L, b"one", None)
  let unrelated = fixture_event("event-x", 1L, 1L, b"x", None)
  let intent = fixture_intent("intent-1", unrelated)
  try store.commit(fixture_request("command-1", 0L, [first], [intent])) catch {
    ValidationFailure(field~) => assert_eq(field, "causative_event_binding")
    _ => fail("unexpected causative binding error")
  } noraise {
    _ => fail("expected causative binding error")
  }
  assert_eq(store.head(fixture_workflow()).event_count(), 0L)
  assert_eq(store.head(fixture_workflow()).intent_count(), 0L)
}

///|
test "FLOW-4A checkpoint is verified and replay tail is deterministic" {
  let store = @storage.MemoryStore::new()
  let first = fixture_event("event-1", 1L, 1L, b"one", None)
  let second = fixture_event(
    "event-2",
    2L,
    2L,
    b"two",
    Some(first.event_ref().digest()),
  )
  ignore(store.commit(fixture_request("command-1", 0L, [first, second], [])))
  let checkpoint = try! @storage.CheckpointRecord::new(
    "1.0.0",
    "1.0.0",
    "1.0.0",
    "checkpoint-1",
    fixture_workflow(),
    1L,
    1L,
    fixture_envelope("snapshot-1", b"snapshot"),
    [fixture_evidence("checkpoint-evidence")],
    last_event_digest=first.event_ref().digest(),
  )
  store.write_checkpoint(checkpoint)
  let replay = store.replay(fixture_workflow())
  assert_true(replay.checkpoint() == Some(checkpoint))
  assert_eq(replay.events().length(), 2)
  assert_eq(replay.tail_events().length(), 1)
  assert_eq(replay.tail_events()[0].event_ref().id(), "event-2")
  assert_true(
    replay.replay_digest() == store.replay(fixture_workflow()).replay_digest(),
  )
}

///|
test "FLOW-4A latest of multiple verified checkpoints is selected" {
  let store = @storage.MemoryStore::new()
  let first = fixture_event("event-1", 1L, 1L, b"one", None)
  let second = fixture_event(
    "event-2",
    2L,
    2L,
    b"two",
    Some(first.event_ref().digest()),
  )
  ignore(store.commit(fixture_request("command-1", 0L, [first, second], [])))
  let earlier = try! @storage.CheckpointRecord::new(
    "1.0.0",
    "1.0.0",
    "1.0.0",
    "checkpoint-1",
    fixture_workflow(),
    1L,
    1L,
    fixture_envelope("snapshot-1", b"snapshot-1"),
    [],
    last_event_digest=first.event_ref().digest(),
  )
  let latest = try! @storage.CheckpointRecord::new(
    "1.0.0",
    "1.0.0",
    "1.0.0",
    "checkpoint-2",
    fixture_workflow(),
    2L,
    2L,
    fixture_envelope("snapshot-2", b"snapshot-2"),
    [],
    last_event_digest=second.event_ref().digest(),
  )
  store.write_checkpoint(latest)
  store.write_checkpoint(earlier)
  let replay = store.replay(fixture_workflow())
  assert_true(replay.checkpoint() == Some(latest))
  assert_eq(replay.tail_events().length(), 0)
}

///|
test "FLOW-4A invalid checkpoint boundary is rejected without changing replay" {
  let store = @storage.MemoryStore::new()
  let first = fixture_event("event-1", 1L, 1L, b"one", None)
  ignore(store.commit(fixture_request("command-1", 0L, [first], [])))
  let invalid = try! @storage.CheckpointRecord::new(
    "1.0.0",
    "1.0.0",
    "1.0.0",
    "checkpoint-invalid",
    fixture_workflow(),
    1L,
    2L,
    fixture_envelope("snapshot-invalid", b"snapshot"),
    [],
    last_event_digest=first.event_ref().digest(),
  )
  try store.write_checkpoint(invalid) catch {
    ValidationFailure(field~) => assert_eq(field, "checkpoint_boundary")
    _ => fail("unexpected checkpoint error")
  } noraise {
    _ => fail("expected invalid checkpoint")
  }
  assert_true(store.read_checkpoint(fixture_workflow()) is None)
  assert_eq(store.replay(fixture_workflow()).events().length(), 1)
}

///|
test "FLOW-4A caller arrays cannot mutate validated records or requests" {
  let evidence = [fixture_evidence("evidence-1")]
  let event = try! @storage.WorkflowEvent::new(
    "1.0.0",
    "1.0.0",
    fixture_workflow(),
    "event-1",
    1L,
    1L,
    "event-key-1",
    fixture_envelope("envelope-1", b"one"),
    evidence,
  )
  evidence.clear()
  assert_eq(event.evidence().length(), 1)
  let events = [event]
  let request = fixture_request("command-1", 0L, events, [])
  events.clear()
  assert_eq(request.events().length(), 1)
}

///|
test "FLOW-4A unsupported durable versions fail closed" {
  try
    @storage.WorkflowEvent::new(
      "2.0.0",
      "1.0.0",
      fixture_workflow(),
      "event-1",
      1L,
      1L,
      "event-key-1",
      fixture_envelope("envelope-1", b"one"),
      [],
    )
  catch {
    UnsupportedVersion(record_kind~, version~) => {
      assert_eq(record_kind, "workflow_event")
      assert_eq(version, "2.0.0")
    }
    _ => fail("unexpected version error")
  } noraise {
    _ => fail("expected unsupported version")
  }
}
