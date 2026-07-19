///|
priv struct RetryWriter {
  buffer : @buffer.Buffer
}

///|
fn RetryWriter::new() -> RetryWriter {
  { buffer: @buffer.Buffer() }
}

///|
fn RetryWriter::byte(self : RetryWriter, value : Byte) -> Unit {
  self.buffer.write_byte(value)
}

///|
fn RetryWriter::int64(self : RetryWriter, value : Int64) -> Unit {
  self.buffer.write_int64_be(value)
}

///|
fn RetryWriter::bytes(
  self : RetryWriter,
  value : Bytes,
) -> Unit raise RetryAuthorityError {
  self.buffer.write_uint_be(value.length().reinterpret_as_uint())
  self.buffer.write_bytes(value)
}

///|
fn RetryWriter::string(
  self : RetryWriter,
  value : String,
) -> Unit raise RetryAuthorityError {
  self.bytes(@utf8.encode(value))
}

///|
fn RetryWriter::optional_int64(self : RetryWriter, value : Int64?) -> Unit {
  match value {
    None => self.byte(0)
    Some(value) => {
      self.byte(1)
      self.int64(value)
    }
  }
}

///|
fn RetryWriter::finish(self : RetryWriter) -> Bytes {
  self.buffer.to_bytes()
}

///|
priv struct RetryReader {
  data : Bytes
  mut offset : Int
}

///|
fn RetryReader::new(data : Bytes) -> RetryReader {
  { data, offset: 0 }
}

///|
fn RetryReader::remaining(self : RetryReader) -> Int {
  self.data.length() - self.offset
}

///|
fn RetryReader::byte(self : RetryReader) -> Byte raise RetryAuthorityError {
  if self.remaining() < 1 {
    raise Malformed(field="truncated_byte")
  }
  let value = self.data[self.offset]
  self.offset += 1
  value
}

///|
fn RetryReader::count(self : RetryReader) -> Int raise RetryAuthorityError {
  if self.remaining() < 4 {
    raise Malformed(field="truncated_count")
  }
  let first = self.byte().to_int()
  if first >= 128 {
    raise BoundViolation(field="count")
  }
  first * 16777216 +
  self.byte().to_int() * 65536 +
  self.byte().to_int() * 256 +
  self.byte().to_int()
}

///|
fn RetryReader::int64(self : RetryReader) -> Int64 raise RetryAuthorityError {
  if self.remaining() < 8 {
    raise Malformed(field="truncated_int64")
  }
  let mut value = 0UL
  for _ in 0..<8 {
    value = (value << 8) | self.byte().to_uint().to_uint64()
  }
  value.reinterpret_as_int64()
}

///|
fn RetryReader::bytes(self : RetryReader) -> Bytes raise RetryAuthorityError {
  let length = self.count()
  if length > self.remaining() {
    raise Malformed(field="truncated_bytes")
  }
  let start = self.offset
  self.offset += length
  self.data[start:self.offset].to_owned()
}

///|
fn RetryReader::string(self : RetryReader) -> String raise RetryAuthorityError {
  @utf8.decode(self.bytes()) catch {
    _ => raise Malformed(field="utf8")
  }
}

///|
fn RetryReader::optional_int64(
  self : RetryReader,
) -> Int64? raise RetryAuthorityError {
  match self.byte() {
    0 => None
    1 => Some(self.int64())
    _ => raise Malformed(field="optional_int64")
  }
}

///|
fn RetryReader::finish(self : RetryReader) -> Unit raise RetryAuthorityError {
  if self.remaining() != 0 {
    raise Malformed(field="trailing_bytes")
  }
}

///|
fn write_ref(
  writer : RetryWriter,
  value : @contracts.RecordRef,
) -> Unit raise RetryAuthorityError {
  writer.string(value.kind())
  writer.string(value.id())
  writer.string(value.version().text())
  writer.string(value.digest().text())
}

///|
fn read_digest(
  reader : RetryReader,
) -> @contracts.ContentDigest raise RetryAuthorityError {
  @contracts.ContentDigest::parse(reader.string()) catch {
    _ => raise Malformed(field="digest")
  }
}

///|
fn read_ref(
  reader : RetryReader,
) -> @contracts.RecordRef raise RetryAuthorityError {
  @contracts.RecordRef::new(
    reader.string(),
    reader.string(),
    reader.string(),
    reader.string(),
  ) catch {
    _ => raise Malformed(field="record_ref")
  }
}

///|
fn require_text(
  value : String,
  field : String,
) -> Unit raise RetryAuthorityError {
  if value.trim().is_empty() {
    raise Malformed(field~)
  }
}

///|
fn proposal_ref(
  kind : String,
  id : String,
  digest : @contracts.ContentDigest,
) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(kind, id, "1.0.0", digest.text())
}
