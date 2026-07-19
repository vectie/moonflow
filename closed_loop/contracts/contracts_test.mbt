///|
fn test_record(
  kind : String,
  id : String,
  seed : Bytes,
) -> @contracts.RecordRef raise @contracts.ContractError {
  @contracts.RecordRef::new(
    kind,
    id,
    "1.0.0",
    @contracts.sha256_digest(seed).text(),
  )
}

///|
fn test_schema() -> @contracts.SchemaRef raise @contracts.ContractError {
  @contracts.SchemaRef::new(
    "neutral.exchange",
    "1.2.0",
    "opaque-envelope",
    "1.0.0",
    @contracts.sha256_digest(b"schema").text(),
  )
}

///|
fn test_artifact(
  id : String,
  locator : String,
) -> @contracts.ArtifactRef raise @contracts.ContractError {
  @contracts.ArtifactRef::new(
    test_record("artifact", id, @utf8.encode(id)),
    locator,
    "application/octet-stream",
    test_record("provenance", "source", b"source"),
    @contracts.sha256_digest(@utf8.encode(locator)).text(),
    run_ref=test_record("run", "run-1", b"run"),
    stage_ref=test_record("stage", "stage-1", b"stage"),
    attempt_ref=test_record("attempt", "attempt-1", b"attempt"),
    confidentiality="restricted",
  )
}

///|
fn test_evidence(
  id : String,
  locator : String,
) -> @contracts.EvidenceRef raise @contracts.ContractError {
  @contracts.EvidenceRef::new(
    test_record("evidence", id, @utf8.encode(id)),
    test_record("provenance", "source", b"source"),
    @contracts.sha256_digest(@utf8.encode(locator)).text(),
    locator~,
    media_type="application/octet-stream",
  )
}

///|
fn test_envelope(
  envelope_id : String,
  payload : Bytes,
  artifacts : Array[@contracts.ArtifactRef],
  evidence : Array[@contracts.EvidenceRef],
) -> @contracts.WireEnvelope raise @contracts.ContractError {
  @contracts.WireEnvelope::new(
    "neutral.exchange",
    "1.2.0",
    envelope_id,
    "opaque-record",
    test_record("subject", "subject-1", b"subject"),
    test_schema(),
    payload,
    "neutral-producer",
    "3.1.4",
    artifacts,
    evidence,
    run_ref=test_record("run", "run-1", b"run"),
    stage_ref=test_record("stage", "stage-1", b"stage"),
    attempt_ref=test_record("attempt", "attempt-1", b"attempt"),
    correlation_ref="correlation-1",
    causation_ref="causation-1",
    idempotency_ref="idempotency-1",
    previous_digest=@contracts.sha256_digest(b"previous"),
    extensions=[
      @contracts.OpaqueExtension::new("org.example", "opaque", [
        0x00, 0xff, 0x80,
      ]),
    ],
  )
}

///|
fn changed_byte(bytes : Bytes, offset : Int, value : Byte) -> Bytes {
  let changed = bytes.to_array()
  changed[offset] = value
  Bytes::from_array(changed)
}

///|
fn changed_ascii(bytes : Bytes, pattern : String, replacement : Byte) -> Bytes {
  guard bytes.find(@utf8.encode(pattern)) is Some(offset) else {
    abort("test pattern not found")
  }
  changed_byte(bytes, offset, replacement)
}

///|
test "FLOW-3 SHA-256 known vectors and strict tagged format" {
  assert_eq(
    @contracts.sha256_hex(b""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    @contracts.sha256_hex(b"abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(
    @contracts.sha256_hex(
      b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
    ),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
  let tagged = @contracts.ContentDigest::parse(
    "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(tagged.algorithm(), "sha256")
  assert_eq(tagged.hex().length(), 64)
}

///|
test "FLOW-3 digest syntax and algorithm failures are typed" {
  try @contracts.ContentDigest::parse("sha256:ABC") catch {
    InvalidDigestSyntax(field~) => assert_eq(field, "digest")
    _ => fail("unexpected digest error")
  } noraise {
    _ => fail("expected invalid digest")
  }
  try
    @contracts.ContentDigest::parse(
      "sha1:0000000000000000000000000000000000000000000000000000000000000000",
    )
  catch {
    UnsupportedDigestAlgorithm(algorithm) => assert_eq(algorithm, "sha1")
    _ => fail("unexpected algorithm error")
  } noraise {
    _ => fail("expected unsupported algorithm")
  }
}

///|
test "FLOW-3 versions normalize and negotiate highest exact common" {
  let offered = @contracts.VersionProfile::new([
    "1.2.0", "1.0.0", "2.0.0", "1.2.0",
  ])
  assert_eq(offered.versions().length(), 3)
  assert_eq(offered.versions()[0].text(), "1.0.0")
  assert_eq(offered.versions()[1].text(), "1.2.0")
  assert_eq(offered.versions()[2].text(), "2.0.0")
  let accepted = @contracts.VersionProfile::new(["1.1.0", "1.2.0", "1.0.0"])
  assert_eq(@contracts.negotiate_highest(offered, accepted).text(), "1.2.0")
}

///|
test "FLOW-3 malformed unsupported and no-common versions fail closed" {
  for malformed in ["", "1", "1.0", "01.0.0", "1.-1.0", "1.0.x"] {
    try @contracts.Version::parse(malformed) catch {
      MalformedVersion(_) => ()
      _ => fail("unexpected malformed-version error")
    } noraise {
      _ => fail("expected malformed version")
    }
  }
  let supported = @contracts.VersionProfile::new(["1.0.0"])
  try supported.require_supported(@contracts.Version::parse("1.1.0")) catch {
    UnsupportedVersion(field~, version~) => {
      assert_eq(field, "supported_version")
      assert_eq(version, "1.1.0")
    }
    _ => fail("unexpected unsupported-version error")
  } noraise {
    _ => fail("expected unsupported version")
  }
  try
    @contracts.negotiate_highest(
      supported,
      @contracts.VersionProfile::new(["2.0.0"]),
    )
  catch {
    NoCommonVersion => ()
    _ => fail("unexpected negotiation error")
  } noraise {
    _ => fail("expected no common version")
  }
}

///|
test "FLOW-3 valid opaque references retain exact immutable values" {
  let artifact = test_artifact("artifact-1", "artifacts/a.bin")
  assert_eq(artifact.record().id(), "artifact-1")
  assert_eq(artifact.locator(), "artifacts/a.bin")
  assert_eq(artifact.media_type(), "application/octet-stream")
  assert_true(artifact.run_ref() is Some(_))
  assert_true(artifact.stage_ref() is Some(_))
  assert_true(artifact.attempt_ref() is Some(_))
  assert_true(artifact.confidentiality() == Some("restricted"))
  let evidence = test_evidence("evidence-1", "evidence/a.bin")
  assert_true(evidence.locator() == Some("evidence/a.bin"))
  assert_true(evidence.media_type() == Some("application/octet-stream"))
}

///|
test "FLOW-3 malformed reference fields locators media and namespaces fail" {
  let digest = @contracts.sha256_digest(b"x").text()
  for pair in [("", "id"), ("kind", " "), (" kind", "id")] {
    let kind = pair.0
    let id = pair.1
    try @contracts.RecordRef::new(kind, id, "1.0.0", digest) catch {
      InvalidReferenceField(_) => ()
      _ => fail("unexpected reference-field error")
    } noraise {
      _ => fail("expected invalid reference")
    }
  }
  try @contracts.RecordRef::new("kind", "id", "", digest) catch {
    MalformedVersion(field~) => assert_eq(field, "record.version")
    _ => fail("unexpected record-version error")
  } noraise {
    _ => fail("expected invalid record version")
  }
  try @contracts.SchemaRef::new("", "1.0.0", "schema", "1.0.0", digest) catch {
    InvalidReferenceField(reference~, field~) => {
      assert_eq(reference, "schema")
      assert_eq(field, "contract_id")
    }
    _ => fail("unexpected schema identity error")
  } noraise {
    _ => fail("expected invalid schema identity")
  }
  try
    @contracts.EvidenceRef::new(
      test_record("evidence", "bad-digest", b"bad"),
      test_record("provenance", "source", b"source"),
      "",
    )
  catch {
    InvalidDigestSyntax(_) => ()
    _ => fail("unexpected observed-digest error")
  } noraise {
    _ => fail("expected invalid observed digest")
  }
  try @contracts.RecordRef::new("provenance", "", "1.0.0", digest) catch {
    InvalidReferenceField(reference~, field~) => {
      assert_eq(reference, "record")
      assert_eq(field, "id")
    }
    _ => fail("unexpected provenance identity error")
  } noraise {
    _ => fail("expected invalid provenance identity")
  }
  for locator in ["", "../outside", "https://user@host/value", "value?token=x"] {
    try
      @contracts.ArtifactRef::new(
        test_record("artifact", "bad", b"bad"),
        locator,
        "application/octet-stream",
        test_record("provenance", "source", b"source"),
        digest,
      )
    catch {
      InvalidReferenceField(_) => ()
      _ => fail("unexpected locator error")
    } noraise {
      _ => fail("expected invalid locator")
    }
  }
  try
    @contracts.ArtifactRef::new(
      test_record("artifact", "bad-media", b"bad"),
      "artifacts/a",
      "invalid",
      test_record("provenance", "source", b"source"),
      digest,
    )
  catch {
    InvalidReferenceField(_) => ()
    _ => fail("unexpected media error")
  } noraise {
    _ => fail("expected invalid media type")
  }
  try @contracts.OpaqueExtension::new("unnamespaced", "field", b"x") catch {
    InvalidReferenceField(_) => ()
    _ => fail("unexpected extension error")
  } noraise {
    _ => fail("expected invalid extension namespace")
  }
}

///|
test "FLOW-3 reference input order and exact duplicates canonicalize identically" {
  let first = test_artifact("artifact-a", "artifacts/a.bin")
  let second = test_artifact("artifact-b", "artifacts/b.bin")
  let evidence_a = test_evidence("evidence-a", "evidence/a.bin")
  let evidence_b = test_evidence("evidence-b", "evidence/b.bin")
  let left = test_envelope(
    "envelope-order",
    b"payload",
    [second, first, first],
    [evidence_b, evidence_a, evidence_a],
  )
  let right = test_envelope("envelope-order", b"payload", [first, second], [
    evidence_a, evidence_b,
  ])
  assert_true(left == right)
  assert_eq(left.artifacts().length(), 2)
  assert_eq(left.evidence().length(), 2)
  assert_true(left.envelope_digest() == right.envelope_digest())
  assert_eq(left.canonical_bytes(), right.canonical_bytes())
}

///|
test "FLOW-3 conflicting duplicate references fail closed" {
  let original = test_artifact("artifact-conflict", "artifacts/a.bin")
  let changed = test_artifact("artifact-conflict", "artifacts/changed.bin")
  try
    test_envelope("envelope-conflict", b"payload", [original, changed], [])
  catch {
    ConflictingReferenceIdentity(kind~, id~, version~) => {
      assert_eq(kind, "artifact")
      assert_eq(id, "artifact-conflict")
      assert_eq(version, "1.0.0")
    }
    _ => fail("unexpected reference conflict")
  } noraise {
    _ => fail("expected conflicting reference")
  }
  let evidence = test_evidence("evidence-conflict", "evidence/a.bin")
  let changed_evidence = test_evidence(
    "evidence-conflict", "evidence/changed.bin",
  )
  try
    test_envelope("envelope-evidence-conflict", b"payload", [], [
      evidence, changed_evidence,
    ])
  catch {
    ConflictingReferenceIdentity(kind~, id~, version~) => {
      assert_eq(kind, "evidence")
      assert_eq(id, "evidence-conflict")
      assert_eq(version, "1.0.0")
    }
    _ => fail("unexpected evidence conflict")
  } noraise {
    _ => fail("expected conflicting evidence")
  }
}

///|
test "FLOW-3 constructor snapshots are immutable after caller array mutation" {
  let artifacts = [test_artifact("artifact-snapshot", "artifacts/a.bin")]
  let evidence = [test_evidence("evidence-snapshot", "evidence/a.bin")]
  let value = test_envelope(
    "envelope-snapshot", b"payload", artifacts, evidence,
  )
  artifacts.push(test_artifact("artifact-later", "artifacts/later.bin"))
  evidence.push(test_evidence("evidence-later", "evidence/later.bin"))
  assert_eq(value.artifacts().length(), 1)
  assert_eq(value.evidence().length(), 1)
}

///|
test "FLOW-3 binary payload roundtrip preserves zero and non-UTF-8 bytes" {
  let payload : Bytes = [0x00, 0xff, 0xfe, 0x80, 0x00, 0x41]
  let value = test_envelope("envelope-binary", payload, [], [])
  let encoded = @contracts.encode_wire_envelope(value)
  let decoded = @contracts.decode_wire_envelope(encoded)
  assert_true(value == decoded)
  assert_eq(decoded.payload(), payload)
  assert_true(decoded.payload_digest() == @contracts.sha256_digest(payload))
  assert_eq(@contracts.encode_wire_envelope(decoded), encoded)
}

///|
test "FLOW-3 payload and metadata tampering fail with typed digest errors" {
  let payload : Bytes = [0x00, 0xff, 0xfe, 0x80]
  let value = test_envelope("envelope-tamper", payload, [], [])
  let encoded = @contracts.encode_wire_envelope(value)
  guard encoded.to_array().search(0xff) is Some(payload_offset) else {
    fail("payload marker missing")
  }
  try
    @contracts.decode_wire_envelope(changed_byte(encoded, payload_offset, 0x7f))
  catch {
    PayloadDigestMismatch(_) => ()
    _ => fail("unexpected payload tamper error")
  } noraise {
    _ => fail("expected payload tamper failure")
  }
  let metadata_tamper = changed_ascii(encoded, "envelope-tamper", b'E')
  try @contracts.decode_wire_envelope(metadata_tamper) catch {
    EnvelopeDigestMismatch(_) => ()
    _ => fail("unexpected metadata tamper error")
  } noraise {
    _ => fail("expected metadata tamper failure")
  }
}

///|
test "FLOW-3 digest metadata and canonical version tampering fail closed" {
  let value = test_envelope("envelope-digest", b"payload", [], [])
  let encoded = @contracts.encode_wire_envelope(value)
  let payload_digest = value.payload_digest().text()
  guard encoded.find(@utf8.encode(payload_digest)) is Some(offset) else {
    fail("payload digest not found")
  }
  let replacement = if encoded[offset + 7] == b'0' { b'1' } else { b'0' }
  try
    @contracts.decode_wire_envelope(
      changed_byte(encoded, offset + 7, replacement),
    )
  catch {
    PayloadDigestMismatch(_) => ()
    _ => fail("unexpected payload digest tamper error")
  } noraise {
    _ => fail("expected payload digest tamper failure")
  }
  let digest_tamper = changed_byte(
    encoded,
    encoded.length() - 1,
    if encoded[encoded.length() - 1] == b'0' {
      b'1'
    } else {
      b'0'
    },
  )
  try @contracts.decode_wire_envelope(digest_tamper) catch {
    EnvelopeDigestMismatch(_) => ()
    _ => fail("unexpected envelope digest tamper error")
  } noraise {
    _ => fail("expected envelope digest tamper failure")
  }
  try
    @contracts.decode_wire_envelope(changed_ascii(encoded, "1.0.0", b'2'))
  catch {
    UnsupportedCanonicalVersion(version) => assert_eq(version, "2.0.0")
    _ => fail("unexpected canonical-version error")
  } noraise {
    _ => fail("expected canonical-version failure")
  }
}

///|
test "FLOW-3 malformed wire and unknown contract major fail closed" {
  let encoded = @contracts.encode_wire_envelope(
    test_envelope("envelope-malformed", b"payload", [], []),
  )
  try @contracts.decode_wire_envelope(encoded + b"x") catch {
    DecodeError(_) => ()
    _ => fail("unexpected trailing-wire error")
  } noraise {
    _ => fail("expected trailing-wire failure")
  }
  try
    @contracts.WireEnvelope::new(
      "neutral.exchange",
      "2.0.0",
      "envelope-v2",
      "opaque-record",
      test_record("subject", "subject-1", b"subject"),
      @contracts.SchemaRef::new(
        "neutral.exchange",
        "2.0.0",
        "opaque-envelope",
        "1.0.0",
        @contracts.sha256_digest(b"schema").text(),
      ),
      b"payload",
      "neutral-producer",
      "1.0.0",
      [],
      [],
    )
  catch {
    UnsupportedVersion(field~, version~) => {
      assert_eq(field, "contract_version")
      assert_eq(version, "2.0.0")
    }
    _ => fail("unexpected contract-version error")
  } noraise {
    _ => fail("expected unsupported contract major")
  }
}

///|
test "FLOW-3 replay decision is pure deterministic and conflicts on reused identity" {
  let value = test_envelope("envelope-replay", b"payload", [], [])
  let replayed = @contracts.decode_wire_envelope(
    @contracts.encode_wire_envelope(value),
  )
  assert_true(
    @contracts.decide_envelope_replay(value, replayed) is ExactDuplicate,
  )
  assert_true(
    @contracts.decide_envelope_replay(
      value,
      test_envelope("envelope-new", b"payload", [], []),
    )
    is NewIdentity,
  )
  try
    @contracts.decide_envelope_replay(
      value,
      test_envelope("envelope-replay", b"changed", [], []),
    )
  catch {
    ConflictingEnvelopeIdentity(id) => assert_eq(id, "envelope-replay")
    _ => fail("unexpected envelope replay error")
  } noraise {
    _ => fail("expected envelope identity conflict")
  }
}

///|
test "FLOW-3 canonical digest golden is stable" {
  let value = test_envelope(
    "envelope-golden",
    [0x00, 0x01, 0x7f, 0x80, 0xff],
    [
      test_artifact("artifact-b", "artifacts/b.bin"),
      test_artifact("artifact-a", "artifacts/a.bin"),
    ],
    [test_evidence("evidence-a", "evidence/a.bin")],
  )
  inspect(
    value.envelope_digest().text(),
    content=(
      #|sha256:284970a283062924773724aeec445abc282b30921c25b8a30bd3bc202c40bea7
    ),
  )
}

///|
struct NeutralEnvelopeCodec {
  marker : Unit
}

///|
impl @contracts.EnvelopeCodec for NeutralEnvelopeCodec with fn supported_versions(
  self,
) {
  ignore(self.marker)
  try! @contracts.VersionProfile::new(["1.0.0", "1.1.0"])
}

///|
impl @contracts.EnvelopeCodec for NeutralEnvelopeCodec with fn encode_envelope(
  self,
  value,
  version,
) {
  self.supported_versions().require_supported(version)
  @contracts.encode_wire_envelope(value)
}

///|
impl @contracts.EnvelopeCodec for NeutralEnvelopeCodec with fn decode_envelope(
  self,
  bytes,
  version,
) {
  self.supported_versions().require_supported(version)
  @contracts.decode_wire_envelope(bytes)
}

///|
struct NeutralReceiptPort {
  marker : Unit
}

///|
impl @contracts.ReceiptExchangePort for NeutralReceiptPort with fn supported_versions(
  self,
) {
  ignore(self.marker)
  try! @contracts.VersionProfile::new(["1.0.0"])
}

///|
impl @contracts.ReceiptExchangePort for NeutralReceiptPort with fn encode_receipt(
  self,
  value,
  version,
) {
  self.supported_versions().require_supported(version)
  @contracts.encode_wire_envelope(value)
}

///|
impl @contracts.ReceiptExchangePort for NeutralReceiptPort with fn decode_receipt(
  self,
  bytes,
  version,
) {
  self.supported_versions().require_supported(version)
  @contracts.decode_wire_envelope(bytes)
}

///|
struct NeutralWorkPort {
  marker : Unit
}

///|
impl @contracts.WorkExchangePort for NeutralWorkPort with fn supported_versions(
  self,
) {
  ignore(self.marker)
  try! @contracts.VersionProfile::new(["1.0.0"])
}

///|
impl @contracts.WorkExchangePort for NeutralWorkPort with fn encode_request(
  self,
  value,
  version,
) {
  self.supported_versions().require_supported(version)
  @contracts.encode_wire_envelope(value)
}

///|
impl @contracts.WorkExchangePort for NeutralWorkPort with fn decode_request(
  self,
  bytes,
  version,
) {
  self.supported_versions().require_supported(version)
  @contracts.decode_wire_envelope(bytes)
}

///|
impl @contracts.WorkExchangePort for NeutralWorkPort with fn encode_result(
  self,
  value,
  version,
) {
  self.supported_versions().require_supported(version)
  @contracts.encode_wire_envelope(value)
}

///|
impl @contracts.WorkExchangePort for NeutralWorkPort with fn decode_result(
  self,
  bytes,
  version,
) {
  self.supported_versions().require_supported(version)
  @contracts.decode_wire_envelope(bytes)
}

///|
fn[C : @contracts.EnvelopeCodec] codec_roundtrip(
  codec : C,
  value : @contracts.WireEnvelope,
  version : @contracts.Version,
) -> @contracts.WireEnvelope raise @contracts.ContractError {
  codec.decode_envelope(codec.encode_envelope(value, version), version)
}

///|
fn[P : @contracts.ReceiptExchangePort] receipt_roundtrip(
  port : P,
  value : @contracts.WireEnvelope,
  version : @contracts.Version,
) -> @contracts.WireEnvelope raise @contracts.ContractError {
  port.decode_receipt(port.encode_receipt(value, version), version)
}

///|
fn[P : @contracts.WorkExchangePort] work_roundtrip(
  port : P,
  value : @contracts.WireEnvelope,
  version : @contracts.Version,
) -> (@contracts.WireEnvelope, @contracts.WireEnvelope) raise @contracts.ContractError {
  (
    port.decode_request(port.encode_request(value, version), version),
    port.decode_result(port.encode_result(value, version), version),
  )
}

///|
test "FLOW-3 pure neutral port conformance maps bytes without state changes" {
  let value = test_envelope("envelope-port", b"opaque", [], [])
  let version = @contracts.Version::parse("1.0.0")
  let codec : NeutralEnvelopeCodec = { marker: () }
  let receipt_port : NeutralReceiptPort = { marker: () }
  let work_port : NeutralWorkPort = { marker: () }
  assert_true(codec_roundtrip(codec, value, version) == value)
  assert_true(receipt_roundtrip(receipt_port, value, version) == value)
  let (request, result) = work_roundtrip(work_port, value, version)
  assert_true(request == value)
  assert_true(result == value)
}
