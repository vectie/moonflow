///|
priv struct EffectsReader {
  data : Bytes
  mut offset : Int
}

///|
fn EffectsReader::new(data : Bytes) -> EffectsReader {
  { data, offset: 0 }
}

///|
fn EffectsReader::remaining(self : EffectsReader) -> Int {
  self.data.length() - self.offset
}

///|
fn EffectsReader::read_byte(self : EffectsReader) -> Byte raise EffectsError {
  if self.remaining() < 1 {
    raise MalformedRecord(field="unexpected_end")
  }
  let value = self.data[self.offset]
  self.offset += 1
  value
}

///|
fn EffectsReader::read_count(self : EffectsReader) -> Int raise EffectsError {
  if self.remaining() < 4 {
    raise MalformedRecord(field="unexpected_end")
  }
  let first = self.data[self.offset]
  if first >= 128 {
    raise MalformedRecord(field="length_overflow")
  }
  let value = (first.to_int() << 24) |
    (self.data[self.offset + 1].to_int() << 16) |
    (self.data[self.offset + 2].to_int() << 8) |
    self.data[self.offset + 3].to_int()
  self.offset += 4
  value
}

///|
fn EffectsReader::read_int64(self : EffectsReader) -> Int64 raise EffectsError {
  if self.remaining() < 8 {
    raise MalformedRecord(field="unexpected_end")
  }
  let mut value = 0UL
  for index = 0; index < 8; index = index + 1 {
    value = (value << 8) | self.data[self.offset + index].to_uint64()
  }
  self.offset += 8
  value.reinterpret_as_int64()
}

///|
fn EffectsReader::read_bytes(self : EffectsReader) -> Bytes raise EffectsError {
  let count = self.read_count()
  if self.remaining() < count {
    raise MalformedRecord(field="unexpected_end")
  }
  let value = self.data[self.offset:self.offset + count].to_owned()
  self.offset += count
  value
}

///|
fn EffectsReader::read_string(
  self : EffectsReader,
) -> String raise EffectsError {
  @utf8.decode(self.read_bytes()) catch {
    _ => raise MalformedRecord(field="invalid_utf8")
  }
}

///|
fn EffectsReader::read_digest(
  self : EffectsReader,
) -> @contracts.ContentDigest raise EffectsError {
  let text = self.read_string()
  let digest = @contracts.ContentDigest::parse(text) catch {
    _ => raise MalformedRecord(field="digest")
  }
  if digest.text() != text {
    raise MalformedRecord(field="digest_canonical")
  }
  digest
}

///|
fn EffectsReader::read_ref(
  self : EffectsReader,
) -> @contracts.RecordRef raise EffectsError {
  let kind = self.read_string()
  let id = self.read_string()
  let version = self.read_string()
  let digest = self.read_string()
  @contracts.RecordRef::new(kind, id, version, digest) catch {
    _ => raise MalformedRecord(field="record_ref")
  }
}

///|
fn EffectsReader::read_optional_ref(
  self : EffectsReader,
) -> @contracts.RecordRef? raise EffectsError {
  match self.read_byte() {
    0 => None
    1 => Some(self.read_ref())
    _ => raise MalformedRecord(field="optional_ref_marker")
  }
}

///|
fn EffectsReader::read_optional_int64(
  self : EffectsReader,
) -> Int64? raise EffectsError {
  match self.read_byte() {
    0 => None
    1 => Some(self.read_int64())
    _ => raise MalformedRecord(field="optional_int64_marker")
  }
}

///|
fn EffectsReader::read_optional_string(
  self : EffectsReader,
  field : String,
) -> String? raise EffectsError {
  match self.read_byte() {
    0 => None
    1 => Some(self.read_string())
    _ => raise MalformedRecord(field~)
  }
}

///|
fn EffectsReader::read_evidence(
  self : EffectsReader,
) -> Array[@contracts.EvidenceRef] raise EffectsError {
  let count = self.read_count()
  if count > 10000 {
    raise MalformedRecord(field="evidence_count")
  }
  let values : Array[@contracts.EvidenceRef] = Array::new(capacity=count)
  for index = 0; index < count; index = index + 1 {
    let record = self.read_ref()
    let provenance = self.read_ref()
    let observed_digest = self.read_string()
    let locator = self.read_optional_string("evidence_locator_marker")
    let media_type = self.read_optional_string("evidence_media_type_marker")
    let value = @contracts.EvidenceRef::new(
      record,
      provenance,
      observed_digest,
      locator?,
      media_type?,
    ) catch {
      _ => raise MalformedRecord(field="evidence_ref")
    }
    values.push(value)
  }
  values
}

///|
fn EffectsReader::require_end(self : EffectsReader) -> Unit raise EffectsError {
  if self.remaining() != 0 {
    raise MalformedRecord(field="trailing_bytes")
  }
}

///|
fn decode_wire(
  bytes : Bytes,
  field : String,
) -> @contracts.WireEnvelope raise EffectsError {
  let value = @contracts.decode_wire_envelope(bytes) catch {
    _ => raise MalformedRecord(field~)
  }
  if @contracts.encode_wire_envelope(value) != bytes {
    raise DigestMismatch(field~)
  }
  value
}

///|
fn decode_fencing_binding(bytes : Bytes) -> FencingBinding raise EffectsError {
  let reader = EffectsReader::new(bytes)
  if reader.read_bytes() != b"MF6AFNC1" {
    raise MalformedRecord(field="fencing_binding_tag")
  }
  let fence_ref = reader.read_ref()
  let lease_epoch = reader.read_int64()
  let fencing_token = reader.read_int64()
  reader.require_end()
  let value = FencingBinding::new(fence_ref, lease_epoch, fencing_token)
  if value.canonical_bytes() != bytes {
    raise DigestMismatch(field="fencing_binding_canonical")
  }
  value
}

///|
fn EffectsReader::read_optional_fencing(
  self : EffectsReader,
) -> FencingBinding? raise EffectsError {
  match self.read_byte() {
    0 => None
    1 => Some(decode_fencing_binding(self.read_bytes()))
    _ => raise MalformedRecord(field="optional_fencing_marker")
  }
}

///|
/// Structurally decoded governance summary. This is not an authorization
/// validation and must never be exposed as a GovernanceBinding.
priv struct DecodedGovernanceSummary {
  semantic_v2 : Bool
  workflow : @contracts.RecordRef
  policy_ref : @contracts.RecordRef
  policy_bytes : Bytes
  authority_request_ref : @contracts.RecordRef
  authority_grant_ref : @contracts.RecordRef
  authority_ref : @contracts.RecordRef
  authority_expires_at : Int64?
  review_request_ref : @contracts.RecordRef
  review_decision_ref : @contracts.RecordRef
  reviewer_ref : @contracts.RecordRef
  review_receipt_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  governed_subject_digest : @contracts.ContentDigest
  projection_digest : @contracts.ContentDigest
  authoritative_replay_digest : @contracts.ContentDigest
  authority_request_bytes : Bytes
  authority_grant_bytes : Bytes
  review_request_bytes : Bytes
  review_decision_bytes : Bytes
  review_receipt_bytes : Bytes
  canonical : Bytes
}

///|
fn validate_governance_record_blob(
  record_ref : @contracts.RecordRef,
  bytes : Bytes,
  field : String,
) -> Unit raise EffectsError {
  let reader = EffectsReader::new(bytes)
  let signing_bytes = reader.read_bytes()
  let embedded_digest = reader.read_digest()
  reader.require_end()
  if @contracts.sha256_digest(signing_bytes) != embedded_digest ||
    embedded_digest != record_ref.digest() {
    raise DigestMismatch(field~)
  }
  let writer = EffectsWriter::new()
  writer.bytes(signing_bytes)
  writer.string(embedded_digest.text())
  if writer.finish() != bytes {
    raise DigestMismatch(field="governance_record_canonical")
  }
}

///|
fn decode_governance_summary(
  bytes : Bytes,
) -> DecodedGovernanceSummary raise EffectsError {
  let reader = EffectsReader::new(bytes)
  let tag = reader.read_bytes()
  let semantic_v2 = tag == b"MF6AGOV2"
  if tag != b"MF6AGOV1" && !semantic_v2 {
    raise MalformedRecord(field="governance_binding_tag")
  }
  let version_text = reader.read_string()
  require_version(version_text, "governance_binding_version")
  let workflow = reader.read_ref()
  let policy_ref = reader.read_ref()
  let policy_bytes = if semantic_v2 { reader.read_bytes() } else { b"" }
  if semantic_v2 &&
    @contracts.sha256_digest(policy_bytes) != policy_ref.digest() {
    raise DigestMismatch(field="governance_policy_digest")
  }
  let authority_request_ref = reader.read_ref()
  let authority_grant_ref = reader.read_ref()
  let authority_ref = reader.read_ref()
  let authority_expires_at = reader.read_optional_int64()
  let review_request_ref = reader.read_ref()
  let review_decision_ref = reader.read_ref()
  let reviewer_ref = reader.read_ref()
  let review_receipt_ref = reader.read_ref()
  let governed_subject = reader.read_ref()
  let governed_subject_digest = reader.read_digest()
  let projection_digest = reader.read_digest()
  let authoritative_replay_digest = reader.read_digest()
  let authority_request_bytes = reader.read_bytes()
  let authority_grant_bytes = reader.read_bytes()
  let review_request_bytes = reader.read_bytes()
  let review_decision_bytes = reader.read_bytes()
  let review_receipt_bytes = reader.read_bytes()
  reader.require_end()
  validate_governance_record_blob(
    authority_request_ref, authority_request_bytes, "governance_authority_request_digest",
  )
  validate_governance_record_blob(
    authority_grant_ref, authority_grant_bytes, "governance_authority_grant_digest",
  )
  validate_governance_record_blob(
    review_request_ref, review_request_bytes, "governance_review_request_digest",
  )
  validate_governance_record_blob(
    review_decision_ref, review_decision_bytes, "governance_review_decision_digest",
  )
  validate_governance_record_blob(
    review_receipt_ref, review_receipt_bytes, "governance_review_receipt_digest",
  )
  let writer = EffectsWriter::new()
  writer.bytes(tag)
  writer.string(version_text)
  write_ref(writer, workflow)
  write_ref(writer, policy_ref)
  if semantic_v2 {
    writer.bytes(policy_bytes)
  }
  write_ref(writer, authority_request_ref)
  write_ref(writer, authority_grant_ref)
  write_ref(writer, authority_ref)
  writer.optional_int64(authority_expires_at)
  write_ref(writer, review_request_ref)
  write_ref(writer, review_decision_ref)
  write_ref(writer, reviewer_ref)
  write_ref(writer, review_receipt_ref)
  write_ref(writer, governed_subject)
  writer.string(governed_subject_digest.text())
  writer.string(projection_digest.text())
  writer.string(authoritative_replay_digest.text())
  writer.bytes(authority_request_bytes)
  writer.bytes(authority_grant_bytes)
  writer.bytes(review_request_bytes)
  writer.bytes(review_decision_bytes)
  writer.bytes(review_receipt_bytes)
  let canonical = writer.finish()
  if canonical != bytes {
    raise DigestMismatch(field="governance_binding_canonical")
  }
  {
    semantic_v2,
    workflow,
    policy_ref,
    policy_bytes,
    authority_request_ref,
    authority_grant_ref,
    authority_ref,
    authority_expires_at,
    review_request_ref,
    review_decision_ref,
    reviewer_ref,
    review_receipt_ref,
    governed_subject,
    governed_subject_digest,
    projection_digest,
    authoritative_replay_digest,
    authority_request_bytes,
    authority_grant_bytes,
    review_request_bytes,
    review_decision_bytes,
    review_receipt_bytes,
    canonical,
  }
}

///|
fn EffectsReader::read_optional_digest(
  self : EffectsReader,
) -> @contracts.ContentDigest? raise EffectsError {
  match self.read_byte() {
    0 => None
    1 => Some(self.read_digest())
    _ => raise MalformedRecord(field="optional_digest_marker")
  }
}

///|
fn write_optional_digest_strict(
  writer : EffectsWriter,
  value : @contracts.ContentDigest?,
) -> Unit raise EffectsError {
  match value {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      writer.string(value.text())
    }
  }
}

///|
fn decode_retry_receipt_strict(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
) -> CommittedRetryEligibilityReceiptV2 raise EffectsError {
  let reader = EffectsReader::new(bytes)
  if reader.read_bytes() != b"MF6/COMMITTED-RETRY-ELIGIBILITY-RECEIPT-V2/2.0.0" {
    raise MalformedRecord(field="retry_receipt_v2_tag")
  }
  let version_text = reader.read_string()
  require_version(version_text, "retry_receipt_v2_version")
  let workflow = reader.read_ref()
  let root_intent_ref = reader.read_ref()
  let root_attempt_ref = reader.read_ref()
  let source_intent_ref = reader.read_ref()
  let source_attempt_ref = reader.read_ref()
  let lineage_digest = reader.read_digest()
  let attempt_count = reader.read_int64()
  let retry_count = reader.read_int64()
  let retry_ordinal = reader.read_int64()
  let cause_key = reader.read_string()
  let source_record_ref = reader.read_ref()
  let source_record_digest = reader.read_digest()
  let source_observed_at = reader.read_int64()
  let source_event_ref = reader.read_ref()
  let source_event_digest = reader.read_digest()
  let unknown_receipt_ref = reader.read_optional_ref()
  let unknown_receipt_digest = reader.read_optional_digest()
  let unknown_receipt_event_ref = reader.read_optional_ref()
  let reconciliation_request_ref = reader.read_optional_ref()
  let reconciliation_request_digest = reader.read_optional_digest()
  let reconciliation_request_event_ref = reader.read_optional_ref()
  let projection_sequence = reader.read_int64()
  let projection_revision = reader.read_int64()
  let projection_head_digest = reader.read_digest()
  let projection_state_digest = reader.read_digest()
  let projection_replay_digest = reader.read_digest()
  reader.require_end()
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6/COMMITTED-RETRY-ELIGIBILITY-RECEIPT-V2/2.0.0")
  writer.string(version_text)
  write_ref(writer, workflow)
  write_ref(writer, root_intent_ref)
  write_ref(writer, root_attempt_ref)
  write_ref(writer, source_intent_ref)
  write_ref(writer, source_attempt_ref)
  writer.string(lineage_digest.text())
  writer.int64(attempt_count)
  writer.int64(retry_count)
  writer.int64(retry_ordinal)
  writer.string(cause_key)
  write_ref(writer, source_record_ref)
  writer.string(source_record_digest.text())
  writer.int64(source_observed_at)
  write_ref(writer, source_event_ref)
  writer.string(source_event_digest.text())
  write_optional_ref(writer, unknown_receipt_ref)
  write_optional_digest_strict(writer, unknown_receipt_digest)
  write_optional_ref(writer, unknown_receipt_event_ref)
  write_optional_ref(writer, reconciliation_request_ref)
  write_optional_digest_strict(writer, reconciliation_request_digest)
  write_optional_ref(writer, reconciliation_request_event_ref)
  writer.int64(projection_sequence)
  writer.int64(projection_revision)
  writer.string(projection_head_digest.text())
  writer.string(projection_state_digest.text())
  writer.string(projection_replay_digest.text())
  let canonical = writer.finish()
  if canonical != bytes {
    raise DigestMismatch(field="retry_receipt_v2_canonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  let receipt_ref = self_ref(
    "committed-retry-eligibility-receipt-v2",
    source_intent_ref.id(),
    digest,
  )
  if receipt_ref != expected_ref {
    raise IdentityMismatch(field="retry_receipt_v2_expected_ref")
  }
  let receipt = {
    receipt_ref,
    workflow,
    root_intent_ref,
    root_attempt_ref,
    source_intent_ref,
    source_attempt_ref,
    lineage_digest,
    attempt_count,
    retry_count,
    retry_ordinal,
    cause_key,
    source_record_ref,
    source_record_digest,
    source_observed_at,
    source_event_ref,
    source_event_digest,
    unknown_receipt_ref,
    unknown_receipt_digest,
    unknown_receipt_event_ref,
    reconciliation_request_ref,
    reconciliation_request_digest,
    reconciliation_request_event_ref,
    projection_sequence,
    projection_revision,
    projection_head_digest,
    projection_state_digest,
    projection_replay_digest,
    canonical,
    digest,
  }
  receipt.require_integrity()
  receipt
}

///|
priv struct DecodedAttemptRecord {
  attempt_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  causal_event_ref : @contracts.RecordRef
  attempt_ordinal : Int64
  requested_work : @contracts.WireEnvelope
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  governance : DecodedGovernanceSummary
  created_at : Int64
  idempotency_key : String
  retry_of_intent_ref : @contracts.RecordRef?
  retry_receipt : CommittedRetryEligibilityReceiptV2?
  retry_plan : @retry_authority.RetryPlanProposalV2?
  previous_digest : @contracts.ContentDigest
  canonical : Bytes
}

///|
fn decode_attempt_record_strict(
  expected_id : String,
  bytes : Bytes,
) -> DecodedAttemptRecord raise EffectsError {
  require_text(expected_id, "attempt_expected_id")
  let reader = EffectsReader::new(bytes)
  if reader.read_bytes() != b"MF6AATT1" {
    raise MalformedRecord(field="attempt_registration_tag")
  }
  let record_version = reader.read_string()
  let schema_version = reader.read_string()
  require_version(record_version, "attempt_record_version")
  require_version(schema_version, "attempt_schema_version")
  let attempt_id = reader.read_string()
  if attempt_id != expected_id {
    raise IdentityMismatch(field="attempt_expected_id")
  }
  let workflow = reader.read_ref()
  let causal_event_ref = reader.read_ref()
  let attempt_ordinal = reader.read_int64()
  let requested_work_bytes = reader.read_bytes()
  let requested_work_digest = reader.read_digest()
  let evidence = reader.read_evidence()
  let evidence_digest = reader.read_digest()
  let governance_bytes = reader.read_bytes()
  let governance = decode_governance_summary(governance_bytes)
  let created_at = reader.read_int64()
  let idempotency_key = reader.read_string()
  let stage_ref = reader.read_optional_ref()
  let retry_of_intent_ref = reader.read_optional_ref()
  let retry_receipt = match retry_of_intent_ref {
    None => None
    Some(_) => {
      let expected_ref = reader.read_ref()
      let expected_digest = reader.read_digest()
      if expected_ref.digest() != expected_digest {
        raise DigestMismatch(field="attempt_retry_receipt_digest")
      }
      Some(decode_retry_receipt_strict(expected_ref, reader.read_bytes()))
    }
  }
  let retry_plan = match retry_of_intent_ref {
    None => None
    Some(_) => {
      let expected_ref = reader.read_ref()
      let expected_digest = reader.read_digest()
      if expected_ref.digest() != expected_digest {
        raise DigestMismatch(field="attempt_retry_plan_digest")
      }
      Some(
        @retry_authority.RetryPlanProposalV2::decode(
          expected_ref,
          reader.read_bytes(),
        ) catch {
          _ => raise MalformedRecord(field="attempt_retry_plan")
        },
      )
    }
  }
  let previous_digest = reader.read_digest()
  reader.require_end()
  let requested_work = decode_wire(
    requested_work_bytes, "attempt_requested_work",
  )
  if requested_work.envelope_digest() != requested_work_digest ||
    evidence_digest != ordered_evidence_digest(b"MF6AATE1", evidence) {
    raise DigestMismatch(field="attempt_nested_digest")
  }
  if governance.workflow != workflow ||
    requested_work.subject() != governance.governed_subject ||
    causal_event_ref.digest() != previous_digest ||
    attempt_ordinal <= 0L {
    raise IdentityMismatch(field="attempt_structural_binding")
  }
  match governance.authority_expires_at {
    Some(expires_at) if created_at >= expires_at =>
      raise AuthorityExpired(expires_at~, observed_at=created_at)
    _ => ()
  }
  match (retry_of_intent_ref, retry_receipt, retry_plan) {
    (None, None, None) => ()
    (Some(source), Some(receipt), Some(plan)) =>
      if receipt.workflow() != workflow ||
        receipt.source_intent_ref() != source ||
        receipt.projection_head_digest() != previous_digest ||
        plan.workflow() != workflow ||
        plan.receipt_ref() != receipt.receipt_ref() ||
        plan.receipt_digest() != receipt.digest() ||
        plan.receipt_bytes() != receipt.canonical_bytes() ||
        plan.source_intent_ref() != source ||
        plan.source_attempt_ref() != receipt.source_attempt_ref() ||
        plan.root_intent_ref() != receipt.root_intent_ref() ||
        plan.root_attempt_ref() != receipt.root_attempt_ref() ||
        plan.lineage_digest() != receipt.lineage_digest() ||
        plan.attempt_count() != receipt.attempt_count() ||
        plan.retry_count() != receipt.retry_count() ||
        plan.retry_ordinal() != receipt.retry_ordinal() ||
        plan.cause_key() != receipt.cause_key() ||
        plan.requested_work_ref().digest() != requested_work_digest ||
        plan.requested_work_digest() != requested_work_digest ||
        plan.child_attempt_ordinal() != attempt_ordinal ||
        plan.child_attempt_idempotency_key() != idempotency_key ||
        plan.prefix_head_ref() != causal_event_ref ||
        plan.prefix_head_digest() != previous_digest ||
        plan.prefix_sequence() != receipt.projection_sequence() ||
        plan.prefix_revision() != receipt.projection_revision() ||
        plan.prefix_replay_digest() != receipt.projection_replay_digest() ||
        plan.governance_digest() !=
        Some(@contracts.sha256_digest(governance_bytes)) ||
        plan.governance_bytes() != Some(governance_bytes) ||
        plan.governance_deadline() != governance.authority_expires_at ||
        created_at < receipt.source_observed_at() {
        raise RetryEligibilityViolation(field="attempt_retry_receipt_binding")
      }
    _ => raise RetryEligibilityViolation(field="attempt_retry_receipt_pair")
  }
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6AATT1")
  writer.string(record_version)
  writer.string(schema_version)
  writer.string(attempt_id)
  write_ref(writer, workflow)
  write_ref(writer, causal_event_ref)
  writer.int64(attempt_ordinal)
  writer.bytes(requested_work_bytes)
  writer.string(requested_work_digest.text())
  write_evidence(writer, evidence)
  writer.string(evidence_digest.text())
  writer.bytes(governance_bytes)
  writer.int64(created_at)
  writer.string(idempotency_key)
  write_optional_ref(writer, stage_ref)
  write_optional_ref(writer, retry_of_intent_ref)
  match retry_receipt {
    None => ()
    Some(receipt) => {
      write_ref(writer, receipt.receipt_ref())
      writer.string(receipt.digest().text())
      writer.bytes(receipt.canonical_bytes())
      guard retry_plan is Some(plan) else {
        raise RetryEligibilityViolation(field="attempt_retry_plan_missing")
      }
      write_ref(writer, plan.plan_ref())
      writer.string(plan.digest().text())
      writer.bytes(plan.canonical_bytes())
    }
  }
  writer.string(previous_digest.text())
  let canonical = writer.finish()
  if canonical != bytes {
    raise DigestMismatch(field="attempt_registration_canonical")
  }
  let attempt_ref = self_ref(
    "effect-attempt",
    attempt_id,
    @contracts.sha256_digest(canonical),
  )
  {
    attempt_ref,
    workflow,
    causal_event_ref,
    attempt_ordinal,
    requested_work,
    evidence: ReadOnlyArray::from_array(evidence),
    governance,
    created_at,
    idempotency_key,
    retry_of_intent_ref,
    retry_receipt,
    retry_plan,
    previous_digest,
    canonical,
  }
}

///|
priv struct DecodedIntentRecord {
  intent_ref : @contracts.RecordRef
  attempt_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  governance : DecodedGovernanceSummary
  effect_request : @contracts.WireEnvelope
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  external_idempotency_key : String
  capability_ref : @contracts.RecordRef
  capability_kind : String
  fencing : FencingBinding?
  causation_ref : @contracts.RecordRef
  previous_digest : @contracts.ContentDigest
  canonical : Bytes
}

///|
fn decode_intent_record_strict(
  bytes : Bytes,
  attempt : DecodedAttemptRecord,
) -> DecodedIntentRecord raise EffectsError {
  let reader = EffectsReader::new(bytes)
  if reader.read_bytes() != b"MF6AINT1" {
    raise MalformedRecord(field="effect_intent_tag")
  }
  let record_version = reader.read_string()
  let schema_version = reader.read_string()
  require_version(record_version, "effect_intent_record_version")
  require_version(schema_version, "effect_intent_schema_version")
  let intent_id = reader.read_string()
  let attempt_ref = reader.read_ref()
  let attempt_digest = reader.read_digest()
  let workflow = reader.read_ref()
  let governed_subject = reader.read_ref()
  let governance_bytes = reader.read_bytes()
  let governance = decode_governance_summary(governance_bytes)
  let effect_request_bytes = reader.read_bytes()
  let effect_request = decode_wire(effect_request_bytes, "effect_request")
  let evidence = reader.read_evidence()
  let evidence_digest = reader.read_digest()
  let external_idempotency_key = reader.read_string()
  let capability_ref = reader.read_ref()
  let capability_kind = reader.read_string()
  let fencing = reader.read_optional_fencing()
  let created_at = reader.read_int64()
  let causation_ref = reader.read_ref()
  let previous_digest = reader.read_digest()
  reader.require_end()
  if attempt_ref != attempt.attempt_ref ||
    attempt_digest != attempt.attempt_ref.digest() ||
    workflow != attempt.workflow ||
    governed_subject != attempt.governance.governed_subject ||
    governance.canonical != attempt.governance.canonical ||
    effect_request.subject() != governed_subject ||
    evidence_digest != ordered_evidence_digest(b"MF6AINE1", evidence) ||
    causation_ref != attempt.attempt_ref {
    raise IdentityMismatch(field="effect_intent_attempt_binding")
  }
  match governance.authority_expires_at {
    Some(expires_at) if created_at >= expires_at =>
      raise AuthorityExpired(expires_at~, observed_at=created_at)
    _ => ()
  }
  require_text(external_idempotency_key, "external_idempotency_key")
  require_text(capability_kind, "capability_kind")
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6AINT1")
  writer.string(record_version)
  writer.string(schema_version)
  writer.string(intent_id)
  write_ref(writer, attempt_ref)
  writer.string(attempt_digest.text())
  write_ref(writer, workflow)
  write_ref(writer, governed_subject)
  writer.bytes(governance_bytes)
  writer.bytes(effect_request_bytes)
  write_evidence(writer, evidence)
  writer.string(evidence_digest.text())
  writer.string(external_idempotency_key)
  write_ref(writer, capability_ref)
  writer.string(capability_kind)
  match fencing {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      writer.bytes(value.canonical_bytes())
    }
  }
  writer.int64(created_at)
  write_ref(writer, causation_ref)
  writer.string(previous_digest.text())
  let canonical = writer.finish()
  if canonical != bytes {
    raise DigestMismatch(field="effect_intent_canonical")
  }
  {
    intent_ref: self_ref(
      "effect-intent",
      intent_id,
      @contracts.sha256_digest(canonical),
    ),
    attempt_ref,
    workflow,
    governed_subject,
    governance,
    effect_request,
    evidence: ReadOnlyArray::from_array(evidence),
    external_idempotency_key,
    capability_ref,
    capability_kind,
    fencing,
    causation_ref,
    previous_digest,
    canonical,
  }
}
