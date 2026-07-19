///|
let effects_record_version = "1.0.0"

///|
let effects_schema_version = "1.0.0"

///|
let effects_contract_id = "closed-loop.effects"

///|
let effects_producer_id = "effects-protocol"

///|
priv struct EffectsWriter {
  buffer : @buffer.Buffer
}

///|
fn EffectsWriter::new() -> EffectsWriter {
  { buffer: Buffer() }
}

///|
fn EffectsWriter::byte(self : EffectsWriter, value : Byte) -> Unit {
  self.buffer.write_byte(value)
}

///|
fn EffectsWriter::count(
  self : EffectsWriter,
  value : Int,
) -> Unit raise EffectsError {
  if value < 0 {
    raise MalformedRecord(field="negative_length")
  }
  self.buffer.write_uint_be(value.reinterpret_as_uint())
}

///|
fn EffectsWriter::int64(self : EffectsWriter, value : Int64) -> Unit {
  self.buffer.write_int64_be(value)
}

///|
fn EffectsWriter::bytes(
  self : EffectsWriter,
  value : Bytes,
) -> Unit raise EffectsError {
  self.count(value.length())
  self.buffer.write_bytes(value)
}

///|
fn EffectsWriter::string(
  self : EffectsWriter,
  value : String,
) -> Unit raise EffectsError {
  self.bytes(@utf8.encode(value))
}

///|
fn EffectsWriter::optional_string(
  self : EffectsWriter,
  value : String?,
) -> Unit raise EffectsError {
  match value {
    None => self.byte(0)
    Some(value) => {
      self.byte(1)
      self.string(value)
    }
  }
}

///|
fn EffectsWriter::optional_int64(self : EffectsWriter, value : Int64?) -> Unit {
  match value {
    None => self.byte(0)
    Some(value) => {
      self.byte(1)
      self.int64(value)
    }
  }
}

///|
fn EffectsWriter::finish(self : EffectsWriter) -> Bytes {
  self.buffer.to_bytes()
}

///|
fn require_text(value : String, field : String) -> Unit raise EffectsError {
  if value.trim().is_empty() || value != value.trim().to_owned() {
    raise InvalidState(field~)
  }
}

///|
fn effects_version() -> @contracts.Version {
  try! @contracts.Version::parse(effects_record_version)
}

///|
fn[T] first(values : ArrayView[T], predicate : (T) -> Bool) -> T? {
  match values.search_by(predicate) {
    Some(index) => Some(values[index])
    None => None
  }
}

///|
fn[T] copy_readonly(values : ReadOnlyArray[T]) -> Array[T] {
  [
    for value in values => value
  ]
}

///|
fn require_version(value : String, field : String) -> Unit raise EffectsError {
  if value != effects_record_version {
    raise UnsupportedVersion(field~, version=value)
  }
}

///|
fn write_ref(
  writer : EffectsWriter,
  value : @contracts.RecordRef,
) -> Unit raise EffectsError {
  writer.string(value.kind())
  writer.string(value.id())
  writer.string(value.version().text())
  writer.string(value.digest().text())
}

///|
fn write_optional_ref(
  writer : EffectsWriter,
  value : @contracts.RecordRef?,
) -> Unit raise EffectsError {
  match value {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value)
    }
  }
}

///|
fn write_evidence(
  writer : EffectsWriter,
  values : ArrayView[@contracts.EvidenceRef],
) -> Unit raise EffectsError {
  writer.count(values.length())
  for value in values {
    write_ref(writer, value.record())
    write_ref(writer, value.provenance_ref())
    writer.string(value.observed_digest().text())
    writer.optional_string(value.locator())
    writer.optional_string(value.media_type())
  }
}

///|
fn ordered_evidence_digest(
  tag : Bytes,
  values : ArrayView[@contracts.EvidenceRef],
) -> @contracts.ContentDigest {
  let writer = EffectsWriter::new()
  try! writer.bytes(tag)
  try! write_evidence(writer, values)
  @contracts.sha256_digest(writer.finish())
}

///|
fn same_evidence(
  left : ArrayView[@contracts.EvidenceRef],
  right : ArrayView[@contracts.EvidenceRef],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index, value in left {
    if value != right[index] {
      return false
    }
  }
  true
}

///|
fn self_ref(
  kind : String,
  id : String,
  digest : @contracts.ContentDigest,
) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(
    kind,
    id,
    effects_record_version,
    digest.text(),
  )
}

///|
fn same_record_identity(
  left : @contracts.RecordRef,
  right : @contracts.RecordRef,
) -> Bool {
  left.kind() == right.kind() &&
  left.id() == right.id() &&
  left.version() == right.version()
}

///|
fn effects_schema(kind : String) -> @contracts.SchemaRef {
  try! @contracts.SchemaRef::new(
    effects_contract_id,
    effects_record_version,
    kind,
    effects_schema_version,
    @contracts.sha256_digest(@utf8.encode("closed-loop.effects/{kind}/1")).text(),
  )
}

///|
fn event_envelope(
  id : String,
  kind : String,
  workflow : @contracts.RecordRef,
  subject : @contracts.RecordRef,
  payload : Bytes,
  evidence : Array[@contracts.EvidenceRef],
  attempt_ref : @contracts.RecordRef,
  causation_ref : String,
  idempotency_ref : String,
  previous_digest : @contracts.ContentDigest,
) -> @contracts.WireEnvelope raise {
  @contracts.WireEnvelope::new(
    effects_contract_id,
    effects_record_version,
    id,
    kind,
    subject,
    effects_schema(kind),
    payload,
    effects_producer_id,
    effects_record_version,
    [],
    evidence,
    run_ref=workflow,
    attempt_ref~,
    correlation_ref=workflow.id(),
    causation_ref~,
    idempotency_ref~,
    previous_digest~,
  )
}
