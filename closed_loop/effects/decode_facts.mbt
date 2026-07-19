///|
priv struct DecodedObservationRecord {
  observation_ref : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  external_idempotency_key : String
  fencing : FencingBinding?
  observed_at : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
}

///|
fn decode_observation_record_strict(
  expected_id : String,
  bytes : Bytes,
  intent : DecodedIntentRecord,
) -> DecodedObservationRecord raise EffectsError {
  let reader = EffectsReader::new(bytes)
  if reader.read_bytes() != b"MF6ADOB1" {
    raise MalformedRecord(field="dispatch_observation_tag")
  }
  let version_text = reader.read_string()
  require_version(version_text, "dispatch_observation_version")
  let observation_id = reader.read_string()
  if observation_id != expected_id {
    raise IdentityMismatch(field="dispatch_observation_expected_id")
  }
  let intent_ref = reader.read_ref()
  let external_idempotency_key = reader.read_string()
  let fencing = reader.read_optional_fencing()
  let observation_bytes = reader.read_bytes()
  let observation = decode_wire(observation_bytes, "dispatch_observation")
  let observed_at = reader.read_int64()
  let evidence = reader.read_evidence()
  reader.require_end()
  if intent_ref != intent.intent_ref ||
    external_idempotency_key != intent.external_idempotency_key ||
    fencing != intent.fencing ||
    observation.subject() != intent.governed_subject {
    raise IdentityMismatch(field="dispatch_observation_intent_binding")
  }
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6ADOB1")
  writer.string(version_text)
  writer.string(observation_id)
  write_ref(writer, intent_ref)
  writer.string(external_idempotency_key)
  match fencing {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      writer.bytes(value.canonical_bytes())
    }
  }
  writer.bytes(observation_bytes)
  writer.int64(observed_at)
  write_evidence(writer, evidence)
  let canonical = writer.finish()
  if canonical != bytes {
    raise DigestMismatch(field="dispatch_observation_canonical")
  }
  {
    observation_ref: self_ref(
      "dispatch-observation",
      observation_id,
      @contracts.sha256_digest(canonical),
    ),
    intent_ref,
    external_idempotency_key,
    fencing,
    observed_at,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical,
  }
}

///|
fn decode_outcome_strict(value : String) -> ExternalOutcome raise EffectsError {
  match value {
    "succeeded" => Succeeded
    "failed" => Failed
    "unknown" => Unknown
    _ => raise MalformedRecord(field="external_outcome")
  }
}

///|
priv struct DecodedReceiptRecord {
  receipt_ref : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  external_idempotency_key : String
  outcome : ExternalOutcome
  observed_at : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
}

///|
fn decode_receipt_record_strict(
  expected_id : String,
  bytes : Bytes,
  intent : DecodedIntentRecord,
) -> DecodedReceiptRecord raise EffectsError {
  let reader = EffectsReader::new(bytes)
  if reader.read_bytes() != b"MF6AERC1" {
    raise MalformedRecord(field="effect_receipt_tag")
  }
  let record_version = reader.read_string()
  let schema_version = reader.read_string()
  require_version(record_version, "effect_receipt_record_version")
  require_version(schema_version, "effect_receipt_schema_version")
  let receipt_id = reader.read_string()
  if receipt_id != expected_id {
    raise IdentityMismatch(field="effect_receipt_expected_id")
  }
  let intent_ref = reader.read_ref()
  let intent_digest = reader.read_digest()
  let external_idempotency_key = reader.read_string()
  let attempt_ref = reader.read_ref()
  let workflow = reader.read_ref()
  let capability_ref = reader.read_ref()
  let governed_subject = reader.read_ref()
  let authority_grant_ref = reader.read_ref()
  let review_receipt_ref = reader.read_ref()
  let fencing = reader.read_optional_fencing()
  let dispatcher_receipt_bytes = reader.read_bytes()
  let dispatcher_receipt = decode_wire(
    dispatcher_receipt_bytes, "dispatcher_receipt",
  )
  let outcome = decode_outcome_strict(reader.read_string())
  let observed_at = reader.read_int64()
  let evidence = reader.read_evidence()
  reader.require_end()
  if intent_ref != intent.intent_ref ||
    intent_digest != intent.intent_ref.digest() ||
    external_idempotency_key != intent.external_idempotency_key ||
    attempt_ref != intent.attempt_ref ||
    workflow != intent.workflow ||
    capability_ref != intent.capability_ref ||
    governed_subject != intent.governed_subject ||
    authority_grant_ref != intent.governance.authority_grant_ref ||
    review_receipt_ref != intent.governance.review_receipt_ref ||
    fencing != intent.fencing ||
    dispatcher_receipt.subject() != intent.governed_subject {
    raise IdentityMismatch(field="effect_receipt_intent_binding")
  }
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6AERC1")
  writer.string(record_version)
  writer.string(schema_version)
  writer.string(receipt_id)
  write_ref(writer, intent_ref)
  writer.string(intent_digest.text())
  writer.string(external_idempotency_key)
  write_ref(writer, attempt_ref)
  write_ref(writer, workflow)
  write_ref(writer, capability_ref)
  write_ref(writer, governed_subject)
  write_ref(writer, authority_grant_ref)
  write_ref(writer, review_receipt_ref)
  match fencing {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      writer.bytes(value.canonical_bytes())
    }
  }
  writer.bytes(dispatcher_receipt_bytes)
  writer.string(outcome.tag())
  writer.int64(observed_at)
  write_evidence(writer, evidence)
  let canonical = writer.finish()
  if canonical != bytes {
    raise DigestMismatch(field="effect_receipt_canonical")
  }
  {
    receipt_ref: self_ref(
      "effect-receipt",
      receipt_id,
      @contracts.sha256_digest(canonical),
    ),
    intent_ref,
    external_idempotency_key,
    outcome,
    observed_at,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical,
  }
}

///|
priv struct DecodedReconciliationRequestRecord {
  request_ref : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  unknown_receipt_ref : @contracts.RecordRef
  external_idempotency_key : String
  requested_at : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
}

///|
fn decode_reconciliation_request_strict(
  expected_id : String,
  bytes : Bytes,
  intent : DecodedIntentRecord,
  unknown_receipt : DecodedReceiptRecord,
) -> DecodedReconciliationRequestRecord raise EffectsError {
  let reader = EffectsReader::new(bytes)
  if reader.read_bytes() != b"MF6ARRQ1" {
    raise MalformedRecord(field="reconciliation_request_tag")
  }
  let version_text = reader.read_string()
  require_version(version_text, "reconciliation_request_version")
  let request_id = reader.read_string()
  if request_id != expected_id {
    raise IdentityMismatch(field="reconciliation_request_expected_id")
  }
  let intent_ref = reader.read_ref()
  let unknown_receipt_ref = reader.read_ref()
  let external_idempotency_key = reader.read_string()
  let requested_at = reader.read_int64()
  let evidence = reader.read_evidence()
  reader.require_end()
  if intent_ref != intent.intent_ref ||
    unknown_receipt_ref != unknown_receipt.receipt_ref ||
    unknown_receipt.intent_ref != intent.intent_ref ||
    unknown_receipt.outcome != Unknown ||
    external_idempotency_key != intent.external_idempotency_key {
    raise ReconciliationViolation(field="request_unknown_identity")
  }
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6ARRQ1")
  writer.string(version_text)
  writer.string(request_id)
  write_ref(writer, intent_ref)
  write_ref(writer, unknown_receipt_ref)
  writer.string(external_idempotency_key)
  writer.int64(requested_at)
  write_evidence(writer, evidence)
  let canonical = writer.finish()
  if canonical != bytes {
    raise DigestMismatch(field="reconciliation_request_canonical")
  }
  {
    request_ref: self_ref(
      "effect-reconciliation-request",
      request_id,
      @contracts.sha256_digest(canonical),
    ),
    intent_ref,
    unknown_receipt_ref,
    external_idempotency_key,
    requested_at,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical,
  }
}

///|
fn decode_resolution_strict(
  value : String,
) -> ReconciliationResolution raise EffectsError {
  match value {
    "reconciled-succeeded" => ReconciledSucceeded
    "reconciled-failed" => ReconciledFailed
    "reconciled-not-applied" => ReconciledNotApplied
    _ => raise MalformedRecord(field="reconciliation_resolution")
  }
}

///|
priv struct DecodedReconciliationRecord {
  reconciliation_ref : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  request_ref : @contracts.RecordRef
  resolution : ReconciliationResolution
  reconciled_at : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
}

///|
fn decode_reconciliation_record_strict(
  expected_id : String,
  bytes : Bytes,
  intent : DecodedIntentRecord,
  request : DecodedReconciliationRequestRecord,
) -> DecodedReconciliationRecord raise EffectsError {
  let reader = EffectsReader::new(bytes)
  if reader.read_bytes() != b"MF6ARSL1" {
    raise MalformedRecord(field="reconciliation_record_tag")
  }
  let version_text = reader.read_string()
  require_version(version_text, "reconciliation_record_version")
  let reconciliation_id = reader.read_string()
  if reconciliation_id != expected_id {
    raise IdentityMismatch(field="reconciliation_expected_id")
  }
  let intent_ref = reader.read_ref()
  let request_ref = reader.read_ref()
  let external_idempotency_key = reader.read_string()
  let resolution = decode_resolution_strict(reader.read_string())
  let observation_bytes = reader.read_bytes()
  let observation = decode_wire(observation_bytes, "reconciliation_observation")
  let reconciled_at = reader.read_int64()
  let evidence = reader.read_evidence()
  reader.require_end()
  if intent_ref != intent.intent_ref ||
    request_ref != request.request_ref ||
    request.intent_ref != intent.intent_ref ||
    external_idempotency_key != intent.external_idempotency_key ||
    observation.subject() != intent.governed_subject {
    raise ReconciliationViolation(field="resolution_request_identity")
  }
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6ARSL1")
  writer.string(version_text)
  writer.string(reconciliation_id)
  write_ref(writer, intent_ref)
  write_ref(writer, request_ref)
  writer.string(external_idempotency_key)
  writer.string(resolution.tag())
  writer.bytes(observation_bytes)
  writer.int64(reconciled_at)
  write_evidence(writer, evidence)
  let canonical = writer.finish()
  if canonical != bytes {
    raise DigestMismatch(field="reconciliation_record_canonical")
  }
  {
    reconciliation_ref: self_ref(
      "effect-reconciliation",
      reconciliation_id,
      @contracts.sha256_digest(canonical),
    ),
    intent_ref,
    request_ref,
    resolution,
    reconciled_at,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical,
  }
}
