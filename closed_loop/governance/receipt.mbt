///|
/// Immutable terminal review receipt bound to the complete validated chain.
pub struct ReviewReceipt {
  record_version : @contracts.Version
  schema_version : @contracts.Version
  policy_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  receipt_ref : @contracts.RecordRef
  authority_request_ref : @contracts.RecordRef
  authority_grant_ref : @contracts.RecordRef
  review_request_ref : @contracts.RecordRef
  review_decision_ref : @contracts.RecordRef
  subject_digest : @contracts.ContentDigest
  authority_evidence_digest : @contracts.ContentDigest
  authority_criteria_digest : @contracts.ContentDigest
  review_evidence_digest : @contracts.ContentDigest
  review_criteria_digest : @contracts.ContentDigest
  supporting_digest : @contracts.ContentDigest
  contradictory_digest : @contracts.ContentDigest
  reviewer_ref : @contracts.RecordRef
  authority_ref : @contracts.RecordRef
  outcome : ReviewOutcome
  bound_at : Int64
  previous_event_digest : @contracts.ContentDigest
  resulting_revision : Int64
  canonical : Bytes
}

///|
fn review_receipt_signing_bytes(
  policy_ref : @contracts.RecordRef,
  workflow : @contracts.RecordRef,
  receipt_id : String,
  receipt_version : String,
  authority_request_ref : @contracts.RecordRef,
  authority_grant_ref : @contracts.RecordRef,
  review_request_ref : @contracts.RecordRef,
  review_decision_ref : @contracts.RecordRef,
  subject_digest : @contracts.ContentDigest,
  authority_evidence_digest : @contracts.ContentDigest,
  authority_criteria_digest : @contracts.ContentDigest,
  review_evidence_digest : @contracts.ContentDigest,
  review_criteria_digest : @contracts.ContentDigest,
  supporting_digest : @contracts.ContentDigest,
  contradictory_digest : @contracts.ContentDigest,
  reviewer_ref : @contracts.RecordRef,
  authority_ref : @contracts.RecordRef,
  outcome : ReviewOutcome,
  bound_at : Int64,
  previous_event_digest : @contracts.ContentDigest,
  resulting_revision : Int64,
) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(b"MFGRCP01")
  try! writer.write_string(governance_record_version)
  try! writer.write_string(governance_schema_version)
  try! writer.write_bytes(record_bytes(policy_ref))
  try! writer.write_bytes(record_bytes(workflow))
  try! writer.write_string(receipt_id)
  try! writer.write_string(receipt_version)
  try! writer.write_bytes(record_bytes(authority_request_ref))
  try! writer.write_bytes(record_bytes(authority_grant_ref))
  try! writer.write_bytes(record_bytes(review_request_ref))
  try! writer.write_bytes(record_bytes(review_decision_ref))
  try! writer.write_string(subject_digest.text())
  try! writer.write_string(authority_evidence_digest.text())
  try! writer.write_string(authority_criteria_digest.text())
  try! writer.write_string(review_evidence_digest.text())
  try! writer.write_string(review_criteria_digest.text())
  try! writer.write_string(supporting_digest.text())
  try! writer.write_string(contradictory_digest.text())
  try! writer.write_bytes(record_bytes(reviewer_ref))
  try! writer.write_bytes(record_bytes(authority_ref))
  try! writer.write_string(outcome.tag())
  writer.write_int64(bound_at)
  try! writer.write_string(previous_event_digest.text())
  writer.write_int64(resulting_revision)
  writer.finish()
}

///|
fn build_review_receipt(
  projection : GovernanceProjection,
  receipt_id : String,
  receipt_version : String,
  bound_at : Int64,
  supplied_digest : @contracts.ContentDigest?,
) -> ReviewReceipt raise {
  require_text(receipt_id, "review_receipt_id")
  if receipt_version != governance_record_version {
    raise UnsupportedVersion(
      field="review_receipt_version",
      version=receipt_version,
    )
  }
  if projection.receipt is Some(_) {
    raise InvalidState(field="review_receipt_already_bound")
  }
  guard projection.authority_request is Some(authority_request) else {
    raise ReceiptBindingFailure(field="authority_request")
  }
  guard projection.authority_decision is Some(authority_grant) else {
    raise ReceiptBindingFailure(field="authority_grant")
  }
  if authority_grant.outcome != Granted {
    raise ReceiptBindingFailure(field="authority_grant_outcome")
  }
  guard projection.review_request is Some(review_request) else {
    raise ReceiptBindingFailure(field="review_request")
  }
  guard projection.review_decision is Some(review_decision) else {
    raise ReceiptBindingFailure(field="review_decision")
  }
  guard projection.last_event_digest is Some(previous_event_digest) else {
    raise ReceiptBindingFailure(field="previous_event_digest")
  }
  if projection.authority_expiration is Some(_) {
    raise ReceiptBindingFailure(field="authority_expired")
  }
  match authority_request.expires_at {
    Some(expiry) if bound_at >= expiry =>
      raise ReceiptBindingFailure(field="authority_expired_at_binding")
    _ => ()
  }
  if bound_at < review_decision.decided_at {
    raise ReceiptBindingFailure(field="binding_instant")
  }
  if !projection.policy.allows_receipt_outcome(review_decision.outcome) {
    raise ReceiptBindingFailure(field="policy_outcome")
  }
  require_exact_record(
    authority_grant.request_ref,
    authority_request.request_ref,
    "authority_request",
  )
  require_exact_record(
    review_request.authority_request_ref,
    authority_request.request_ref,
    "review_authority_request",
  )
  require_exact_record(
    review_request.authority_grant_ref,
    authority_grant.decision_ref,
    "review_authority_grant",
  )
  require_exact_record(
    review_decision.request_ref,
    review_request.request_ref,
    "review_request",
  )
  let resulting_revision = projection.revision + 1L
  let canonical = review_receipt_signing_bytes(
    projection.policy.policy_ref,
    projection.workflow,
    receipt_id,
    receipt_version,
    authority_request.request_ref,
    authority_grant.decision_ref,
    review_request.request_ref,
    review_decision.decision_ref,
    review_request.subject.envelope_digest(),
    authority_request.evidence_digest,
    authority_request.criteria_digest,
    review_request.evidence_digest,
    review_request.criteria_digest,
    review_decision.supporting_digest,
    review_decision.contradictory_digest,
    review_decision.reviewer_ref,
    authority_grant.authority_ref,
    review_decision.outcome,
    bound_at,
    previous_event_digest,
    resulting_revision,
  )
  let binding = @contracts.sha256_digest(canonical)
  match supplied_digest {
    Some(expected) => require_digest(binding, expected, "review_receipt_digest")
    None => ()
  }
  {
    record_version: @contracts.Version::parse(governance_record_version),
    schema_version: @contracts.Version::parse(governance_schema_version),
    policy_ref: projection.policy.policy_ref,
    workflow: projection.workflow,
    receipt_ref: self_record(
      "governance-review-receipt", receipt_id, receipt_version, binding,
    ),
    authority_request_ref: authority_request.request_ref,
    authority_grant_ref: authority_grant.decision_ref,
    review_request_ref: review_request.request_ref,
    review_decision_ref: review_decision.decision_ref,
    subject_digest: review_request.subject.envelope_digest(),
    authority_evidence_digest: authority_request.evidence_digest,
    authority_criteria_digest: authority_request.criteria_digest,
    review_evidence_digest: review_request.evidence_digest,
    review_criteria_digest: review_request.criteria_digest,
    supporting_digest: review_decision.supporting_digest,
    contradictory_digest: review_decision.contradictory_digest,
    reviewer_ref: review_decision.reviewer_ref,
    authority_ref: authority_grant.authority_ref,
    outcome: review_decision.outcome,
    bound_at,
    previous_event_digest,
    resulting_revision,
    canonical,
  }
}

///|
pub fn ReviewReceipt::bind(
  projection : GovernanceProjection,
  receipt_id : String,
  receipt_version : String,
  bound_at : Int64,
) -> ReviewReceipt raise {
  build_review_receipt(projection, receipt_id, receipt_version, bound_at, None)
}

///|
pub fn ReviewReceipt::receipt_ref(self : ReviewReceipt) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn ReviewReceipt::outcome(self : ReviewReceipt) -> ReviewOutcome {
  self.outcome
}

///|
pub fn ReviewReceipt::is_terminal_approved(self : ReviewReceipt) -> Bool {
  self.outcome == Approved
}

///|
pub fn ReviewReceipt::resulting_revision(self : ReviewReceipt) -> Int64 {
  self.resulting_revision
}

///|
/// Committed logical bind time retained in the canonical receipt.
pub fn ReviewReceipt::bound_at(self : ReviewReceipt) -> Int64 {
  self.bound_at
}

///|
/// Exact authority identity retained by the terminal receipt.
pub fn ReviewReceipt::authority_ref(
  self : ReviewReceipt,
) -> @contracts.RecordRef {
  self.authority_ref
}

///|
/// Exact reviewer identity retained by the terminal receipt.
pub fn ReviewReceipt::reviewer_ref(
  self : ReviewReceipt,
) -> @contracts.RecordRef {
  self.reviewer_ref
}

///|
pub fn ReviewReceipt::binding_digest(
  self : ReviewReceipt,
) -> @contracts.ContentDigest {
  self.receipt_ref.digest()
}

///|
pub fn ReviewReceipt::canonical_bytes(self : ReviewReceipt) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(self.canonical)
  try! writer.write_string(self.receipt_ref.digest().text())
  writer.finish()
}

///|
fn decode_review_receipt(
  bytes : Bytes,
  projection : GovernanceProjection,
) -> ReviewReceipt raise {
  let outer = GovernanceReader::new(bytes)
  let signing = outer.read_bytes()
  let supplied = @contracts.ContentDigest::parse(outer.read_string())
  outer.require_end()
  let reader = GovernanceReader::new(signing)
  if reader.read_bytes() != b"MFGRCP01" {
    raise MalformedPayload(field="review_receipt_magic")
  }
  let encoded_record_version = reader.read_string()
  let encoded_schema_version = reader.read_string()
  if encoded_record_version != governance_record_version {
    raise UnsupportedVersion(
      field="review_receipt_version",
      version=encoded_record_version,
    )
  }
  if encoded_schema_version != governance_schema_version {
    raise UnsupportedVersion(
      field="review_receipt_schema",
      version=encoded_schema_version,
    )
  }
  require_exact_record(
    read_nested_record(reader),
    projection.policy.policy_ref,
    "policy",
  )
  require_exact_record(
    read_nested_record(reader),
    projection.workflow,
    "workflow",
  )
  let receipt_id = reader.read_string()
  let version = reader.read_string()
  guard projection.authority_request is Some(authority_request) &&
    projection.authority_decision is Some(authority_grant) &&
    projection.review_request is Some(review_request) &&
    projection.review_decision is Some(review_decision) else {
    raise ReceiptBindingFailure(field="incomplete_chain")
  }
  require_exact_record(
    read_nested_record(reader),
    authority_request.request_ref,
    "authority_request",
  )
  require_exact_record(
    read_nested_record(reader),
    authority_grant.decision_ref,
    "authority_grant",
  )
  require_exact_record(
    read_nested_record(reader),
    review_request.request_ref,
    "review_request",
  )
  require_exact_record(
    read_nested_record(reader),
    review_decision.decision_ref,
    "review_decision",
  )
  require_digest(
    @contracts.ContentDigest::parse(reader.read_string()),
    review_request.subject.envelope_digest(),
    "review_subject_digest",
  )
  for
    item in [
      (
        reader.read_string(),
        authority_request.evidence_digest,
        "authority_evidence_digest",
      ),
      (
        reader.read_string(),
        authority_request.criteria_digest,
        "authority_criteria_digest",
      ),
      (
        reader.read_string(),
        review_request.evidence_digest,
        "review_evidence_digest",
      ),
      (
        reader.read_string(),
        review_request.criteria_digest,
        "review_criteria_digest",
      ),
      (
        reader.read_string(),
        review_decision.supporting_digest,
        "supporting_evidence_digest",
      ),
      (
        reader.read_string(),
        review_decision.contradictory_digest,
        "contradictory_evidence_digest",
      ),
    ] {
    let (encoded, expected, field) = item
    require_digest(@contracts.ContentDigest::parse(encoded), expected, field)
  }
  require_exact_record(
    read_nested_record(reader),
    review_decision.reviewer_ref,
    "reviewer",
  )
  require_exact_record(
    read_nested_record(reader),
    authority_grant.authority_ref,
    "authority",
  )
  let outcome = review_outcome_from_tag(reader.read_string())
  if outcome != review_decision.outcome {
    raise ReceiptBindingFailure(field="review_outcome")
  }
  let bound_at = reader.read_int64()
  guard projection.last_event_digest is Some(previous) else {
    raise ReceiptBindingFailure(field="previous_event_digest")
  }
  require_digest(
    @contracts.ContentDigest::parse(reader.read_string()),
    previous,
    "previous_event_digest",
  )
  let resulting_revision = reader.read_int64()
  reader.require_end()
  if resulting_revision != projection.revision + 1L {
    raise RevisionMismatch(
      field="receipt_revision",
      expected=projection.revision + 1L,
      actual=resulting_revision,
    )
  }
  build_review_receipt(
    projection,
    receipt_id,
    version,
    bound_at,
    Some(supplied),
  )
}
