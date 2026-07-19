///|
pub(all) enum AuthorityStatus {
  AuthorityNotRequested
  AuthorityPending
  AuthorityGrantedStatus
  AuthorityDeniedStatus
  AuthorityExpiredStatus
} derive(Eq, Debug)

///|
pub(all) enum ReviewStatus {
  ReviewNotRequested
  ReviewPending
  ReviewApprovedStatus
  ReviewRejectedStatus
  ReviewChangesRequestedStatus
  ReviewReceiptBoundStatus(ReviewOutcome)
} derive(Eq, Debug)

///|
/// Deterministic projection derived only from accepted governance events.
pub struct GovernanceProjection {
  projection_version : @contracts.Version
  policy : GovernancePolicy
  workflow : @contracts.RecordRef
  sequence : Int64
  revision : Int64
  last_event_digest : @contracts.ContentDigest?
  attachment : EvidenceAttachment?
  authority_request : AuthorityRequest?
  authority_decision : AuthorityDecision?
  authority_expiration : AuthorityExpiration?
  review_request : ReviewRequest?
  review_decision : ReviewDecision?
  receipt : ReviewReceipt?
  accepted_events : ReadOnlyArray[@storage.WorkflowEvent]
}

///|
pub fn GovernanceProjection::new(
  policy : GovernancePolicy,
  workflow : @contracts.RecordRef,
) -> GovernanceProjection {
  {
    projection_version: try! @contracts.Version::parse(
      governance_schema_version,
    ),
    policy,
    workflow,
    sequence: 0L,
    revision: 0L,
    last_event_digest: None,
    attachment: None,
    authority_request: None,
    authority_decision: None,
    authority_expiration: None,
    review_request: None,
    review_decision: None,
    receipt: None,
    accepted_events: ReadOnlyArray::from_array([]),
  }
}

///|
pub fn GovernanceProjection::workflow(
  self : GovernanceProjection,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn GovernanceProjection::sequence(self : GovernanceProjection) -> Int64 {
  self.sequence
}

///|
pub fn GovernanceProjection::revision(self : GovernanceProjection) -> Int64 {
  self.revision
}

///|
pub fn GovernanceProjection::last_event_digest(
  self : GovernanceProjection,
) -> @contracts.ContentDigest? {
  self.last_event_digest
}

///|
pub fn GovernanceProjection::authority_status(
  self : GovernanceProjection,
) -> AuthorityStatus {
  match
    (self.authority_request, self.authority_decision, self.authority_expiration) {
    (None, _, _) => AuthorityNotRequested
    (Some(_), None, None) => AuthorityPending
    (_, Some(value), _) if value.outcome == Granted => AuthorityGrantedStatus
    (_, Some(_), _) => AuthorityDeniedStatus
    (_, _, Some(_)) => AuthorityExpiredStatus
  }
}

///|
pub fn GovernanceProjection::review_status(
  self : GovernanceProjection,
) -> ReviewStatus {
  match self.receipt {
    Some(value) => ReviewReceiptBoundStatus(value.outcome)
    None =>
      match self.review_decision {
        Some(value) =>
          match value.outcome {
            Approved => ReviewApprovedStatus
            Rejected => ReviewRejectedStatus
            ChangesRequested => ReviewChangesRequestedStatus
          }
        None =>
          if self.review_request is Some(_) {
            ReviewPending
          } else {
            ReviewNotRequested
          }
      }
  }
}

///|
pub fn GovernanceProjection::receipt(
  self : GovernanceProjection,
) -> ReviewReceipt? {
  self.receipt
}

///|
/// Exact evidence attachment retained by authoritative semantic replay.
/// This is a read-only fact; it does not confer authority by itself.
pub fn GovernanceProjection::evidence_attachment_record(
  self : GovernanceProjection,
) -> EvidenceAttachment? {
  self.attachment
}

///|
/// Exact authority request retained by authoritative semantic replay.
pub fn GovernanceProjection::authority_request_record(
  self : GovernanceProjection,
) -> AuthorityRequest? {
  self.authority_request
}

///|
/// Exact authority decision retained by authoritative semantic replay.
pub fn GovernanceProjection::authority_decision_record(
  self : GovernanceProjection,
) -> AuthorityDecision? {
  self.authority_decision
}

///|
/// Exact review request retained by authoritative semantic replay.
pub fn GovernanceProjection::review_request_record(
  self : GovernanceProjection,
) -> ReviewRequest? {
  self.review_request
}

///|
/// Exact review decision retained by authoritative semantic replay.
pub fn GovernanceProjection::review_decision_record(
  self : GovernanceProjection,
) -> ReviewDecision? {
  self.review_decision
}

///|
pub fn GovernanceProjection::canonical_bytes(
  self : GovernanceProjection,
) -> Bytes {
  let writer = GovernanceWriter::new()
  try! writer.write_bytes(b"MFGPRJ01")
  try! writer.write_string(self.projection_version.text())
  try! writer.write_bytes(record_bytes(self.policy.policy_ref))
  try! writer.write_bytes(record_bytes(self.workflow))
  writer.write_int64(self.sequence)
  writer.write_int64(self.revision)
  try! writer.write_optional_digest(self.last_event_digest)
  try! writer.write_count(self.accepted_events.length())
  for event in self.accepted_events {
    try! writer.write_bytes(event.canonical_bytes())
  }
  writer.finish()
}

///|
pub fn GovernanceProjection::state_digest(
  self : GovernanceProjection,
) -> @contracts.ContentDigest {
  @contracts.sha256_digest(self.canonical_bytes())
}

///|
fn accepted_event_by_ref(
  projection : GovernanceProjection,
  reference : @contracts.RecordRef,
) -> @storage.WorkflowEvent? {
  projection.accepted_events
  .search_by(event => event.event_ref() == reference)
  .map(index => projection.accepted_events[index])
}

///|
fn event_identity_equal(
  left : @contracts.RecordRef,
  right : @contracts.RecordRef,
) -> Bool {
  left.kind() == right.kind() &&
  left.id() == right.id() &&
  left.version() == right.version()
}

///|
fn duplicate_or_conflict(
  projection : GovernanceProjection,
  event : @storage.WorkflowEvent,
) -> GovernanceProjection? raise GovernanceError {
  for prior in projection.accepted_events {
    if event_identity_equal(prior.event_ref(), event.event_ref()) {
      if prior.canonical_bytes() == event.canonical_bytes() {
        return Some(projection)
      }
      raise IdentityMismatch(field="event_identity")
    }
    if prior.idempotency_key() == event.idempotency_key() {
      if prior.canonical_bytes() == event.canonical_bytes() {
        return Some(projection)
      }
      raise IdempotencyConflict(key=event.idempotency_key())
    }
  }
  None
}

///|
fn validate_event_envelope(
  projection : GovernanceProjection,
  event : @storage.WorkflowEvent,
) -> Unit raise GovernanceError {
  projection.policy.require_versions(event)
  require_exact_record(event.workflow(), projection.workflow, "event_workflow")
  if event.sequence() != projection.sequence + 1L {
    raise RevisionMismatch(
      field="event_sequence",
      expected=projection.sequence + 1L,
      actual=event.sequence(),
    )
  }
  if event.revision() != projection.revision + 1L {
    raise RevisionMismatch(
      field="event_revision",
      expected=projection.revision + 1L,
      actual=event.revision(),
    )
  }
  if event.previous_event_digest() != projection.last_event_digest {
    raise DigestMismatch(field="previous_event_digest")
  }
  let envelope = event.payload()
  if envelope.contract_id() != governance_contract_id ||
    envelope.contract_version().text() != governance_contract_version {
    raise UnsupportedVersion(
      field="governance_contract",
      version=envelope.contract_version().text(),
    )
  }
  let kind = envelope.envelope_kind()
  if !supported_event_kind(kind) {
    raise InvalidEventKind(kind)
  }
  if envelope.schema() != schema_for(kind) {
    raise DigestMismatch(field="event_schema")
  }
  if envelope.envelope_id() != event.event_ref().id() {
    raise IdentityMismatch(field="envelope_event_identity")
  }
  if envelope.subject().kind() != expected_record_kind(kind) {
    raise IdentityMismatch(field="event_subject_kind")
  }
  if envelope.producer_id() != governance_producer_id ||
    envelope.producer_version().text() != governance_producer_version {
    raise IdentityMismatch(field="event_producer")
  }
  if envelope.run_ref() != Some(projection.workflow) ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() is Some(_) {
    raise IdentityMismatch(field="event_workflow_binding")
  }
  if envelope.correlation_ref() != Some(projection.workflow.id()) {
    raise CausationMismatch(field="event_correlation")
  }
  if envelope.idempotency_ref() != Some(event.idempotency_key()) {
    raise IdempotencyConflict(key=event.idempotency_key())
  }
  let expected_causation = projection.accepted_events
    .last()
    .map(value => value.event_ref().id())
  if envelope.causation_ref() != expected_causation {
    raise CausationMismatch(field="event_causation")
  }
  if envelope.previous_digest() != projection.last_event_digest {
    raise DigestMismatch(field="envelope_previous_digest")
  }
  if !envelope.artifacts().is_empty() || !envelope.extensions().is_empty() {
    raise MalformedPayload(field="event_extras")
  }
}

///|
fn require_event_evidence(
  event : @storage.WorkflowEvent,
  expected : ArrayView[@contracts.EvidenceRef],
) -> Unit raise GovernanceError {
  if !same_evidence(event.evidence(), expected) {
    raise EvidenceViolation(field="event_evidence_order")
  }
}

///|
fn require_event_subject(
  event : @storage.WorkflowEvent,
  expected : @contracts.RecordRef,
) -> Unit raise GovernanceError {
  require_exact_record(event.payload().subject(), expected, "event_subject")
}

///|
pub fn GovernanceProjection::apply_event(
  self : GovernanceProjection,
  event : @storage.WorkflowEvent,
) -> GovernanceProjection raise {
  match duplicate_or_conflict(self, event) {
    Some(value) => return value
    None => ()
  }
  if self.receipt is Some(_) {
    raise InvalidState(field="terminal_projection")
  }
  validate_event_envelope(self, event)
  let kind = event.payload().envelope_kind()
  let mut next = self
  match kind {
    "EvidenceAttached" => {
      if self.attachment is Some(_) || self.authority_request is Some(_) {
        raise InvalidState(field="evidence_attachment")
      }
      let value = decode_evidence_attachment(
        event.payload().payload(),
        self.policy,
      )
      require_exact_record(value.workflow, self.workflow, "workflow")
      if value.attached_revision != event.revision() {
        raise RevisionMismatch(
          field="attached_revision",
          expected=event.revision(),
          actual=value.attached_revision,
        )
      }
      require_event_subject(event, value.attachment_ref)
      require_event_evidence(event, value.evidence)
      next = { ..next, attachment: Some(value) }
    }
    "AuthorityRequested" => {
      guard self.attachment is Some(attachment) else {
        raise InvalidState(field="authority_before_evidence")
      }
      if self.authority_request is Some(_) {
        raise InvalidState(field="authority_request")
      }
      let value = decode_authority_request(
        event.payload().payload(),
        self.policy,
        attachment,
      )
      require_exact_record(value.workflow, self.workflow, "workflow")
      if value.workflow_revision != event.revision() {
        raise RevisionMismatch(
          field="authority_request_revision",
          expected=event.revision(),
          actual=value.workflow_revision,
        )
      }
      if value.idempotency_key != event.idempotency_key() {
        raise IdempotencyConflict(key=event.idempotency_key())
      }
      require_event_subject(event, value.request_ref)
      require_event_evidence(event, value.evidence)
      next = { ..next, authority_request: Some(value) }
    }
    "AuthorityGranted" | "AuthorityDenied" => {
      guard self.authority_request is Some(request) else {
        raise InvalidState(field="authority_decision_before_request")
      }
      if self.authority_decision is Some(_) ||
        self.authority_expiration is Some(_) {
        raise InvalidState(field="authority_terminal_conflict")
      }
      let value = decode_authority_decision(
        event.payload().payload(),
        self.policy,
        request,
      )
      if value.prior_revision != self.revision {
        raise RevisionMismatch(
          field="authority_decision_revision",
          expected=self.revision,
          actual=value.prior_revision,
        )
      }
      if (kind == authority_granted_kind && value.outcome != Granted) ||
        (kind == authority_denied_kind && value.outcome != Denied) {
        raise InvalidEventKind(kind)
      }
      require_event_subject(event, value.decision_ref)
      require_event_evidence(event, [])
      next = { ..next, authority_decision: Some(value) }
    }
    "AuthorityExpired" => {
      guard self.authority_request is Some(request) else {
        raise InvalidState(field="authority_expiry_before_request")
      }
      if self.authority_decision is Some(_) ||
        self.authority_expiration is Some(_) {
        raise InvalidState(field="authority_terminal_conflict")
      }
      let value = decode_authority_expiration(
        event.payload().payload(),
        self.policy,
        request,
      )
      if value.prior_revision != self.revision {
        raise RevisionMismatch(
          field="authority_expiration_revision",
          expected=self.revision,
          actual=value.prior_revision,
        )
      }
      require_event_subject(event, value.expiration_ref)
      require_event_evidence(event, [])
      next = { ..next, authority_expiration: Some(value) }
    }
    "ReviewRequested" => {
      guard self.authority_request is Some(authority_request) &&
        self.authority_decision is Some(authority_grant) else {
        raise InvalidState(field="review_before_grant")
      }
      if authority_grant.outcome != Granted ||
        self.authority_expiration is Some(_) {
        raise InvalidState(field="review_without_active_grant")
      }
      if self.review_request is Some(_) {
        raise InvalidState(field="review_request")
      }
      let value = decode_review_request(
        event.payload().payload(),
        self.policy,
        authority_request,
        authority_grant,
      )
      if value.requested_revision != event.revision() {
        raise RevisionMismatch(
          field="review_request_revision",
          expected=event.revision(),
          actual=value.requested_revision,
        )
      }
      if value.idempotency_key != event.idempotency_key() {
        raise IdempotencyConflict(key=event.idempotency_key())
      }
      require_event_subject(event, value.request_ref)
      require_event_evidence(event, value.evidence)
      next = { ..next, review_request: Some(value) }
    }
    "ReviewDecisionRecorded" => {
      guard self.review_request is Some(request) else {
        raise InvalidState(field="review_decision_before_request")
      }
      if self.review_decision is Some(_) {
        raise InvalidState(field="review_decision")
      }
      let value = decode_review_decision(
        event.payload().payload(),
        self.policy,
        request,
      )
      if value.workflow_revision != event.revision() {
        raise RevisionMismatch(
          field="review_decision_revision",
          expected=event.revision(),
          actual=value.workflow_revision,
        )
      }
      let ordered = [ for evidence in value.supporting_evidence => evidence ]
      for evidence in value.contradictory_evidence {
        ordered.push(evidence)
      }
      require_event_subject(event, value.decision_ref)
      require_event_evidence(event, ordered)
      next = { ..next, review_decision: Some(value) }
    }
    "ReviewReceiptBound" => {
      let value = decode_review_receipt(event.payload().payload(), self)
      if value.resulting_revision != event.revision() {
        raise RevisionMismatch(
          field="receipt_revision",
          expected=event.revision(),
          actual=value.resulting_revision,
        )
      }
      require_event_subject(event, value.receipt_ref)
      require_event_evidence(event, [])
      next = { ..next, receipt: Some(value) }
    }
    _ => raise InvalidEventKind(kind)
  }
  let events = [ for accepted in self.accepted_events => accepted ]
  events.push(event)
  {
    ..next,
    sequence: event.sequence(),
    revision: event.revision(),
    last_event_digest: Some(event.event_ref().digest()),
    accepted_events: ReadOnlyArray::from_array(events),
  }
}

///|
pub fn fold_replay(
  policy : GovernancePolicy,
  replay : @storage.ReplayResult,
) -> GovernanceProjection raise {
  let mut projection = GovernanceProjection::new(policy, replay.workflow())
  for event in replay.events() {
    projection = projection.apply_event(event)
  }
  let head = replay.head()
  if head.sequence() != projection.sequence ||
    head.revision() != projection.revision {
    raise RevisionMismatch(
      field="replay_head",
      expected=projection.revision,
      actual=head.revision(),
    )
  }
  if head.last_event_digest() != projection.last_event_digest {
    raise DigestMismatch(field="replay_head_digest")
  }
  for intent in replay.intents() {
    validate_request_intent(projection, intent)
  }
  projection
}
