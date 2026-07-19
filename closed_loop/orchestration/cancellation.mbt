///|
pub struct CancellationRecord {
  record_version : @contracts.Version
  cancellation_ref : @contracts.RecordRef
  schedule_ref : @contracts.RecordRef
  schedule_digest : @contracts.ContentDigest
  workflow : @contracts.RecordRef
  clock : ClockInput
  reason_ref : @contracts.RecordRef
  idempotency_key : String
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation_ref : @contracts.RecordRef
  previous_digest : @contracts.ContentDigest
  canonical : Bytes
}

///|
pub fn CancellationRecord::new(
  cancellation_id : String,
  cancellation_version : String,
  schedule : ScheduleIntent,
  clock : ClockInput,
  reason_ref : @contracts.RecordRef,
  idempotency_key : String,
  evidence : Array[@contracts.EvidenceRef],
  causation_ref : @contracts.RecordRef,
  previous_digest : @contracts.ContentDigest,
) -> CancellationRecord raise OrchestrationError {
  require_version(cancellation_version, "cancellation")
  require_text(cancellation_id, "cancellation_id")
  require_text(idempotency_key, "cancellation_idempotency_key")
  if clock.workflow() != schedule.workflow() {
    raise WorkflowMismatch(field="cancellation_clock_workflow")
  }
  let snapshot = evidence.copy()
  let writer = OrchestrationWriter::new()
  writer.bytes(b"MF7ACANCEL1")
  writer.string(cancellation_version)
  writer.string(cancellation_id)
  write_ref(writer, schedule.schedule_ref())
  writer.string(schedule.binding_digest().text())
  write_ref(writer, schedule.workflow())
  writer.bytes(clock.canonical_bytes())
  write_ref(writer, reason_ref)
  writer.string(idempotency_key)
  write_evidence(writer, snapshot)
  write_ref(writer, causation_ref)
  writer.string(previous_digest.text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_version: orchestration_version(),
    cancellation_ref: self_ref(
      "orchestration-cancellation", cancellation_id, digest,
    ),
    schedule_ref: schedule.schedule_ref(),
    schedule_digest: schedule.binding_digest(),
    workflow: schedule.workflow(),
    clock,
    reason_ref,
    idempotency_key,
    evidence: ReadOnlyArray::from_array(snapshot),
    causation_ref,
    previous_digest,
    canonical,
  }
}

///|
pub fn CancellationRecord::cancellation_ref(
  self : CancellationRecord,
) -> @contracts.RecordRef {
  self.cancellation_ref
}

///|
pub fn CancellationRecord::schedule_ref(
  self : CancellationRecord,
) -> @contracts.RecordRef {
  self.schedule_ref
}

///|
pub fn CancellationRecord::clock(self : CancellationRecord) -> ClockInput {
  self.clock
}

///|
pub fn CancellationRecord::reason_ref(
  self : CancellationRecord,
) -> @contracts.RecordRef {
  self.reason_ref
}

///|
pub fn CancellationRecord::idempotency_key(self : CancellationRecord) -> String {
  self.idempotency_key
}

///|
pub fn CancellationRecord::canonical_bytes(self : CancellationRecord) -> Bytes {
  self.canonical
}

///|
pub fn CancellationRecord::binding_digest(
  self : CancellationRecord,
) -> @contracts.ContentDigest {
  self.cancellation_ref.digest()
}

///|
pub impl Eq for CancellationRecord with fn equal(left, right) {
  left.canonical_bytes() == right.canonical_bytes()
}
