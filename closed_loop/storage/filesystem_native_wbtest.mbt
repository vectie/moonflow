///|
#borrow(status)
extern "c" fn native_temporary_root(status : Ref[Int]) -> Bytes = "moonflow_storage_native_temporary_root"

///|
extern "c" fn native_unique_suffix() -> Bytes = "moonflow_storage_native_unique_suffix"

///|
fn set_native_fault_point(value : Int) -> Unit {
  native_fault_point.val = value
}

///|
fn native_fixture_root() -> String {
  let status = Ref(0)
  let bytes = native_temporary_root(status)
  if status.val != 0 {
    abort("temporary root unavailable")
  }
  try! @utf8.decode(bytes)
}

///|
fn native_fixture_relative() -> String {
  try! @utf8.decode(native_unique_suffix())
}

///|
fn native_fixture_store() -> FileSystemStore {
  FileSystemStore::open(native_fixture_root(), native_fixture_relative()) catch {
    error => abort("native fixture store unavailable: \{to_repr(error)}")
  }
}

///|
fn native_request(
  workflow : @contracts.RecordRef,
  command : String,
  expected : Int64,
  event : WorkflowEvent,
  intents : Array[OutboxIntent],
) -> CommitRequest {
  try! CommitRequest::new(
    "1.0.0",
    "1.0.0",
    workflow,
    expected,
    command,
    [event],
    intents,
  )
}

///|
fn native_second_event(first : WorkflowEvent, id : String) -> WorkflowEvent {
  wb_event(id, 2L, Some(first.event_ref.digest()))
}

///|
fn store_raw(store : FileSystemStore, name : String, bytes : Bytes) -> Unit {
  let session = try! acquire_native_session(
    store.workspace_root,
    store.storage_root,
    true,
  )
  try! native_atomic_store_named(session, name, bytes)
  native_close(session)
}

///|
#borrow(path)
extern "c" fn native_fixture_unlink(path : Bytes) -> Int = "unlink"

///|
#borrow(target, path)
extern "c" fn native_fixture_symlink(target : Bytes, path : Bytes) -> Int = "symlink"

///|
test "FLOW-4A filesystem restart preserves one atomic batch" {
  let store = native_fixture_store()
  let event = wb_event("native-event-1", 1L, None)
  let intent = try! OutboxIntent::new(
    "1.0.0",
    "1.0.0",
    "native-intent-1",
    event.workflow,
    event.event_ref,
    "native-intent-key-1",
    wb_envelope("native-intent-envelope-1", b"intent"),
    [],
  )
  let committed = store.commit(
    native_request(event.workflow, "native-command-1", 0L, event, [intent]),
  )
  let restarted = try! FileSystemStore::open(
    store.workspace_root(),
    store.storage_root(),
  )
  let replay = restarted.replay(event.workflow)
  assert_eq(replay.events().length(), 1)
  assert_eq(replay.intents().length(), 1)
  assert_true(
    replay.head().last_event_digest() == Some(committed.last_event_digest()),
  )
}

///|
test "FLOW-4A filesystem and memory produce identical canonical replay" {
  let filesystem = native_fixture_store()
  let memory = MemoryStore::new()
  let first = wb_event("parity-event-1", 1L, None)
  let second = native_second_event(first, "parity-event-2")
  let intent = try! OutboxIntent::new(
    "1.0.0",
    "1.0.0",
    "parity-intent-1",
    first.workflow,
    second.event_ref,
    "parity-intent-key-1",
    wb_envelope("parity-intent-envelope-1", b"intent"),
    [],
  )
  let request = try! CommitRequest::new(
    "1.0.0",
    "1.0.0",
    first.workflow,
    0L,
    "parity-command-1",
    [first, second],
    [intent],
  )
  let memory_result = memory.commit(request)
  let filesystem_result = filesystem.commit(request)
  assert_true(memory_result == filesystem_result)
  let memory_replay = memory.replay(first.workflow)
  let filesystem_replay = filesystem.replay(first.workflow)
  assert_true(memory_replay.replay_digest == filesystem_replay.replay_digest)
  assert_true(memory_replay.head == filesystem_replay.head)
  assert_eq(filesystem_replay.events.length(), 2)
  assert_eq(filesystem_replay.events[0].event_ref.id(), "parity-event-1")
  assert_eq(filesystem_replay.events[1].event_ref.id(), "parity-event-2")
}

///|
test "FLOW-4A interleaved filesystem writers lose no accepted commit" {
  let first_store = native_fixture_store()
  let second_store = try! FileSystemStore::open(
    first_store.workspace_root,
    first_store.storage_root,
  )
  let first = wb_event("writer-event-1", 1L, None)
  ignore(
    first_store.commit(
      native_request(first.workflow, "writer-command-1", 0L, first, []),
    ),
  )
  let second = native_second_event(first, "writer-event-2")
  ignore(
    second_store.commit(
      native_request(first.workflow, "writer-command-2", 1L, second, []),
    ),
  )
  let stale = native_second_event(first, "writer-event-stale")
  try
    first_store.commit(
      native_request(first.workflow, "writer-command-stale", 1L, stale, []),
    )
  catch {
    OptimisticRevisionConflict(actual~, ..) => assert_eq(actual, 2L)
    _ => fail("unexpected interleaved writer error")
  } noraise {
    _ => fail("expected interleaved optimistic conflict")
  }
  assert_eq(first_store.replay(first.workflow).events.length(), 2)
}

///|
test "FLOW-4A every native publication fault boundary recovers atomically" {
  for point in 1..<=8 {
    let store = native_fixture_store()
    let event = wb_event("fault-event-\{point}", 1L, None)
    set_native_fault_point(point)
    try
      store.commit(
        native_request(event.workflow, "fault-command-\{point}", 0L, event, []),
      )
    catch {
      IoFailure(operation~, status~) => {
        assert_eq(operation, "fault_injection")
        assert_eq(status, point)
      }
      _ => fail("unexpected injected fault error")
    } noraise {
      _ => fail("expected injected publication fault")
    }
    let restarted = try! FileSystemStore::open(
      store.workspace_root,
      store.storage_root,
    )
    let expected = if point <= 6 { 0L } else { 1L }
    assert_eq(restarted.head(event.workflow).event_count, expected)
    assert_eq(restarted.head(event.workflow).intent_count, 0L)
  }
}

///|
test "FLOW-4A corrupt newest checkpoint falls back to earlier verified boundary" {
  let store = native_fixture_store()
  let first = wb_event("checkpoint-event-1", 1L, None)
  let second = native_second_event(first, "checkpoint-event-2")
  ignore(
    store.commit(
      try! CommitRequest::new(
        "1.0.0",
        "1.0.0",
        first.workflow,
        0L,
        "checkpoint-command-1",
        [first, second],
        [],
      ),
    ),
  )
  let earlier = try! CheckpointRecord::new(
    "1.0.0",
    "1.0.0",
    "1.0.0",
    "checkpoint-earlier",
    first.workflow,
    1L,
    1L,
    wb_envelope("checkpoint-snapshot-1", b"snapshot-1"),
    [],
    last_event_digest=first.event_ref.digest(),
  )
  store.write_checkpoint(earlier)
  let newest = try! CheckpointRecord::new(
    "1.0.0",
    "1.0.0",
    "1.0.0",
    "checkpoint-newest",
    first.workflow,
    2L,
    2L,
    wb_envelope("checkpoint-snapshot-2", b"snapshot-2"),
    [],
    last_event_digest=second.event_ref.digest(),
  )
  store_raw(
    store,
    checkpoint_file_name(newest),
    newest.canonical_bytes()[0:12].to_owned(),
  )
  let replay = store.replay(first.workflow)
  assert_true(replay.checkpoint == Some(earlier))
  assert_eq(replay.tail_events.length(), 1)
  assert_eq(replay.tail_events[0].event_ref.id(), "checkpoint-event-2")
}

///|
test "FLOW-4A partial committed batch and duplicate generation fail closed" {
  let corrupt_store = native_fixture_store()
  let valid = wb_event("corrupt-tail-event-1", 1L, None)
  ignore(
    corrupt_store.commit(
      native_request(valid.workflow, "corrupt-tail-command-1", 0L, valid, []),
    ),
  )
  store_raw(
    corrupt_store, "batch-0000000000000000000000000000000000000000000000000000000000000000-0000000000000001-0000000000000000000000000000000000000000000000000000000000000000.mfb",
    b"partial",
  )
  try corrupt_store.replay(valid.workflow) catch {
    CorruptCommittedData(name~) => assert_true(name.has_prefix("batch-"))
    _ => fail("unexpected partial committed batch error")
  } noraise {
    _ => fail("expected partial committed batch rejection")
  }

  let duplicate_store = native_fixture_store()
  let first = wb_event("duplicate-event-1", 1L, None)
  ignore(
    duplicate_store.commit(
      native_request(first.workflow, "duplicate-command-1", 0L, first, []),
    ),
  )
  let alternate = wb_event("duplicate-event-2", 1L, None)
  let alternate_request = native_request(
    first.workflow,
    "duplicate-command-2",
    0L,
    alternate,
    [],
  )
  let alternate_batch = make_stored_batch(alternate_request, 1L, 0L)
  store_raw(
    duplicate_store,
    batch_file_name(alternate_batch),
    encode_batch(alternate_batch),
  )
  try duplicate_store.replay(first.workflow) catch {
    CorruptCommittedData(name~) => assert_true(name.has_prefix("batch-"))
    _ => fail("unexpected duplicate generation error")
  } noraise {
    _ => fail("expected duplicate generation rejection")
  }
}

///|
test "FLOW-4A relative storage path validation rejects escape forms" {
  let root = native_fixture_root()
  for
    invalid in [
      "", "/absolute", ".", "..", "../outside", "a/../b", "a/./b", "a//b", "a\\b",
      "a\u{0}b",
    ] {
    try FileSystemStore::open(root, invalid) catch {
      UnsafePath(path~) => assert_eq(path, invalid)
      _ => fail("unexpected unsafe path error")
    } noraise {
      _ => fail("expected unsafe path rejection")
    }
  }
  try FileSystemStore::open(root + "/..", native_fixture_relative()) catch {
    UnsafePath(_) => ()
    _ => fail("unexpected noncanonical workspace error")
  } noraise {
    _ => fail("expected noncanonical workspace rejection")
  }
}

///|
test "FLOW-4A symlink workspace component and committed target are rejected" {
  let root = native_fixture_root()
  let workspace_link = root + "/" + native_fixture_relative()
  assert_eq(
    native_fixture_symlink(@utf8.encode(root), @utf8.encode(workspace_link)),
    0,
  )
  try FileSystemStore::open(workspace_link, "store") catch {
    SymlinkRejected(_) => ()
    _ => fail("unexpected workspace symlink error")
  } noraise {
    _ => fail("expected workspace symlink rejection")
  }

  let component = native_fixture_relative()
  let component_path = root + "/" + component
  assert_eq(
    native_fixture_symlink(@utf8.encode(root), @utf8.encode(component_path)),
    0,
  )
  try FileSystemStore::open(root, component + "/child") catch {
    SymlinkRejected(_) => ()
    _ => fail("unexpected component symlink error")
  } noraise {
    _ => fail("expected component symlink rejection")
  }

  let lock_store = native_fixture_store()
  let lock_path = lock_store.workspace_root + "/.moonflow-flow4a.lock"
  assert_eq(native_fixture_unlink(@utf8.encode(lock_path)), 0)
  assert_eq(
    native_fixture_symlink(@utf8.encode("/dev/null"), @utf8.encode(lock_path)),
    0,
  )
  try
    FileSystemStore::open(lock_store.workspace_root, lock_store.storage_root)
  catch {
    SymlinkRejected(_) => ()
    _ => fail("unexpected lock symlink error")
  } noraise {
    _ => fail("expected lock symlink rejection")
  }
  assert_eq(native_fixture_unlink(@utf8.encode(lock_path)), 0)
  ignore(
    try! FileSystemStore::open(
      lock_store.workspace_root,
      lock_store.storage_root,
    ),
  )

  let store = native_fixture_store()
  let event = wb_event("symlink-event-1", 1L, None)
  ignore(
    store.commit(
      native_request(event.workflow, "symlink-command-1", 0L, event, []),
    ),
  )
  let session = try! acquire_native_session(
    store.workspace_root,
    store.storage_root,
    true,
  )
  let committed_name = native_names(session).filter(name => {
      name.has_prefix("batch-")
    })[0]
  native_close(session)
  let committed_path = root + "/" + store.storage_root + "/" + committed_name
  assert_eq(native_fixture_unlink(@utf8.encode(committed_path)), 0)
  assert_eq(
    native_fixture_symlink(
      @utf8.encode("/dev/null"),
      @utf8.encode(committed_path),
    ),
    0,
  )
  try store.replay(event.workflow) catch {
    SymlinkRejected(path~) => assert_eq(path, committed_name)
    _ => fail("unexpected committed symlink error")
  } noraise {
    _ => fail("expected committed target symlink rejection")
  }
}

///|
fn copy_native_store_bytes(
  source : FileSystemStore,
  destination : FileSystemStore,
  corrupt_first_batch : Bool,
) -> String? raise StorageError {
  let source_session = acquire_native_session(
    source.workspace_root,
    source.storage_root,
    false,
  )
  let mut corrupted : String? = None
  let copied_entries : Array[(String, Bytes)] = []
  for name in native_names(source_session) {
    if name == ".flow4a.lock" || name.has_prefix(".flow4a-tmp-") {
      continue
    }
    let bytes = native_read_named(source_session, name)
    let copied = if corrupt_first_batch &&
      corrupted is None &&
      name.has_prefix("batch-") {
      corrupted = Some(name)
      bytes[0:12].to_owned()
    } else {
      bytes
    }
    copied_entries.push((name, copied))
  }
  native_close(source_session)
  let destination_session = acquire_native_session(
    destination.workspace_root,
    destination.storage_root,
    true,
  )
  for entry in copied_entries {
    native_atomic_store_named(destination_session, entry.0, entry.1)
  }
  native_close(destination_session)
  corrupted
}

///|
test "FLOW-4A bytes-only copied store replays in a fresh instance and corruption fails closed" {
  let root = native_fixture_root()
  let source = try! FileSystemStore::open(root, native_fixture_relative())
  let first = wb_event("bytes-only-copy-event-1", 1L, None)
  let second = native_second_event(first, "bytes-only-copy-event-2")
  let intent = try! OutboxIntent::new(
    "1.0.0",
    "1.0.0",
    "bytes-only-copy-intent",
    first.workflow,
    second.event_ref,
    "bytes-only-copy-intent-key",
    wb_envelope("bytes-only-copy-intent-envelope", b"intent"),
    [],
  )
  ignore(
    source.commit(
      try! CommitRequest::new(
        "1.0.0",
        "1.0.0",
        first.workflow,
        0L,
        "bytes-only-copy-command",
        [first, second],
        [intent],
      ),
    ),
  )
  let source_replay = source.replay(first.workflow)

  let copied_relative = native_fixture_relative()
  let copied_shell = try! FileSystemStore::open(root, copied_relative)
  assert_true(copy_native_store_bytes(source, copied_shell, false) is None)
  let copied = try! FileSystemStore::open(root, copied_relative)
  let copied_replay = copied.replay(first.workflow)
  assert_true(copied_replay.replay_digest() == source_replay.replay_digest())
  assert_true(copied_replay.head() == source_replay.head())
  assert_eq(copied_replay.events().length(), source_replay.events().length())
  for index, event in copied_replay.events() {
    assert_true(
      event.canonical_bytes() == source_replay.events()[index].canonical_bytes(),
    )
  }
  assert_eq(copied_replay.intents().length(), source_replay.intents().length())
  for index, value in copied_replay.intents() {
    assert_true(
      value.canonical_bytes() ==
      source_replay.intents()[index].canonical_bytes(),
    )
  }
  assert_eq(
    copied_replay.committed_batches().length(),
    source_replay.committed_batches().length(),
  )
  let copied_batch = copied_replay.committed_batches()[0]
  let source_batch = source_replay.committed_batches()[0]
  assert_true(copied_batch.batch_digest() == source_batch.batch_digest())
  assert_eq(
    copied_batch.command_idempotency_key(),
    source_batch.command_idempotency_key(),
  )
  assert_eq(copied_batch.event_refs().length(), 2)
  assert_eq(copied_batch.intent_refs().length(), 1)

  let corrupt_relative = native_fixture_relative()
  let corrupt_shell = try! FileSystemStore::open(root, corrupt_relative)
  guard copy_native_store_bytes(source, corrupt_shell, true)
    is Some(corrupt_name) else {
    fail("expected one copied batch to be truncated")
  }
  let corrupt = try! FileSystemStore::open(root, corrupt_relative)
  try corrupt.replay(first.workflow) catch {
    CorruptCommittedData(name~) => assert_eq(name, corrupt_name)
    _ => fail("unexpected copied-store corruption error")
  } noraise {
    _ => fail("accepted corrupted bytes-only store copy")
  }
}

///|
fn native_guarded_event(
  workflow : @contracts.RecordRef,
  id : String,
  revision : Int64,
  previous : @contracts.ContentDigest?,
) -> WorkflowEvent {
  match previous {
    None =>
      try! WorkflowEvent::new(
        "1.0.0",
        "1.0.0",
        workflow,
        id,
        revision,
        revision,
        "native-guarded-event-key-" + id,
        wb_envelope("native-guarded-envelope-" + id, @utf8.encode(id)),
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
        "native-guarded-event-key-" + id,
        wb_envelope("native-guarded-envelope-" + id, @utf8.encode(id)),
        [],
        previous_event_digest=digest,
      )
  }
}

///|
fn native_guarded_request(
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
fn native_head_guard(replay : ReplayResult) -> WorkflowHeadGuard {
  try! WorkflowHeadGuard::new(
    replay.workflow(),
    replay.head().revision(),
    replay.head().last_event_digest(),
    replay.replay_digest(),
  )
}

///|
test "FLOW-4A cross-root guarded filesystem commit survives restart and exact retry" {
  let root = native_fixture_root()
  let work_root = native_fixture_relative()
  let governance_root = native_fixture_relative()
  let work = try! FileSystemStore::open(root, work_root)
  let governance = try! FileSystemStore::open(root, governance_root)
  let work_ref = wb_ref(
    "workflow", "native-cross-root-work", b"native-cross-root-work",
  )
  let governance_ref = wb_ref(
    "workflow", "native-cross-root-governance", b"native-cross-root-governance",
  )
  let governance_first = native_guarded_event(
    governance_ref,
    "native-cross-root-governance-1",
    1L,
    None,
  )
  ignore(
    governance.commit(
      native_guarded_request(
        governance_ref, "native-cross-root-governance-command-1", 0L, governance_first,
      ),
    ),
  )
  let request = try! GuardedCommitRequest::new(
    native_guarded_request(
      work_ref,
      "native-cross-root-work-command",
      0L,
      native_guarded_event(work_ref, "native-cross-root-work-1", 1L, None),
    ),
    [native_head_guard(governance.replay(governance_ref))],
  )
  let capability = try! FileSystemGuardedStore::new(work, [governance])
  guard capability.guarded_commit(request) is GuardedCommitSucceeded(original) else {
    fail("cross-root guarded commit failed")
  }
  let governance_second = native_guarded_event(
    governance_ref,
    "native-cross-root-governance-2",
    2L,
    Some(governance_first.event_ref().digest()),
  )
  ignore(
    governance.commit(
      native_guarded_request(
        governance_ref, "native-cross-root-governance-command-2", 1L, governance_second,
      ),
    ),
  )
  let work_restart = try! FileSystemStore::open(root, work_root)
  let governance_restart = try! FileSystemStore::open(root, governance_root)
  let restarted = try! FileSystemGuardedStore::new(work_restart, [
    governance_restart,
  ])
  guard restarted.guarded_commit(request) is GuardedCommitSucceeded(duplicate) else {
    fail("exact guarded retry failed after governance advance and restart")
  }
  assert_true(original == duplicate)
  assert_eq(restarted.replay(work_ref).events().length(), 1)
}

///|
test "FLOW-4A cross-root same-revision governance fork rejects without mutation" {
  let root = native_fixture_root()
  let work = try! FileSystemStore::open(root, native_fixture_relative())
  let governance = try! FileSystemStore::open(root, native_fixture_relative())
  let work_ref = wb_ref("workflow", "native-fork-work", b"native-fork-work")
  let governance_ref = wb_ref(
    "workflow", "native-fork-governance", b"native-fork-governance",
  )
  let expected_store = MemoryStore::new()
  ignore(
    expected_store.commit(
      native_guarded_request(
        governance_ref,
        "native-fork-governance-command-a",
        0L,
        native_guarded_event(
          governance_ref,
          "native-fork-governance-a",
          1L,
          None,
        ),
      ),
    ),
  )
  ignore(
    governance.commit(
      native_guarded_request(
        governance_ref,
        "native-fork-governance-command-b",
        0L,
        native_guarded_event(
          governance_ref,
          "native-fork-governance-b",
          1L,
          None,
        ),
      ),
    ),
  )
  let request = try! GuardedCommitRequest::new(
    native_guarded_request(
      work_ref,
      "native-fork-work-command",
      0L,
      native_guarded_event(work_ref, "native-fork-work-1", 1L, None),
    ),
    [native_head_guard(expected_store.replay(governance_ref))],
  )
  let capability = try! FileSystemGuardedStore::new(work, [governance])
  guard capability.guarded_commit(request) is GuardedCommitRejected(receipt) else {
    fail("same-revision alternate governance fork was accepted")
  }
  assert_eq(receipt.expected_revision(), 1L)
  assert_eq(receipt.actual_revision(), 1L)
  assert_true(receipt.expected_head_digest() != receipt.actual_head_digest())
  receipt.validate_current(governance.replay(governance_ref))
  assert_eq(work.replay(work_ref).events().length(), 0)
}

///|
test "FLOW-4A guarded filesystem publication faults recover atomically" {
  for point in 1..<=8 {
    let root = native_fixture_root()
    let work_root = native_fixture_relative()
    let governance_root = native_fixture_relative()
    let work = try! FileSystemStore::open(root, work_root)
    let governance = try! FileSystemStore::open(root, governance_root)
    let work_ref = wb_ref(
      "workflow",
      "native-guarded-fault-work-\{point}",
      @utf8.encode("native-guarded-fault-work-\{point}"),
    )
    let governance_ref = wb_ref(
      "workflow",
      "native-guarded-fault-governance-\{point}",
      @utf8.encode("native-guarded-fault-governance-\{point}"),
    )
    ignore(
      governance.commit(
        native_guarded_request(
          governance_ref,
          "native-guarded-fault-governance-command-\{point}",
          0L,
          native_guarded_event(
            governance_ref,
            "native-guarded-fault-governance-event-\{point}",
            1L,
            None,
          ),
        ),
      ),
    )
    let request = try! GuardedCommitRequest::new(
      native_guarded_request(
        work_ref,
        "native-guarded-fault-work-command-\{point}",
        0L,
        native_guarded_event(
          work_ref,
          "native-guarded-fault-work-event-\{point}",
          1L,
          None,
        ),
      ),
      [native_head_guard(governance.replay(governance_ref))],
    )
    let capability = try! FileSystemGuardedStore::new(work, [governance])
    set_native_fault_point(point)
    try capability.guarded_commit(request) catch {
      IoFailure(operation="fault_injection", status~) =>
        assert_eq(status, point)
      error => fail("unexpected guarded fault error: \{to_repr(error)}")
    } noraise {
      _ => fail("expected guarded publication fault")
    }
    let restarted = try! FileSystemStore::open(root, work_root)
    let expected = if point <= 6 { 0 } else { 1 }
    assert_eq(restarted.replay(work_ref).events().length(), expected)
  }
}

///|
test "FLOW-4A filesystem registry blocks raw bypass and survives restart" {
  let root = native_fixture_root()
  let work_root = native_fixture_relative()
  let governance_root = native_fixture_relative()
  let work = try! FileSystemStore::open(root, work_root)
  let governance = try! FileSystemStore::open(root, governance_root)
  let work_ref = wb_ref(
    "workflow", "native-registry-work", b"native-registry-work",
  )
  let governance_ref = wb_ref(
    "workflow", "native-registry-governance", b"native-registry-governance",
  )
  let first = native_guarded_event(
    governance_ref,
    "native-registry-governance-1",
    1L,
    None,
  )
  ignore(
    governance.commit(
      native_guarded_request(
        governance_ref, "native-registry-governance-command-1", 0L, first,
      ),
    ),
  )
  let mutation = native_guarded_request(
    work_ref,
    "native-registry-work-command",
    0L,
    native_guarded_event(work_ref, "native-registry-work-1", 1L, None),
  )
  let guarded = try! GuardedCommitRequest::new(mutation, [
    native_head_guard(governance.replay(governance_ref)),
  ])
  let activation = work.activate_guarded_workflow(work_ref, [governance], [
    governance_ref,
  ])
  assert_eq(activation.activation_revision(), 0L)
  try ignore(work.commit(mutation)) catch {
    GuardedCommitRequired(
      workflow_id="native-registry-work",
      key="native-registry-work-command",
      binding_digest~
    ) => assert_eq(binding_digest, activation.registry_digest().text())
    error => fail("unexpected filesystem raw rejection: \{to_repr(error)}")
  } noraise {
    _ => fail("registered filesystem root accepted raw mutation")
  }
  let bound = try! RegistryBoundFileSystemStore::new(work, activation)
  guard bound.guarded_commit(guarded) is GuardedCommitSucceeded(original) else {
    fail("registry-bound filesystem commit failed")
  }
  let identical = work.activate_guarded_workflow(work_ref, [governance], [
    governance_ref,
  ])
  assert_true(identical.canonical_bytes() == activation.canonical_bytes())
  assert_eq(identical.activation_revision(), 0L)
  let second = native_guarded_event(
    governance_ref,
    "native-registry-governance-2",
    2L,
    Some(first.event_ref().digest()),
  )
  ignore(
    governance.commit(
      native_guarded_request(
        governance_ref, "native-registry-governance-command-2", 1L, second,
      ),
    ),
  )
  let restarted = try! RegistryBoundFileSystemStore::new(
    try! FileSystemStore::open(root, work_root),
    activation,
  )
  guard restarted.guarded_commit(guarded) is GuardedCommitSucceeded(duplicate) else {
    fail("registry-bound restart lost exact guarded idempotency")
  }
  assert_true(original == duplicate)
  assert_eq(restarted.replay(work_ref).events().length(), 1)
}

///|
test "FLOW-4A filesystem registry rejects shadow root and stale real guard" {
  let root = native_fixture_root()
  let work = try! FileSystemStore::open(root, native_fixture_relative())
  let governance = try! FileSystemStore::open(root, native_fixture_relative())
  let shadow = try! FileSystemStore::open(root, native_fixture_relative())
  let work_ref = wb_ref(
    "workflow", "native-registry-shadow-work", b"native-registry-shadow-work",
  )
  let governance_ref = wb_ref(
    "workflow", "native-registry-shadow-governance", b"native-registry-shadow-governance",
  )
  let first = native_guarded_event(
    governance_ref,
    "native-registry-shadow-governance-1",
    1L,
    None,
  )
  let first_request = native_guarded_request(
    governance_ref, "native-registry-shadow-governance-command-1", 0L, first,
  )
  ignore(governance.commit(first_request))
  ignore(shadow.commit(first_request))
  let mutation = native_guarded_request(
    work_ref,
    "native-registry-shadow-work-command",
    0L,
    native_guarded_event(work_ref, "native-registry-shadow-work-1", 1L, None),
  )
  let guarded = try! GuardedCommitRequest::new(mutation, [
    native_head_guard(governance.replay(governance_ref)),
  ])
  let activation = work.activate_guarded_workflow(work_ref, [governance], [
    governance_ref,
  ])
  let substituted = try! FileSystemGuardedStore::new(work, [shadow])
  try substituted.guarded_commit(guarded) catch {
    GuardedBindingConflict(field="guard_set", ..) => ()
    error => fail("unexpected shadow-root rejection: \{to_repr(error)}")
  } noraise {
    _ => fail("shadow governance root satisfied authoritative registry")
  }
  try
    work.activate_guarded_workflow(work_ref, [shadow], [governance_ref])
  catch {
    GuardedBindingConflict(field="binding_configuration", ..) => ()
    error => fail("unexpected filesystem rebind rejection: \{to_repr(error)}")
  } noraise {
    _ => fail("active filesystem binding was silently rebound")
  }
  let second = native_guarded_event(
    governance_ref,
    "native-registry-shadow-governance-2",
    2L,
    Some(first.event_ref().digest()),
  )
  ignore(
    governance.commit(
      native_guarded_request(
        governance_ref, "native-registry-shadow-governance-command-2", 1L, second,
      ),
    ),
  )
  let bound = try! RegistryBoundFileSystemStore::new(work, activation)
  guard bound.guarded_commit(guarded) is GuardedCommitRejected(receipt) else {
    fail("advanced authoritative guard did not stale filesystem mutation")
  }
  assert_eq(receipt.expected_revision(), 1L)
  assert_eq(receipt.actual_revision(), 2L)
  assert_eq(work.replay(work_ref).events().length(), 0)
}

///|
test "FLOW-4A filesystem classified guarded commit survives cross-root restart" {
  let root = native_fixture_root()
  let work_root = native_fixture_relative()
  let governance_root = native_fixture_relative()
  let work = try! FileSystemStore::open(root, work_root)
  let governance = try! FileSystemStore::open(root, governance_root)
  let work_ref = wb_ref(
    "workflow", "native-classified-work", b"native-classified-work",
  )
  let governance_ref = wb_ref(
    "workflow", "native-classified-governance", b"native-classified-governance",
  )
  let governance_event = native_guarded_event(
    governance_ref,
    "native-classified-governance-event",
    1L,
    None,
  )
  ignore(
    governance.commit(
      native_guarded_request(
        governance_ref, "native-classified-governance-command", 0L, governance_event,
      ),
    ),
  )
  let guarded = try! GuardedCommitRequest::new(
    native_guarded_request(
      work_ref,
      "native-classified-work-command",
      0L,
      native_guarded_event(work_ref, "native-classified-work-event", 1L, None),
    ),
    [native_head_guard(governance.replay(governance_ref))],
  )
  let activation = work.activate_guarded_workflow(work_ref, [governance], [
    governance_ref,
  ])
  let bound = try! RegistryBoundFileSystemStore::new(work, activation)
  guard bound.classified_guarded_commit(guarded) is FreshlyApplied(first) else {
    fail("filesystem classified commit was not fresh")
  }
  let restarted = try! RegistryBoundFileSystemStore::new(
    try! FileSystemStore::open(root, work_root),
    activation,
  )
  guard restarted.classified_guarded_commit(guarded) is AlreadyCommitted(second) else {
    fail("filesystem classified retry was not already committed")
  }
  assert_true(first == second)
  assert_eq(restarted.replay(work_ref).events().length(), 1)
  let boundary = restarted.replay(work_ref).committed_batches()[0]
  assert_eq(boundary.guards().length(), 1)
  assert_true(
    boundary.guards()[0].canonical_bytes() ==
    guarded.guards()[0].canonical_bytes(),
  )
}

///|
test "FLOW-4A filesystem registry missing and corrupt markers fail closed" {
  let root = native_fixture_root()
  let work_root = native_fixture_relative()
  let work = try! FileSystemStore::open(root, work_root)
  let governance = try! FileSystemStore::open(root, native_fixture_relative())
  let work_ref = wb_ref(
    "workflow", "native-registry-corrupt-work", b"native-registry-corrupt-work",
  )
  let governance_ref = wb_ref(
    "workflow", "native-registry-corrupt-governance", b"native-registry-corrupt-governance",
  )
  let mutation = native_guarded_request(
    work_ref,
    "native-registry-corrupt-work-command",
    0L,
    native_guarded_event(work_ref, "native-registry-corrupt-work-1", 1L, None),
  )
  let activation = work.activate_guarded_workflow(work_ref, [governance], [
    governance_ref,
  ])
  let binding = activation.binding
  let marker = guarded_binding_marker_name(binding)
  let marker_path = root + "/" + work_root + "/" + marker
  assert_eq(native_fixture_unlink(@utf8.encode(marker_path)), 0)
  try ignore(work.commit(mutation)) catch {
    GuardedRegistryMissing(name~) => assert_eq(name, marker)
    error => fail("unexpected missing-marker raw error: \{to_repr(error)}")
  } noraise {
    _ => fail("missing registry marker reopened raw mutation")
  }
  try RegistryBoundFileSystemStore::new(work, activation) catch {
    GuardedRegistryMissing(name~) => assert_eq(name, marker)
    error =>
      fail("unexpected missing-marker capability error: \{to_repr(error)}")
  } noraise {
    _ => fail("missing registry marker constructed official capability")
  }
  let recovered = work.activate_guarded_workflow(work_ref, [governance], [
    governance_ref,
  ])
  assert_true(recovered.canonical_bytes() == activation.canonical_bytes())
  assert_eq(native_fixture_unlink(@utf8.encode(marker_path)), 0)
  store_raw(work, marker, b"truncated")
  try ignore(work.commit(mutation)) catch {
    GuardedRegistryCorrupt(name~) => assert_eq(name, marker)
    error => fail("unexpected corrupt-marker raw error: \{to_repr(error)}")
  } noraise {
    _ => fail("corrupt registry marker reopened raw mutation")
  }
  try RegistryBoundFileSystemStore::new(work, activation) catch {
    GuardedRegistryCorrupt(name~) => assert_eq(name, marker)
    error =>
      fail("unexpected corrupt-marker capability error: \{to_repr(error)}")
  } noraise {
    _ => fail("corrupt registry marker constructed official capability")
  }
}

///|
test "FLOW-4A filesystem registry migrates existing root and rejects relocated copy" {
  let root = native_fixture_root()
  let work_root = native_fixture_relative()
  let work = try! FileSystemStore::open(root, work_root)
  let governance = try! FileSystemStore::open(root, native_fixture_relative())
  let work_ref = wb_ref(
    "workflow", "native-registry-migration-work", b"native-registry-migration-work",
  )
  let governance_ref = wb_ref(
    "workflow", "native-registry-migration-governance", b"native-registry-migration-governance",
  )
  let first = native_guarded_event(
    work_ref,
    "native-registry-migration-work-1",
    1L,
    None,
  )
  let first_request = native_guarded_request(
    work_ref, "native-registry-migration-command-1", 0L, first,
  )
  ignore(work.commit(first_request))
  let activation = work.activate_guarded_workflow(work_ref, [governance], [
    governance_ref,
  ])
  assert_eq(activation.activation_revision(), 1L)
  try ignore(work.commit(first_request)) catch {
    GuardedCommitRequired(key="native-registry-migration-command-1", ..) => ()
    error =>
      fail("unexpected migrated filesystem retry error: \{to_repr(error)}")
  } noraise {
    _ => fail("migrated filesystem accepted exact raw retry")
  }
  let second = native_guarded_event(
    work_ref,
    "native-registry-migration-work-2",
    2L,
    Some(first.event_ref().digest()),
  )
  let second_request = native_guarded_request(
    work_ref, "native-registry-migration-command-2", 1L, second,
  )
  let guarded = try! GuardedCommitRequest::new(second_request, [
    native_head_guard(governance.replay(governance_ref)),
  ])
  let bound = try! RegistryBoundFileSystemStore::new(work, activation)
  guard bound.guarded_commit(guarded) is GuardedCommitSucceeded(_) else {
    fail("migrated filesystem guarded append failed")
  }

  let copied_root = native_fixture_relative()
  let copied_shell = try! FileSystemStore::open(root, copied_root)
  assert_true(copy_native_store_bytes(work, copied_shell, false) is None)
  let copied = try! FileSystemStore::open(root, copied_root)
  try ignore(copied.commit(second_request)) catch {
    GuardedBindingConflict(field="filesystem_root_identity", ..) => ()
    error => fail("unexpected relocated raw error: \{to_repr(error)}")
  } noraise {
    _ => fail("relocated authoritative root silently accepted raw mutation")
  }
  try RegistryBoundFileSystemStore::new(copied, activation) catch {
    GuardedBindingConflict(field="activation_receipt_store", ..) => ()
    error => fail("unexpected relocated receipt error: \{to_repr(error)}")
  } noraise {
    _ => fail("relocated authoritative root accepted old activation receipt")
  }
}
