///|
fn wb_ref(kind : String, id : String, seed : Bytes) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(
    kind,
    id,
    "1.0.0",
    @contracts.sha256_digest(seed).text(),
  )
}

///|
fn wb_envelope(id : String, payload : Bytes) -> @contracts.WireEnvelope {
  let workflow = wb_ref("workflow", "workflow-wb", b"workflow-wb")
  let schema = try! @contracts.SchemaRef::new(
    "neutral.storage",
    "1.0.0",
    "opaque-value",
    "1.0.0",
    @contracts.sha256_digest(b"schema").text(),
  )
  try! @contracts.WireEnvelope::new(
    "neutral.storage",
    "1.0.0",
    id,
    "opaque-value",
    wb_ref("subject", id, @utf8.encode(id)),
    schema,
    payload,
    "neutral-writer",
    "1.0.0",
    [],
    [],
    run_ref=workflow,
  )
}

///|
fn wb_event(
  id : String,
  sequence : Int64,
  previous : @contracts.ContentDigest?,
) -> WorkflowEvent {
  match previous {
    None =>
      try! WorkflowEvent::new(
        "1.0.0",
        "1.0.0",
        wb_ref("workflow", "workflow-wb", b"workflow-wb"),
        id,
        sequence,
        sequence,
        "event-key-\{id}",
        wb_envelope("envelope-\{id}", @utf8.encode(id)),
        [],
      )
    Some(previous) =>
      try! WorkflowEvent::new(
        "1.0.0",
        "1.0.0",
        wb_ref("workflow", "workflow-wb", b"workflow-wb"),
        id,
        sequence,
        sequence,
        "event-key-\{id}",
        wb_envelope("envelope-\{id}", @utf8.encode(id)),
        [],
        previous_event_digest=previous,
      )
  }
}

///|
fn wb_changed(bytes : Bytes, offset : Int) -> Bytes {
  let changed = bytes.to_array()
  changed[offset] = changed[offset] ^ 1
  Bytes::from_array(changed)
}

///|
fn wb_changed_ascii(bytes : Bytes, text : String, replacement : Byte) -> Bytes {
  let offset = bytes.find(@utf8.encode(text)).unwrap()
  let changed = bytes.to_array()
  changed[offset] = replacement
  Bytes::from_array(changed)
}

///|
test "FLOW-4A self-addressed event bytes roundtrip exactly" {
  let event = wb_event("event-1", 1L, None)
  assert_true(decode_event(event.canonical_bytes()) == event)
  assert_true(
    event.event_ref.digest() ==
    @contracts.sha256_digest(event_signing_bytes(event)),
  )
}

///|
test "FLOW-4A unsupported event record version is typed during replay decode" {
  let event = wb_event("event-1", 1L, None)
  let outer = StorageReader::new(event.canonical_bytes())
  let signing = outer.read_bytes()
  let digest = outer.read_string()
  let writer = StorageWriter::new()
  writer.write_bytes(wb_changed_ascii(signing, "1.0.0", b'2'))
  writer.write_string(digest)
  try decode_event(writer.finish()) catch {
    UnsupportedVersion(record_kind~, version~) => {
      assert_eq(record_kind, "workflow_event")
      assert_eq(version, "2.0.0")
    }
    _ => fail("unexpected unsupported event version error")
  } noraise {
    _ => fail("expected unsupported event version")
  }
}

///|
test "FLOW-4A event digest tamper is typed" {
  let event = wb_event("event-1", 1L, None)
  let bytes = event.canonical_bytes()
  try decode_event(wb_changed(bytes, bytes.length() - 1)) catch {
    ValidationFailure(_) | DigestMismatch(_) => ()
    _ => fail("unexpected event tamper error")
  } noraise {
    _ => fail("expected event tamper rejection")
  }
}

///|
test "FLOW-4A ordered evidence tamper is covered by the event digest" {
  let evidence = try! @contracts.EvidenceRef::new(
    wb_ref("evidence", "evidence-1", b"evidence-1"),
    wb_ref("provenance", "source", b"source"),
    @contracts.sha256_digest(b"observed").text(),
  )
  let event = try! WorkflowEvent::new(
    "1.0.0",
    "1.0.0",
    wb_ref("workflow", "workflow-wb", b"workflow-wb"),
    "event-evidence",
    1L,
    1L,
    "event-evidence-key",
    wb_envelope("event-evidence-envelope", b"payload"),
    [evidence],
  )
  let signing = event_signing_bytes(event)
  let tampered = wb_changed_ascii(signing, "evidence-1", b'E')
  let writer = StorageWriter::new()
  writer.write_bytes(tampered)
  writer.write_string(event.event_ref.digest().text())
  try decode_event(writer.finish()) catch {
    ValidationFailure(_) | DigestMismatch(_) => ()
    _ => fail("unexpected evidence tamper error")
  } noraise {
    _ => fail("expected evidence tamper rejection")
  }
}

///|
test "FLOW-4A envelope and reference tamper cannot survive event framing" {
  let event = wb_event("event-1", 1L, None)
  let signing = event_signing_bytes(event)
  let envelope_offset = signing.find(b"envelope-event-1").unwrap()
  let tampered_signing = wb_changed(signing, envelope_offset)
  let writer = StorageWriter::new()
  writer.write_bytes(tampered_signing)
  writer.write_string(event.event_ref.digest().text())
  try decode_event(writer.finish()) catch {
    ValidationFailure(_) | DigestMismatch(_) => ()
    _ => fail("unexpected nested tamper error")
  } noraise {
    _ => fail("expected nested tamper rejection")
  }
}

///|
test "FLOW-4A outbox intent is self-addressed and tamper-evident" {
  let event = wb_event("event-1", 1L, None)
  let intent = try! OutboxIntent::new(
    "1.0.0",
    "1.0.0",
    "intent-1",
    event.workflow,
    event.event_ref,
    "intent-key-1",
    wb_envelope("intent-envelope-1", b"intent"),
    [],
  )
  assert_true(decode_intent(intent.canonical_bytes()) == intent)
  assert_true(
    intent.intent_ref.digest() ==
    @contracts.sha256_digest(intent_signing_bytes(intent)),
  )
  let bytes = intent.canonical_bytes()
  try decode_intent(wb_changed(bytes, bytes.length() - 1)) catch {
    ValidationFailure(_) | DigestMismatch(_) => ()
    _ => fail("unexpected intent tamper error")
  } noraise {
    _ => fail("expected intent tamper rejection")
  }
}

///|
test "FLOW-7 Phase1A committed first-batch digest corruption is storage-verified" {
  let event = wb_event("event-1", 1L, None)
  let request = try! CommitRequest::new(
    "1.0.0",
    "1.0.0",
    event.workflow,
    0L,
    "command-1",
    [event],
    [],
  )
  let store = MemoryStore::new()
  ignore(store.commit(request))
  let bytes = store.batches[0]
  let outer = StorageReader::new(bytes)
  let committed_body = outer.read_bytes()
  ignore(outer.read_string())
  outer.require_end()
  let corrupt_digest_writer = StorageWriter::new()
  corrupt_digest_writer.write_bytes(committed_body)
  corrupt_digest_writer.write_string(
    @contracts.sha256_digest(b"corrupt-first-batch-digest").text(),
  )
  store.batches[0] = corrupt_digest_writer.finish()
  try store.replay(event.workflow) catch {
    DigestMismatch(record_kind="commit_batch", ..) => ()
    _ => fail("unexpected committed first-batch digest error")
  } noraise {
    _ => fail("authoritative replay accepted corrupted first-batch digest")
  }
}

///|
test "FLOW-4A batch framing rejects partial and corrupt committed bytes" {
  let event = wb_event("event-1", 1L, None)
  let request = try! CommitRequest::new(
    "1.0.0",
    "1.0.0",
    event.workflow,
    0L,
    "command-1",
    [event],
    [],
  )
  let batch = make_stored_batch(request, 1L, 0L)
  let bytes = encode_batch(batch)
  assert_eq(encode_batch(decode_batch(bytes)), bytes)
  try decode_batch(bytes[0:bytes.length() - 1].to_owned()) catch {
    ValidationFailure(_) | DigestMismatch(_) => ()
    _ => fail("unexpected partial batch error")
  } noraise {
    _ => fail("expected partial batch rejection")
  }
  try decode_batch(wb_changed(bytes, bytes.length() / 2)) catch {
    ValidationFailure(_) | DigestMismatch(_) => ()
    _ => fail("unexpected corrupt batch error")
  } noraise {
    _ => fail("expected corrupt batch rejection")
  }
}

///|
test "FLOW-4A checkpoint self-addressing covers boundary and snapshot" {
  let event = wb_event("event-1", 1L, None)
  let checkpoint = try! CheckpointRecord::new(
    "1.0.0",
    "1.0.0",
    "1.0.0",
    "checkpoint-1",
    event.workflow,
    1L,
    1L,
    wb_envelope("snapshot-1", b"snapshot"),
    [],
    last_event_digest=event.event_ref.digest(),
  )
  assert_true(decode_checkpoint(checkpoint.canonical_bytes()) == checkpoint)
  assert_true(
    checkpoint.checkpoint_ref.digest() ==
    @contracts.sha256_digest(checkpoint_signing_bytes(checkpoint)),
  )
}

///|
test "FLOW-4A unsupported checkpoint projection version is typed" {
  let event = wb_event("event-1", 1L, None)
  let checkpoint = try! CheckpointRecord::new(
    "1.0.0",
    "1.0.0",
    "1.0.0",
    "checkpoint-1",
    event.workflow,
    1L,
    1L,
    wb_envelope("snapshot-1", b"snapshot"),
    [],
    last_event_digest=event.event_ref.digest(),
  )
  let outer = StorageReader::new(checkpoint.canonical_bytes())
  let signing = outer.read_bytes()
  let digest = outer.read_string()
  let first_version = signing.find(@utf8.encode("1.0.0")).unwrap()
  let second_view = signing[first_version + 1:]
  let second_version = first_version +
    1 +
    second_view.find(@utf8.encode("1.0.0")).unwrap()
  let third_view = signing[second_version + 1:]
  let projection_offset = second_version +
    1 +
    third_view.find(@utf8.encode("1.0.0")).unwrap()
  let changed = signing.to_array()
  changed[projection_offset] = b'2'
  let writer = StorageWriter::new()
  writer.write_bytes(Bytes::from_array(changed))
  writer.write_string(digest)
  try decode_checkpoint(writer.finish()) catch {
    UnsupportedVersion(record_kind~, version~) => {
      assert_eq(record_kind, "checkpoint_projection")
      assert_eq(version, "2.0.0")
    }
    _ => fail("unexpected checkpoint projection error")
  } noraise {
    _ => fail("expected unsupported checkpoint projection")
  }
}

///|
test "FLOW-4A canonical framing is injective for adjacent fields" {
  let first = StorageWriter::new()
  first.write_string("ab")
  first.write_string("c")
  let second = StorageWriter::new()
  second.write_string("a")
  second.write_string("bc")
  assert_true(first.finish() != second.finish())
}
