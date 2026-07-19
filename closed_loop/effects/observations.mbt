///|
/// Opaque fact returned by a dispatcher port. It does not itself assert an
/// external outcome or alter durable state.
pub struct DispatchObservation {
  record_version : @contracts.Version
  observation_ref : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  external_idempotency_key : String
  fencing : FencingBinding?
  observation : @contracts.WireEnvelope
  observed_at : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
}

///|
pub fn DispatchObservation::new(
  observation_id : String,
  intent : EffectIntent,
  observation : @contracts.WireEnvelope,
  observed_at : Int64,
  evidence : Array[@contracts.EvidenceRef],
) -> DispatchObservation raise EffectsError {
  require_text(observation_id, "dispatch_observation_id")
  if observation.subject() != intent.governance().governed_subject() {
    raise IdentityMismatch(field="dispatch_observation_subject")
  }
  let snapshot = evidence.copy()
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6ADOB1")
  writer.string(effects_record_version)
  writer.string(observation_id)
  write_ref(writer, intent.intent_ref())
  writer.string(intent.external_idempotency_key())
  match intent.fencing() {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      writer.bytes(value.canonical_bytes())
    }
  }
  writer.bytes(@contracts.encode_wire_envelope(observation))
  writer.int64(observed_at)
  write_evidence(writer, snapshot)
  let canonical = writer.finish()
  {
    record_version: effects_version(),
    observation_ref: self_ref(
      "dispatch-observation",
      observation_id,
      @contracts.sha256_digest(canonical),
    ),
    intent_ref: intent.intent_ref(),
    external_idempotency_key: intent.external_idempotency_key(),
    fencing: intent.fencing(),
    observation,
    observed_at,
    evidence: ReadOnlyArray::from_array(snapshot),
    canonical,
  }
}

///|
pub fn DispatchObservation::observation_ref(
  self : DispatchObservation,
) -> @contracts.RecordRef {
  self.observation_ref
}

///|
pub fn DispatchObservation::intent_ref(
  self : DispatchObservation,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
/// Inert identity evidence used by the governed dispatcher boundary.
pub fn DispatchObservation::external_idempotency_key(
  self : DispatchObservation,
) -> String {
  self.external_idempotency_key
}

///|
pub fn DispatchObservation::evidence(
  self : DispatchObservation,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn DispatchObservation::canonical_bytes(
  self : DispatchObservation,
) -> Bytes {
  self.canonical
}

///|
pub struct EffectReceipt {
  record_version : @contracts.Version
  schema_version : @contracts.Version
  receipt_ref : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  intent_digest : @contracts.ContentDigest
  external_idempotency_key : String
  attempt_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  capability_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  authority_grant_ref : @contracts.RecordRef
  review_receipt_ref : @contracts.RecordRef
  fencing : FencingBinding?
  dispatcher_receipt : @contracts.WireEnvelope
  dispatcher_receipt_bytes : Bytes
  outcome : ExternalOutcome
  observed_at : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
}

///|
pub fn EffectReceipt::new(
  receipt_id : String,
  receipt_version : String,
  intent : EffectIntent,
  dispatcher_receipt : @contracts.WireEnvelope,
  outcome : ExternalOutcome,
  observed_at : Int64,
  evidence : Array[@contracts.EvidenceRef],
  observed_fencing? : FencingBinding,
) -> EffectReceipt raise EffectsError {
  require_version(receipt_version, "effect_receipt_version")
  require_text(receipt_id, "effect_receipt_id")
  if observed_fencing != intent.fencing() {
    raise FencingViolation(field="receipt_fencing_binding")
  }
  if dispatcher_receipt.subject() != intent.governance().governed_subject() {
    raise IdentityMismatch(field="receipt_subject")
  }
  let snapshot = evidence.copy()
  let dispatcher_receipt_bytes = @contracts.encode_wire_envelope(
    dispatcher_receipt,
  )
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6AERC1")
  writer.string(effects_record_version)
  writer.string(effects_schema_version)
  writer.string(receipt_id)
  write_ref(writer, intent.intent_ref())
  writer.string(intent.binding_digest().text())
  writer.string(intent.external_idempotency_key())
  write_ref(writer, intent.attempt_ref())
  write_ref(writer, intent.workflow())
  write_ref(writer, intent.capability_ref())
  write_ref(writer, intent.governance().governed_subject())
  write_ref(writer, intent.governance().authority_grant_ref())
  write_ref(writer, intent.governance().review_receipt_ref())
  match intent.fencing() {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      writer.bytes(value.canonical_bytes())
    }
  }
  writer.bytes(dispatcher_receipt_bytes)
  writer.string(outcome.tag())
  writer.int64(observed_at)
  write_evidence(writer, snapshot)
  let canonical = writer.finish()
  {
    record_version: effects_version(),
    schema_version: effects_version(),
    receipt_ref: self_ref(
      "effect-receipt",
      receipt_id,
      @contracts.sha256_digest(canonical),
    ),
    intent_ref: intent.intent_ref(),
    intent_digest: intent.binding_digest(),
    external_idempotency_key: intent.external_idempotency_key(),
    attempt_ref: intent.attempt_ref(),
    workflow: intent.workflow(),
    capability_ref: intent.capability_ref(),
    governed_subject: intent.governance().governed_subject(),
    authority_grant_ref: intent.governance().authority_grant_ref(),
    review_receipt_ref: intent.governance().review_receipt_ref(),
    fencing: intent.fencing(),
    dispatcher_receipt,
    dispatcher_receipt_bytes,
    outcome,
    observed_at,
    evidence: ReadOnlyArray::from_array(snapshot),
    canonical,
  }
}

///|
pub fn EffectReceipt::receipt_ref(self : EffectReceipt) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn EffectReceipt::intent_ref(self : EffectReceipt) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn EffectReceipt::outcome(self : EffectReceipt) -> ExternalOutcome {
  self.outcome
}

///|
pub fn EffectReceipt::external_idempotency_key(self : EffectReceipt) -> String {
  self.external_idempotency_key
}

///|
pub fn EffectReceipt::evidence(
  self : EffectReceipt,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn EffectReceipt::canonical_bytes(self : EffectReceipt) -> Bytes {
  self.canonical
}

///|
pub fn EffectReceipt::binding_digest(
  self : EffectReceipt,
) -> @contracts.ContentDigest {
  self.receipt_ref.digest()
}

///|
pub impl Eq for EffectReceipt with fn equal(left, right) {
  left.receipt_ref == right.receipt_ref && left.canonical == right.canonical
}

///|
pub struct ReconciliationRequest {
  record_version : @contracts.Version
  request_ref : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  unknown_receipt_ref : @contracts.RecordRef
  external_idempotency_key : String
  requested_at : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
}

///|
pub fn ReconciliationRequest::new(
  request_id : String,
  intent : EffectIntent,
  unknown_receipt : EffectReceipt,
  requested_at : Int64,
  evidence : Array[@contracts.EvidenceRef],
) -> ReconciliationRequest raise EffectsError {
  require_text(request_id, "reconciliation_request_id")
  if unknown_receipt.intent_ref() != intent.intent_ref() ||
    unknown_receipt.external_idempotency_key() !=
    intent.external_idempotency_key() {
    raise ReconciliationViolation(field="foreign_unknown_receipt")
  }
  if unknown_receipt.outcome() != Unknown {
    raise ReconciliationViolation(field="outcome_not_unknown")
  }
  let snapshot = evidence.copy()
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6ARRQ1")
  writer.string(effects_record_version)
  writer.string(request_id)
  write_ref(writer, intent.intent_ref())
  write_ref(writer, unknown_receipt.receipt_ref())
  writer.string(intent.external_idempotency_key())
  writer.int64(requested_at)
  write_evidence(writer, snapshot)
  let canonical = writer.finish()
  {
    record_version: effects_version(),
    request_ref: self_ref(
      "effect-reconciliation-request",
      request_id,
      @contracts.sha256_digest(canonical),
    ),
    intent_ref: intent.intent_ref(),
    unknown_receipt_ref: unknown_receipt.receipt_ref(),
    external_idempotency_key: intent.external_idempotency_key(),
    requested_at,
    evidence: ReadOnlyArray::from_array(snapshot),
    canonical,
  }
}

///|
pub fn ReconciliationRequest::request_ref(
  self : ReconciliationRequest,
) -> @contracts.RecordRef {
  self.request_ref
}

///|
pub fn ReconciliationRequest::intent_ref(
  self : ReconciliationRequest,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn ReconciliationRequest::external_idempotency_key(
  self : ReconciliationRequest,
) -> String {
  self.external_idempotency_key
}

///|
pub fn ReconciliationRequest::evidence(
  self : ReconciliationRequest,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn ReconciliationRequest::canonical_bytes(
  self : ReconciliationRequest,
) -> Bytes {
  self.canonical
}

///|
pub struct ReconciliationRecord {
  record_version : @contracts.Version
  reconciliation_ref : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  request_ref : @contracts.RecordRef
  external_idempotency_key : String
  resolution : ReconciliationResolution
  observation : @contracts.WireEnvelope
  reconciled_at : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
}

///|
pub fn ReconciliationRecord::new(
  reconciliation_id : String,
  intent : EffectIntent,
  request : ReconciliationRequest,
  resolution : ReconciliationResolution,
  observation : @contracts.WireEnvelope,
  reconciled_at : Int64,
  evidence : Array[@contracts.EvidenceRef],
) -> ReconciliationRecord raise EffectsError {
  require_text(reconciliation_id, "reconciliation_id")
  if request.intent_ref() != intent.intent_ref() {
    raise ReconciliationViolation(field="foreign_reconciliation_request")
  }
  if observation.subject() != intent.governance().governed_subject() {
    raise IdentityMismatch(field="reconciliation_subject")
  }
  let snapshot = evidence.copy()
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6ARSL1")
  writer.string(effects_record_version)
  writer.string(reconciliation_id)
  write_ref(writer, intent.intent_ref())
  write_ref(writer, request.request_ref())
  writer.string(intent.external_idempotency_key())
  writer.string(resolution.tag())
  writer.bytes(@contracts.encode_wire_envelope(observation))
  writer.int64(reconciled_at)
  write_evidence(writer, snapshot)
  let canonical = writer.finish()
  {
    record_version: effects_version(),
    reconciliation_ref: self_ref(
      "effect-reconciliation",
      reconciliation_id,
      @contracts.sha256_digest(canonical),
    ),
    intent_ref: intent.intent_ref(),
    request_ref: request.request_ref(),
    external_idempotency_key: intent.external_idempotency_key(),
    resolution,
    observation,
    reconciled_at,
    evidence: ReadOnlyArray::from_array(snapshot),
    canonical,
  }
}

///|
pub fn ReconciliationRecord::reconciliation_ref(
  self : ReconciliationRecord,
) -> @contracts.RecordRef {
  self.reconciliation_ref
}

///|
pub fn ReconciliationRecord::intent_ref(
  self : ReconciliationRecord,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn ReconciliationRecord::external_idempotency_key(
  self : ReconciliationRecord,
) -> String {
  self.external_idempotency_key
}

///|
pub fn ReconciliationRecord::evidence(
  self : ReconciliationRecord,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn ReconciliationRecord::resolution(
  self : ReconciliationRecord,
) -> ReconciliationResolution {
  self.resolution
}

///|
pub fn ReconciliationRecord::canonical_bytes(
  self : ReconciliationRecord,
) -> Bytes {
  self.canonical
}
