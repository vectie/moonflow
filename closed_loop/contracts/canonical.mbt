///|
priv struct CanonWriter {
  buffer : @buffer.Buffer
}

///|
fn CanonWriter::new() -> CanonWriter {
  { buffer: Buffer() }
}

///|
fn CanonWriter::write_byte(self : CanonWriter, value : Byte) -> Unit {
  self.buffer.write_byte(value)
}

///|
fn CanonWriter::write_count(
  self : CanonWriter,
  value : Int,
) -> Unit raise ContractError {
  if value < 0 {
    raise CanonicalizationError("negative length")
  }
  self.buffer.write_uint_be(value.reinterpret_as_uint())
}

///|
fn CanonWriter::write_bytes(
  self : CanonWriter,
  value : Bytes,
) -> Unit raise ContractError {
  self.write_count(value.length())
  self.buffer.write_bytes(value)
}

///|
fn CanonWriter::write_string(
  self : CanonWriter,
  value : String,
) -> Unit raise ContractError {
  self.write_bytes(@utf8.encode(value))
}

///|
fn CanonWriter::write_optional_string(
  self : CanonWriter,
  value : String?,
) -> Unit raise ContractError {
  match value {
    None => self.write_byte(0)
    Some(value) => {
      self.write_byte(1)
      self.write_string(value)
    }
  }
}

///|
fn CanonWriter::finish(self : CanonWriter) -> Bytes {
  self.buffer.to_bytes()
}

///|
priv struct CanonReader {
  data : Bytes
  mut offset : Int
}

///|
fn CanonReader::new(data : Bytes) -> CanonReader {
  { data, offset: 0 }
}

///|
fn CanonReader::remaining(self : CanonReader) -> Int {
  self.data.length() - self.offset
}

///|
fn CanonReader::read_byte(self : CanonReader) -> Byte raise ContractError {
  if self.remaining() < 1 {
    raise DecodeError("unexpected end of canonical bytes")
  }
  let value = self.data[self.offset]
  self.offset = self.offset + 1
  value
}

///|
fn CanonReader::read_count(self : CanonReader) -> Int raise ContractError {
  if self.remaining() < 4 {
    raise DecodeError("truncated length prefix")
  }
  let first = self.read_byte().to_int()
  if first >= 128 {
    raise DecodeError("length exceeds supported bound")
  }
  first * 16777216 +
  self.read_byte().to_int() * 65536 +
  self.read_byte().to_int() * 256 +
  self.read_byte().to_int()
}

///|
fn CanonReader::read_bytes(self : CanonReader) -> Bytes raise ContractError {
  let length = self.read_count()
  if length > self.remaining() {
    raise DecodeError("length prefix exceeds remaining bytes")
  }
  let start = self.offset
  self.offset = self.offset + length
  self.data[start:self.offset].to_owned()
}

///|
fn CanonReader::read_string(self : CanonReader) -> String raise ContractError {
  let bytes = self.read_bytes()
  @utf8.decode(bytes) catch {
    _ => raise DecodeError("invalid UTF-8 canonical text")
  }
}

///|
fn CanonReader::read_optional_string(
  self : CanonReader,
) -> String? raise ContractError {
  match self.read_byte() {
    0 => None
    1 => Some(self.read_string())
    _ => raise DecodeError("invalid optional marker")
  }
}

///|
fn CanonReader::require_end(self : CanonReader) -> Unit raise ContractError {
  if self.remaining() != 0 {
    raise DecodeError("trailing canonical bytes")
  }
}

///|
fn canonical_record_ref(value : RecordRef) -> Bytes {
  let writer = CanonWriter::new()
  try! writer.write_string(value.kind)
  try! writer.write_string(value.id)
  try! writer.write_string(value.version.text())
  try! writer.write_string(value.digest.text())
  writer.finish()
}

///|
fn decode_record_ref_bytes(bytes : Bytes) -> RecordRef raise ContractError {
  let reader = CanonReader::new(bytes)
  let value = RecordRef::new(
    reader.read_string(),
    reader.read_string(),
    reader.read_string(),
    reader.read_string(),
  )
  reader.require_end()
  value
}

///|
fn canonical_schema_ref(value : SchemaRef) -> Bytes {
  let writer = CanonWriter::new()
  try! writer.write_string(value.contract_id)
  try! writer.write_string(value.contract_version.text())
  try! writer.write_string(value.schema_id)
  try! writer.write_string(value.schema_version.text())
  try! writer.write_string(value.schema_digest.text())
  writer.finish()
}

///|
fn decode_schema_ref_bytes(bytes : Bytes) -> SchemaRef raise ContractError {
  let reader = CanonReader::new(bytes)
  let value = SchemaRef::new(
    reader.read_string(),
    reader.read_string(),
    reader.read_string(),
    reader.read_string(),
    reader.read_string(),
  )
  reader.require_end()
  value
}

///|
fn write_optional_record(
  writer : CanonWriter,
  value : RecordRef?,
) -> Unit raise ContractError {
  match value {
    None => writer.write_byte(0)
    Some(value) => {
      writer.write_byte(1)
      writer.write_bytes(canonical_record_ref(value))
    }
  }
}

///|
fn read_optional_record(reader : CanonReader) -> RecordRef? raise ContractError {
  match reader.read_byte() {
    0 => None
    1 => Some(decode_record_ref_bytes(reader.read_bytes()))
    _ => raise DecodeError("invalid optional record marker")
  }
}

///|
fn canonical_artifact(value : ArtifactRef) -> Bytes {
  let writer = CanonWriter::new()
  try! writer.write_bytes(canonical_record_ref(value.record))
  try! writer.write_string(value.locator)
  try! writer.write_string(value.media_type)
  try! write_optional_record(writer, value.run_ref)
  try! write_optional_record(writer, value.stage_ref)
  try! write_optional_record(writer, value.attempt_ref)
  try! writer.write_bytes(canonical_record_ref(value.provenance_ref))
  try! writer.write_string(value.observed_digest.text())
  try! writer.write_optional_string(value.confidentiality)
  writer.finish()
}

///|
fn decode_artifact_bytes(bytes : Bytes) -> ArtifactRef raise ContractError {
  let reader = CanonReader::new(bytes)
  let record = decode_record_ref_bytes(reader.read_bytes())
  let locator = reader.read_string()
  let media_type = reader.read_string()
  let run_ref = read_optional_record(reader)
  let stage_ref = read_optional_record(reader)
  let attempt_ref = read_optional_record(reader)
  let provenance_ref = decode_record_ref_bytes(reader.read_bytes())
  let observed_digest = reader.read_string()
  let confidentiality = reader.read_optional_string()
  reader.require_end()
  ArtifactRef::new(
    record,
    locator,
    media_type,
    provenance_ref,
    observed_digest,
    run_ref?,
    stage_ref?,
    attempt_ref?,
    confidentiality?,
  )
}

///|
fn canonical_evidence(value : EvidenceRef) -> Bytes {
  let writer = CanonWriter::new()
  try! writer.write_bytes(canonical_record_ref(value.record))
  try! writer.write_bytes(canonical_record_ref(value.provenance_ref))
  try! writer.write_string(value.observed_digest.text())
  try! writer.write_optional_string(value.locator)
  try! writer.write_optional_string(value.media_type)
  writer.finish()
}

///|
fn decode_evidence_bytes(bytes : Bytes) -> EvidenceRef raise ContractError {
  let reader = CanonReader::new(bytes)
  let record = decode_record_ref_bytes(reader.read_bytes())
  let provenance_ref = decode_record_ref_bytes(reader.read_bytes())
  let observed_digest = reader.read_string()
  let locator = reader.read_optional_string()
  let media_type = reader.read_optional_string()
  reader.require_end()
  EvidenceRef::new(
    record,
    provenance_ref,
    observed_digest,
    locator?,
    media_type?,
  )
}

///|
fn extension_identity(value : OpaqueExtension) -> String {
  "\{value.namespace_id}:\{value.name}"
}

///|
fn canonical_extension(value : OpaqueExtension) -> Bytes {
  let writer = CanonWriter::new()
  try! writer.write_string(value.namespace_id)
  try! writer.write_string(value.name)
  try! writer.write_bytes(value.value)
  writer.finish()
}

///|
fn decode_extension_bytes(bytes : Bytes) -> OpaqueExtension raise ContractError {
  let reader = CanonReader::new(bytes)
  let value = OpaqueExtension::new(
    reader.read_string(),
    reader.read_string(),
    reader.read_bytes(),
  )
  reader.require_end()
  value
}

///|
fn normalize_artifacts(
  values : Array[ArtifactRef],
) -> ReadOnlyArray[ArtifactRef] raise ContractError {
  let copy = values.copy()
  copy.sort_by((left, right) => {
    let identity_order = record_identity_text(left.record).compare(
      record_identity_text(right.record),
    )
    if identity_order != 0 {
      identity_order
    } else {
      canonical_artifact(left).compare(canonical_artifact(right))
    }
  })
  let normalized : Array[ArtifactRef] = []
  for value in copy {
    match normalized.last() {
      Some(previous) if record_identity_equal(previous.record, value.record) =>
        if canonical_artifact(previous) != canonical_artifact(value) {
          raise ConflictingReferenceIdentity(
            kind=value.record.kind,
            id=value.record.id,
            version=value.record.version.text(),
          )
        }
      _ => normalized.push(value)
    }
  }
  ReadOnlyArray::from_array(normalized)
}

///|
fn normalize_evidence(
  values : Array[EvidenceRef],
) -> ReadOnlyArray[EvidenceRef] raise ContractError {
  let copy = values.copy()
  copy.sort_by((left, right) => {
    let identity_order = record_identity_text(left.record).compare(
      record_identity_text(right.record),
    )
    if identity_order != 0 {
      identity_order
    } else {
      canonical_evidence(left).compare(canonical_evidence(right))
    }
  })
  let normalized : Array[EvidenceRef] = []
  for value in copy {
    match normalized.last() {
      Some(previous) if record_identity_equal(previous.record, value.record) =>
        if canonical_evidence(previous) != canonical_evidence(value) {
          raise ConflictingReferenceIdentity(
            kind=value.record.kind,
            id=value.record.id,
            version=value.record.version.text(),
          )
        }
      _ => normalized.push(value)
    }
  }
  ReadOnlyArray::from_array(normalized)
}

///|
fn normalize_extensions(
  values : Array[OpaqueExtension],
) -> ReadOnlyArray[OpaqueExtension] raise ContractError {
  let copy = values.copy()
  copy.sort_by((left, right) => {
    let identity_order = extension_identity(left).compare(
      extension_identity(right),
    )
    if identity_order != 0 {
      identity_order
    } else {
      canonical_extension(left).compare(canonical_extension(right))
    }
  })
  let normalized : Array[OpaqueExtension] = []
  for value in copy {
    match normalized.last() {
      Some(previous) if extension_identity(previous) ==
        extension_identity(value) =>
        if previous != value {
          raise CanonicalizationError(
            "conflicting extension identity \{extension_identity(value)}",
          )
        }
      _ => normalized.push(value)
    }
  }
  ReadOnlyArray::from_array(normalized)
}
