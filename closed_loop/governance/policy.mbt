///|
/// Typed review result. It is deliberately not a boolean or free text.
pub(all) enum ReviewOutcome {
  Approved
  Rejected
  ChangesRequested
} derive(Eq, Debug)

///|
fn ReviewOutcome::tag(self : ReviewOutcome) -> String {
  match self {
    Approved => "approved"
    Rejected => "rejected"
    ChangesRequested => "changes-requested"
  }
}

///|
fn review_outcome_from_tag(
  value : String,
) -> ReviewOutcome raise GovernanceError {
  match value {
    "approved" => Approved
    "rejected" => Rejected
    "changes-requested" => ChangesRequested
    _ => raise MalformedPayload(field="review_outcome")
  }
}

///|
/// Typed criterion finding. Its meaning is bound to one criterion identity.
pub(all) enum CriterionDisposition {
  Satisfied
  Unsatisfied
  NeedsRevision
} derive(Eq, Debug)

///|
fn CriterionDisposition::tag(self : CriterionDisposition) -> String {
  match self {
    Satisfied => "satisfied"
    Unsatisfied => "unsatisfied"
    NeedsRevision => "needs-revision"
  }
}

///|
fn criterion_disposition_from_tag(
  value : String,
) -> CriterionDisposition raise GovernanceError {
  match value {
    "satisfied" => Satisfied
    "unsatisfied" => Unsatisfied
    "needs-revision" => NeedsRevision
    _ => raise MalformedPayload(field="criterion_disposition")
  }
}

///|
/// Immutable versioned policy for deterministic structural validation only.
pub struct GovernancePolicy {
  policy_ref : @contracts.RecordRef
  event_version : @contracts.Version
  schema_version : @contracts.Version
  authority_kinds : ReadOnlyArray[String]
  reviewer_kinds : ReadOnlyArray[String]
  minimum_evidence : Int
  minimum_criteria : Int
  receipt_outcomes : ReadOnlyArray[ReviewOutcome]
  canonical : Bytes
}

///|
fn normalized_kinds(
  values : Array[String],
  field : String,
) -> Array[String] raise GovernanceError {
  if values.is_empty() {
    raise MalformedPayload(field~)
  }
  let sorted = values.copy()
  sorted.sort()
  let result : Array[String] = []
  for value in sorted {
    require_text(value, field)
    if result.last() != Some(value) {
      result.push(value)
    }
  }
  result
}

///|
fn normalized_outcomes(
  values : Array[ReviewOutcome],
) -> Array[ReviewOutcome] raise GovernanceError {
  if values.is_empty() {
    raise MalformedPayload(field="receipt_outcomes")
  }
  let result : Array[ReviewOutcome] = []
  for candidate in [Approved, Rejected, ChangesRequested] {
    if values.any(value => value == candidate) {
      result.push(candidate)
    }
  }
  result
}

///|
fn policy_signing_bytes(
  policy_id : String,
  policy_version : String,
  event_version : String,
  schema_version : String,
  authority_kinds : ArrayView[String],
  reviewer_kinds : ArrayView[String],
  minimum_evidence : Int,
  minimum_criteria : Int,
  receipt_outcomes : ArrayView[ReviewOutcome],
) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(b"MFGPOL01")
  try! writer.write_string(policy_id)
  try! writer.write_string(policy_version)
  try! writer.write_string(event_version)
  try! writer.write_string(schema_version)
  try! writer.write_count(authority_kinds.length())
  for value in authority_kinds {
    try! writer.write_string(value)
  }
  try! writer.write_count(reviewer_kinds.length())
  for value in reviewer_kinds {
    try! writer.write_string(value)
  }
  try! writer.write_count(minimum_evidence)
  try! writer.write_count(minimum_criteria)
  try! writer.write_count(receipt_outcomes.length())
  for value in receipt_outcomes {
    try! writer.write_string(value.tag())
  }
  try! writer.write_string("logical-expiry-at-or-after-v1")
  writer.finish()
}

///|
pub fn GovernancePolicy::new(
  policy_id : String,
  policy_version : String,
  event_version : String,
  schema_version : String,
  authority_kinds : Array[String],
  reviewer_kinds : Array[String],
  minimum_evidence : Int,
  minimum_criteria : Int,
  receipt_outcomes : Array[ReviewOutcome],
) -> GovernancePolicy raise {
  require_text(policy_id, "policy_id")
  if policy_version != governance_record_version {
    raise UnsupportedVersion(field="policy_version", version=policy_version)
  }
  if event_version != governance_record_version {
    raise UnsupportedVersion(field="event_version", version=event_version)
  }
  if schema_version != governance_schema_version {
    raise UnsupportedVersion(field="schema_version", version=schema_version)
  }
  if minimum_evidence <= 0 {
    raise EvidenceViolation(field="minimum_evidence")
  }
  if minimum_criteria <= 0 {
    raise CriteriaViolation(field="minimum_criteria")
  }
  let authority_kinds = normalized_kinds(authority_kinds, "authority_kinds")
  let reviewer_kinds = normalized_kinds(reviewer_kinds, "reviewer_kinds")
  let receipt_outcomes = normalized_outcomes(receipt_outcomes)
  let canonical = policy_signing_bytes(
    policy_id, policy_version, event_version, schema_version, authority_kinds, reviewer_kinds,
    minimum_evidence, minimum_criteria, receipt_outcomes,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    policy_ref: self_record(
      "governance-policy", policy_id, policy_version, digest,
    ),
    event_version: @contracts.Version::parse(event_version),
    schema_version: @contracts.Version::parse(schema_version),
    authority_kinds: ReadOnlyArray::from_array(authority_kinds),
    reviewer_kinds: ReadOnlyArray::from_array(reviewer_kinds),
    minimum_evidence,
    minimum_criteria,
    receipt_outcomes: ReadOnlyArray::from_array(receipt_outcomes),
    canonical,
  }
}

///|
/// Reconstruct an exact policy from its durable canonical bytes.
pub fn GovernancePolicy::decode(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
) -> GovernancePolicy raise {
  let reader = GovernanceReader::new(bytes)
  if reader.read_bytes() != b"MFGPOL01" {
    raise MalformedPayload(field="policy_tag")
  }
  let policy_id = reader.read_string()
  let policy_version = reader.read_string()
  let event_version = reader.read_string()
  let schema_version = reader.read_string()
  let authority_kinds : Array[String] = []
  let authority_count = reader.read_count()
  for _ in 0..<authority_count {
    authority_kinds.push(reader.read_string())
  }
  let reviewer_kinds : Array[String] = []
  let reviewer_count = reader.read_count()
  for _ in 0..<reviewer_count {
    reviewer_kinds.push(reader.read_string())
  }
  let minimum_evidence = reader.read_count()
  let minimum_criteria = reader.read_count()
  let receipt_outcomes : Array[ReviewOutcome] = []
  let outcome_count = reader.read_count()
  for _ in 0..<outcome_count {
    receipt_outcomes.push(review_outcome_from_tag(reader.read_string()))
  }
  if reader.read_string() != "logical-expiry-at-or-after-v1" {
    raise MalformedPayload(field="policy_expiry_semantics")
  }
  reader.require_end()
  let policy = GovernancePolicy::new(
    policy_id, policy_version, event_version, schema_version, authority_kinds, reviewer_kinds,
    minimum_evidence, minimum_criteria, receipt_outcomes,
  )
  if policy.policy_ref != expected_ref || policy.canonical != bytes {
    raise IdentityMismatch(field="policy_canonical")
  }
  policy
}

///|
pub fn GovernancePolicy::policy_ref(
  self : GovernancePolicy,
) -> @contracts.RecordRef {
  self.policy_ref
}

///|
pub fn GovernancePolicy::digest(
  self : GovernancePolicy,
) -> @contracts.ContentDigest {
  self.policy_ref.digest()
}

///|
pub fn GovernancePolicy::canonical_bytes(self : GovernancePolicy) -> Bytes {
  self.canonical
}

///|
fn GovernancePolicy::allows_authority(
  self : GovernancePolicy,
  value : @contracts.RecordRef,
) -> Bool {
  self.authority_kinds.any(kind => kind == value.kind())
}

///|
fn GovernancePolicy::allows_reviewer(
  self : GovernancePolicy,
  value : @contracts.RecordRef,
) -> Bool {
  self.reviewer_kinds.any(kind => kind == value.kind())
}

///|
fn GovernancePolicy::allows_receipt_outcome(
  self : GovernancePolicy,
  value : ReviewOutcome,
) -> Bool {
  self.receipt_outcomes.any(candidate => candidate == value)
}

///|
fn GovernancePolicy::require_evidence_count(
  self : GovernancePolicy,
  values : ArrayView[@contracts.EvidenceRef],
  field : String,
) -> Unit raise GovernanceError {
  if values.length() < self.minimum_evidence {
    raise EvidenceViolation(field~)
  }
}

///|
fn GovernancePolicy::require_criteria_count(
  self : GovernancePolicy,
  values : ArrayView[@contracts.RecordRef],
  field : String,
) -> Unit raise GovernanceError {
  if values.length() < self.minimum_criteria {
    raise CriteriaViolation(field~)
  }
}

///|
fn GovernancePolicy::require_versions(
  self : GovernancePolicy,
  event : @storage.WorkflowEvent,
) -> Unit raise GovernanceError {
  if event.record_version() != self.event_version {
    raise UnsupportedVersion(
      field="event_version",
      version=event.record_version().text(),
    )
  }
  if event.schema_version() != self.schema_version {
    raise UnsupportedVersion(
      field="schema_version",
      version=event.schema_version().text(),
    )
  }
}
