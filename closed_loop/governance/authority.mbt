///|
/// Typed effective authority decision.
pub(all) enum AuthorityDecisionOutcome {
  Granted
  Denied
} derive(Eq, Debug)

///|
fn AuthorityDecisionOutcome::tag(self : AuthorityDecisionOutcome) -> String {
  match self {
    Granted => "granted"
    Denied => "denied"
  }
}

///|
fn authority_outcome_from_tag(
  value : String,
) -> AuthorityDecisionOutcome raise GovernanceError {
  match value {
    "granted" => Granted
    "denied" => Denied
    _ => raise MalformedPayload(field="authority_outcome")
  }
}

///|
/// Immutable authority request bound to ordered criteria and evidence.
pub struct AuthorityRequest {
  record_version : @contracts.Version
  schema_version : @contracts.Version
  policy_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  request_ref : @contracts.RecordRef
  attachment_ref : @contracts.RecordRef
  authority_subject : @contracts.WireEnvelope
  criteria : ReadOnlyArray[@contracts.RecordRef]
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  requested_at : Int64
  expires_at : Int64?
  workflow_revision : Int64
  evidence_digest : @contracts.ContentDigest
  criteria_digest : @contracts.ContentDigest
  idempotency_key : String
  canonical : Bytes
}

///|
fn require_unique_criteria(
  values : ArrayView[@contracts.RecordRef],
  field : String,
) -> Unit raise GovernanceError {
  for index, value in values {
    for prior in 0..<index {
      if values[prior] == value {
        raise CriteriaViolation(field~)
      }
    }
  }
}

///|
fn authority_request_signing_bytes(
  policy_ref : @contracts.RecordRef,
  workflow : @contracts.RecordRef,
  request_id : String,
  request_version : String,
  attachment_ref : @contracts.RecordRef,
  authority_subject : @contracts.WireEnvelope,
  criteria : ArrayView[@contracts.RecordRef],
  evidence : ArrayView[@contracts.EvidenceRef],
  requested_at : Int64,
  expires_at : Int64?,
  workflow_revision : Int64,
  evidence_digest : @contracts.ContentDigest,
  criteria_digest : @contracts.ContentDigest,
  idempotency_key : String,
) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(b"MFGARQ01")
  try! writer.write_string(governance_record_version)
  try! writer.write_string(governance_schema_version)
  try! writer.write_bytes(record_bytes(policy_ref))
  try! writer.write_bytes(record_bytes(workflow))
  try! writer.write_string(request_id)
  try! writer.write_string(request_version)
  try! writer.write_bytes(record_bytes(attachment_ref))
  try! write_envelope(writer, authority_subject)
  try! write_records(writer, criteria)
  try! write_evidence_list(writer, evidence)
  writer.write_int64(requested_at)
  writer.write_optional_int64(expires_at)
  writer.write_int64(workflow_revision)
  try! writer.write_string(evidence_digest.text())
  try! writer.write_string(criteria_digest.text())
  try! writer.write_string(idempotency_key)
  writer.finish()
}

///|
fn build_authority_request(
  policy : GovernancePolicy,
  workflow : @contracts.RecordRef,
  request_id : String,
  request_version : String,
  attachment_ref : @contracts.RecordRef,
  attachment_evidence_digest : @contracts.ContentDigest,
  authority_subject : @contracts.WireEnvelope,
  criteria : Array[@contracts.RecordRef],
  evidence : Array[@contracts.EvidenceRef],
  requested_at : Int64,
  expires_at : Int64?,
  workflow_revision : Int64,
  idempotency_key : String,
  supplied_digest : @contracts.ContentDigest?,
) -> AuthorityRequest raise {
  require_text(request_id, "authority_request_id")
  require_text(idempotency_key, "authority_request_idempotency")
  if request_version != governance_record_version {
    raise UnsupportedVersion(
      field="authority_request_version",
      version=request_version,
    )
  }
  require_revision(workflow_revision, "authority_request_revision")
  policy.require_evidence_count(evidence, "authority_request_evidence")
  policy.require_criteria_count(criteria, "authority_request_criteria")
  require_unique_criteria(criteria, "authority_request_criteria")
  match expires_at {
    Some(expiry) if expiry <= requested_at =>
      raise ExpiryViolation(field="authority_request_expiry")
    _ => ()
  }
  let evidence_digest = ordered_evidence_digest(b"MFGEVL01", evidence)
  require_digest(
    evidence_digest, attachment_evidence_digest, "attachment_evidence_digest",
  )
  let criteria_digest = ordered_record_digest(b"MFGACR01", criteria)
  let canonical = authority_request_signing_bytes(
    policy.policy_ref,
    workflow,
    request_id,
    request_version,
    attachment_ref,
    authority_subject,
    criteria,
    evidence,
    requested_at,
    expires_at,
    workflow_revision,
    evidence_digest,
    criteria_digest,
    idempotency_key,
  )
  let binding = @contracts.sha256_digest(canonical)
  match supplied_digest {
    Some(expected) =>
      require_digest(binding, expected, "authority_request_digest")
    None => ()
  }
  {
    record_version: @contracts.Version::parse(governance_record_version),
    schema_version: @contracts.Version::parse(governance_schema_version),
    policy_ref: policy.policy_ref,
    workflow,
    request_ref: self_record(
      "governance-authority-request", request_id, request_version, binding,
    ),
    attachment_ref,
    authority_subject,
    criteria: ReadOnlyArray::from_array(criteria.copy()),
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    requested_at,
    expires_at,
    workflow_revision,
    evidence_digest,
    criteria_digest,
    idempotency_key,
    canonical,
  }
}

///|
pub fn AuthorityRequest::new(
  policy : GovernancePolicy,
  workflow : @contracts.RecordRef,
  request_id : String,
  request_version : String,
  attachment : EvidenceAttachment,
  authority_subject : @contracts.WireEnvelope,
  criteria : Array[@contracts.RecordRef],
  evidence : Array[@contracts.EvidenceRef],
  requested_at : Int64,
  expires_at : Int64?,
  workflow_revision : Int64,
  idempotency_key : String,
) -> AuthorityRequest raise {
  require_exact_record(attachment.workflow, workflow, "attachment_workflow")
  require_exact_record(attachment.policy_ref, policy.policy_ref, "policy")
  if !same_evidence(attachment.evidence, evidence) {
    raise EvidenceViolation(field="attachment_evidence_order")
  }
  build_authority_request(
    policy,
    workflow,
    request_id,
    request_version,
    attachment.attachment_ref,
    attachment.evidence_digest,
    authority_subject,
    criteria,
    evidence,
    requested_at,
    expires_at,
    workflow_revision,
    idempotency_key,
    None,
  )
}

///|
pub fn AuthorityRequest::workflow(
  self : AuthorityRequest,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn AuthorityRequest::request_ref(
  self : AuthorityRequest,
) -> @contracts.RecordRef {
  self.request_ref
}

///|
pub fn AuthorityRequest::authority_subject(
  self : AuthorityRequest,
) -> @contracts.WireEnvelope {
  self.authority_subject
}

///|
pub fn AuthorityRequest::criteria(
  self : AuthorityRequest,
) -> ReadOnlyArray[@contracts.RecordRef] {
  self.criteria
}

///|
pub fn AuthorityRequest::evidence(
  self : AuthorityRequest,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn AuthorityRequest::requested_at(self : AuthorityRequest) -> Int64 {
  self.requested_at
}

///|
pub fn AuthorityRequest::expires_at(self : AuthorityRequest) -> Int64? {
  self.expires_at
}

///|
pub fn AuthorityRequest::workflow_revision(self : AuthorityRequest) -> Int64 {
  self.workflow_revision
}

///|
pub fn AuthorityRequest::evidence_digest(
  self : AuthorityRequest,
) -> @contracts.ContentDigest {
  self.evidence_digest
}

///|
pub fn AuthorityRequest::criteria_digest(
  self : AuthorityRequest,
) -> @contracts.ContentDigest {
  self.criteria_digest
}

///|
pub fn AuthorityRequest::idempotency_key(self : AuthorityRequest) -> String {
  self.idempotency_key
}

///|
pub fn AuthorityRequest::binding_digest(
  self : AuthorityRequest,
) -> @contracts.ContentDigest {
  self.request_ref.digest()
}

///|
pub fn AuthorityRequest::canonical_bytes(self : AuthorityRequest) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(self.canonical)
  try! writer.write_string(self.request_ref.digest().text())
  writer.finish()
}

///|
pub struct AuthorityDecision {
  policy_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  decision_ref : @contracts.RecordRef
  request_ref : @contracts.RecordRef
  outcome : AuthorityDecisionOutcome
  attestation : @contracts.WireEnvelope
  authority_ref : @contracts.RecordRef
  decided_at : Int64
  evidence_digest : @contracts.ContentDigest
  criteria_digest : @contracts.ContentDigest
  prior_revision : Int64
  canonical : Bytes
}

///|
fn authority_decision_signing_bytes(
  policy_ref : @contracts.RecordRef,
  workflow : @contracts.RecordRef,
  decision_id : String,
  decision_version : String,
  request_ref : @contracts.RecordRef,
  outcome : AuthorityDecisionOutcome,
  attestation : @contracts.WireEnvelope,
  authority_ref : @contracts.RecordRef,
  decided_at : Int64,
  evidence_digest : @contracts.ContentDigest,
  criteria_digest : @contracts.ContentDigest,
  prior_revision : Int64,
) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(b"MFGADC01")
  try! writer.write_bytes(record_bytes(policy_ref))
  try! writer.write_bytes(record_bytes(workflow))
  try! writer.write_string(decision_id)
  try! writer.write_string(decision_version)
  try! writer.write_bytes(record_bytes(request_ref))
  try! writer.write_string(outcome.tag())
  try! write_envelope(writer, attestation)
  try! writer.write_bytes(record_bytes(authority_ref))
  writer.write_int64(decided_at)
  try! writer.write_string(evidence_digest.text())
  try! writer.write_string(criteria_digest.text())
  writer.write_int64(prior_revision)
  writer.finish()
}

///|
fn build_authority_decision(
  policy : GovernancePolicy,
  workflow : @contracts.RecordRef,
  decision_id : String,
  decision_version : String,
  request : AuthorityRequest,
  outcome : AuthorityDecisionOutcome,
  attestation : @contracts.WireEnvelope,
  authority_ref : @contracts.RecordRef,
  decided_at : Int64,
  prior_revision : Int64,
  supplied_digest : @contracts.ContentDigest?,
) -> AuthorityDecision raise {
  require_text(decision_id, "authority_decision_id")
  if decision_version != governance_record_version {
    raise UnsupportedVersion(
      field="authority_decision_version",
      version=decision_version,
    )
  }
  require_exact_record(request.workflow, workflow, "authority_request_workflow")
  require_exact_record(request.policy_ref, policy.policy_ref, "policy")
  if !policy.allows_authority(authority_ref) {
    raise IdentityMismatch(field="authority_kind")
  }
  require_exact_record(
    attestation.subject(),
    authority_ref,
    "authority_attestation_subject",
  )
  if decided_at < request.requested_at {
    raise ExpiryViolation(field="authority_decision_instant")
  }
  match request.expires_at {
    Some(expiry) if decided_at >= expiry =>
      raise ExpiryViolation(field="authority_decision_after_expiry")
    _ => ()
  }
  require_revision(prior_revision, "authority_decision_revision")
  let canonical = authority_decision_signing_bytes(
    policy.policy_ref,
    workflow,
    decision_id,
    decision_version,
    request.request_ref,
    outcome,
    attestation,
    authority_ref,
    decided_at,
    request.evidence_digest,
    request.criteria_digest,
    prior_revision,
  )
  let binding = @contracts.sha256_digest(canonical)
  match supplied_digest {
    Some(expected) =>
      require_digest(binding, expected, "authority_decision_digest")
    None => ()
  }
  {
    policy_ref: policy.policy_ref,
    workflow,
    decision_ref: self_record(
      "governance-authority-decision", decision_id, decision_version, binding,
    ),
    request_ref: request.request_ref,
    outcome,
    attestation,
    authority_ref,
    decided_at,
    evidence_digest: request.evidence_digest,
    criteria_digest: request.criteria_digest,
    prior_revision,
    canonical,
  }
}

///|
pub fn AuthorityDecision::grant(
  policy : GovernancePolicy,
  workflow : @contracts.RecordRef,
  decision_id : String,
  decision_version : String,
  request : AuthorityRequest,
  attestation : @contracts.WireEnvelope,
  authority_ref : @contracts.RecordRef,
  decided_at : Int64,
  prior_revision : Int64,
) -> AuthorityDecision raise {
  build_authority_decision(
    policy,
    workflow,
    decision_id,
    decision_version,
    request,
    Granted,
    attestation,
    authority_ref,
    decided_at,
    prior_revision,
    None,
  )
}

///|
pub fn AuthorityDecision::deny(
  policy : GovernancePolicy,
  workflow : @contracts.RecordRef,
  decision_id : String,
  decision_version : String,
  request : AuthorityRequest,
  attestation : @contracts.WireEnvelope,
  authority_ref : @contracts.RecordRef,
  decided_at : Int64,
  prior_revision : Int64,
) -> AuthorityDecision raise {
  build_authority_decision(
    policy,
    workflow,
    decision_id,
    decision_version,
    request,
    Denied,
    attestation,
    authority_ref,
    decided_at,
    prior_revision,
    None,
  )
}

///|
pub fn AuthorityDecision::decision_ref(
  self : AuthorityDecision,
) -> @contracts.RecordRef {
  self.decision_ref
}

///|
pub fn AuthorityDecision::request_ref(
  self : AuthorityDecision,
) -> @contracts.RecordRef {
  self.request_ref
}

///|
pub fn AuthorityDecision::outcome(
  self : AuthorityDecision,
) -> AuthorityDecisionOutcome {
  self.outcome
}

///|
pub fn AuthorityDecision::authority_ref(
  self : AuthorityDecision,
) -> @contracts.RecordRef {
  self.authority_ref
}

///|
pub fn AuthorityDecision::decided_at(self : AuthorityDecision) -> Int64 {
  self.decided_at
}

///|
pub fn AuthorityDecision::binding_digest(
  self : AuthorityDecision,
) -> @contracts.ContentDigest {
  self.decision_ref.digest()
}

///|
pub fn AuthorityDecision::canonical_bytes(self : AuthorityDecision) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(self.canonical)
  try! writer.write_string(self.decision_ref.digest().text())
  writer.finish()
}

///|
pub struct AuthorityExpiration {
  policy_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  expiration_ref : @contracts.RecordRef
  request_ref : @contracts.RecordRef
  expires_at : Int64
  asserted_at : Int64
  prior_revision : Int64
  canonical : Bytes
}

///|
fn authority_expiration_signing_bytes(
  policy_ref : @contracts.RecordRef,
  workflow : @contracts.RecordRef,
  expiration_id : String,
  expiration_version : String,
  request_ref : @contracts.RecordRef,
  expires_at : Int64,
  asserted_at : Int64,
  prior_revision : Int64,
) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(b"MFGAEX01")
  try! writer.write_bytes(record_bytes(policy_ref))
  try! writer.write_bytes(record_bytes(workflow))
  try! writer.write_string(expiration_id)
  try! writer.write_string(expiration_version)
  try! writer.write_bytes(record_bytes(request_ref))
  writer.write_int64(expires_at)
  writer.write_int64(asserted_at)
  writer.write_int64(prior_revision)
  writer.finish()
}

///|
fn build_authority_expiration(
  policy : GovernancePolicy,
  workflow : @contracts.RecordRef,
  expiration_id : String,
  expiration_version : String,
  request : AuthorityRequest,
  asserted_at : Int64,
  prior_revision : Int64,
  supplied_digest : @contracts.ContentDigest?,
) -> AuthorityExpiration raise {
  require_text(expiration_id, "authority_expiration_id")
  if expiration_version != governance_record_version {
    raise UnsupportedVersion(
      field="authority_expiration_version",
      version=expiration_version,
    )
  }
  require_exact_record(request.workflow, workflow, "authority_request_workflow")
  require_exact_record(request.policy_ref, policy.policy_ref, "policy")
  guard request.expires_at is Some(expires_at) else {
    raise ExpiryViolation(field="missing_authority_expiry")
  }
  if asserted_at < expires_at {
    raise ExpiryViolation(field="premature_authority_expiry")
  }
  require_revision(prior_revision, "authority_expiration_revision")
  let canonical = authority_expiration_signing_bytes(
    policy.policy_ref,
    workflow,
    expiration_id,
    expiration_version,
    request.request_ref,
    expires_at,
    asserted_at,
    prior_revision,
  )
  let binding = @contracts.sha256_digest(canonical)
  match supplied_digest {
    Some(expected) =>
      require_digest(binding, expected, "authority_expiration_digest")
    None => ()
  }
  {
    policy_ref: policy.policy_ref,
    workflow,
    expiration_ref: self_record(
      "governance-authority-expiration", expiration_id, expiration_version, binding,
    ),
    request_ref: request.request_ref,
    expires_at,
    asserted_at,
    prior_revision,
    canonical,
  }
}

///|
pub fn AuthorityExpiration::new(
  policy : GovernancePolicy,
  workflow : @contracts.RecordRef,
  expiration_id : String,
  expiration_version : String,
  request : AuthorityRequest,
  asserted_at : Int64,
  prior_revision : Int64,
) -> AuthorityExpiration raise {
  build_authority_expiration(
    policy,
    workflow,
    expiration_id,
    expiration_version,
    request,
    asserted_at,
    prior_revision,
    None,
  )
}

///|
pub fn AuthorityExpiration::expiration_ref(
  self : AuthorityExpiration,
) -> @contracts.RecordRef {
  self.expiration_ref
}

///|
pub fn AuthorityExpiration::request_ref(
  self : AuthorityExpiration,
) -> @contracts.RecordRef {
  self.request_ref
}

///|
pub fn AuthorityExpiration::asserted_at(self : AuthorityExpiration) -> Int64 {
  self.asserted_at
}

///|
pub fn AuthorityExpiration::canonical_bytes(
  self : AuthorityExpiration,
) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(self.canonical)
  try! writer.write_string(self.expiration_ref.digest().text())
  writer.finish()
}

///|
fn decode_authority_request(
  bytes : Bytes,
  policy : GovernancePolicy,
  attachment : EvidenceAttachment,
) -> AuthorityRequest raise {
  let outer = GovernanceReader::new(bytes)
  let signing = outer.read_bytes()
  let supplied = @contracts.ContentDigest::parse(outer.read_string())
  outer.require_end()
  let reader = GovernanceReader::new(signing)
  if reader.read_bytes() != b"MFGARQ01" {
    raise MalformedPayload(field="authority_request_magic")
  }
  let encoded_record_version = reader.read_string()
  let encoded_schema_version = reader.read_string()
  if encoded_record_version != governance_record_version {
    raise UnsupportedVersion(
      field="authority_request_version",
      version=encoded_record_version,
    )
  }
  if encoded_schema_version != governance_schema_version {
    raise UnsupportedVersion(
      field="authority_request_schema",
      version=encoded_schema_version,
    )
  }
  require_exact_record(read_nested_record(reader), policy.policy_ref, "policy")
  let workflow = read_nested_record(reader)
  let request_id = reader.read_string()
  let version = reader.read_string()
  let attachment_ref = read_nested_record(reader)
  require_exact_record(
    attachment_ref,
    attachment.attachment_ref,
    "evidence_attachment",
  )
  let subject = read_envelope(reader)
  let criteria = read_records(reader)
  let evidence = read_evidence_list(reader)
  let requested_at = reader.read_int64()
  let expires_at = reader.read_optional_int64()
  let revision = reader.read_int64()
  let evidence_digest = @contracts.ContentDigest::parse(reader.read_string())
  let criteria_digest = @contracts.ContentDigest::parse(reader.read_string())
  let key = reader.read_string()
  reader.require_end()
  if !same_evidence(attachment.evidence, evidence) {
    raise EvidenceViolation(field="attachment_evidence_order")
  }
  let value = build_authority_request(
    policy,
    workflow,
    request_id,
    version,
    attachment_ref,
    attachment.evidence_digest,
    subject,
    criteria,
    evidence,
    requested_at,
    expires_at,
    revision,
    key,
    Some(supplied),
  )
  require_digest(
    value.evidence_digest,
    evidence_digest,
    "authority_evidence_digest",
  )
  require_digest(
    value.criteria_digest,
    criteria_digest,
    "authority_criteria_digest",
  )
  value
}

///|
fn decode_authority_decision(
  bytes : Bytes,
  policy : GovernancePolicy,
  request : AuthorityRequest,
) -> AuthorityDecision raise {
  let outer = GovernanceReader::new(bytes)
  let signing = outer.read_bytes()
  let supplied = @contracts.ContentDigest::parse(outer.read_string())
  outer.require_end()
  let reader = GovernanceReader::new(signing)
  if reader.read_bytes() != b"MFGADC01" {
    raise MalformedPayload(field="authority_decision_magic")
  }
  require_exact_record(read_nested_record(reader), policy.policy_ref, "policy")
  let workflow = read_nested_record(reader)
  let decision_id = reader.read_string()
  let version = reader.read_string()
  require_exact_record(
    read_nested_record(reader),
    request.request_ref,
    "authority_request",
  )
  let outcome = authority_outcome_from_tag(reader.read_string())
  let attestation = read_envelope(reader)
  let authority_ref = read_nested_record(reader)
  let decided_at = reader.read_int64()
  let evidence_digest = @contracts.ContentDigest::parse(reader.read_string())
  let criteria_digest = @contracts.ContentDigest::parse(reader.read_string())
  let prior_revision = reader.read_int64()
  reader.require_end()
  let value = build_authority_decision(
    policy,
    workflow,
    decision_id,
    version,
    request,
    outcome,
    attestation,
    authority_ref,
    decided_at,
    prior_revision,
    Some(supplied),
  )
  require_digest(
    value.evidence_digest,
    evidence_digest,
    "authority_evidence_digest",
  )
  require_digest(
    value.criteria_digest,
    criteria_digest,
    "authority_criteria_digest",
  )
  value
}

///|
fn decode_authority_expiration(
  bytes : Bytes,
  policy : GovernancePolicy,
  request : AuthorityRequest,
) -> AuthorityExpiration raise {
  let outer = GovernanceReader::new(bytes)
  let signing = outer.read_bytes()
  let supplied = @contracts.ContentDigest::parse(outer.read_string())
  outer.require_end()
  let reader = GovernanceReader::new(signing)
  if reader.read_bytes() != b"MFGAEX01" {
    raise MalformedPayload(field="authority_expiration_magic")
  }
  require_exact_record(read_nested_record(reader), policy.policy_ref, "policy")
  let workflow = read_nested_record(reader)
  let expiration_id = reader.read_string()
  let version = reader.read_string()
  require_exact_record(
    read_nested_record(reader),
    request.request_ref,
    "authority_request",
  )
  let expires_at = reader.read_int64()
  let asserted_at = reader.read_int64()
  let prior_revision = reader.read_int64()
  reader.require_end()
  guard request.expires_at is Some(expected_expiry) else {
    raise ExpiryViolation(field="missing_authority_expiry")
  }
  if expires_at != expected_expiry {
    raise ExpiryViolation(field="authority_expiry_binding")
  }
  build_authority_expiration(
    policy,
    workflow,
    expiration_id,
    version,
    request,
    asserted_at,
    prior_revision,
    Some(supplied),
  )
}
