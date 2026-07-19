///|
/// One typed finding bound to an exact criterion identity.
pub struct CriterionFinding {
  criterion : @contracts.RecordRef
  disposition : CriterionDisposition
}

///|
pub fn CriterionFinding::new(
  criterion : @contracts.RecordRef,
  disposition : CriterionDisposition,
) -> CriterionFinding {
  { criterion, disposition }
}

///|
pub fn CriterionFinding::criterion(
  self : CriterionFinding,
) -> @contracts.RecordRef {
  self.criterion
}

///|
pub fn CriterionFinding::disposition(
  self : CriterionFinding,
) -> CriterionDisposition {
  self.disposition
}

///|
fn finding_bytes(value : CriterionFinding) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(record_bytes(value.criterion))
  try! writer.write_string(value.disposition.tag())
  writer.finish()
}

///|
fn read_finding(reader : GovernanceReader) -> CriterionFinding raise {
  let nested = GovernanceReader::new(reader.read_bytes())
  let criterion = read_record(nested)
  nested.require_end()
  let disposition = criterion_disposition_from_tag(reader.read_string())
  { criterion, disposition }
}

///|
pub struct ReviewRequest {
  record_version : @contracts.Version
  schema_version : @contracts.Version
  policy_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  request_ref : @contracts.RecordRef
  authority_request_ref : @contracts.RecordRef
  authority_grant_ref : @contracts.RecordRef
  authority_expires_at : Int64?
  criteria : ReadOnlyArray[@contracts.RecordRef]
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  subject : @contracts.WireEnvelope
  requested_at : Int64
  requested_revision : Int64
  authority_evidence_digest : @contracts.ContentDigest
  authority_criteria_digest : @contracts.ContentDigest
  evidence_digest : @contracts.ContentDigest
  criteria_digest : @contracts.ContentDigest
  idempotency_key : String
  canonical : Bytes
}

///|
fn review_request_signing_bytes(
  policy_ref : @contracts.RecordRef,
  workflow : @contracts.RecordRef,
  request_id : String,
  request_version : String,
  authority_request_ref : @contracts.RecordRef,
  authority_grant_ref : @contracts.RecordRef,
  authority_expires_at : Int64?,
  criteria : ArrayView[@contracts.RecordRef],
  evidence : ArrayView[@contracts.EvidenceRef],
  subject : @contracts.WireEnvelope,
  requested_at : Int64,
  requested_revision : Int64,
  authority_evidence_digest : @contracts.ContentDigest,
  authority_criteria_digest : @contracts.ContentDigest,
  evidence_digest : @contracts.ContentDigest,
  criteria_digest : @contracts.ContentDigest,
  idempotency_key : String,
) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(b"MFGRRQ01")
  try! writer.write_string(governance_record_version)
  try! writer.write_string(governance_schema_version)
  try! writer.write_bytes(record_bytes(policy_ref))
  try! writer.write_bytes(record_bytes(workflow))
  try! writer.write_string(request_id)
  try! writer.write_string(request_version)
  try! writer.write_bytes(record_bytes(authority_request_ref))
  try! writer.write_bytes(record_bytes(authority_grant_ref))
  writer.write_optional_int64(authority_expires_at)
  try! write_records(writer, criteria)
  try! write_evidence_list(writer, evidence)
  try! write_envelope(writer, subject)
  writer.write_int64(requested_at)
  writer.write_int64(requested_revision)
  try! writer.write_string(authority_evidence_digest.text())
  try! writer.write_string(authority_criteria_digest.text())
  try! writer.write_string(evidence_digest.text())
  try! writer.write_string(criteria_digest.text())
  try! writer.write_string(idempotency_key)
  writer.finish()
}

///|
fn build_review_request(
  policy : GovernancePolicy,
  workflow : @contracts.RecordRef,
  request_id : String,
  request_version : String,
  authority_request : AuthorityRequest,
  authority_grant : AuthorityDecision,
  criteria : Array[@contracts.RecordRef],
  evidence : Array[@contracts.EvidenceRef],
  subject : @contracts.WireEnvelope,
  requested_at : Int64,
  requested_revision : Int64,
  idempotency_key : String,
  supplied_digest : @contracts.ContentDigest?,
) -> ReviewRequest raise {
  require_text(request_id, "review_request_id")
  require_text(idempotency_key, "review_request_idempotency")
  if request_version != governance_record_version {
    raise UnsupportedVersion(
      field="review_request_version",
      version=request_version,
    )
  }
  require_exact_record(
    authority_request.workflow,
    workflow,
    "authority_request_workflow",
  )
  require_exact_record(
    authority_grant.workflow,
    workflow,
    "authority_grant_workflow",
  )
  require_exact_record(
    authority_request.policy_ref,
    policy.policy_ref,
    "policy",
  )
  require_exact_record(authority_grant.policy_ref, policy.policy_ref, "policy")
  require_exact_record(
    authority_grant.request_ref,
    authority_request.request_ref,
    "authority_request",
  )
  if authority_grant.outcome != Granted {
    raise InvalidState(field="authority_not_granted")
  }
  if requested_at < authority_grant.decided_at {
    raise ExpiryViolation(field="review_requested_before_grant")
  }
  match authority_request.expires_at {
    Some(expiry) if requested_at >= expiry =>
      raise ExpiryViolation(field="review_requested_after_expiry")
    _ => ()
  }
  require_revision(requested_revision, "review_request_revision")
  policy.require_evidence_count(evidence, "review_request_evidence")
  policy.require_criteria_count(criteria, "review_request_criteria")
  require_unique_criteria(criteria, "review_request_criteria")
  let evidence_digest = ordered_evidence_digest(b"MFGREV01", evidence)
  let criteria_digest = ordered_record_digest(b"MFGREC01", criteria)
  let canonical = review_request_signing_bytes(
    policy.policy_ref,
    workflow,
    request_id,
    request_version,
    authority_request.request_ref,
    authority_grant.decision_ref,
    authority_request.expires_at,
    criteria,
    evidence,
    subject,
    requested_at,
    requested_revision,
    authority_request.evidence_digest,
    authority_request.criteria_digest,
    evidence_digest,
    criteria_digest,
    idempotency_key,
  )
  let binding = @contracts.sha256_digest(canonical)
  match supplied_digest {
    Some(expected) => require_digest(binding, expected, "review_request_digest")
    None => ()
  }
  {
    record_version: @contracts.Version::parse(governance_record_version),
    schema_version: @contracts.Version::parse(governance_schema_version),
    policy_ref: policy.policy_ref,
    workflow,
    request_ref: self_record(
      "governance-review-request", request_id, request_version, binding,
    ),
    authority_request_ref: authority_request.request_ref,
    authority_grant_ref: authority_grant.decision_ref,
    authority_expires_at: authority_request.expires_at,
    criteria: ReadOnlyArray::from_array(criteria.copy()),
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    subject,
    requested_at,
    requested_revision,
    authority_evidence_digest: authority_request.evidence_digest,
    authority_criteria_digest: authority_request.criteria_digest,
    evidence_digest,
    criteria_digest,
    idempotency_key,
    canonical,
  }
}

///|
pub fn ReviewRequest::new(
  policy : GovernancePolicy,
  workflow : @contracts.RecordRef,
  request_id : String,
  request_version : String,
  authority_request : AuthorityRequest,
  authority_grant : AuthorityDecision,
  criteria : Array[@contracts.RecordRef],
  evidence : Array[@contracts.EvidenceRef],
  subject : @contracts.WireEnvelope,
  requested_at : Int64,
  requested_revision : Int64,
  idempotency_key : String,
) -> ReviewRequest raise {
  build_review_request(
    policy,
    workflow,
    request_id,
    request_version,
    authority_request,
    authority_grant,
    criteria,
    evidence,
    subject,
    requested_at,
    requested_revision,
    idempotency_key,
    None,
  )
}

///|
pub fn ReviewRequest::request_ref(self : ReviewRequest) -> @contracts.RecordRef {
  self.request_ref
}

///|
pub fn ReviewRequest::criteria(
  self : ReviewRequest,
) -> ReadOnlyArray[@contracts.RecordRef] {
  self.criteria
}

///|
pub fn ReviewRequest::evidence(
  self : ReviewRequest,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn ReviewRequest::subject(self : ReviewRequest) -> @contracts.WireEnvelope {
  self.subject
}

///|
pub fn ReviewRequest::requested_at(self : ReviewRequest) -> Int64 {
  self.requested_at
}

///|
pub fn ReviewRequest::binding_digest(
  self : ReviewRequest,
) -> @contracts.ContentDigest {
  self.request_ref.digest()
}

///|
pub fn ReviewRequest::evidence_digest(
  self : ReviewRequest,
) -> @contracts.ContentDigest {
  self.evidence_digest
}

///|
pub fn ReviewRequest::criteria_digest(
  self : ReviewRequest,
) -> @contracts.ContentDigest {
  self.criteria_digest
}

///|
pub fn ReviewRequest::canonical_bytes(self : ReviewRequest) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(self.canonical)
  try! writer.write_string(self.request_ref.digest().text())
  writer.finish()
}

///|
pub struct ReviewDecision {
  policy_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  decision_ref : @contracts.RecordRef
  request_ref : @contracts.RecordRef
  reviewer_ref : @contracts.RecordRef
  reviewer_attestation : @contracts.WireEnvelope
  outcome : ReviewOutcome
  findings : ReadOnlyArray[CriterionFinding]
  supporting_evidence : ReadOnlyArray[@contracts.EvidenceRef]
  contradictory_evidence : ReadOnlyArray[@contracts.EvidenceRef]
  decided_at : Int64
  workflow_revision : Int64
  criteria_digest : @contracts.ContentDigest
  supporting_digest : @contracts.ContentDigest
  contradictory_digest : @contracts.ContentDigest
  canonical : Bytes
}

///|
fn validate_findings(
  request : ReviewRequest,
  outcome : ReviewOutcome,
  findings : ArrayView[CriterionFinding],
) -> Unit raise GovernanceError {
  if findings.length() != request.criteria.length() {
    raise CriteriaViolation(field="review_finding_cardinality")
  }
  for index, finding in findings {
    if finding.criterion != request.criteria[index] {
      raise OrderingMismatch(field="review_findings")
    }
  }
  match outcome {
    Approved =>
      if findings.any(value => value.disposition != Satisfied) {
        raise CriteriaViolation(field="approved_findings")
      }
    Rejected =>
      if !findings.any(value => value.disposition == Unsatisfied) {
        raise CriteriaViolation(field="rejected_findings")
      }
    ChangesRequested =>
      if !findings.any(value => value.disposition == NeedsRevision) {
        raise CriteriaViolation(field="changes_requested_findings")
      }
  }
}

///|
fn review_decision_signing_bytes(
  policy_ref : @contracts.RecordRef,
  workflow : @contracts.RecordRef,
  decision_id : String,
  decision_version : String,
  request_ref : @contracts.RecordRef,
  reviewer_ref : @contracts.RecordRef,
  reviewer_attestation : @contracts.WireEnvelope,
  outcome : ReviewOutcome,
  findings : ArrayView[CriterionFinding],
  supporting_evidence : ArrayView[@contracts.EvidenceRef],
  contradictory_evidence : ArrayView[@contracts.EvidenceRef],
  decided_at : Int64,
  workflow_revision : Int64,
  criteria_digest : @contracts.ContentDigest,
  supporting_digest : @contracts.ContentDigest,
  contradictory_digest : @contracts.ContentDigest,
) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(b"MFGRDC01")
  try! writer.write_bytes(record_bytes(policy_ref))
  try! writer.write_bytes(record_bytes(workflow))
  try! writer.write_string(decision_id)
  try! writer.write_string(decision_version)
  try! writer.write_bytes(record_bytes(request_ref))
  try! writer.write_bytes(record_bytes(reviewer_ref))
  try! write_envelope(writer, reviewer_attestation)
  try! writer.write_string(outcome.tag())
  try! writer.write_count(findings.length())
  for finding in findings {
    try! writer.write_bytes(finding_bytes(finding))
  }
  try! write_evidence_list(writer, supporting_evidence)
  try! write_evidence_list(writer, contradictory_evidence)
  writer.write_int64(decided_at)
  writer.write_int64(workflow_revision)
  try! writer.write_string(criteria_digest.text())
  try! writer.write_string(supporting_digest.text())
  try! writer.write_string(contradictory_digest.text())
  writer.finish()
}

///|
fn build_review_decision(
  policy : GovernancePolicy,
  workflow : @contracts.RecordRef,
  decision_id : String,
  decision_version : String,
  request : ReviewRequest,
  reviewer_ref : @contracts.RecordRef,
  reviewer_attestation : @contracts.WireEnvelope,
  outcome : ReviewOutcome,
  findings : Array[CriterionFinding],
  supporting_evidence : Array[@contracts.EvidenceRef],
  contradictory_evidence : Array[@contracts.EvidenceRef],
  decided_at : Int64,
  workflow_revision : Int64,
  supplied_digest : @contracts.ContentDigest?,
) -> ReviewDecision raise {
  require_text(decision_id, "review_decision_id")
  if decision_version != governance_record_version {
    raise UnsupportedVersion(
      field="review_decision_version",
      version=decision_version,
    )
  }
  require_exact_record(request.workflow, workflow, "review_request_workflow")
  require_exact_record(request.policy_ref, policy.policy_ref, "policy")
  if !policy.allows_reviewer(reviewer_ref) {
    raise IdentityMismatch(field="reviewer_kind")
  }
  require_exact_record(
    reviewer_attestation.subject(),
    reviewer_ref,
    "reviewer_attestation_subject",
  )
  if decided_at < request.requested_at {
    raise ExpiryViolation(field="review_decision_instant")
  }
  match request.authority_expires_at {
    Some(expiry) if decided_at >= expiry =>
      raise ExpiryViolation(field="review_decision_after_expiry")
    _ => ()
  }
  require_revision(workflow_revision, "review_decision_revision")
  validate_findings(request, outcome, findings)
  policy.require_evidence_count(
    supporting_evidence, "review_decision_supporting_evidence",
  )
  let criteria_digest = ordered_record_digest(b"MFGREC01", request.criteria)
  require_digest(
    criteria_digest,
    request.criteria_digest,
    "review_criteria_digest",
  )
  let supporting_digest = ordered_evidence_digest(
    b"MFGRSP01", supporting_evidence,
  )
  let contradictory_digest = ordered_evidence_digest(
    b"MFGRCT01", contradictory_evidence,
  )
  let canonical = review_decision_signing_bytes(
    policy.policy_ref,
    workflow,
    decision_id,
    decision_version,
    request.request_ref,
    reviewer_ref,
    reviewer_attestation,
    outcome,
    findings,
    supporting_evidence,
    contradictory_evidence,
    decided_at,
    workflow_revision,
    criteria_digest,
    supporting_digest,
    contradictory_digest,
  )
  let binding = @contracts.sha256_digest(canonical)
  match supplied_digest {
    Some(expected) =>
      require_digest(binding, expected, "review_decision_digest")
    None => ()
  }
  {
    policy_ref: policy.policy_ref,
    workflow,
    decision_ref: self_record(
      "governance-review-decision", decision_id, decision_version, binding,
    ),
    request_ref: request.request_ref,
    reviewer_ref,
    reviewer_attestation,
    outcome,
    findings: ReadOnlyArray::from_array(findings.copy()),
    supporting_evidence: ReadOnlyArray::from_array(supporting_evidence.copy()),
    contradictory_evidence: ReadOnlyArray::from_array(
      contradictory_evidence.copy(),
    ),
    decided_at,
    workflow_revision,
    criteria_digest,
    supporting_digest,
    contradictory_digest,
    canonical,
  }
}

///|
pub fn ReviewDecision::new(
  policy : GovernancePolicy,
  workflow : @contracts.RecordRef,
  decision_id : String,
  decision_version : String,
  request : ReviewRequest,
  reviewer_ref : @contracts.RecordRef,
  reviewer_attestation : @contracts.WireEnvelope,
  outcome : ReviewOutcome,
  findings : Array[CriterionFinding],
  supporting_evidence : Array[@contracts.EvidenceRef],
  contradictory_evidence : Array[@contracts.EvidenceRef],
  decided_at : Int64,
  workflow_revision : Int64,
) -> ReviewDecision raise {
  build_review_decision(
    policy,
    workflow,
    decision_id,
    decision_version,
    request,
    reviewer_ref,
    reviewer_attestation,
    outcome,
    findings,
    supporting_evidence,
    contradictory_evidence,
    decided_at,
    workflow_revision,
    None,
  )
}

///|
pub fn ReviewDecision::decision_ref(
  self : ReviewDecision,
) -> @contracts.RecordRef {
  self.decision_ref
}

///|
pub fn ReviewDecision::request_ref(
  self : ReviewDecision,
) -> @contracts.RecordRef {
  self.request_ref
}

///|
pub fn ReviewDecision::reviewer_ref(
  self : ReviewDecision,
) -> @contracts.RecordRef {
  self.reviewer_ref
}

///|
pub fn ReviewDecision::outcome(self : ReviewDecision) -> ReviewOutcome {
  self.outcome
}

///|
/// Committed logical decision time retained in the canonical decision.
pub fn ReviewDecision::decided_at(self : ReviewDecision) -> Int64 {
  self.decided_at
}

///|
pub fn ReviewDecision::findings(
  self : ReviewDecision,
) -> ReadOnlyArray[CriterionFinding] {
  self.findings
}

///|
pub fn ReviewDecision::supporting_evidence(
  self : ReviewDecision,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.supporting_evidence
}

///|
pub fn ReviewDecision::contradictory_evidence(
  self : ReviewDecision,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.contradictory_evidence
}

///|
pub fn ReviewDecision::binding_digest(
  self : ReviewDecision,
) -> @contracts.ContentDigest {
  self.decision_ref.digest()
}

///|
pub fn ReviewDecision::canonical_bytes(self : ReviewDecision) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(self.canonical)
  try! writer.write_string(self.decision_ref.digest().text())
  writer.finish()
}

///|
fn decode_review_request(
  bytes : Bytes,
  policy : GovernancePolicy,
  authority_request : AuthorityRequest,
  authority_grant : AuthorityDecision,
) -> ReviewRequest raise {
  let outer = GovernanceReader::new(bytes)
  let signing = outer.read_bytes()
  let supplied = @contracts.ContentDigest::parse(outer.read_string())
  outer.require_end()
  let reader = GovernanceReader::new(signing)
  if reader.read_bytes() != b"MFGRRQ01" {
    raise MalformedPayload(field="review_request_magic")
  }
  let encoded_record_version = reader.read_string()
  let encoded_schema_version = reader.read_string()
  if encoded_record_version != governance_record_version {
    raise UnsupportedVersion(
      field="review_request_version",
      version=encoded_record_version,
    )
  }
  if encoded_schema_version != governance_schema_version {
    raise UnsupportedVersion(
      field="review_request_schema",
      version=encoded_schema_version,
    )
  }
  require_exact_record(read_nested_record(reader), policy.policy_ref, "policy")
  let workflow = read_nested_record(reader)
  let request_id = reader.read_string()
  let version = reader.read_string()
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
  let encoded_expiry = reader.read_optional_int64()
  if encoded_expiry != authority_request.expires_at {
    raise ExpiryViolation(field="authority_expiry_binding")
  }
  let criteria = read_records(reader)
  let evidence = read_evidence_list(reader)
  let subject = read_envelope(reader)
  let requested_at = reader.read_int64()
  let requested_revision = reader.read_int64()
  let authority_evidence_digest = @contracts.ContentDigest::parse(
    reader.read_string(),
  )
  let authority_criteria_digest = @contracts.ContentDigest::parse(
    reader.read_string(),
  )
  let evidence_digest = @contracts.ContentDigest::parse(reader.read_string())
  let criteria_digest = @contracts.ContentDigest::parse(reader.read_string())
  let key = reader.read_string()
  reader.require_end()
  let value = build_review_request(
    policy,
    workflow,
    request_id,
    version,
    authority_request,
    authority_grant,
    criteria,
    evidence,
    subject,
    requested_at,
    requested_revision,
    key,
    Some(supplied),
  )
  require_digest(
    value.authority_evidence_digest,
    authority_evidence_digest,
    "authority_evidence_digest",
  )
  require_digest(
    value.authority_criteria_digest,
    authority_criteria_digest,
    "authority_criteria_digest",
  )
  require_digest(
    value.evidence_digest,
    evidence_digest,
    "review_evidence_digest",
  )
  require_digest(
    value.criteria_digest,
    criteria_digest,
    "review_criteria_digest",
  )
  value
}

///|
fn decode_review_decision(
  bytes : Bytes,
  policy : GovernancePolicy,
  request : ReviewRequest,
) -> ReviewDecision raise {
  let outer = GovernanceReader::new(bytes)
  let signing = outer.read_bytes()
  let supplied = @contracts.ContentDigest::parse(outer.read_string())
  outer.require_end()
  let reader = GovernanceReader::new(signing)
  if reader.read_bytes() != b"MFGRDC01" {
    raise MalformedPayload(field="review_decision_magic")
  }
  require_exact_record(read_nested_record(reader), policy.policy_ref, "policy")
  let workflow = read_nested_record(reader)
  let decision_id = reader.read_string()
  let version = reader.read_string()
  require_exact_record(
    read_nested_record(reader),
    request.request_ref,
    "review_request",
  )
  let reviewer_ref = read_nested_record(reader)
  let reviewer_attestation = read_envelope(reader)
  let outcome = review_outcome_from_tag(reader.read_string())
  let findings : Array[CriterionFinding] = []
  let finding_count = reader.read_count()
  for _ in 0..<finding_count {
    let nested = GovernanceReader::new(reader.read_bytes())
    findings.push(read_finding(nested))
    nested.require_end()
  }
  let supporting = read_evidence_list(reader)
  let contradictory = read_evidence_list(reader)
  let decided_at = reader.read_int64()
  let workflow_revision = reader.read_int64()
  let criteria_digest = @contracts.ContentDigest::parse(reader.read_string())
  let supporting_digest = @contracts.ContentDigest::parse(reader.read_string())
  let contradictory_digest = @contracts.ContentDigest::parse(
    reader.read_string(),
  )
  reader.require_end()
  let value = build_review_decision(
    policy,
    workflow,
    decision_id,
    version,
    request,
    reviewer_ref,
    reviewer_attestation,
    outcome,
    findings,
    supporting,
    contradictory,
    decided_at,
    workflow_revision,
    Some(supplied),
  )
  require_digest(
    value.criteria_digest,
    criteria_digest,
    "review_criteria_digest",
  )
  require_digest(
    value.supporting_digest,
    supporting_digest,
    "supporting_evidence_digest",
  )
  require_digest(
    value.contradictory_digest,
    contradictory_digest,
    "contradictory_evidence_digest",
  )
  value
}
