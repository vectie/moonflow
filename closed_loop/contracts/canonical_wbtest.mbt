///|
fn wb_record(kind : String, id : String, seed : Bytes) -> RecordRef {
  try! RecordRef::new(kind, id, "1.0.0", sha256_digest(seed).text())
}

///|
fn wb_schema() -> SchemaRef {
  try! SchemaRef::new(
    "neutral.exchange",
    "1.0.0",
    "opaque-envelope",
    "1.0.0",
    sha256_digest(b"schema").text(),
  )
}

///|
fn wb_envelope(payload : Bytes) -> WireEnvelope {
  try! WireEnvelope::new(
    "neutral.exchange",
    "1.0.0",
    "envelope-internal",
    "opaque-record",
    wb_record("subject", "subject-1", b"subject"),
    wb_schema(),
    payload,
    "neutral-producer",
    "1.0.0",
    [],
    [],
  )
}

///|
fn rebuild_decoded(
  decoded : DecodedEnvelope,
  envelope_id : String,
  payload : Bytes,
  supplied_envelope_digest : ContentDigest,
) -> WireEnvelope raise ContractError {
  build_envelope(
    decoded.canonical_version,
    decoded.contract_id,
    decoded.contract_version,
    envelope_id,
    decoded.envelope_kind,
    decoded.subject,
    decoded.schema,
    payload,
    decoded.producer_id,
    decoded.producer_version,
    decoded.artifacts,
    decoded.evidence,
    decoded.run_ref,
    decoded.stage_ref,
    decoded.attempt_ref,
    decoded.correlation_ref,
    decoded.causation_ref,
    decoded.idempotency_ref,
    decoded.previous_digest,
    decoded.extensions,
    Some(decoded.payload_digest),
    Some(supplied_envelope_digest),
  )
}

///|
test "FLOW-3 internal canonical prefixes markers and reader writer roundtrip" {
  let writer = CanonWriter::new()
  writer.write_count(0x01020304)
  writer.write_bytes([0xaa, 0xbb])
  writer.write_optional_string(None)
  writer.write_optional_string(Some("A"))
  let encoded = writer.finish()
  assert_eq(encoded, [
    0x01, 0x02, 0x03, 0x04, 0x00, 0x00, 0x00, 0x02, 0xaa, 0xbb, 0x00, 0x01, 0x00,
    0x00, 0x00, 0x01, 0x41,
  ])
  let reader = CanonReader::new(encoded)
  assert_eq(reader.read_count(), 0x01020304)
  assert_eq(reader.read_bytes(), [0xaa, 0xbb])
  assert_true(reader.read_optional_string() is None)
  assert_true(reader.read_optional_string() == Some("A"))
  reader.require_end()
}

///|
test "FLOW-3 internal canonical reader rejects malformed boundaries" {
  try CanonReader::new([0x00, 0x00, 0x00]).read_count() catch {
    DecodeError(message) => assert_eq(message, "truncated length prefix")
    _ => fail("unexpected truncated-length error")
  } noraise {
    _ => fail("expected truncated length rejection")
  }
  try CanonReader::new([0x80, 0x00, 0x00, 0x00]).read_count() catch {
    DecodeError(message) => assert_eq(message, "length exceeds supported bound")
    _ => fail("unexpected oversized-length error")
  } noraise {
    _ => fail("expected oversized length rejection")
  }
  try CanonReader::new([0x00, 0x00, 0x00, 0x02, 0xaa]).read_bytes() catch {
    DecodeError(message) =>
      assert_eq(message, "length prefix exceeds remaining bytes")
    _ => fail("unexpected remaining-length error")
  } noraise {
    _ => fail("expected remaining-length rejection")
  }
  try CanonReader::new([0x02]).read_optional_string() catch {
    DecodeError(message) => assert_eq(message, "invalid optional marker")
    _ => fail("unexpected option-marker error")
  } noraise {
    _ => fail("expected invalid option rejection")
  }
  let trailing = CanonReader::new([0x00, 0xff])
  ignore(trailing.read_byte())
  try trailing.require_end() catch {
    DecodeError(message) => assert_eq(message, "trailing canonical bytes")
    _ => fail("unexpected trailing-byte error")
  } noraise {
    _ => fail("expected trailing-byte rejection")
  }
}

///|
test "FLOW-3 internal nested canonical references remain byte stable" {
  let record = wb_record("artifact", "artifact-1", b"artifact")
  let record_bytes = canonical_record_ref(record)
  assert_eq(
    canonical_record_ref(decode_record_ref_bytes(record_bytes)),
    record_bytes,
  )
  let schema = wb_schema()
  let schema_bytes = canonical_schema_ref(schema)
  assert_eq(
    canonical_schema_ref(decode_schema_ref_bytes(schema_bytes)),
    schema_bytes,
  )
  let provenance = wb_record("provenance", "source-1", b"source")
  let run = wb_record("run", "run-1", b"run")
  let artifact = try! ArtifactRef::new(
    record,
    "artifacts/value.bin",
    "application/octet-stream",
    provenance,
    sha256_digest(b"value").text(),
    run_ref=run,
    confidentiality="restricted",
  )
  let artifact_bytes = canonical_artifact(artifact)
  assert_eq(
    canonical_artifact(decode_artifact_bytes(artifact_bytes)),
    artifact_bytes,
  )
  let evidence = try! EvidenceRef::new(
    wb_record("evidence", "evidence-1", b"evidence"),
    provenance,
    sha256_digest(b"proof").text(),
    locator="evidence/proof.bin",
    media_type="application/octet-stream",
  )
  let evidence_bytes = canonical_evidence(evidence)
  assert_eq(
    canonical_evidence(decode_evidence_bytes(evidence_bytes)),
    evidence_bytes,
  )
  let extension = try! OpaqueExtension::new("org.example", "opaque", [
    0x00, 0xff, 0x80,
  ])
  let extension_bytes = canonical_extension(extension)
  assert_eq(
    canonical_extension(decode_extension_bytes(extension_bytes)),
    extension_bytes,
  )
}

///|
test "FLOW-3 internal build boundary validates exact digests and tampering" {
  let value = wb_envelope([0x00, 0xff, 0x80])
  let body = canonical_envelope_body(value)
  let decoded = decode_envelope_body(body)
  let rebuilt = rebuild_decoded(
    decoded,
    decoded.envelope_id,
    decoded.payload,
    value.envelope_digest,
  )
  assert_eq(canonical_envelope_body(rebuilt), body)
  assert_true(rebuilt.envelope_digest == value.envelope_digest)
  try
    rebuild_decoded(
      decoded,
      decoded.envelope_id,
      [0x00, 0xff, 0x81],
      value.envelope_digest,
    )
  catch {
    PayloadDigestMismatch(expected~, actual~) => assert_true(expected != actual)
    _ => fail("unexpected direct payload-tamper error")
  } noraise {
    _ => fail("expected direct payload-tamper rejection")
  }
  try
    rebuild_decoded(
      decoded,
      "envelope-internal-changed",
      decoded.payload,
      value.envelope_digest,
    )
  catch {
    EnvelopeDigestMismatch(expected~, actual~) =>
      assert_true(expected != actual)
    _ => fail("unexpected direct envelope-tamper error")
  } noraise {
    _ => fail("expected direct envelope-tamper rejection")
  }
}
