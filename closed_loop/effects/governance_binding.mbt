///|
/// Immutable proof summary of one exact accepted FLOW-5A chain. Construction
/// succeeds only from the authoritative replay-derived projection.
pub struct GovernanceBinding {
  record_version : @contracts.Version
  workflow : @contracts.RecordRef
  policy_ref : @contracts.RecordRef
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
  binding_digest : @contracts.ContentDigest
  canonical : Bytes
}

///|
fn build_governance_binding(
  policy : @governance.GovernancePolicy,
  replay : @storage.ReplayResult,
  authority_request : @governance.AuthorityRequest,
  authority_grant : @governance.AuthorityDecision,
  review_request : @governance.ReviewRequest,
  review_decision : @governance.ReviewDecision,
  review_receipt : @governance.ReviewReceipt,
  semantic_v2 : Bool,
) -> GovernanceBinding raise EffectsError {
  let projection = try @governance.fold_replay(policy, replay) catch {
    _ => raise GovernanceViolation(field="authoritative_governance_replay")
  } noraise {
    value => value
  }
  let workflow = projection.workflow()
  if replay.workflow() != workflow {
    raise IdentityMismatch(field="governance_replay_workflow")
  }
  if authority_request.workflow() != workflow {
    raise IdentityMismatch(field="authority_request_workflow")
  }
  if authority_grant.request_ref() != authority_request.request_ref() {
    raise IdentityMismatch(field="authority_request")
  }
  if authority_grant.outcome() != Granted ||
    projection.authority_status() != AuthorityGrantedStatus {
    raise GovernanceViolation(field="authority_grant")
  }
  if review_decision.request_ref() != review_request.request_ref() {
    raise IdentityMismatch(field="review_request")
  }
  if review_decision.outcome() != Approved ||
    !review_receipt.is_terminal_approved() ||
    projection.review_status() != ReviewReceiptBoundStatus(Approved) {
    raise ReviewReceiptViolation(field="terminal_approved")
  }
  guard projection.receipt() is Some(projected_receipt) else {
    raise ReviewReceiptViolation(field="missing_projection_receipt")
  }
  if projected_receipt.canonical_bytes() != review_receipt.canonical_bytes() ||
    projected_receipt.receipt_ref() != review_receipt.receipt_ref() {
    raise ReviewReceiptViolation(field="projection_receipt")
  }
  require_governance_record(
    replay,
    "AuthorityRequested",
    authority_request.request_ref(),
    authority_request.canonical_bytes(),
    "authority_request_replay",
  )
  require_governance_record(
    replay,
    "AuthorityGranted",
    authority_grant.decision_ref(),
    authority_grant.canonical_bytes(),
    "authority_grant_replay",
  )
  require_governance_record(
    replay,
    "ReviewRequested",
    review_request.request_ref(),
    review_request.canonical_bytes(),
    "review_request_replay",
  )
  require_governance_record(
    replay,
    "ReviewDecisionRecorded",
    review_decision.decision_ref(),
    review_decision.canonical_bytes(),
    "review_decision_replay",
  )
  require_governance_record(
    replay,
    "ReviewReceiptBound",
    review_receipt.receipt_ref(),
    review_receipt.canonical_bytes(),
    "review_receipt_replay",
  )
  let governed_subject = review_request.subject().subject()
  let governed_subject_digest = review_request.subject().envelope_digest()
  let projection_digest = projection.state_digest()
  let authoritative_replay_digest = replay.replay_digest()
  let writer = EffectsWriter::new()
  writer.bytes(if semantic_v2 { b"MF6AGOV2" } else { b"MF6AGOV1" })
  writer.string(effects_record_version)
  write_ref(writer, workflow)
  write_ref(writer, policy.policy_ref())
  if semantic_v2 {
    writer.bytes(policy.canonical_bytes())
  }
  write_ref(writer, authority_request.request_ref())
  write_ref(writer, authority_grant.decision_ref())
  write_ref(writer, authority_grant.authority_ref())
  writer.optional_int64(authority_request.expires_at())
  write_ref(writer, review_request.request_ref())
  write_ref(writer, review_decision.decision_ref())
  write_ref(writer, review_decision.reviewer_ref())
  write_ref(writer, review_receipt.receipt_ref())
  write_ref(writer, governed_subject)
  writer.string(governed_subject_digest.text())
  writer.string(projection_digest.text())
  writer.string(authoritative_replay_digest.text())
  writer.bytes(authority_request.canonical_bytes())
  writer.bytes(authority_grant.canonical_bytes())
  writer.bytes(review_request.canonical_bytes())
  writer.bytes(review_decision.canonical_bytes())
  writer.bytes(review_receipt.canonical_bytes())
  let canonical = writer.finish()
  let binding_digest = @contracts.sha256_digest(canonical)
  {
    record_version: effects_version(),
    workflow,
    policy_ref: policy.policy_ref(),
    authority_request_ref: authority_request.request_ref(),
    authority_grant_ref: authority_grant.decision_ref(),
    authority_ref: authority_grant.authority_ref(),
    authority_expires_at: authority_request.expires_at(),
    review_request_ref: review_request.request_ref(),
    review_decision_ref: review_decision.decision_ref(),
    reviewer_ref: review_decision.reviewer_ref(),
    review_receipt_ref: review_receipt.receipt_ref(),
    governed_subject,
    governed_subject_digest,
    projection_digest,
    authoritative_replay_digest,
    binding_digest,
    canonical,
  }
}

///|
pub fn GovernanceBinding::new(
  policy : @governance.GovernancePolicy,
  replay : @storage.ReplayResult,
  authority_request : @governance.AuthorityRequest,
  authority_grant : @governance.AuthorityDecision,
  review_request : @governance.ReviewRequest,
  review_decision : @governance.ReviewDecision,
  review_receipt : @governance.ReviewReceipt,
) -> GovernanceBinding raise EffectsError {
  build_governance_binding(
    policy, replay, authority_request, authority_grant, review_request, review_decision,
    review_receipt, false,
  )
}

///|
/// Semantic-policy binding required by aggregate closed-loop replay.
pub fn GovernanceBinding::new_strict_v2(
  policy : @governance.GovernancePolicy,
  replay : @storage.ReplayResult,
  authority_request : @governance.AuthorityRequest,
  authority_grant : @governance.AuthorityDecision,
  review_request : @governance.ReviewRequest,
  review_decision : @governance.ReviewDecision,
  review_receipt : @governance.ReviewReceipt,
) -> GovernanceBinding raise EffectsError {
  build_governance_binding(
    policy, replay, authority_request, authority_grant, review_request, review_decision,
    review_receipt, true,
  )
}

///|
fn require_governance_record(
  replay : @storage.ReplayResult,
  event_kind : String,
  record_ref : @contracts.RecordRef,
  canonical : Bytes,
  field : String,
) -> Unit raise EffectsError {
  let matches = replay
    .events()
    .filter(event => {
      let envelope = event.payload()
      envelope.envelope_kind() == event_kind &&
      envelope.subject() == record_ref &&
      envelope.payload() == canonical
    })
  if matches.length() != 1 {
    raise GovernanceViolation(field~)
  }
}

///|
pub fn GovernanceBinding::workflow(
  self : GovernanceBinding,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn GovernanceBinding::policy_ref(
  self : GovernanceBinding,
) -> @contracts.RecordRef {
  self.policy_ref
}

///|
pub fn GovernanceBinding::authority_request_ref(
  self : GovernanceBinding,
) -> @contracts.RecordRef {
  self.authority_request_ref
}

///|
pub fn GovernanceBinding::authority_grant_ref(
  self : GovernanceBinding,
) -> @contracts.RecordRef {
  self.authority_grant_ref
}

///|
pub fn GovernanceBinding::authority_ref(
  self : GovernanceBinding,
) -> @contracts.RecordRef {
  self.authority_ref
}

///|
pub fn GovernanceBinding::authority_expires_at(
  self : GovernanceBinding,
) -> Int64? {
  self.authority_expires_at
}

///|
pub fn GovernanceBinding::review_receipt_ref(
  self : GovernanceBinding,
) -> @contracts.RecordRef {
  self.review_receipt_ref
}

///|
pub fn GovernanceBinding::governed_subject(
  self : GovernanceBinding,
) -> @contracts.RecordRef {
  self.governed_subject
}

///|
pub fn GovernanceBinding::governed_subject_digest(
  self : GovernanceBinding,
) -> @contracts.ContentDigest {
  self.governed_subject_digest
}

///|
pub fn GovernanceBinding::binding_digest(
  self : GovernanceBinding,
) -> @contracts.ContentDigest {
  self.binding_digest
}

///|
pub fn GovernanceBinding::canonical_bytes(self : GovernanceBinding) -> Bytes {
  self.canonical
}

///|
fn GovernanceBinding::require_active(
  self : GovernanceBinding,
  observed_at : Int64,
) -> Unit raise EffectsError {
  match self.authority_expires_at {
    Some(expires_at) if observed_at >= expires_at =>
      raise AuthorityExpired(expires_at~, observed_at~)
    _ => ()
  }
}
