///|
let event_magic : Bytes = b"MF4AEVT1"

///|
let intent_magic : Bytes = b"MF4AINT1"

///|
let checkpoint_magic : Bytes = b"MF4ACHK1"

///|
fn self_record_ref(
  kind : String,
  id : String,
  version : @contracts.Version,
  digest : @contracts.ContentDigest,
) -> @contracts.RecordRef raise StorageError {
  new_contract_record_ref(kind, id, version.text(), digest.text(), kind)
}

///|
fn write_evidence(
  writer : StorageWriter,
  evidence : ReadOnlyArray[@contracts.EvidenceRef],
) -> Unit raise StorageError {
  writer.write_count(evidence.length())
  for value in evidence {
    writer.write_bytes(encode_evidence_ref(value))
  }
}

///|
fn read_evidence(
  reader : StorageReader,
) -> ReadOnlyArray[@contracts.EvidenceRef] raise StorageError {
  let values : Array[@contracts.EvidenceRef] = []
  let count = reader.read_count()
  for _ in 0..<count {
    values.push(decode_evidence_ref(reader.read_bytes()))
  }
  ReadOnlyArray::from_array(values)
}

///|
/// A validated, self-addressed event. Its signing bytes omit only the digest
/// of `event_ref`; the event identity, exact workflow reference, payload,
/// ordered evidence, versions, sequence, revision, idempotency key, and prior
/// digest remain covered.
pub struct WorkflowEvent {
  record_version : @contracts.Version
  schema_version : @contracts.Version
  workflow : @contracts.RecordRef
  event_ref : @contracts.RecordRef
  sequence : Int64
  revision : Int64
  idempotency_key : String
  payload : @contracts.WireEnvelope
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  previous_event_digest : @contracts.ContentDigest?
}

///|
fn event_signing_bytes(value : WorkflowEvent) -> Bytes {
  let writer = StorageWriter::new()
  try! writer.write_bytes(event_magic)
  try! writer.write_string(value.record_version.text())
  try! writer.write_string(value.schema_version.text())
  try! writer.write_bytes(encode_record_ref(value.workflow, false))
  try! writer.write_bytes(encode_record_ref(value.event_ref, true))
  writer.write_int64(value.sequence)
  writer.write_int64(value.revision)
  try! writer.write_string(value.idempotency_key)
  try! writer.write_bytes(@contracts.encode_wire_envelope(value.payload))
  try! write_evidence(writer, value.evidence)
  try! write_optional_digest(writer, value.previous_event_digest)
  writer.finish()
}

///|
fn build_event(
  record_version_text : String,
  schema_version_text : String,
  workflow : @contracts.RecordRef,
  event_id : String,
  sequence : Int64,
  revision : Int64,
  idempotency_key : String,
  payload : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  previous_event_digest : @contracts.ContentDigest?,
  supplied_digest : @contracts.ContentDigest?,
) -> WorkflowEvent raise StorageError {
  let record_version = storage_version(record_version_text, "workflow_event")
  let schema_version = storage_version(
    schema_version_text, "workflow_event_schema",
  )
  require_storage_text(event_id, "event_id")
  require_storage_text(idempotency_key, "event_idempotency_key")
  if sequence <= 0L {
    raise ValidationFailure(field="event_sequence")
  }
  if revision <= 0L {
    raise ValidationFailure(field="event_revision")
  }
  if (sequence == 1L && previous_event_digest is Some(_)) ||
    (sequence > 1L && previous_event_digest is None) {
    raise ValidationFailure(field="previous_event_digest")
  }
  let provisional_ref = self_record_ref(
    "workflow-event",
    event_id,
    record_version,
    @contracts.sha256_digest(b""),
  )
  let provisional : WorkflowEvent = {
    record_version,
    schema_version,
    workflow,
    event_ref: provisional_ref,
    sequence,
    revision,
    idempotency_key,
    payload,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    previous_event_digest,
  }
  let digest = @contracts.sha256_digest(event_signing_bytes(provisional))
  match supplied_digest {
    Some(expected) if expected != digest =>
      raise DigestMismatch(
        record_kind="workflow_event",
        record_id=event_id,
        expected=expected.text(),
        actual=digest.text(),
      )
    _ => ()
  }
  {
    ..provisional,
    event_ref: self_record_ref(
      "workflow-event", event_id, record_version, digest,
    ),
  }
}

///|
pub fn WorkflowEvent::new(
  record_version : String,
  schema_version : String,
  workflow : @contracts.RecordRef,
  event_id : String,
  sequence : Int64,
  revision : Int64,
  idempotency_key : String,
  payload : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  previous_event_digest? : @contracts.ContentDigest,
) -> WorkflowEvent raise StorageError {
  build_event(
    record_version,
    schema_version,
    workflow,
    event_id,
    sequence,
    revision,
    idempotency_key,
    payload,
    evidence,
    previous_event_digest,
    None,
  )
}

///|
pub fn WorkflowEvent::record_version(
  self : WorkflowEvent,
) -> @contracts.Version {
  self.record_version
}

///|
pub fn WorkflowEvent::schema_version(
  self : WorkflowEvent,
) -> @contracts.Version {
  self.schema_version
}

///|
pub fn WorkflowEvent::workflow(self : WorkflowEvent) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn WorkflowEvent::event_ref(self : WorkflowEvent) -> @contracts.RecordRef {
  self.event_ref
}

///|
pub fn WorkflowEvent::sequence(self : WorkflowEvent) -> Int64 {
  self.sequence
}

///|
pub fn WorkflowEvent::revision(self : WorkflowEvent) -> Int64 {
  self.revision
}

///|
pub fn WorkflowEvent::idempotency_key(self : WorkflowEvent) -> String {
  self.idempotency_key
}

///|
pub fn WorkflowEvent::payload(self : WorkflowEvent) -> @contracts.WireEnvelope {
  self.payload
}

///|
pub fn WorkflowEvent::evidence(
  self : WorkflowEvent,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn WorkflowEvent::previous_event_digest(
  self : WorkflowEvent,
) -> @contracts.ContentDigest? {
  self.previous_event_digest
}

///|
pub fn WorkflowEvent::canonical_bytes(self : WorkflowEvent) -> Bytes {
  let writer = StorageWriter::new()
  try! writer.write_bytes(event_signing_bytes(self))
  try! writer.write_string(self.event_ref.digest().text())
  writer.finish()
}

///|
pub impl Eq for WorkflowEvent with fn equal(left, right) {
  left.canonical_bytes() == right.canonical_bytes()
}

///|
fn decode_event(bytes : Bytes) -> WorkflowEvent raise StorageError {
  let outer = StorageReader::new(bytes)
  let signing = outer.read_bytes()
  let supplied = parse_content_digest(outer.read_string(), "workflow_event")
  outer.require_end()
  let reader = StorageReader::new(signing)
  if reader.read_bytes() != event_magic {
    raise ValidationFailure(field="event_magic")
  }
  let record_version = reader.read_string()
  let schema_version = reader.read_string()
  ignore(storage_version(record_version, "workflow_event"))
  ignore(storage_version(schema_version, "workflow_event_schema"))
  let workflow = decode_record_ref(reader.read_bytes())
  let identity_reader = StorageReader::new(reader.read_bytes())
  let event_kind = identity_reader.read_string()
  let event_id = identity_reader.read_string()
  let identity_version = identity_reader.read_string()
  identity_reader.require_end()
  if event_kind != "workflow-event" || identity_version != record_version {
    raise ValidationFailure(field="event_reference")
  }
  let sequence = reader.read_int64()
  let revision = reader.read_int64()
  let key = reader.read_string()
  let payload = decode_contract_envelope(
    reader.read_bytes(),
    "workflow_event_payload",
  )
  let evidence = read_evidence(reader)
  let previous = read_optional_digest(reader)
  reader.require_end()
  build_event(
    record_version,
    schema_version,
    workflow,
    event_id,
    sequence,
    revision,
    key,
    payload,
    [
      for value in evidence => value
    ],
    previous,
    Some(supplied),
  )
}

///|
/// An immutable self-addressed outbox intent. It records opaque data only and
/// exposes no external-action, timing, retry, ownership, or state-transition
/// capability.
pub struct OutboxIntent {
  record_version : @contracts.Version
  schema_version : @contracts.Version
  intent_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  causative_event : @contracts.RecordRef
  idempotency_key : String
  payload : @contracts.WireEnvelope
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
}

///|
fn intent_signing_bytes(value : OutboxIntent) -> Bytes {
  let writer = StorageWriter::new()
  try! writer.write_bytes(intent_magic)
  try! writer.write_string(value.record_version.text())
  try! writer.write_string(value.schema_version.text())
  try! writer.write_bytes(encode_record_ref(value.intent_ref, true))
  try! writer.write_bytes(encode_record_ref(value.workflow, false))
  try! writer.write_bytes(encode_record_ref(value.causative_event, false))
  try! writer.write_string(value.idempotency_key)
  try! writer.write_bytes(@contracts.encode_wire_envelope(value.payload))
  try! write_evidence(writer, value.evidence)
  writer.finish()
}

///|
fn build_intent(
  record_version_text : String,
  schema_version_text : String,
  intent_id : String,
  workflow : @contracts.RecordRef,
  causative_event : @contracts.RecordRef,
  idempotency_key : String,
  payload : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  supplied_digest : @contracts.ContentDigest?,
) -> OutboxIntent raise StorageError {
  let record_version = storage_version(record_version_text, "outbox_intent")
  let schema_version = storage_version(
    schema_version_text, "outbox_intent_schema",
  )
  require_storage_text(intent_id, "intent_id")
  require_storage_text(idempotency_key, "intent_idempotency_key")
  if causative_event.kind() != "workflow-event" {
    raise ValidationFailure(field="causative_event")
  }
  let provisional : OutboxIntent = {
    record_version,
    schema_version,
    intent_ref: self_record_ref(
      "outbox-intent",
      intent_id,
      record_version,
      @contracts.sha256_digest(b""),
    ),
    workflow,
    causative_event,
    idempotency_key,
    payload,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
  }
  let digest = @contracts.sha256_digest(intent_signing_bytes(provisional))
  match supplied_digest {
    Some(expected) if expected != digest =>
      raise DigestMismatch(
        record_kind="outbox_intent",
        record_id=intent_id,
        expected=expected.text(),
        actual=digest.text(),
      )
    _ => ()
  }
  {
    ..provisional,
    intent_ref: self_record_ref(
      "outbox-intent", intent_id, record_version, digest,
    ),
  }
}

///|
pub fn OutboxIntent::new(
  record_version : String,
  schema_version : String,
  intent_id : String,
  workflow : @contracts.RecordRef,
  causative_event : @contracts.RecordRef,
  idempotency_key : String,
  payload : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
) -> OutboxIntent raise StorageError {
  build_intent(
    record_version,
    schema_version,
    intent_id,
    workflow,
    causative_event,
    idempotency_key,
    payload,
    evidence,
    None,
  )
}

///|
pub fn OutboxIntent::record_version(self : OutboxIntent) -> @contracts.Version {
  self.record_version
}

///|
pub fn OutboxIntent::schema_version(self : OutboxIntent) -> @contracts.Version {
  self.schema_version
}

///|
pub fn OutboxIntent::intent_ref(self : OutboxIntent) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn OutboxIntent::workflow(self : OutboxIntent) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn OutboxIntent::causative_event(
  self : OutboxIntent,
) -> @contracts.RecordRef {
  self.causative_event
}

///|
pub fn OutboxIntent::idempotency_key(self : OutboxIntent) -> String {
  self.idempotency_key
}

///|
pub fn OutboxIntent::payload(self : OutboxIntent) -> @contracts.WireEnvelope {
  self.payload
}

///|
pub fn OutboxIntent::evidence(
  self : OutboxIntent,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn OutboxIntent::canonical_bytes(self : OutboxIntent) -> Bytes {
  let writer = StorageWriter::new()
  try! writer.write_bytes(intent_signing_bytes(self))
  try! writer.write_string(self.intent_ref.digest().text())
  writer.finish()
}

///|
pub impl Eq for OutboxIntent with fn equal(left, right) {
  left.canonical_bytes() == right.canonical_bytes()
}

///|
fn decode_intent(bytes : Bytes) -> OutboxIntent raise StorageError {
  let outer = StorageReader::new(bytes)
  let signing = outer.read_bytes()
  let supplied = parse_content_digest(outer.read_string(), "outbox_intent")
  outer.require_end()
  let reader = StorageReader::new(signing)
  if reader.read_bytes() != intent_magic {
    raise ValidationFailure(field="intent_magic")
  }
  let record_version = reader.read_string()
  let schema_version = reader.read_string()
  ignore(storage_version(record_version, "outbox_intent"))
  ignore(storage_version(schema_version, "outbox_intent_schema"))
  let identity_reader = StorageReader::new(reader.read_bytes())
  let intent_kind = identity_reader.read_string()
  let intent_id = identity_reader.read_string()
  let identity_version = identity_reader.read_string()
  identity_reader.require_end()
  if intent_kind != "outbox-intent" || identity_version != record_version {
    raise ValidationFailure(field="intent_reference")
  }
  let workflow = decode_record_ref(reader.read_bytes())
  let event = decode_record_ref(reader.read_bytes())
  let key = reader.read_string()
  let payload = decode_contract_envelope(
    reader.read_bytes(),
    "outbox_intent_payload",
  )
  let evidence = read_evidence(reader)
  reader.require_end()
  build_intent(
    record_version,
    schema_version,
    intent_id,
    workflow,
    event,
    key,
    payload,
    [
      for value in evidence => value
    ],
    Some(supplied),
  )
}

///|
/// A derived checkpoint at an exact authoritative event boundary. Its signing
/// bytes omit only `checkpoint_ref.digest`; the identity and every referenced
/// digest remain covered.
pub struct CheckpointRecord {
  record_version : @contracts.Version
  schema_version : @contracts.Version
  projection_version : @contracts.Version
  checkpoint_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  event_sequence : Int64
  workflow_revision : Int64
  last_event_digest : @contracts.ContentDigest?
  snapshot : @contracts.WireEnvelope
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
}

///|
fn checkpoint_signing_bytes(value : CheckpointRecord) -> Bytes {
  let writer = StorageWriter::new()
  try! writer.write_bytes(checkpoint_magic)
  try! writer.write_string(value.record_version.text())
  try! writer.write_string(value.schema_version.text())
  try! writer.write_string(value.projection_version.text())
  try! writer.write_bytes(encode_record_ref(value.checkpoint_ref, true))
  try! writer.write_bytes(encode_record_ref(value.workflow, false))
  writer.write_int64(value.event_sequence)
  writer.write_int64(value.workflow_revision)
  try! write_optional_digest(writer, value.last_event_digest)
  try! writer.write_bytes(@contracts.encode_wire_envelope(value.snapshot))
  try! write_evidence(writer, value.evidence)
  writer.finish()
}

///|
fn build_checkpoint(
  record_version_text : String,
  schema_version_text : String,
  projection_version_text : String,
  checkpoint_id : String,
  workflow : @contracts.RecordRef,
  event_sequence : Int64,
  workflow_revision : Int64,
  last_event_digest : @contracts.ContentDigest?,
  snapshot : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  supplied_digest : @contracts.ContentDigest?,
) -> CheckpointRecord raise StorageError {
  let record_version = storage_version(record_version_text, "checkpoint_record")
  let schema_version = storage_version(schema_version_text, "checkpoint_schema")
  let projection_version = storage_version(
    projection_version_text, "checkpoint_projection",
  )
  require_storage_text(checkpoint_id, "checkpoint_id")
  if event_sequence < 0L || workflow_revision < 0L {
    raise ValidationFailure(field="checkpoint_boundary")
  }
  if (event_sequence == 0L && last_event_digest is Some(_)) ||
    (event_sequence > 0L && last_event_digest is None) {
    raise ValidationFailure(field="checkpoint_last_event_digest")
  }
  let provisional : CheckpointRecord = {
    record_version,
    schema_version,
    projection_version,
    checkpoint_ref: self_record_ref(
      "checkpoint-record",
      checkpoint_id,
      record_version,
      @contracts.sha256_digest(b""),
    ),
    workflow,
    event_sequence,
    workflow_revision,
    last_event_digest,
    snapshot,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
  }
  let digest = @contracts.sha256_digest(checkpoint_signing_bytes(provisional))
  match supplied_digest {
    Some(expected) if expected != digest =>
      raise DigestMismatch(
        record_kind="checkpoint_record",
        record_id=checkpoint_id,
        expected=expected.text(),
        actual=digest.text(),
      )
    _ => ()
  }
  {
    ..provisional,
    checkpoint_ref: self_record_ref(
      "checkpoint-record", checkpoint_id, record_version, digest,
    ),
  }
}

///|
pub fn CheckpointRecord::new(
  record_version : String,
  schema_version : String,
  projection_version : String,
  checkpoint_id : String,
  workflow : @contracts.RecordRef,
  event_sequence : Int64,
  workflow_revision : Int64,
  snapshot : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  last_event_digest? : @contracts.ContentDigest,
) -> CheckpointRecord raise StorageError {
  build_checkpoint(
    record_version,
    schema_version,
    projection_version,
    checkpoint_id,
    workflow,
    event_sequence,
    workflow_revision,
    last_event_digest,
    snapshot,
    evidence,
    None,
  )
}

///|
pub fn CheckpointRecord::record_version(
  self : CheckpointRecord,
) -> @contracts.Version {
  self.record_version
}

///|
pub fn CheckpointRecord::schema_version(
  self : CheckpointRecord,
) -> @contracts.Version {
  self.schema_version
}

///|
pub fn CheckpointRecord::projection_version(
  self : CheckpointRecord,
) -> @contracts.Version {
  self.projection_version
}

///|
pub fn CheckpointRecord::checkpoint_ref(
  self : CheckpointRecord,
) -> @contracts.RecordRef {
  self.checkpoint_ref
}

///|
pub fn CheckpointRecord::workflow(
  self : CheckpointRecord,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn CheckpointRecord::event_sequence(self : CheckpointRecord) -> Int64 {
  self.event_sequence
}

///|
pub fn CheckpointRecord::workflow_revision(self : CheckpointRecord) -> Int64 {
  self.workflow_revision
}

///|
pub fn CheckpointRecord::last_event_digest(
  self : CheckpointRecord,
) -> @contracts.ContentDigest? {
  self.last_event_digest
}

///|
pub fn CheckpointRecord::snapshot(
  self : CheckpointRecord,
) -> @contracts.WireEnvelope {
  self.snapshot
}

///|
pub fn CheckpointRecord::evidence(
  self : CheckpointRecord,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn CheckpointRecord::canonical_bytes(self : CheckpointRecord) -> Bytes {
  let writer = StorageWriter::new()
  try! writer.write_bytes(checkpoint_signing_bytes(self))
  try! writer.write_string(self.checkpoint_ref.digest().text())
  writer.finish()
}

///|
pub impl Eq for CheckpointRecord with fn equal(left, right) {
  left.canonical_bytes() == right.canonical_bytes()
}

///|
fn decode_checkpoint(bytes : Bytes) -> CheckpointRecord raise StorageError {
  let outer = StorageReader::new(bytes)
  let signing = outer.read_bytes()
  let supplied = parse_content_digest(outer.read_string(), "checkpoint_record")
  outer.require_end()
  let reader = StorageReader::new(signing)
  if reader.read_bytes() != checkpoint_magic {
    raise ValidationFailure(field="checkpoint_magic")
  }
  let record_version = reader.read_string()
  let schema_version = reader.read_string()
  let projection_version = reader.read_string()
  ignore(storage_version(record_version, "checkpoint_record"))
  ignore(storage_version(schema_version, "checkpoint_schema"))
  ignore(storage_version(projection_version, "checkpoint_projection"))
  let identity_reader = StorageReader::new(reader.read_bytes())
  let checkpoint_kind = identity_reader.read_string()
  let checkpoint_id = identity_reader.read_string()
  let identity_version = identity_reader.read_string()
  identity_reader.require_end()
  if checkpoint_kind != "checkpoint-record" ||
    identity_version != record_version {
    raise ValidationFailure(field="checkpoint_reference")
  }
  let workflow = decode_record_ref(reader.read_bytes())
  let event_sequence = reader.read_int64()
  let workflow_revision = reader.read_int64()
  let last_event_digest = read_optional_digest(reader)
  let snapshot = decode_contract_envelope(
    reader.read_bytes(),
    "checkpoint_snapshot",
  )
  let evidence = read_evidence(reader)
  reader.require_end()
  build_checkpoint(
    record_version,
    schema_version,
    projection_version,
    checkpoint_id,
    workflow,
    event_sequence,
    workflow_revision,
    last_event_digest,
    snapshot,
    [
      for value in evidence => value
    ],
    Some(supplied),
  )
}
