///|
let governance_record_version : String = "1.0.0"

///|
let governance_schema_version : String = "1.0.0"

///|
let governance_contract_id : String = "neutral.governance"

///|
let governance_contract_version : String = "1.0.0"

///|
let governance_producer_id : String = "neutral-governance-state-machine"

///|
let governance_producer_version : String = "1.0.0"

///|
let evidence_attached_kind : String = "EvidenceAttached"

///|
let authority_requested_kind : String = "AuthorityRequested"

///|
let authority_granted_kind : String = "AuthorityGranted"

///|
let authority_denied_kind : String = "AuthorityDenied"

///|
let authority_expired_kind : String = "AuthorityExpired"

///|
let review_requested_kind : String = "ReviewRequested"

///|
let review_decision_recorded_kind : String = "ReviewDecisionRecorded"

///|
let review_receipt_bound_kind : String = "ReviewReceiptBound"

///|
let request_intent_kind : String = "GovernanceRequestIntent"

///|
fn supported_event_kind(value : String) -> Bool {
  value == evidence_attached_kind ||
  value == authority_requested_kind ||
  value == authority_granted_kind ||
  value == authority_denied_kind ||
  value == authority_expired_kind ||
  value == review_requested_kind ||
  value == review_decision_recorded_kind ||
  value == review_receipt_bound_kind
}

///|
fn expected_record_kind(event_kind : String) -> String {
  match event_kind {
    "EvidenceAttached" => "governance-evidence-attachment"
    "AuthorityRequested" => "governance-authority-request"
    "AuthorityGranted" | "AuthorityDenied" => "governance-authority-decision"
    "AuthorityExpired" => "governance-authority-expiration"
    "ReviewRequested" => "governance-review-request"
    "ReviewDecisionRecorded" => "governance-review-decision"
    "ReviewReceiptBound" => "governance-review-receipt"
    _ => "unsupported"
  }
}

///|
fn schema_for(kind : String) -> @contracts.SchemaRef {
  try! @contracts.SchemaRef::new(
    governance_contract_id,
    governance_contract_version,
    "governance-event-\{kind}",
    governance_schema_version,
    @contracts.sha256_digest(
      @utf8.encode("neutral.governance.schema:\{kind}:1.0.0"),
    ).text(),
  )
}
