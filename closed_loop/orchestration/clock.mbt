///|
/// An immutable explicit logical-clock fact. It is data, never ambient authority.
pub struct ClockInput {
  record_version : @contracts.Version
  clock_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  logical_instant : Int64
  source_ref : @contracts.RecordRef
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation_ref : @contracts.RecordRef
  previous_digest : @contracts.ContentDigest?
  idempotency_key : String
  canonical : Bytes
}

///|
pub fn ClockInput::new(
  clock_id : String,
  clock_version : String,
  workflow : @contracts.RecordRef,
  logical_instant : Int64,
  source_ref : @contracts.RecordRef,
  evidence : Array[@contracts.EvidenceRef],
  causation_ref : @contracts.RecordRef,
  idempotency_key : String,
  previous_digest? : @contracts.ContentDigest,
) -> ClockInput raise OrchestrationError {
  require_version(clock_version, "clock_input")
  require_text(clock_id, "clock_id")
  require_text(idempotency_key, "clock_idempotency_key")
  require_non_negative(logical_instant, "logical_instant")
  let snapshot = evidence.copy()
  let writer = OrchestrationWriter::new()
  writer.bytes(b"MF7ACLOCK1")
  writer.string(clock_version)
  writer.string(clock_id)
  write_ref(writer, workflow)
  writer.int64(logical_instant)
  write_ref(writer, source_ref)
  write_evidence(writer, snapshot)
  write_ref(writer, causation_ref)
  writer.optional_digest(previous_digest)
  writer.string(idempotency_key)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_version: orchestration_version(),
    clock_ref: self_ref("logical-clock-input", clock_id, digest),
    workflow,
    logical_instant,
    source_ref,
    evidence: ReadOnlyArray::from_array(snapshot),
    causation_ref,
    previous_digest,
    idempotency_key,
    canonical,
  }
}

///|
pub fn ClockInput::clock_ref(self : ClockInput) -> @contracts.RecordRef {
  self.clock_ref
}

///|
pub fn ClockInput::workflow(self : ClockInput) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn ClockInput::logical_instant(self : ClockInput) -> Int64 {
  self.logical_instant
}

///|
pub fn ClockInput::source_ref(self : ClockInput) -> @contracts.RecordRef {
  self.source_ref
}

///|
pub fn ClockInput::evidence(
  self : ClockInput,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn ClockInput::causation_ref(self : ClockInput) -> @contracts.RecordRef {
  self.causation_ref
}

///|
pub fn ClockInput::previous_digest(
  self : ClockInput,
) -> @contracts.ContentDigest? {
  self.previous_digest
}

///|
pub fn ClockInput::idempotency_key(self : ClockInput) -> String {
  self.idempotency_key
}

///|
pub fn ClockInput::canonical_bytes(self : ClockInput) -> Bytes {
  self.canonical
}

///|
pub fn ClockInput::binding_digest(
  self : ClockInput,
) -> @contracts.ContentDigest {
  self.clock_ref.digest()
}

///|
pub impl Eq for ClockInput with fn equal(left, right) {
  left.canonical_bytes() == right.canonical_bytes()
}
