///|
fn fixture_ref(
  kind : String,
  id : String,
  seed : Bytes,
) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(
    kind,
    id,
    "1.0.0",
    @contracts.sha256_digest(seed).text(),
  )
}

///|
fn fixture_policy(id? : String = "policy-1") -> @governance.GovernancePolicy {
  try! @governance.GovernancePolicy::new(
    id,
    "1.0.0",
    "1.0.0",
    "1.0.0",
    ["authority-ref"],
    ["named-human-reviewer"],
    1,
    1,
    [Approved, Rejected, ChangesRequested],
  )
}

///|
fn fixture_workflow() -> @contracts.RecordRef {
  fixture_ref("workflow", "workflow-5a", b"workflow-5a")
}

///|
fn fixture_evidence(id : String) -> @contracts.EvidenceRef {
  try! @contracts.EvidenceRef::new(
    fixture_ref("evidence", id, @utf8.encode(id)),
    fixture_ref("provenance", "source-1", b"source-1"),
    @contracts.sha256_digest(@utf8.encode("observed-\{id}")).text(),
  )
}

///|
fn fixture_schema(kind : String) -> @contracts.SchemaRef {
  try! @contracts.SchemaRef::new(
    "neutral.fixture",
    "1.0.0",
    kind,
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode("schema-\{kind}")).text(),
  )
}

///|
fn fixture_envelope(
  id : String,
  kind : String,
  subject : @contracts.RecordRef,
  payload : Bytes,
  evidence? : Array[@contracts.EvidenceRef] = [],
) -> @contracts.WireEnvelope {
  try! @contracts.WireEnvelope::new(
    "neutral.fixture",
    "1.0.0",
    id,
    kind,
    subject,
    fixture_schema(kind),
    payload,
    "neutral-fixture",
    "1.0.0",
    [],
    evidence,
  )
}

///|
struct ReviewedChain {
  policy : @governance.GovernancePolicy
  workflow : @contracts.RecordRef
  evidence : Array[@contracts.EvidenceRef]
  criteria : Array[@contracts.RecordRef]
  attachment : @governance.EvidenceAttachment
  authority_request : @governance.AuthorityRequest
  authority_grant : @governance.AuthorityDecision
  review_request : @governance.ReviewRequest
  review_decision : @governance.ReviewDecision
  events : Array[@storage.WorkflowEvent]
  projection : @governance.GovernanceProjection
}

///|
fn reviewed_chain(outcome : @governance.ReviewOutcome) -> ReviewedChain raise {
  let policy = fixture_policy()
  let workflow = fixture_workflow()
  let evidence = [
    fixture_evidence("evidence-1"),
    fixture_evidence("evidence-2"),
  ]
  let criteria = [
    fixture_ref("criterion", "criterion-1", b"criterion-1"),
    fixture_ref("criterion", "criterion-2", b"criterion-2"),
  ]
  let purpose = fixture_ref("criterion-set", "purpose-1", b"purpose-1")
  let authority = fixture_ref("authority-ref", "authority-1", b"authority-1")
  let reviewer = fixture_ref(
    "named-human-reviewer", "reviewer-1", b"reviewer-1",
  )
  let attachment = try! @governance.EvidenceAttachment::new(
    policy, workflow, "attachment-1", "1.0.0", evidence, purpose, 1L,
  )
  let mut projection = @governance.GovernanceProjection::new(policy, workflow)
  let events : Array[@storage.WorkflowEvent] = []
  let attached_event = try! @governance.prepare_event(
    projection,
    "event-1",
    @governance.GovernanceAction::evidence_attached(attachment, "event-key-1"),
  )
  projection = projection.apply_event(attached_event)
  events.push(attached_event)
  let authority_subject = fixture_envelope(
    "authority-subject-1",
    "authority-subject",
    fixture_ref("subject", "authority-subject-1", b"authority-subject-1"),
    b"opaque-authority-subject",
    evidence~,
  )
  let authority_request = try! @governance.AuthorityRequest::new(
    policy,
    workflow,
    "authority-request-1",
    "1.0.0",
    attachment,
    authority_subject,
    criteria,
    evidence,
    10L,
    Some(100L),
    2L,
    "event-key-2",
  )
  let requested_event = try! @governance.prepare_event(
    projection,
    "event-2",
    @governance.GovernanceAction::authority_requested(authority_request),
  )
  projection = projection.apply_event(requested_event)
  events.push(requested_event)
  let grant = try! @governance.AuthorityDecision::grant(
    policy,
    workflow,
    "authority-decision-1",
    "1.0.0",
    authority_request,
    fixture_envelope(
      "authority-attestation-1", "authority-attestation", authority, b"opaque",
    ),
    authority,
    20L,
    2L,
  )
  let granted_event = try! @governance.prepare_event(
    projection,
    "event-3",
    @governance.GovernanceAction::authority_decided(grant, "event-key-3"),
  )
  projection = projection.apply_event(granted_event)
  events.push(granted_event)
  let subject = fixture_envelope(
    "review-subject-1",
    "review-subject",
    fixture_ref("subject", "review-subject-1", b"review-subject-1"),
    b"opaque-review-subject",
    evidence~,
  )
  let review_request = try! @governance.ReviewRequest::new(
    policy, workflow, "review-request-1", "1.0.0", authority_request, grant, criteria,
    evidence, subject, 30L, 4L, "event-key-4",
  )
  let review_requested_event = try! @governance.prepare_event(
    projection,
    "event-4",
    @governance.GovernanceAction::review_requested(review_request),
  )
  projection = projection.apply_event(review_requested_event)
  events.push(review_requested_event)
  let disposition = match outcome {
    Approved => @governance.Satisfied
    Rejected => Unsatisfied
    ChangesRequested => NeedsRevision
  }
  let findings = [
    @governance.CriterionFinding::new(criteria[0], disposition),
    @governance.CriterionFinding::new(criteria[1], disposition),
  ]
  let review_decision = try! @governance.ReviewDecision::new(
    policy,
    workflow,
    "review-decision-1",
    "1.0.0",
    review_request,
    reviewer,
    fixture_envelope(
      "reviewer-attestation-1", "reviewer-attestation", reviewer, b"opaque",
    ),
    outcome,
    findings,
    [evidence[0]],
    [evidence[1]],
    40L,
    5L,
  )
  let decision_event = try! @governance.prepare_event(
    projection,
    "event-5",
    @governance.GovernanceAction::review_decision_recorded(
      review_decision, "event-key-5",
    ),
  )
  projection = projection.apply_event(decision_event)
  events.push(decision_event)
  {
    policy,
    workflow,
    evidence,
    criteria,
    attachment,
    authority_request,
    authority_grant: grant,
    review_request,
    review_decision,
    events,
    projection,
  }
}

///|
fn bind_reviewed_chain(
  chain : ReviewedChain,
) -> (
  @governance.ReviewReceipt,
  @storage.WorkflowEvent,
  @governance.GovernanceProjection,
) {
  let receipt = try! @governance.ReviewReceipt::bind(
    chain.projection,
    "review-receipt-1",
    "1.0.0",
    50L,
  )
  let event = try! @governance.prepare_event(
    chain.projection,
    "event-6",
    @governance.GovernanceAction::review_receipt_bound(receipt, "event-key-6"),
  )
  (receipt, event, try! chain.projection.apply_event(event))
}

///|
test "FLOW-5A full named-human approved chain binds the only terminal receipt" {
  let chain = reviewed_chain(Approved)
  let (receipt, event, projection) = bind_reviewed_chain(chain)
  assert_true(receipt.is_terminal_approved())
  assert_eq(receipt.resulting_revision(), 6L)
  assert_eq(projection.revision(), 6L)
  assert_true(projection.authority_status() == AuthorityGrantedStatus)
  assert_true(projection.review_status() == ReviewReceiptBoundStatus(Approved))
  assert_true(projection.receipt() is Some(_))
  assert_true(event.payload().envelope_kind() == "ReviewReceiptBound")
  assert_true(receipt.binding_digest() == receipt.receipt_ref().digest())
}

///|
test "FLOW-5A rejection and changes requested cannot become approved receipts" {
  for outcome in [@governance.Rejected, ChangesRequested] {
    let chain = reviewed_chain(outcome)
    let (receipt, _, projection) = bind_reviewed_chain(chain)
    assert_false(receipt.is_terminal_approved())
    assert_true(receipt.outcome() == outcome)
    assert_true(projection.review_status() == ReviewReceiptBoundStatus(outcome))
  }
}

///|
test "FLOW-5A memory commit keeps event and request intent atomic" {
  let chain = reviewed_chain(Approved)
  let store = @storage.MemoryStore::new()
  let mut projection = @governance.GovernanceProjection::new(
    chain.policy,
    chain.workflow,
  )
  for index, event in chain.events {
    let intents = if index == 1 || index == 3 {
      let requested_work = fixture_envelope(
        "requested-work-\{index}",
        "opaque-requested-work",
        chain.workflow,
        @utf8.encode("requested-work-\{index}"),
        evidence=chain.evidence,
      )
      [
        try! @governance.prepare_request_intent(
          event,
          "request-intent-\{index}",
          "request-intent-key-\{index}",
          requested_work,
          chain.evidence,
        ),
      ]
    } else {
      []
    }
    let request = try! @governance.prepare_governance_commit(
      projection,
      "command-\{index}",
      [event],
      intents,
    )
    ignore(store.commit(request))
    projection = try! @governance.fold_replay(
      chain.policy,
      store.replay(chain.workflow),
    )
    assert_eq(projection.revision(), Int64::from_int(index + 1))
  }
  assert_eq(store.replay(chain.workflow).intents().length(), 2)
  assert_true(projection.state_digest() == chain.projection.state_digest())
}

///|
test "FLOW-5A exact duplicate replay is idempotent and changed key conflicts" {
  let chain = reviewed_chain(Approved)
  let first = chain.events[0]
  let empty = @governance.GovernanceProjection::new(
    chain.policy,
    chain.workflow,
  )
  let once = try! empty.apply_event(first)
  let twice = try! once.apply_event(first)
  assert_true(once.state_digest() == twice.state_digest())
  try
    @governance.prepare_event(
      once,
      "event-different",
      @governance.GovernanceAction::evidence_attached(
        chain.attachment,
        "event-key-1",
      ),
    )
  catch {
    @governance.IdempotencyConflict(key~) => assert_eq(key, "event-key-1")
    _ => fail("unexpected duplicate conflict")
  } noraise {
    _ => fail("expected idempotency conflict")
  }
}

///|
test "FLOW-5A concurrent commits from one revision yield one revision conflict" {
  let chain = reviewed_chain(Approved)
  let store = @storage.MemoryStore::new()
  let empty = @governance.GovernanceProjection::new(
    chain.policy,
    chain.workflow,
  )
  let first_request = try! @governance.prepare_governance_commit(
    empty,
    "concurrent-command-1",
    [chain.events[0]],
    [],
  )
  ignore(store.commit(first_request))
  let alternative_attachment = try! @governance.EvidenceAttachment::new(
    chain.policy,
    chain.workflow,
    "attachment-alternative",
    "1.0.0",
    chain.evidence,
    fixture_ref("criterion-set", "purpose-2", b"purpose-2"),
    1L,
  )
  let alternative_event = try! @governance.prepare_event(
    empty,
    "event-alternative",
    @governance.GovernanceAction::evidence_attached(
      alternative_attachment, "alternative-key",
    ),
  )
  let second_request = try! @governance.prepare_governance_commit(
    empty,
    "concurrent-command-2",
    [alternative_event],
    [],
  )
  try store.commit(second_request) catch {
    OptimisticRevisionConflict(expected~, actual~, ..) => {
      assert_eq(expected, 0L)
      assert_eq(actual, 1L)
    }
    _ => fail("unexpected concurrency error")
  } noraise {
    _ => fail("expected optimistic revision conflict")
  }
}

///|
fn projection_after(
  chain : ReviewedChain,
  count : Int,
) -> @governance.GovernanceProjection raise {
  let mut projection = @governance.GovernanceProjection::new(
    chain.policy,
    chain.workflow,
  )
  for index in 0..<count {
    projection = projection.apply_event(chain.events[index])
  }
  projection
}

///|
test "FLOW-5A authority denial and explicit expiry are terminal and conflicting" {
  let chain = reviewed_chain(Approved)
  let requested = projection_after(chain, 2)
  let authority = chain.authority_grant.authority_ref()
  let denial = try! @governance.AuthorityDecision::deny(
    chain.policy,
    chain.workflow,
    "authority-denial-1",
    "1.0.0",
    chain.authority_request,
    fixture_envelope(
      "authority-denial-attestation", "authority-attestation", authority, b"denied",
    ),
    authority,
    20L,
    2L,
  )
  let denial_event = try! @governance.prepare_event(
    requested,
    "denial-event",
    @governance.GovernanceAction::authority_decided(denial, "denial-event-key"),
  )
  let denied = try! requested.apply_event(denial_event)
  assert_true(denied.authority_status() == AuthorityDeniedStatus)
  try
    @governance.prepare_event(
      denied,
      "grant-after-denial",
      @governance.GovernanceAction::authority_decided(
        chain.authority_grant,
        "grant-after-denial-key",
      ),
    )
  catch {
    @governance.InvalidState(field~) =>
      assert_eq(field, "authority_terminal_conflict")
    _ => fail("unexpected grant-after-denial error")
  } noraise {
    _ => fail("expected grant-after-denial failure")
  }
  let expiration = try! @governance.AuthorityExpiration::new(
    chain.policy,
    chain.workflow,
    "authority-expiration-1",
    "1.0.0",
    chain.authority_request,
    100L,
    2L,
  )
  let expiration_event = try! @governance.prepare_event(
    requested,
    "expiration-event",
    @governance.GovernanceAction::authority_expired(
      expiration, "expiration-event-key",
    ),
  )
  let expired = try! requested.apply_event(expiration_event)
  assert_true(expired.authority_status() == AuthorityExpiredStatus)
  try
    @governance.prepare_event(
      expired,
      "grant-after-expiry",
      @governance.GovernanceAction::authority_decided(
        chain.authority_grant,
        "grant-after-expiry-key",
      ),
    )
  catch {
    @governance.InvalidState(field~) =>
      assert_eq(field, "authority_terminal_conflict")
    _ => fail("unexpected grant-after-expiry error")
  } noraise {
    _ => fail("expected grant-after-expiry failure")
  }
}

///|
test "FLOW-5A lifecycle prerequisites fail closed without bypasses" {
  let chain = reviewed_chain(Approved)
  let attached = projection_after(chain, 1)
  try
    @governance.prepare_event(
      attached,
      "grant-before-request",
      @governance.GovernanceAction::authority_decided(
        chain.authority_grant,
        "grant-before-request-key",
      ),
    )
  catch {
    @governance.InvalidState(field~) =>
      assert_eq(field, "authority_decision_before_request")
    _ => fail("unexpected authority prerequisite error")
  } noraise {
    _ => fail("expected authority prerequisite failure")
  }
  let requested = projection_after(chain, 2)
  try
    @governance.prepare_event(
      requested,
      "review-before-grant",
      @governance.GovernanceAction::review_requested(chain.review_request),
    )
  catch {
    @governance.InvalidState(field~) => assert_eq(field, "review_before_grant")
    _ => fail("unexpected review prerequisite error")
  } noraise {
    _ => fail("expected review prerequisite failure")
  }
  let granted = projection_after(chain, 3)
  try
    @governance.prepare_event(
      granted,
      "decision-before-review",
      @governance.GovernanceAction::review_decision_recorded(
        chain.review_decision,
        "decision-before-review-key",
      ),
    )
  catch {
    @governance.InvalidState(field~) =>
      assert_eq(field, "review_decision_before_request")
    _ => fail("unexpected decision prerequisite error")
  } noraise {
    _ => fail("expected decision prerequisite failure")
  }
  let review_requested = projection_after(chain, 4)
  try
    @governance.ReviewReceipt::bind(
      review_requested, "premature-receipt", "1.0.0", 35L,
    )
  catch {
    @governance.ReceiptBindingFailure(field~) =>
      assert_eq(field, "review_decision")
    _ => fail("unexpected receipt prerequisite error")
  } noraise {
    _ => fail("expected receipt prerequisite failure")
  }
  let empty = @governance.GovernanceProjection::new(
    chain.policy,
    chain.workflow,
  )
  try
    @governance.ReviewReceipt::bind(empty, "bare-outcome-receipt", "1.0.0", 1L)
  catch {
    @governance.ReceiptBindingFailure(field~) =>
      assert_eq(field, "authority_request")
    _ => fail("unexpected bare-outcome error")
  } noraise {
    _ => fail("expected bare-outcome failure")
  }
}

///|
test "FLOW-5A expiry boundaries are caller supplied and deterministic" {
  let chain = reviewed_chain(Approved)
  try
    @governance.AuthorityExpiration::new(
      chain.policy,
      chain.workflow,
      "premature-expiration",
      "1.0.0",
      chain.authority_request,
      99L,
      2L,
    )
  catch {
    @governance.ExpiryViolation(field~) =>
      assert_eq(field, "premature_authority_expiry")
    _ => fail("unexpected premature-expiry error")
  } noraise {
    _ => fail("expected premature-expiry failure")
  }
  let authority = chain.authority_grant.authority_ref()
  try
    @governance.AuthorityDecision::grant(
      chain.policy,
      chain.workflow,
      "late-grant",
      "1.0.0",
      chain.authority_request,
      fixture_envelope(
        "late-attestation", "authority-attestation", authority, b"late",
      ),
      authority,
      100L,
      2L,
    )
  catch {
    @governance.ExpiryViolation(field~) =>
      assert_eq(field, "authority_decision_after_expiry")
    _ => fail("unexpected late-grant error")
  } noraise {
    _ => fail("expected late-grant failure")
  }
  let at_boundary = try! @governance.AuthorityExpiration::new(
    chain.policy,
    chain.workflow,
    "boundary-expiration",
    "1.0.0",
    chain.authority_request,
    100L,
    2L,
  )
  assert_eq(at_boundary.asserted_at(), 100L)
}

///|
test "FLOW-5A required ordered evidence and criteria fail closed" {
  let chain = reviewed_chain(Approved)
  let reversed_evidence = [chain.evidence[1], chain.evidence[0]]
  try
    @governance.AuthorityRequest::new(
      chain.policy,
      chain.workflow,
      "reordered-evidence-request",
      "1.0.0",
      chain.attachment,
      chain.authority_request.authority_subject(),
      chain.criteria,
      reversed_evidence,
      10L,
      Some(100L),
      2L,
      "reordered-evidence-key",
    )
  catch {
    @governance.EvidenceViolation(field~) =>
      assert_eq(field, "attachment_evidence_order")
    _ => fail("unexpected reordered-evidence error")
  } noraise {
    _ => fail("expected reordered-evidence failure")
  }
  try
    @governance.AuthorityRequest::new(
      chain.policy,
      chain.workflow,
      "empty-criteria-request",
      "1.0.0",
      chain.attachment,
      chain.authority_request.authority_subject(),
      [],
      chain.evidence,
      10L,
      Some(100L),
      2L,
      "empty-criteria-key",
    )
  catch {
    @governance.CriteriaViolation(field~) =>
      assert_eq(field, "authority_request_criteria")
    _ => fail("unexpected empty-criteria error")
  } noraise {
    _ => fail("expected empty-criteria failure")
  }
  try
    @governance.AuthorityRequest::new(
      chain.policy,
      chain.workflow,
      "duplicate-criteria-request",
      "1.0.0",
      chain.attachment,
      chain.authority_request.authority_subject(),
      [chain.criteria[0], chain.criteria[0]],
      chain.evidence,
      10L,
      Some(100L),
      2L,
      "duplicate-criteria-key",
    )
  catch {
    @governance.CriteriaViolation(field~) =>
      assert_eq(field, "authority_request_criteria")
    _ => fail("unexpected duplicate-criteria error")
  } noraise {
    _ => fail("expected duplicate-criteria failure")
  }
}

///|
test "FLOW-5A criterion findings must be complete exact and ordered" {
  let chain = reviewed_chain(Approved)
  let reviewer = chain.review_decision.reviewer_ref()
  let attestation = fixture_envelope(
    "finding-attestation", "reviewer-attestation", reviewer, b"opaque",
  )
  let correct = [
    @governance.CriterionFinding::new(chain.criteria[0], Satisfied),
    @governance.CriterionFinding::new(chain.criteria[1], Satisfied),
  ]
  let cases = [
    [correct[0]],
    [correct[1], correct[0]],
    [correct[0], correct[0]],
    [
      correct[0],
      @governance.CriterionFinding::new(
        fixture_ref("criterion", "foreign", b"foreign"),
        Satisfied,
      ),
    ],
  ]
  for index, findings in cases {
    try
      @governance.ReviewDecision::new(
        chain.policy,
        chain.workflow,
        "invalid-findings-\{index}",
        "1.0.0",
        chain.review_request,
        reviewer,
        attestation,
        Approved,
        findings,
        [chain.evidence[0]],
        [chain.evidence[1]],
        40L,
        5L,
      )
    catch {
      @governance.CriteriaViolation(_) | @governance.OrderingMismatch(_) => ()
      _ => fail("unexpected finding validation error")
    } noraise {
      _ => fail("expected finding validation failure")
    }
  }
}

///|
test "FLOW-5A contradictory evidence remains separate in projection and receipt" {
  let chain = reviewed_chain(Approved)
  assert_eq(chain.review_decision.supporting_evidence().length(), 1)
  assert_eq(chain.review_decision.contradictory_evidence().length(), 1)
  assert_true(
    chain.review_decision.supporting_evidence()[0] == chain.evidence[0],
  )
  assert_true(
    chain.review_decision.contradictory_evidence()[0] == chain.evidence[1],
  )
  let (original_receipt, _, _) = bind_reviewed_chain(chain)
  let reviewer = chain.review_decision.reviewer_ref()
  let without_contradiction = try! @governance.ReviewDecision::new(
    chain.policy,
    chain.workflow,
    "review-decision-without-contradiction",
    "1.0.0",
    chain.review_request,
    reviewer,
    fixture_envelope(
      "reviewer-attestation-without", "reviewer-attestation", reviewer, b"opaque",
    ),
    Approved,
    [
      @governance.CriterionFinding::new(chain.criteria[0], Satisfied),
      @governance.CriterionFinding::new(chain.criteria[1], Satisfied),
    ],
    [chain.evidence[0]],
    [],
    40L,
    5L,
  )
  let before_decision = projection_after(chain, 4)
  let changed_event = try! @governance.prepare_event(
    before_decision,
    "event-without-contradiction",
    @governance.GovernanceAction::review_decision_recorded(
      without_contradiction, "event-without-contradiction-key",
    ),
  )
  let changed_projection = try! before_decision.apply_event(changed_event)
  let changed_receipt = try! @governance.ReviewReceipt::bind(
    changed_projection, "changed-receipt", "1.0.0", 50L,
  )
  assert_true(
    original_receipt.binding_digest() != changed_receipt.binding_digest(),
  )
  assert_true(
    chain.projection.state_digest() != changed_projection.state_digest(),
  )
}

///|
fn rebuilt_envelope(
  original : @contracts.WireEnvelope,
  subject : @contracts.RecordRef,
  payload : Bytes,
  causation_override? : String,
  envelope_id_override? : String,
  producer_id_override? : String,
  producer_version_override? : String,
  correlation_override? : String,
  stage_ref_override? : @contracts.RecordRef,
  attempt_ref_override? : @contracts.RecordRef,
  artifacts_override? : Array[@contracts.ArtifactRef],
  extensions_override? : Array[@contracts.OpaqueExtension],
) -> @contracts.WireEnvelope {
  let run_ref = original.run_ref()
  let stage_ref = match stage_ref_override {
    Some(value) => Some(value)
    None => original.stage_ref()
  }
  let attempt_ref = match attempt_ref_override {
    Some(value) => Some(value)
    None => original.attempt_ref()
  }
  let correlation_ref = match correlation_override {
    Some(value) => Some(value)
    None => original.correlation_ref()
  }
  let causation_ref = match causation_override {
    Some(value) => Some(value)
    None => original.causation_ref()
  }
  let idempotency_ref = original.idempotency_ref()
  let previous_digest = original.previous_digest()
  let envelope_id = envelope_id_override.unwrap_or(original.envelope_id())
  let producer_id = producer_id_override.unwrap_or(original.producer_id())
  let producer_version = producer_version_override.unwrap_or(
    original.producer_version().text(),
  )
  let artifacts = match artifacts_override {
    Some(value) => value
    None => [ for value in original.artifacts() => value ]
  }
  let extensions = match extensions_override {
    Some(value) => value
    None => [ for value in original.extensions() => value ]
  }
  try! @contracts.WireEnvelope::new(
    original.contract_id(),
    original.contract_version().text(),
    envelope_id,
    original.envelope_kind(),
    subject,
    original.schema(),
    payload,
    producer_id,
    producer_version,
    artifacts,
    [
      for value in original.evidence() => value
    ],
    run_ref?,
    stage_ref?,
    attempt_ref?,
    correlation_ref?,
    causation_ref?,
    idempotency_ref?,
    previous_digest?,
    extensions~,
  )
}

///|
fn rebuilt_event(
  original : @storage.WorkflowEvent,
  workflow : @contracts.RecordRef,
  envelope : @contracts.WireEnvelope,
  sequence : Int64,
  revision : Int64,
  evidence : Array[@contracts.EvidenceRef],
  previous : @contracts.ContentDigest?,
) -> @storage.WorkflowEvent {
  match previous {
    None =>
      try! @storage.WorkflowEvent::new(
        "1.0.0",
        "1.0.0",
        workflow,
        original.event_ref().id(),
        sequence,
        revision,
        original.idempotency_key(),
        envelope,
        evidence,
      )
    Some(previous) =>
      try! @storage.WorkflowEvent::new(
        "1.0.0",
        "1.0.0",
        workflow,
        original.event_ref().id(),
        sequence,
        revision,
        original.idempotency_key(),
        envelope,
        evidence,
        previous_event_digest=previous,
      )
  }
}

///|
struct RequestIntentFixture {
  projection : @governance.GovernanceProjection
  event : @storage.WorkflowEvent
  requested_work : @contracts.WireEnvelope
  evidence : Array[@contracts.EvidenceRef]
  intent : @storage.OutboxIntent
}

///|
fn request_intent_fixture() -> RequestIntentFixture {
  let chain = try! reviewed_chain(Approved)
  let event = chain.events[1]
  let projection = try! projection_after(chain, 1)
  let requested_work = fixture_envelope(
    "requested-work-identity",
    "opaque-requested-work",
    chain.workflow,
    b"requested-work-identity",
    evidence=chain.evidence,
  )
  let intent = try! @governance.prepare_request_intent(
    event,
    "request-intent-identity",
    "request-intent-identity-key",
    requested_work,
    chain.evidence,
  )
  {
    projection,
    event,
    requested_work,
    evidence: [
      for value in intent.evidence() => value
    ],
    intent,
  }
}

///|
fn rebuilt_request_intent(
  fixture : RequestIntentFixture,
  payload : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
) -> @storage.OutboxIntent {
  try! @storage.OutboxIntent::new(
    "1.0.0",
    "1.0.0",
    fixture.intent.intent_ref().id(),
    fixture.intent.workflow(),
    fixture.intent.causative_event(),
    fixture.intent.idempotency_key(),
    payload,
    evidence,
  )
}

///|
fn validate_request_intent_fixture(
  fixture : RequestIntentFixture,
  intent : @storage.OutboxIntent,
) -> Unit raise {
  ignore(
    @governance.prepare_governance_commit(
      fixture.projection,
      "request-intent-substitution-command",
      [fixture.event],
      [intent],
    ),
  )
}

///|
fn expect_request_intent_rejection(
  fixture : RequestIntentFixture,
  intent : @storage.OutboxIntent,
) -> Unit raise {
  try validate_request_intent_fixture(fixture, intent) catch {
    _ => ()
  } noraise {
    _ => fail("expected request-intent identity rejection")
  }
}

///|
test "FLOW-5A tampered payload subject evidence policy and chain are rejected" {
  let chain = reviewed_chain(Approved)
  let before_request = projection_after(chain, 1)
  let original = chain.events[1]
  let reversed = [chain.evidence[1], chain.evidence[0]]
  let evidence_tampered = rebuilt_event(
    original,
    chain.workflow,
    original.payload(),
    2L,
    2L,
    reversed,
    original.previous_event_digest(),
  )
  try before_request.apply_event(evidence_tampered) catch {
    @governance.EvidenceViolation(field~) =>
      assert_eq(field, "event_evidence_order")
    _ => fail("unexpected event-evidence tamper error")
  } noraise {
    _ => fail("expected event-evidence tamper failure")
  }
  let bytes = original.payload().payload().to_array()
  bytes[bytes.length() - 1] = bytes[bytes.length() - 1] ^ 1
  let payload_tampered_envelope = rebuilt_envelope(
    original.payload(),
    original.payload().subject(),
    Bytes::from_array(bytes),
  )
  let payload_tampered = rebuilt_event(
    original,
    chain.workflow,
    payload_tampered_envelope,
    2L,
    2L,
    chain.evidence,
    original.previous_event_digest(),
  )
  try before_request.apply_event(payload_tampered) catch {
    @governance.DigestMismatch(_) => ()
    _ => fail("unexpected payload tamper error")
  } noraise {
    _ => fail("expected payload tamper failure")
  }
  let changed_subject = fixture_ref(
    "governance-authority-request", "changed-subject", b"changed-subject",
  )
  let subject_tampered_envelope = rebuilt_envelope(
    original.payload(),
    changed_subject,
    original.payload().payload(),
  )
  let subject_tampered = rebuilt_event(
    original,
    chain.workflow,
    subject_tampered_envelope,
    2L,
    2L,
    chain.evidence,
    original.previous_event_digest(),
  )
  try before_request.apply_event(subject_tampered) catch {
    @governance.IdentityMismatch(field~) => assert_eq(field, "event_subject")
    _ => fail("unexpected subject tamper error")
  } noraise {
    _ => fail("expected subject tamper failure")
  }
  let other_policy_projection = @governance.GovernanceProjection::new(
    fixture_policy(id="policy-2"),
    chain.workflow,
  )
  try other_policy_projection.apply_event(chain.events[0]) catch {
    @governance.IdentityMismatch(field~) => assert_eq(field, "policy")
    _ => fail("unexpected policy tamper error")
  } noraise {
    _ => fail("expected policy tamper failure")
  }
  let wrong_workflow = fixture_ref("workflow", "wrong", b"wrong")
  let workflow_tampered = rebuilt_event(
    chain.events[0],
    wrong_workflow,
    chain.events[0].payload(),
    1L,
    1L,
    chain.evidence,
    None,
  )
  let empty = @governance.GovernanceProjection::new(
    chain.policy,
    chain.workflow,
  )
  try empty.apply_event(workflow_tampered) catch {
    @governance.IdentityMismatch(field~) => assert_eq(field, "event_workflow")
    _ => fail("unexpected workflow tamper error")
  } noraise {
    _ => fail("expected workflow tamper failure")
  }
  let wrong_chain = rebuilt_event(
    original,
    chain.workflow,
    original.payload(),
    2L,
    2L,
    chain.evidence,
    Some(@contracts.sha256_digest(b"wrong-previous")),
  )
  try before_request.apply_event(wrong_chain) catch {
    @governance.DigestMismatch(field~) =>
      assert_eq(field, "previous_event_digest")
    _ => fail("unexpected previous-digest error")
  } noraise {
    _ => fail("expected previous-digest failure")
  }
  let wrong_sequence = rebuilt_event(
    original,
    chain.workflow,
    original.payload(),
    3L,
    3L,
    chain.evidence,
    original.previous_event_digest(),
  )
  try before_request.apply_event(wrong_sequence) catch {
    @governance.RevisionMismatch(field~, ..) =>
      assert_eq(field, "event_sequence")
    _ => fail("unexpected sequence error")
  } noraise {
    _ => fail("expected sequence failure")
  }
}

///|
test "FLOW-5A causation and request-only outbox boundaries reject substitution" {
  let chain = reviewed_chain(Approved)
  let before_request = projection_after(chain, 1)
  let original = chain.events[1]
  let causation_tampered_envelope = rebuilt_envelope(
    original.payload(),
    original.payload().subject(),
    original.payload().payload(),
    causation_override="wrong-event",
  )
  let causation_tampered = rebuilt_event(
    original,
    chain.workflow,
    causation_tampered_envelope,
    2L,
    2L,
    chain.evidence,
    original.previous_event_digest(),
  )
  try before_request.apply_event(causation_tampered) catch {
    @governance.CausationMismatch(field~) => assert_eq(field, "event_causation")
    _ => fail("unexpected causation error")
  } noraise {
    _ => fail("expected causation failure")
  }
  let requested_work = fixture_envelope(
    "requested-work-valid",
    "opaque-requested-work",
    chain.workflow,
    b"requested-work",
    evidence=chain.evidence,
  )
  let valid_intent = try! @governance.prepare_request_intent(
    original,
    "valid-intent",
    "valid-intent-key",
    requested_work,
    chain.evidence,
  )
  let valid_request = try! @governance.prepare_governance_commit(
    before_request,
    "valid-intent-command",
    [original],
    [valid_intent],
  )
  assert_eq(valid_request.intents().length(), 1)
  let substituted = try! @storage.OutboxIntent::new(
    "1.0.0",
    "1.0.0",
    "substituted-intent",
    chain.workflow,
    original.event_ref(),
    "substituted-intent-key",
    requested_work,
    chain.evidence,
  )
  try
    @governance.prepare_governance_commit(
      before_request,
      "substituted-command",
      [original],
      [substituted],
    )
  catch {
    @governance.InvalidEventKind(_) => ()
    _ => fail("unexpected request-intent substitution error")
  } noraise {
    _ => fail("expected request-intent substitution failure")
  }
  try
    @governance.prepare_request_intent(
      chain.events[2],
      "decision-intent",
      "decision-intent-key",
      requested_work,
      chain.evidence,
    )
  catch {
    @governance.InvalidState(field~) =>
      assert_eq(field, "request_intent_causation")
    _ => fail("unexpected non-request event intent error")
  } noraise {
    _ => fail("expected non-request event intent failure")
  }
}

///|
test "FLOW-5A prepare canonicalizes one immutable request-intent evidence identity" {
  let chain = reviewed_chain(Approved)
  let event = chain.events[1]
  let caller_evidence = [
    fixture_evidence("evidence-z"),
    fixture_evidence("evidence-a"),
  ]
  let requested_work = fixture_envelope(
    "requested-work-canonical-evidence",
    "opaque-requested-work",
    chain.workflow,
    b"requested-work-canonical-evidence",
  )
  let intent = try! @governance.prepare_request_intent(
    event, "canonical-evidence-intent", "canonical-evidence-key", requested_work,
    caller_evidence,
  )
  let wrapper_evidence = intent.payload().evidence()
  let intent_evidence = intent.evidence()
  assert_eq(wrapper_evidence.length(), 2)
  assert_eq(intent_evidence.length(), 2)
  assert_eq(wrapper_evidence[0].record().id(), "evidence-a")
  assert_eq(wrapper_evidence[1].record().id(), "evidence-z")
  assert_eq(
    intent.intent_ref().digest().text(),
    "sha256:cb66ad32784d0bd319ddf05dfeb798a4ff448f5df9dee0700d3ed40ab3eb4a68",
  )
  for index, value in wrapper_evidence {
    assert_true(value == intent_evidence[index])
  }
  caller_evidence[0] = fixture_evidence("evidence-foreign")
  caller_evidence.push(fixture_evidence("evidence-added"))
  assert_eq(wrapper_evidence.length(), 2)
  assert_eq(intent_evidence.length(), 2)
  assert_eq(wrapper_evidence[0].record().id(), "evidence-a")
  assert_eq(intent_evidence[1].record().id(), "evidence-z")
  let projection = projection_after(chain, 1)
  ignore(
    try! @governance.prepare_governance_commit(
      projection,
      "canonical-evidence-command",
      [event],
      [intent],
    ),
  )
}

///|
test "FLOW-5A request intent rejects substituted record version" {
  let fixture = request_intent_fixture()
  try
    @storage.OutboxIntent::new(
      "1.1.0",
      "1.0.0",
      fixture.intent.intent_ref().id(),
      fixture.intent.workflow(),
      fixture.intent.causative_event(),
      fixture.intent.idempotency_key(),
      fixture.intent.payload(),
      fixture.evidence,
    )
  catch {
    UnsupportedVersion(record_kind~, version~) => {
      assert_eq(record_kind, "outbox_intent")
      assert_eq(version, "1.1.0")
    }
    _ => fail("unexpected request-intent record-version error")
  } noraise {
    _ => fail("expected request-intent record-version rejection")
  }
}

///|
test "FLOW-5A request intent rejects substituted schema version" {
  let fixture = request_intent_fixture()
  try
    @storage.OutboxIntent::new(
      "1.0.0",
      "1.1.0",
      fixture.intent.intent_ref().id(),
      fixture.intent.workflow(),
      fixture.intent.causative_event(),
      fixture.intent.idempotency_key(),
      fixture.intent.payload(),
      fixture.evidence,
    )
  catch {
    UnsupportedVersion(record_kind~, version~) => {
      assert_eq(record_kind, "outbox_intent_schema")
      assert_eq(version, "1.1.0")
    }
    _ => fail("unexpected request-intent schema-version error")
  } noraise {
    _ => fail("expected request-intent schema-version rejection")
  }
}

///|
test "FLOW-5A request wrapper rejects substituted producer id" {
  let fixture = request_intent_fixture()
  let payload = rebuilt_envelope(
    fixture.intent.payload(),
    fixture.event.event_ref(),
    fixture.intent.payload().payload(),
    producer_id_override="foreign-producer",
  )
  let substituted = rebuilt_request_intent(fixture, payload, fixture.evidence)
  try validate_request_intent_fixture(fixture, substituted) catch {
    @governance.IdentityMismatch(field~) =>
      assert_eq(field, "request_intent_producer")
    _ => fail("unexpected request-intent producer-id error")
  } noraise {
    _ => fail("expected request-intent producer-id rejection")
  }
}

///|
test "FLOW-5A request wrapper rejects substituted producer version" {
  let fixture = request_intent_fixture()
  let payload = rebuilt_envelope(
    fixture.intent.payload(),
    fixture.event.event_ref(),
    fixture.intent.payload().payload(),
    producer_version_override="1.1.0",
  )
  let substituted = rebuilt_request_intent(fixture, payload, fixture.evidence)
  try validate_request_intent_fixture(fixture, substituted) catch {
    @governance.IdentityMismatch(field~) =>
      assert_eq(field, "request_intent_producer")
    _ => fail("unexpected request-intent producer-version error")
  } noraise {
    _ => fail("expected request-intent producer-version rejection")
  }
}

///|
test "FLOW-5A request wrapper rejects substituted envelope id" {
  let fixture = request_intent_fixture()
  let payload = rebuilt_envelope(
    fixture.intent.payload(),
    fixture.event.event_ref(),
    fixture.intent.payload().payload(),
    envelope_id_override="request-intent-envelope-foreign",
  )
  let substituted = rebuilt_request_intent(fixture, payload, fixture.evidence)
  try validate_request_intent_fixture(fixture, substituted) catch {
    @governance.IdentityMismatch(field~) =>
      assert_eq(field, "request_intent_envelope_identity")
    _ => fail("unexpected request-intent envelope-id error")
  } noraise {
    _ => fail("expected request-intent envelope-id rejection")
  }
}

///|
test "FLOW-5A request wrapper rejects substituted correlation ref" {
  let fixture = request_intent_fixture()
  let payload = rebuilt_envelope(
    fixture.intent.payload(),
    fixture.event.event_ref(),
    fixture.intent.payload().payload(),
    correlation_override="foreign-workflow",
  )
  let substituted = rebuilt_request_intent(fixture, payload, fixture.evidence)
  try validate_request_intent_fixture(fixture, substituted) catch {
    @governance.CausationMismatch(field~) =>
      assert_eq(field, "request_intent_correlation")
    _ => fail("unexpected request-intent correlation error")
  } noraise {
    _ => fail("expected request-intent correlation rejection")
  }
}

///|
test "FLOW-5A request wrapper rejects substituted stage ref" {
  let fixture = request_intent_fixture()
  let payload = rebuilt_envelope(
    fixture.intent.payload(),
    fixture.event.event_ref(),
    fixture.intent.payload().payload(),
    stage_ref_override=fixture_ref("stage", "foreign-stage", b"foreign-stage"),
  )
  let substituted = rebuilt_request_intent(fixture, payload, fixture.evidence)
  try validate_request_intent_fixture(fixture, substituted) catch {
    @governance.IdentityMismatch(field~) =>
      assert_eq(field, "request_intent_workflow_binding")
    _ => fail("unexpected request-intent stage-ref error")
  } noraise {
    _ => fail("expected request-intent stage-ref rejection")
  }
}

///|
test "FLOW-5A request wrapper rejects substituted attempt ref" {
  let fixture = request_intent_fixture()
  let payload = rebuilt_envelope(
    fixture.intent.payload(),
    fixture.event.event_ref(),
    fixture.intent.payload().payload(),
    attempt_ref_override=fixture_ref(
      "attempt", "foreign-attempt", b"foreign-attempt",
    ),
  )
  let substituted = rebuilt_request_intent(fixture, payload, fixture.evidence)
  try validate_request_intent_fixture(fixture, substituted) catch {
    @governance.IdentityMismatch(field~) =>
      assert_eq(field, "request_intent_workflow_binding")
    _ => fail("unexpected request-intent attempt-ref error")
  } noraise {
    _ => fail("expected request-intent attempt-ref rejection")
  }
}

///|
test "FLOW-5A request wrapper rejects substituted artifacts" {
  let fixture = request_intent_fixture()
  let artifact_record = fixture_ref(
    "artifact", "foreign-artifact", b"foreign-artifact",
  )
  let artifact = try! @contracts.ArtifactRef::new(
    artifact_record,
    "evidence/foreign-artifact.bin",
    "application/octet-stream",
    fixture_ref("provenance", "foreign-source", b"foreign-source"),
    artifact_record.digest().text(),
  )
  let payload = rebuilt_envelope(
    fixture.intent.payload(),
    fixture.event.event_ref(),
    fixture.intent.payload().payload(),
    artifacts_override=[artifact],
  )
  let substituted = rebuilt_request_intent(fixture, payload, fixture.evidence)
  try validate_request_intent_fixture(fixture, substituted) catch {
    @governance.MalformedPayload(field~) =>
      assert_eq(field, "request_intent_extras")
    _ => fail("unexpected request-intent artifacts error")
  } noraise {
    _ => fail("expected request-intent artifacts rejection")
  }
}

///|
test "FLOW-5A request wrapper rejects substituted extensions" {
  let fixture = request_intent_fixture()
  let extension = try! @contracts.OpaqueExtension::new(
    "neutral.fixture", "foreign-extension", b"foreign-extension",
  )
  let payload = rebuilt_envelope(
    fixture.intent.payload(),
    fixture.event.event_ref(),
    fixture.intent.payload().payload(),
    extensions_override=[extension],
  )
  let substituted = rebuilt_request_intent(fixture, payload, fixture.evidence)
  try validate_request_intent_fixture(fixture, substituted) catch {
    @governance.MalformedPayload(field~) =>
      assert_eq(field, "request_intent_extras")
    _ => fail("unexpected request-intent extensions error")
  } noraise {
    _ => fail("expected request-intent extensions rejection")
  }
}

///|
test "FLOW-5A request wrapper rejects malformed embedded requested-work bytes" {
  let fixture = request_intent_fixture()
  let payload = rebuilt_envelope(
    fixture.intent.payload(),
    fixture.event.event_ref(),
    b"malformed-requested-work",
  )
  let substituted = rebuilt_request_intent(fixture, payload, fixture.evidence)
  expect_request_intent_rejection(fixture, substituted)
}

///|
test "FLOW-5A request wrapper rejects noncanonical embedded requested-work bytes" {
  let fixture = request_intent_fixture()
  let noncanonical = @contracts.encode_wire_envelope(fixture.requested_work) +
    b"trailing"
  let payload = rebuilt_envelope(
    fixture.intent.payload(),
    fixture.event.event_ref(),
    noncanonical,
  )
  let substituted = rebuilt_request_intent(fixture, payload, fixture.evidence)
  expect_request_intent_rejection(fixture, substituted)
}

///|
test "FLOW-5A request intent rejects duplicate multiset evidence substitution" {
  let fixture = request_intent_fixture()
  let substituted = rebuilt_request_intent(fixture, fixture.intent.payload(), [
    fixture.evidence[0],
    fixture.evidence[0],
  ])
  try validate_request_intent_fixture(fixture, substituted) catch {
    @governance.EvidenceViolation(field~) =>
      assert_eq(field, "request_intent_evidence")
    _ => fail("unexpected request-intent duplicate-evidence error")
  } noraise {
    _ => fail("expected request-intent duplicate-evidence rejection")
  }
}

///|
test "FLOW-5A request intent rejects missing evidence substitution" {
  let fixture = request_intent_fixture()
  let substituted = rebuilt_request_intent(fixture, fixture.intent.payload(), [
    fixture.evidence[0],
  ])
  try validate_request_intent_fixture(fixture, substituted) catch {
    @governance.EvidenceViolation(field~) =>
      assert_eq(field, "request_intent_evidence")
    _ => fail("unexpected request-intent missing-evidence error")
  } noraise {
    _ => fail("expected request-intent missing-evidence rejection")
  }
}

///|
test "FLOW-5A request intent rejects added evidence substitution" {
  let fixture = request_intent_fixture()
  let substituted = rebuilt_request_intent(
    fixture,
    fixture.intent.payload(),
    fixture.evidence + [fixture_evidence("evidence-added")],
  )
  try validate_request_intent_fixture(fixture, substituted) catch {
    @governance.EvidenceViolation(field~) =>
      assert_eq(field, "request_intent_evidence")
    _ => fail("unexpected request-intent added-evidence error")
  } noraise {
    _ => fail("expected request-intent added-evidence rejection")
  }
}

///|
test "FLOW-5A request intent rejects foreign evidence substitution" {
  let fixture = request_intent_fixture()
  let substituted = rebuilt_request_intent(fixture, fixture.intent.payload(), [
    fixture.evidence[0],
    fixture_evidence("evidence-foreign"),
  ])
  try validate_request_intent_fixture(fixture, substituted) catch {
    @governance.EvidenceViolation(field~) =>
      assert_eq(field, "request_intent_evidence")
    _ => fail("unexpected request-intent foreign-evidence error")
  } noraise {
    _ => fail("expected request-intent foreign-evidence rejection")
  }
}

///|
test "FLOW-5A request intent rejects evidence order substitution" {
  let fixture = request_intent_fixture()
  let substituted = rebuilt_request_intent(fixture, fixture.intent.payload(), [
    fixture.evidence[1],
    fixture.evidence[0],
  ])
  try validate_request_intent_fixture(fixture, substituted) catch {
    @governance.EvidenceViolation(field~) =>
      assert_eq(field, "request_intent_evidence")
    _ => fail("unexpected request-intent evidence-order error")
  } noraise {
    _ => fail("expected request-intent evidence-order rejection")
  }
}

///|
test "FLOW-5A replay ignores stale checkpoint snapshots and remains byte exact" {
  let chain = reviewed_chain(Approved)
  let (receipt, receipt_event, terminal) = bind_reviewed_chain(chain)
  let all_events = [ for event in chain.events => event ]
  all_events.push(receipt_event)
  let empty = @governance.GovernanceProjection::new(
    chain.policy,
    chain.workflow,
  )
  let store = @storage.MemoryStore::new()
  ignore(
    store.commit(
      try! @governance.prepare_governance_commit(
        empty,
        "complete-chain-command",
        all_events,
        [],
      ),
    ),
  )
  let stale_checkpoint = try! @storage.CheckpointRecord::new(
    "1.0.0",
    "1.0.0",
    "1.0.0",
    "stale-governance-checkpoint",
    chain.workflow,
    3L,
    3L,
    fixture_envelope(
      "stale-snapshot",
      "opaque-snapshot",
      chain.workflow,
      b"not-authoritative-projection-bytes",
    ),
    chain.evidence,
    last_event_digest=chain.events[2].event_ref().digest(),
  )
  store.write_checkpoint(stale_checkpoint)
  let replay = store.replay(chain.workflow)
  assert_true(replay.checkpoint() == Some(stale_checkpoint))
  assert_eq(replay.tail_events().length(), 3)
  let restarted = try! @governance.fold_replay(chain.policy, replay)
  assert_true(restarted.canonical_bytes() == terminal.canonical_bytes())
  assert_true(restarted.state_digest() == terminal.state_digest())
  guard restarted.receipt() is Some(restarted_receipt) else {
    fail("missing restarted receipt")
  }
  assert_true(restarted_receipt.canonical_bytes() == receipt.canonical_bytes())
  assert_true(restarted_receipt.binding_digest() == receipt.binding_digest())
}

///|
test "FLOW-5A malformed versions references and attestation identities fail typed" {
  try
    @governance.GovernancePolicy::new(
      "unsupported-policy",
      "2.0.0",
      "1.0.0",
      "1.0.0",
      ["authority-ref"],
      ["named-human-reviewer"],
      1,
      1,
      [Approved],
    )
  catch {
    @governance.UnsupportedVersion(field~, version~) => {
      assert_eq(field, "policy_version")
      assert_eq(version, "2.0.0")
    }
    _ => fail("unexpected policy-version error")
  } noraise {
    _ => fail("expected policy-version failure")
  }
  let chain = reviewed_chain(Approved)
  let wrong_authority = fixture_ref(
    "foreign-authority-kind", "authority-foreign", b"authority-foreign",
  )
  try
    @governance.AuthorityDecision::grant(
      chain.policy,
      chain.workflow,
      "foreign-authority-decision",
      "1.0.0",
      chain.authority_request,
      fixture_envelope(
        "foreign-authority-attestation", "authority-attestation", wrong_authority,
        b"opaque",
      ),
      wrong_authority,
      20L,
      2L,
    )
  catch {
    @governance.IdentityMismatch(field~) => assert_eq(field, "authority_kind")
    _ => fail("unexpected authority-kind error")
  } noraise {
    _ => fail("expected authority-kind failure")
  }
  let reviewer = chain.review_decision.reviewer_ref()
  try
    @governance.ReviewDecision::new(
      chain.policy,
      chain.workflow,
      "mismatched-reviewer-decision",
      "1.0.0",
      chain.review_request,
      reviewer,
      fixture_envelope(
        "mismatched-reviewer-attestation",
        "reviewer-attestation",
        fixture_ref("named-human-reviewer", "other", b"other"),
        b"opaque",
      ),
      Approved,
      [
        @governance.CriterionFinding::new(chain.criteria[0], Satisfied),
        @governance.CriterionFinding::new(chain.criteria[1], Satisfied),
      ],
      [chain.evidence[0]],
      [chain.evidence[1]],
      40L,
      5L,
    )
  catch {
    @governance.IdentityMismatch(field~) =>
      assert_eq(field, "reviewer_attestation_subject")
    _ => fail("unexpected reviewer binding error")
  } noraise {
    _ => fail("expected reviewer binding failure")
  }
  try
    @contracts.RecordRef::new(
      "",
      "bad",
      "1.0.0",
      @contracts.sha256_digest(b"bad").text(),
    )
  catch {
    InvalidReferenceField(..) => ()
    _ => fail("unexpected malformed-reference error")
  } noraise {
    _ => fail("expected malformed-reference failure")
  }
}

///|
test "FLOW-5A canonical state and receipt golden digests are frozen" {
  let chain = reviewed_chain(Approved)
  let (receipt, _, terminal) = bind_reviewed_chain(chain)
  assert_eq(
    terminal.state_digest().text(),
    "sha256:98932d60b3b8d80f6d5b2e5b20d56bbdc99a675e43bf94bbb9840954c8a0d3cf",
  )
  assert_eq(
    receipt.binding_digest().text(),
    "sha256:9190a8f1deaa7894a3e7e394c5ca3b51b15e56543a246eaec01c9c276d763798",
  )
}
