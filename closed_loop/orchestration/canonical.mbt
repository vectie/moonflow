///|
let orchestration_record_version = "1.0.0"

///|
let orchestration_record_version_v2 = "2.0.0"

///|
let orchestration_schema_version = "1.0.0"

///|
let orchestration_contract_id = "closed-loop.orchestration"

///|
let orchestration_producer_id = "orchestration-protocol"

///|
let int64_max = 9223372036854775807L

///|
priv struct OrchestrationWriter {
  buffer : @buffer.Buffer
}

///|
fn OrchestrationWriter::new() -> OrchestrationWriter {
  { buffer: Buffer() }
}

///|
fn OrchestrationWriter::byte(self : OrchestrationWriter, value : Byte) -> Unit {
  self.buffer.write_byte(value)
}

///|
fn OrchestrationWriter::count(
  self : OrchestrationWriter,
  value : Int,
) -> Unit raise OrchestrationError {
  if value < 0 {
    raise MalformedInput(field="negative_length")
  }
  self.buffer.write_uint_be(value.reinterpret_as_uint())
}

///|
fn OrchestrationWriter::int64(
  self : OrchestrationWriter,
  value : Int64,
) -> Unit {
  self.buffer.write_int64_be(value)
}

///|
fn OrchestrationWriter::bytes(
  self : OrchestrationWriter,
  value : Bytes,
) -> Unit raise OrchestrationError {
  self.count(value.length())
  self.buffer.write_bytes(value)
}

///|
fn OrchestrationWriter::string(
  self : OrchestrationWriter,
  value : String,
) -> Unit raise OrchestrationError {
  self.bytes(@utf8.encode(value))
}

///|
fn OrchestrationWriter::optional_int64(
  self : OrchestrationWriter,
  value : Int64?,
) -> Unit {
  match value {
    None => self.byte(0)
    Some(value) => {
      self.byte(1)
      self.int64(value)
    }
  }
}

///|
fn OrchestrationWriter::optional_digest(
  self : OrchestrationWriter,
  value : @contracts.ContentDigest?,
) -> Unit raise OrchestrationError {
  match value {
    None => self.byte(0)
    Some(value) => {
      self.byte(1)
      self.string(value.text())
    }
  }
}

///|
fn OrchestrationWriter::finish(self : OrchestrationWriter) -> Bytes {
  self.buffer.to_bytes()
}

///|
priv struct OrchestrationReader {
  data : Bytes
  mut offset : Int
}

///|
fn OrchestrationReader::new(
  data : Bytes,
) -> OrchestrationReader raise OrchestrationError {
  { data, offset: 0 }
}

///|
fn OrchestrationReader::remaining(
  self : OrchestrationReader,
) -> Int raise OrchestrationError {
  self.data.length() - self.offset
}

///|
fn OrchestrationReader::read_byte(
  self : OrchestrationReader,
) -> Byte raise OrchestrationError {
  if self.remaining() < 1 {
    raise MalformedInput(field="unexpected_end")
  }
  let value = self.data[self.offset]
  self.offset += 1
  value
}

///|
fn OrchestrationReader::read_count(
  self : OrchestrationReader,
) -> Int raise OrchestrationError {
  if self.remaining() < 4 {
    raise MalformedInput(field="unexpected_end")
  }
  let first = self.data[self.offset]
  if first >= 128 {
    raise MalformedInput(field="length_overflow")
  }
  let value = (first.to_int() << 24) |
    (self.data[self.offset + 1].to_int() << 16) |
    (self.data[self.offset + 2].to_int() << 8) |
    self.data[self.offset + 3].to_int()
  self.offset += 4
  value
}

///|
fn OrchestrationReader::read_int64(
  self : OrchestrationReader,
) -> Int64 raise OrchestrationError {
  if self.remaining() < 8 {
    raise MalformedInput(field="unexpected_end")
  }
  let mut value = 0UL
  for index = 0; index < 8; index = index + 1 {
    value = (value << 8) | self.data[self.offset + index].to_uint64()
  }
  self.offset += 8
  value.reinterpret_as_int64()
}

///|
fn OrchestrationReader::read_bytes(
  self : OrchestrationReader,
) -> Bytes raise OrchestrationError {
  let count = self.read_count()
  if self.remaining() < count {
    raise MalformedInput(field="unexpected_end")
  }
  let value = self.data[self.offset:self.offset + count].to_owned()
  self.offset += count
  value
}

///|
fn OrchestrationReader::read_string(
  self : OrchestrationReader,
) -> String raise OrchestrationError {
  @utf8.decode(self.read_bytes()) catch {
    _ => raise MalformedInput(field="invalid_utf8")
  }
}

///|
fn OrchestrationReader::read_optional_int64(
  self : OrchestrationReader,
) -> Int64? raise OrchestrationError {
  match self.read_byte() {
    0 => None
    1 => Some(self.read_int64())
    _ => raise MalformedInput(field="optional_int64_marker")
  }
}

///|
fn OrchestrationReader::read_digest(
  self : OrchestrationReader,
) -> @contracts.ContentDigest raise OrchestrationError {
  @contracts.ContentDigest::parse(self.read_string()) catch {
    _ => raise MalformedInput(field="digest")
  }
}

///|
fn OrchestrationReader::read_optional_digest(
  self : OrchestrationReader,
) -> @contracts.ContentDigest? raise OrchestrationError {
  match self.read_byte() {
    0 => None
    1 => Some(self.read_digest())
    _ => raise MalformedInput(field="optional_digest_marker")
  }
}

///|
fn OrchestrationReader::read_ref(
  self : OrchestrationReader,
) -> @contracts.RecordRef raise OrchestrationError {
  let kind = self.read_string()
  let id = self.read_string()
  let version = self.read_string()
  let digest_text = self.read_string()
  @contracts.RecordRef::new(kind, id, version, digest_text) catch {
    _ => raise MalformedInput(field="record_ref")
  }
}

///|
fn OrchestrationReader::read_optional_ref(
  self : OrchestrationReader,
) -> @contracts.RecordRef? raise OrchestrationError {
  match self.read_byte() {
    0 => None
    1 => Some(self.read_ref())
    _ => raise MalformedInput(field="optional_ref_marker")
  }
}

///|
fn OrchestrationReader::read_optional_string(
  self : OrchestrationReader,
  field : String,
) -> String? raise OrchestrationError {
  match self.read_byte() {
    0 => None
    1 => Some(self.read_string())
    _ => raise MalformedInput(field~)
  }
}

///|
fn OrchestrationReader::read_evidence(
  self : OrchestrationReader,
) -> Array[@contracts.EvidenceRef] raise OrchestrationError {
  let count = self.read_count()
  if count > 10000 {
    raise MalformedInput(field="evidence_count")
  }
  let evidence : Array[@contracts.EvidenceRef] = Array::new(capacity=count)
  for index = 0; index < count; index = index + 1 {
    let record = self.read_ref()
    let provenance = self.read_ref()
    let observed_digest_text = self.read_string()
    let locator = self.read_optional_string("evidence_locator_marker")
    let media_type = self.read_optional_string("evidence_media_type_marker")
    let item = @contracts.EvidenceRef::new(
      record,
      provenance,
      observed_digest_text,
      locator?,
      media_type?,
    ) catch {
      _ => raise MalformedInput(field="evidence_ref")
    }
    evidence.push(item)
  }
  evidence
}

///|
fn OrchestrationReader::require_end(
  self : OrchestrationReader,
) -> Unit raise OrchestrationError {
  if self.remaining() != 0 {
    raise MalformedInput(field="trailing_bytes")
  }
}

///|
fn orchestration_version() -> @contracts.Version {
  try! @contracts.Version::parse(orchestration_record_version)
}

///|
fn require_version(
  value : String,
  field : String,
) -> Unit raise OrchestrationError {
  if value != orchestration_record_version {
    raise UnsupportedVersion(field~, version=value)
  }
}

///|
fn require_version_v2(
  value : String,
  field : String,
) -> Unit raise OrchestrationError {
  if value != orchestration_record_version_v2 {
    raise UnsupportedVersion(field~, version=value)
  }
}

///|
fn require_text(
  value : String,
  field : String,
) -> Unit raise OrchestrationError {
  if !@base.is_canonical_text(value) {
    raise MalformedInput(field~)
  }
}

///|
fn require_non_negative(
  value : Int64,
  field : String,
) -> Unit raise OrchestrationError {
  if value < 0L {
    raise MalformedInput(field~)
  }
}

///|
fn checked_add_non_negative(
  left : Int64,
  right : Int64,
  field : String,
) -> Int64 raise OrchestrationError {
  match @base.checked_add_non_negative(left, right) {
    Value(value) => value
    Negative => raise MalformedInput(field~)
    Overflow => raise ArithmeticOverflow(field~)
  }
}

///|
fn checked_multiply_non_negative(
  left : Int64,
  right : Int64,
  field : String,
) -> Int64 raise OrchestrationError {
  match @base.checked_multiply_non_negative(left, right) {
    Value(value) => value
    Negative => raise MalformedInput(field~)
    Overflow => raise ArithmeticOverflow(field~)
  }
}

///|
fn write_ref(
  writer : OrchestrationWriter,
  value : @contracts.RecordRef,
) -> Unit raise OrchestrationError {
  writer.string(value.kind())
  writer.string(value.id())
  writer.string(value.version().text())
  writer.string(value.digest().text())
}

///|
fn write_optional_ref(
  writer : OrchestrationWriter,
  value : @contracts.RecordRef?,
) -> Unit raise OrchestrationError {
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
  writer : OrchestrationWriter,
  values : ArrayView[@contracts.EvidenceRef],
) -> Unit raise OrchestrationError {
  writer.count(values.length())
  for value in values {
    write_ref(writer, value.record())
    write_ref(writer, value.provenance_ref())
    writer.string(value.observed_digest().text())
    match value.locator() {
      None => writer.byte(0)
      Some(value) => {
        writer.byte(1)
        writer.string(value)
      }
    }
    match value.media_type() {
      None => writer.byte(0)
      Some(value) => {
        writer.byte(1)
        writer.string(value)
      }
    }
  }
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
fn[T] first(values : ArrayView[T], predicate : (T) -> Bool) -> T? {
  match values.search_by(predicate) {
    Some(index) => Some(values[index])
    None => None
  }
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
    orchestration_record_version,
    digest.text(),
  )
}

///|
fn self_ref_v2(
  kind : String,
  id : String,
  digest : @contracts.ContentDigest,
) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(
    kind,
    id,
    orchestration_record_version_v2,
    digest.text(),
  )
}

///|
fn orchestration_schema(kind : String) -> @contracts.SchemaRef {
  try! @contracts.SchemaRef::new(
    orchestration_contract_id,
    orchestration_record_version,
    kind,
    orchestration_schema_version,
    @contracts.sha256_digest(@utf8.encode("closed-loop.orchestration/{kind}/1")).text(),
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
  previous_digest : @contracts.ContentDigest?,
) -> @contracts.WireEnvelope raise {
  @contracts.WireEnvelope::new(
    orchestration_contract_id,
    orchestration_record_version,
    id,
    kind,
    subject,
    orchestration_schema(kind),
    payload,
    orchestration_producer_id,
    orchestration_record_version,
    [],
    evidence,
    run_ref=workflow,
    attempt_ref~,
    correlation_ref=workflow.id(),
    causation_ref~,
    idempotency_ref~,
    previous_digest?,
  )
}
