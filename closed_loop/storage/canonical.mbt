///|
priv struct StorageWriter {
  buffer : @buffer.Buffer
}

///|
fn StorageWriter::new() -> StorageWriter {
  { buffer: Buffer() }
}

///|
fn StorageWriter::write_byte(self : StorageWriter, value : Byte) -> Unit {
  self.buffer.write_byte(value)
}

///|
fn StorageWriter::write_count(
  self : StorageWriter,
  value : Int,
) -> Unit raise StorageError {
  if value < 0 {
    raise ValidationFailure(field="negative_length")
  }
  self.buffer.write_uint_be(value.reinterpret_as_uint())
}

///|
fn StorageWriter::write_int64(self : StorageWriter, value : Int64) -> Unit {
  self.buffer.write_int64_be(value)
}

///|
fn StorageWriter::write_bytes(
  self : StorageWriter,
  value : Bytes,
) -> Unit raise StorageError {
  self.write_count(value.length())
  self.buffer.write_bytes(value)
}

///|
fn StorageWriter::write_string(
  self : StorageWriter,
  value : String,
) -> Unit raise StorageError {
  self.write_bytes(@utf8.encode(value))
}

///|
fn StorageWriter::write_optional_string(
  self : StorageWriter,
  value : String?,
) -> Unit raise StorageError {
  match value {
    None => self.write_byte(0)
    Some(value) => {
      self.write_byte(1)
      self.write_string(value)
    }
  }
}

///|
fn StorageWriter::finish(self : StorageWriter) -> Bytes {
  self.buffer.to_bytes()
}

///|
priv struct StorageReader {
  data : Bytes
  mut offset : Int
}

///|
fn StorageReader::new(data : Bytes) -> StorageReader {
  { data, offset: 0 }
}

///|
fn StorageReader::remaining(self : StorageReader) -> Int {
  self.data.length() - self.offset
}

///|
fn StorageReader::read_byte(self : StorageReader) -> Byte raise StorageError {
  if self.remaining() < 1 {
    raise ValidationFailure(field="truncated_byte")
  }
  let value = self.data[self.offset]
  self.offset += 1
  value
}

///|
fn StorageReader::read_count(self : StorageReader) -> Int raise StorageError {
  if self.remaining() < 4 {
    raise ValidationFailure(field="truncated_length")
  }
  let first = self.read_byte().to_int()
  if first >= 128 {
    raise ValidationFailure(field="length_bound")
  }
  first * 16777216 +
  self.read_byte().to_int() * 65536 +
  self.read_byte().to_int() * 256 +
  self.read_byte().to_int()
}

///|
fn StorageReader::read_int64(self : StorageReader) -> Int64 raise StorageError {
  if self.remaining() < 8 {
    raise ValidationFailure(field="truncated_int64")
  }
  let mut value = 0UL
  for _ in 0..<8 {
    value = (value << 8) | self.read_byte().to_uint().to_uint64()
  }
  value.reinterpret_as_int64()
}

///|
fn StorageReader::read_bytes(self : StorageReader) -> Bytes raise StorageError {
  let length = self.read_count()
  if length > self.remaining() {
    raise ValidationFailure(field="length_exceeds_record")
  }
  let start = self.offset
  self.offset += length
  self.data[start:self.offset].to_owned()
}

///|
fn StorageReader::read_string(
  self : StorageReader,
) -> String raise StorageError {
  @utf8.decode(self.read_bytes()) catch {
    _ => raise ValidationFailure(field="invalid_utf8")
  }
}

///|
fn StorageReader::read_optional_string(
  self : StorageReader,
) -> String? raise StorageError {
  match self.read_byte() {
    0 => None
    1 => Some(self.read_string())
    _ => raise ValidationFailure(field="optional_marker")
  }
}

///|
fn StorageReader::require_end(self : StorageReader) -> Unit raise StorageError {
  if self.remaining() != 0 {
    raise ValidationFailure(field="trailing_bytes")
  }
}

///|
fn encode_record_ref(value : @contracts.RecordRef, omit_digest : Bool) -> Bytes {
  let writer = StorageWriter::new()
  try! writer.write_string(value.kind())
  try! writer.write_string(value.id())
  try! writer.write_string(value.version().text())
  if !omit_digest {
    try! writer.write_string(value.digest().text())
  }
  writer.finish()
}

///|
fn decode_record_ref(bytes : Bytes) -> @contracts.RecordRef raise StorageError {
  let reader = StorageReader::new(bytes)
  let kind = reader.read_string()
  let id = reader.read_string()
  let version = reader.read_string()
  let digest = reader.read_string()
  reader.require_end()
  new_contract_record_ref(kind, id, version, digest, "record_ref")
}

///|
fn write_optional_digest(
  writer : StorageWriter,
  digest : @contracts.ContentDigest?,
) -> Unit raise StorageError {
  writer.write_optional_string(digest.map(value => value.text()))
}

///|
fn read_optional_digest(
  reader : StorageReader,
) -> @contracts.ContentDigest? raise StorageError {
  match reader.read_optional_string() {
    None => None
    Some(value) => Some(parse_content_digest(value, "digest"))
  }
}

///|
fn encode_evidence_ref(value : @contracts.EvidenceRef) -> Bytes {
  let writer = StorageWriter::new()
  try! writer.write_bytes(encode_record_ref(value.record(), false))
  try! writer.write_bytes(encode_record_ref(value.provenance_ref(), false))
  try! writer.write_string(value.observed_digest().text())
  try! writer.write_optional_string(value.locator())
  try! writer.write_optional_string(value.media_type())
  writer.finish()
}

///|
fn decode_evidence_ref(
  bytes : Bytes,
) -> @contracts.EvidenceRef raise StorageError {
  let reader = StorageReader::new(bytes)
  let record = decode_record_ref(reader.read_bytes())
  let provenance = decode_record_ref(reader.read_bytes())
  let observed = reader.read_string()
  let locator = reader.read_optional_string()
  let media_type = reader.read_optional_string()
  reader.require_end()
  new_contract_evidence_ref(record, provenance, observed, locator, media_type)
}

///|
fn record_identity_equal(
  left : @contracts.RecordRef,
  right : @contracts.RecordRef,
) -> Bool {
  left.kind() == right.kind() &&
  left.id() == right.id() &&
  left.version() == right.version()
}

///|
fn exact_record_equal(
  left : @contracts.RecordRef,
  right : @contracts.RecordRef,
) -> Bool {
  record_identity_equal(left, right) && left.digest() == right.digest()
}
