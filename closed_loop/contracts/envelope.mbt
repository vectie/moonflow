///|
let canonical_envelope_version : String = "1.0.0"

///|
let canonical_envelope_magic : Bytes = b"MFCLE001"

///|
/// Versioned neutral envelope with exact opaque payload bytes and immutable,
/// canonically ordered reference snapshots.
pub struct WireEnvelope {
  canonical_version : Version
  contract_id : String
  contract_version : Version
  envelope_id : String
  envelope_kind : String
  subject : RecordRef
  schema : SchemaRef
  payload : Bytes
  payload_digest : ContentDigest
  producer_id : String
  producer_version : Version
  run_ref : RecordRef?
  stage_ref : RecordRef?
  attempt_ref : RecordRef?
  correlation_ref : String?
  causation_ref : String?
  idempotency_ref : String?
  artifacts : ReadOnlyArray[ArtifactRef]
  evidence : ReadOnlyArray[EvidenceRef]
  previous_digest : ContentDigest?
  extensions : ReadOnlyArray[OpaqueExtension]
  envelope_digest : ContentDigest
}

///|
priv struct DecodedEnvelope {
  canonical_version : String
  contract_id : String
  contract_version : String
  envelope_id : String
  envelope_kind : String
  subject : RecordRef
  schema : SchemaRef
  payload : Bytes
  payload_digest : ContentDigest
  producer_id : String
  producer_version : String
  run_ref : RecordRef?
  stage_ref : RecordRef?
  attempt_ref : RecordRef?
  correlation_ref : String?
  causation_ref : String?
  idempotency_ref : String?
  artifacts : Array[ArtifactRef]
  evidence : Array[EvidenceRef]
  previous_digest : ContentDigest?
  extensions : Array[OpaqueExtension]
}

///|
fn require_supported_contract_version(
  version : Version,
) -> Unit raise ContractError {
  if version.major() != 1 {
    raise UnsupportedVersion(field="contract_version", version=version.text())
  }
}

///|
fn canonical_envelope_body(value : WireEnvelope) -> Bytes {
  let writer = CanonWriter::new()
  try! writer.write_bytes(canonical_envelope_magic)
  try! writer.write_string(value.canonical_version.text())
  try! writer.write_string(value.contract_id)
  try! writer.write_string(value.contract_version.text())
  try! writer.write_string(value.envelope_id)
  try! writer.write_string(value.envelope_kind)
  try! writer.write_bytes(canonical_record_ref(value.subject))
  try! writer.write_bytes(canonical_schema_ref(value.schema))
  try! writer.write_bytes(value.payload)
  try! writer.write_string(value.payload_digest.text())
  try! writer.write_string(value.producer_id)
  try! writer.write_string(value.producer_version.text())
  try! write_optional_record(writer, value.run_ref)
  try! write_optional_record(writer, value.stage_ref)
  try! write_optional_record(writer, value.attempt_ref)
  try! writer.write_optional_string(value.correlation_ref)
  try! writer.write_optional_string(value.causation_ref)
  try! writer.write_optional_string(value.idempotency_ref)
  try! writer.write_count(value.artifacts.length())
  for artifact in value.artifacts {
    try! writer.write_bytes(canonical_artifact(artifact))
  }
  try! writer.write_count(value.evidence.length())
  for evidence in value.evidence {
    try! writer.write_bytes(canonical_evidence(evidence))
  }
  try! writer.write_optional_string(
    value.previous_digest.map(digest => digest.text()),
  )
  try! writer.write_count(value.extensions.length())
  for extension in value.extensions {
    try! writer.write_bytes(canonical_extension(extension))
  }
  writer.finish()
}

///|
fn build_envelope(
  canonical_version : String,
  contract_id : String,
  contract_version : String,
  envelope_id : String,
  envelope_kind : String,
  subject : RecordRef,
  schema : SchemaRef,
  payload : Bytes,
  producer_id : String,
  producer_version : String,
  artifacts : Array[ArtifactRef],
  evidence : Array[EvidenceRef],
  run_ref : RecordRef?,
  stage_ref : RecordRef?,
  attempt_ref : RecordRef?,
  correlation_ref : String?,
  causation_ref : String?,
  idempotency_ref : String?,
  previous_digest : ContentDigest?,
  extensions : Array[OpaqueExtension],
  supplied_payload_digest : ContentDigest?,
  supplied_envelope_digest : ContentDigest?,
) -> WireEnvelope raise ContractError {
  if canonical_version != canonical_envelope_version {
    raise UnsupportedCanonicalVersion(canonical_version)
  }
  let canonical_version = parse_version_named(
    canonical_version, "canonical_version",
  )
  require_text(contract_id, "envelope", "contract_id")
  let contract_version = parse_version_named(
    contract_version, "envelope.contract_version",
  )
  require_supported_contract_version(contract_version)
  require_text(envelope_id, "envelope", "envelope_id")
  require_text(envelope_kind, "envelope", "envelope_kind")
  require_text(producer_id, "envelope", "producer_id")
  let producer_version = parse_version_named(
    producer_version, "envelope.producer_version",
  )
  require_optional_text(correlation_ref, "envelope", "correlation_ref")
  require_optional_text(causation_ref, "envelope", "causation_ref")
  require_optional_text(idempotency_ref, "envelope", "idempotency_ref")
  if schema.contract_id != contract_id ||
    schema.contract_version != contract_version {
    raise CanonicalizationError("schema contract binding mismatch")
  }
  let payload_digest = sha256_digest(payload)
  match supplied_payload_digest {
    Some(expected) if expected != payload_digest =>
      raise PayloadDigestMismatch(
        expected=expected.text(),
        actual=payload_digest.text(),
      )
    _ => ()
  }
  let artifacts = normalize_artifacts(artifacts)
  let evidence = normalize_evidence(evidence)
  let extensions = normalize_extensions(extensions)
  let placeholder = sha256_digest(b"")
  let provisional : WireEnvelope = {
    canonical_version,
    contract_id,
    contract_version,
    envelope_id,
    envelope_kind,
    subject,
    schema,
    payload,
    payload_digest,
    producer_id,
    producer_version,
    run_ref,
    stage_ref,
    attempt_ref,
    correlation_ref,
    causation_ref,
    idempotency_ref,
    artifacts,
    evidence,
    previous_digest,
    extensions,
    envelope_digest: placeholder,
  }
  let envelope_digest = sha256_digest(canonical_envelope_body(provisional))
  match supplied_envelope_digest {
    Some(expected) if expected != envelope_digest =>
      raise EnvelopeDigestMismatch(
        expected=expected.text(),
        actual=envelope_digest.text(),
      )
    _ => ()
  }
  { ..provisional, envelope_digest, }
}

///|
/// Construct a validated envelope. Payload and envelope digests are always
/// recomputed. Input arrays are copied, sorted canonically, exact-deduplicated,
/// and stored as immutable snapshots.
pub fn WireEnvelope::new(
  contract_id : String,
  contract_version : String,
  envelope_id : String,
  envelope_kind : String,
  subject : RecordRef,
  schema : SchemaRef,
  payload : Bytes,
  producer_id : String,
  producer_version : String,
  artifacts : Array[ArtifactRef],
  evidence : Array[EvidenceRef],
  run_ref? : RecordRef,
  stage_ref? : RecordRef,
  attempt_ref? : RecordRef,
  correlation_ref? : String,
  causation_ref? : String,
  idempotency_ref? : String,
  previous_digest? : ContentDigest,
  extensions? : Array[OpaqueExtension] = [],
) -> WireEnvelope raise ContractError {
  build_envelope(
    canonical_envelope_version,
    contract_id,
    contract_version,
    envelope_id,
    envelope_kind,
    subject,
    schema,
    payload,
    producer_id,
    producer_version,
    artifacts,
    evidence,
    run_ref,
    stage_ref,
    attempt_ref,
    correlation_ref,
    causation_ref,
    idempotency_ref,
    previous_digest,
    extensions,
    None,
    None,
  )
}

///|
pub fn WireEnvelope::canonical_version(self : WireEnvelope) -> Version {
  self.canonical_version
}

///|
pub fn WireEnvelope::contract_id(self : WireEnvelope) -> String {
  self.contract_id
}

///|
pub fn WireEnvelope::contract_version(self : WireEnvelope) -> Version {
  self.contract_version
}

///|
pub fn WireEnvelope::envelope_id(self : WireEnvelope) -> String {
  self.envelope_id
}

///|
pub fn WireEnvelope::envelope_kind(self : WireEnvelope) -> String {
  self.envelope_kind
}

///|
pub fn WireEnvelope::subject(self : WireEnvelope) -> RecordRef {
  self.subject
}

///|
pub fn WireEnvelope::schema(self : WireEnvelope) -> SchemaRef {
  self.schema
}

///|
pub fn WireEnvelope::payload(self : WireEnvelope) -> Bytes {
  self.payload
}

///|
pub fn WireEnvelope::payload_digest(self : WireEnvelope) -> ContentDigest {
  self.payload_digest
}

///|
pub fn WireEnvelope::producer_id(self : WireEnvelope) -> String {
  self.producer_id
}

///|
pub fn WireEnvelope::producer_version(self : WireEnvelope) -> Version {
  self.producer_version
}

///|
pub fn WireEnvelope::run_ref(self : WireEnvelope) -> RecordRef? {
  self.run_ref
}

///|
pub fn WireEnvelope::stage_ref(self : WireEnvelope) -> RecordRef? {
  self.stage_ref
}

///|
pub fn WireEnvelope::attempt_ref(self : WireEnvelope) -> RecordRef? {
  self.attempt_ref
}

///|
pub fn WireEnvelope::correlation_ref(self : WireEnvelope) -> String? {
  self.correlation_ref
}

///|
pub fn WireEnvelope::causation_ref(self : WireEnvelope) -> String? {
  self.causation_ref
}

///|
pub fn WireEnvelope::idempotency_ref(self : WireEnvelope) -> String? {
  self.idempotency_ref
}

///|
pub fn WireEnvelope::artifacts(
  self : WireEnvelope,
) -> ReadOnlyArray[ArtifactRef] {
  self.artifacts
}

///|
pub fn WireEnvelope::evidence(
  self : WireEnvelope,
) -> ReadOnlyArray[EvidenceRef] {
  self.evidence
}

///|
pub fn WireEnvelope::previous_digest(self : WireEnvelope) -> ContentDigest? {
  self.previous_digest
}

///|
pub fn WireEnvelope::extensions(
  self : WireEnvelope,
) -> ReadOnlyArray[OpaqueExtension] {
  self.extensions
}

///|
pub fn WireEnvelope::envelope_digest(self : WireEnvelope) -> ContentDigest {
  self.envelope_digest
}

///|
/// Canonical v1 bytes covered by `envelope_digest`. The only excluded field is
/// `envelope_digest` itself. Exact order is: magic, canonical version, contract
/// id/version, envelope id/kind, subject, schema, opaque payload, payload
/// digest, producer id/version, optional run/stage/attempt records, optional
/// correlation/causation/idempotency references, sorted artifacts, sorted
/// evidence, optional previous digest, and sorted extensions. Every variable
/// byte sequence has a four-byte unsigned big-endian length; arrays have a
/// four-byte count; options have a one-byte 0/1 marker. Nested values are
/// length-prefixed canonical byte sequences. Text is UTF-8. No map, locale,
/// debug representation, or platform hash participates.
pub fn WireEnvelope::canonical_bytes(self : WireEnvelope) -> Bytes {
  canonical_envelope_body(self)
}

///|
fn decode_envelope_body(body : Bytes) -> DecodedEnvelope raise ContractError {
  let reader = CanonReader::new(body)
  if reader.read_bytes() != canonical_envelope_magic {
    raise DecodeError("invalid canonical envelope magic")
  }
  let canonical_version = reader.read_string()
  if canonical_version != canonical_envelope_version {
    raise UnsupportedCanonicalVersion(canonical_version)
  }
  let contract_id = reader.read_string()
  let contract_version = reader.read_string()
  let envelope_id = reader.read_string()
  let envelope_kind = reader.read_string()
  let subject = decode_record_ref_bytes(reader.read_bytes())
  let schema = decode_schema_ref_bytes(reader.read_bytes())
  let payload = reader.read_bytes()
  let payload_digest = ContentDigest::parse(reader.read_string())
  let producer_id = reader.read_string()
  let producer_version = reader.read_string()
  let run_ref = read_optional_record(reader)
  let stage_ref = read_optional_record(reader)
  let attempt_ref = read_optional_record(reader)
  let correlation_ref = reader.read_optional_string()
  let causation_ref = reader.read_optional_string()
  let idempotency_ref = reader.read_optional_string()
  let artifacts : Array[ArtifactRef] = []
  let artifact_count = reader.read_count()
  for _ in 0..<artifact_count {
    artifacts.push(decode_artifact_bytes(reader.read_bytes()))
  }
  let evidence : Array[EvidenceRef] = []
  let evidence_count = reader.read_count()
  for _ in 0..<evidence_count {
    evidence.push(decode_evidence_bytes(reader.read_bytes()))
  }
  let previous_digest = reader
    .read_optional_string()
    .map(value => ContentDigest::parse(value))
  let extensions : Array[OpaqueExtension] = []
  let extension_count = reader.read_count()
  for _ in 0..<extension_count {
    extensions.push(decode_extension_bytes(reader.read_bytes()))
  }
  reader.require_end()
  {
    canonical_version,
    contract_id,
    contract_version,
    envelope_id,
    envelope_kind,
    subject,
    schema,
    payload,
    payload_digest,
    producer_id,
    producer_version,
    run_ref,
    stage_ref,
    attempt_ref,
    correlation_ref,
    causation_ref,
    idempotency_ref,
    artifacts,
    evidence,
    previous_digest,
    extensions,
  }
}

///|
/// Encode canonical body bytes plus the separately length-prefixed envelope
/// digest field.
pub fn encode_wire_envelope(value : WireEnvelope) -> Bytes {
  let writer = CanonWriter::new()
  try! writer.write_bytes(canonical_envelope_body(value))
  try! writer.write_string(value.envelope_digest.text())
  writer.finish()
}

///|
/// Decode only canonical wire bytes. Both digests are recomputed and compared;
/// non-canonical ordering, trailing data, malformed fields, and tampering fail
/// closed.
pub fn decode_wire_envelope(bytes : Bytes) -> WireEnvelope raise ContractError {
  let reader = CanonReader::new(bytes)
  let body = reader.read_bytes()
  let decoded = decode_envelope_body(body)
  let supplied_envelope_digest = ContentDigest::parse(reader.read_string())
  reader.require_end()
  let value = build_envelope(
    decoded.canonical_version,
    decoded.contract_id,
    decoded.contract_version,
    decoded.envelope_id,
    decoded.envelope_kind,
    decoded.subject,
    decoded.schema,
    decoded.payload,
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
  if canonical_envelope_body(value) != body ||
    encode_wire_envelope(value) != bytes {
    raise CanonicalizationError("wire bytes are not canonical")
  }
  value
}

///|
pub impl Eq for WireEnvelope with fn equal(left, right) {
  encode_wire_envelope(left) == encode_wire_envelope(right)
}

///|
pub(all) enum ReplayDecision {
  ExactDuplicate
  NewIdentity
} derive(Eq, Debug)

///|
/// Pure replay classification. Same envelope identity with different canonical
/// content is a typed conflict; no value is mutated.
pub fn decide_envelope_replay(
  existing : WireEnvelope,
  incoming : WireEnvelope,
) -> ReplayDecision raise ContractError {
  if existing.envelope_id != incoming.envelope_id {
    NewIdentity
  } else if existing == incoming {
    ExactDuplicate
  } else {
    raise ConflictingEnvelopeIdentity(incoming.envelope_id)
  }
}
