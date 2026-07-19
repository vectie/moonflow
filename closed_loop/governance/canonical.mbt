///|
priv struct GovernanceWriter {
  buffer : @buffer.Buffer
}

///|
fn GovernanceWriter::new() -> GovernanceWriter {
  { buffer: Buffer() }
}

///|
fn GovernanceWriter::write_byte(self : GovernanceWriter, value : Byte) -> Unit {
  self.buffer.write_byte(value)
}

///|
fn GovernanceWriter::write_count(
  self : GovernanceWriter,
  value : Int,
) -> Unit raise GovernanceError {
  if value < 0 {
    raise MalformedPayload(field="negative_length")
  }
  self.buffer.write_uint_be(value.reinterpret_as_uint())
}

///|
fn GovernanceWriter::write_int64(
  self : GovernanceWriter,
  value : Int64,
) -> Unit {
  self.buffer.write_int64_be(value)
}

///|
fn GovernanceWriter::write_bytes(
  self : GovernanceWriter,
  value : Bytes,
) -> Unit raise GovernanceError {
  self.write_count(value.length())
  self.buffer.write_bytes(value)
}

///|
fn GovernanceWriter::write_string(
  self : GovernanceWriter,
  value : String,
) -> Unit raise GovernanceError {
  self.write_bytes(@utf8.encode(value))
}

///|
fn GovernanceWriter::write_optional_string(
  self : GovernanceWriter,
  value : String?,
) -> Unit raise GovernanceError {
  match value {
    None => self.write_byte(0)
    Some(value) => {
      self.write_byte(1)
      self.write_string(value)
    }
  }
}

///|
fn GovernanceWriter::write_optional_digest(
  self : GovernanceWriter,
  value : @contracts.ContentDigest?,
) -> Unit raise GovernanceError {
  self.write_optional_string(value.map(digest => digest.text()))
}

///|
fn GovernanceWriter::write_optional_int64(
  self : GovernanceWriter,
  value : Int64?,
) -> Unit {
  match value {
    None => self.write_byte(0)
    Some(value) => {
      self.write_byte(1)
      self.write_int64(value)
    }
  }
}

///|
fn GovernanceWriter::finish(self : GovernanceWriter) -> Bytes {
  self.buffer.to_bytes()
}

///|
priv struct GovernanceReader {
  data : Bytes
  mut offset : Int
}

///|
fn GovernanceReader::new(data : Bytes) -> GovernanceReader {
  { data, offset: 0 }
}

///|
fn GovernanceReader::remaining(self : GovernanceReader) -> Int {
  self.data.length() - self.offset
}

///|
fn GovernanceReader::read_byte(
  self : GovernanceReader,
) -> Byte raise GovernanceError {
  if self.remaining() < 1 {
    raise MalformedPayload(field="truncated_byte")
  }
  let value = self.data[self.offset]
  self.offset += 1
  value
}

///|
fn GovernanceReader::read_count(
  self : GovernanceReader,
) -> Int raise GovernanceError {
  if self.remaining() < 4 {
    raise MalformedPayload(field="truncated_length")
  }
  let first = self.read_byte().to_int()
  if first >= 128 {
    raise MalformedPayload(field="length_bound")
  }
  first * 16777216 +
  self.read_byte().to_int() * 65536 +
  self.read_byte().to_int() * 256 +
  self.read_byte().to_int()
}

///|
fn GovernanceReader::read_int64(
  self : GovernanceReader,
) -> Int64 raise GovernanceError {
  if self.remaining() < 8 {
    raise MalformedPayload(field="truncated_int64")
  }
  let mut value = 0UL
  for _ in 0..<8 {
    value = (value << 8) | self.read_byte().to_uint().to_uint64()
  }
  value.reinterpret_as_int64()
}

///|
fn GovernanceReader::read_bytes(
  self : GovernanceReader,
) -> Bytes raise GovernanceError {
  let length = self.read_count()
  if length > self.remaining() {
    raise MalformedPayload(field="length_exceeds_record")
  }
  let start = self.offset
  self.offset += length
  self.data[start:self.offset].to_owned()
}

///|
fn GovernanceReader::read_string(self : GovernanceReader) -> String raise {
  @utf8.decode(self.read_bytes()) catch {
    _ => raise MalformedPayload(field="invalid_utf8")
  }
}

///|
fn GovernanceReader::read_optional_string(
  self : GovernanceReader,
) -> String? raise {
  match self.read_byte() {
    0 => None
    1 => Some(self.read_string())
    _ => raise MalformedPayload(field="optional_marker")
  }
}

///|
fn GovernanceReader::read_optional_int64(
  self : GovernanceReader,
) -> Int64? raise GovernanceError {
  match self.read_byte() {
    0 => None
    1 => Some(self.read_int64())
    _ => raise MalformedPayload(field="optional_int64_marker")
  }
}

///|
fn GovernanceReader::require_end(
  self : GovernanceReader,
) -> Unit raise GovernanceError {
  if self.remaining() != 0 {
    raise MalformedPayload(field="trailing_bytes")
  }
}

///|
fn write_record(
  writer : GovernanceWriter,
  value : @contracts.RecordRef,
  omit_digest : Bool,
) -> Unit raise GovernanceError {
  writer.write_string(value.kind())
  writer.write_string(value.id())
  writer.write_string(value.version().text())
  if !omit_digest {
    writer.write_string(value.digest().text())
  }
}

///|
fn record_bytes(value : @contracts.RecordRef) -> Bytes {
  let writer = GovernanceWriter::new()
  try! write_record(writer, value, false)
  writer.finish()
}

///|
fn read_record(reader : GovernanceReader) -> @contracts.RecordRef raise {
  @contracts.RecordRef::new(
    reader.read_string(),
    reader.read_string(),
    reader.read_string(),
    reader.read_string(),
  )
}

///|
fn read_nested_record(reader : GovernanceReader) -> @contracts.RecordRef raise {
  let nested = GovernanceReader::new(reader.read_bytes())
  let value = read_record(nested)
  nested.require_end()
  value
}

///|
fn write_evidence(
  writer : GovernanceWriter,
  value : @contracts.EvidenceRef,
) -> Unit raise GovernanceError {
  writer.write_bytes(record_bytes(value.record()))
  writer.write_bytes(record_bytes(value.provenance_ref()))
  writer.write_string(value.observed_digest().text())
  writer.write_optional_string(value.locator())
  writer.write_optional_string(value.media_type())
}

///|
fn evidence_bytes(value : @contracts.EvidenceRef) -> Bytes {
  let writer = GovernanceWriter::new()
  try! write_evidence(writer, value)
  writer.finish()
}

///|
fn read_evidence(reader : GovernanceReader) -> @contracts.EvidenceRef raise {
  let record_reader = GovernanceReader::new(reader.read_bytes())
  let record = read_record(record_reader)
  record_reader.require_end()
  let provenance_reader = GovernanceReader::new(reader.read_bytes())
  let provenance = read_record(provenance_reader)
  provenance_reader.require_end()
  let observed = reader.read_string()
  let locator = reader.read_optional_string()
  let media_type = reader.read_optional_string()
  @contracts.EvidenceRef::new(
    record,
    provenance,
    observed,
    locator?,
    media_type?,
  )
}

///|
fn write_records(
  writer : GovernanceWriter,
  values : ArrayView[@contracts.RecordRef],
) -> Unit raise GovernanceError {
  writer.write_count(values.length())
  for value in values {
    writer.write_bytes(record_bytes(value))
  }
}

///|
fn read_records(reader : GovernanceReader) -> Array[@contracts.RecordRef] raise {
  let values : Array[@contracts.RecordRef] = []
  let count = reader.read_count()
  for _ in 0..<count {
    let nested = GovernanceReader::new(reader.read_bytes())
    values.push(read_record(nested))
    nested.require_end()
  }
  values
}

///|
fn write_evidence_list(
  writer : GovernanceWriter,
  values : ArrayView[@contracts.EvidenceRef],
) -> Unit raise GovernanceError {
  writer.write_count(values.length())
  for value in values {
    writer.write_bytes(evidence_bytes(value))
  }
}

///|
fn read_evidence_list(
  reader : GovernanceReader,
) -> Array[@contracts.EvidenceRef] raise {
  let values : Array[@contracts.EvidenceRef] = []
  let count = reader.read_count()
  for _ in 0..<count {
    let nested = GovernanceReader::new(reader.read_bytes())
    values.push(read_evidence(nested))
    nested.require_end()
  }
  values
}

///|
fn ordered_record_digest(
  label : Bytes,
  values : ArrayView[@contracts.RecordRef],
) -> @contracts.ContentDigest {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(label)
  try! write_records(writer, values)
  @contracts.sha256_digest(writer.finish())
}

///|
fn ordered_evidence_digest(
  label : Bytes,
  values : ArrayView[@contracts.EvidenceRef],
) -> @contracts.ContentDigest {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(label)
  try! write_evidence_list(writer, values)
  @contracts.sha256_digest(writer.finish())
}

///|
fn self_record(
  kind : String,
  id : String,
  version : String,
  digest : @contracts.ContentDigest,
) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(kind, id, version, digest.text())
}

///|
fn read_envelope(reader : GovernanceReader) -> @contracts.WireEnvelope raise {
  @contracts.decode_wire_envelope(reader.read_bytes())
}

///|
fn write_envelope(
  writer : GovernanceWriter,
  value : @contracts.WireEnvelope,
) -> Unit raise GovernanceError {
  writer.write_bytes(@contracts.encode_wire_envelope(value))
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
