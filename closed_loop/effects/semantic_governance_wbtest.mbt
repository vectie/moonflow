///|
fn sg_envelope(
  id : String,
  kind : String,
  subject : @contracts.RecordRef,
  evidence : Array[@contracts.EvidenceRef],
) -> @contracts.WireEnvelope {
  try! @contracts.WireEnvelope::new(
    "neutral.fixture",
    "1.0.0",
    id,
    kind,
    subject,
    try! @contracts.SchemaRef::new(
      "neutral.fixture",
      "1.0.0",
      kind,
      "1.0.0",
      @contracts.sha256_digest(@utf8.encode("schema-" + kind)).text(),
    ),
    @utf8.encode("payload-" + id),
    "neutral-fixture",
    "1.0.0",
    [],
    evidence,
  )
}

///|
fn sg_encode_summary(
  summary : DecodedGovernanceSummary,
) -> Bytes raise EffectsError {
  let writer = EffectsWriter::new()
  writer.bytes(if summary.semantic_v2 { b"MF6AGOV2" } else { b"MF6AGOV1" })
  writer.string(effects_record_version)
  write_ref(writer, summary.workflow)
  write_ref(writer, summary.policy_ref)
  if summary.semantic_v2 {
    writer.bytes(summary.policy_bytes)
  }
  write_ref(writer, summary.authority_request_ref)
  write_ref(writer, summary.authority_grant_ref)
  write_ref(writer, summary.authority_ref)
  writer.optional_int64(summary.authority_expires_at)
  write_ref(writer, summary.review_request_ref)
  write_ref(writer, summary.review_decision_ref)
  write_ref(writer, summary.reviewer_ref)
  write_ref(writer, summary.review_receipt_ref)
  write_ref(writer, summary.governed_subject)
  writer.string(summary.governed_subject_digest.text())
  writer.string(summary.projection_digest.text())
  writer.string(summary.authoritative_replay_digest.text())
  writer.bytes(summary.authority_request_bytes)
  writer.bytes(summary.authority_grant_bytes)
  writer.bytes(summary.review_request_bytes)
  writer.bytes(summary.review_decision_bytes)
  writer.bytes(summary.review_receipt_bytes)
  writer.finish()
}

///|
fn sg_clone_position(
  event : @storage.WorkflowEvent,
  sequence : Int64,
  previous : @contracts.ContentDigest?,
  envelope_idempotency_override? : String,
) -> @storage.WorkflowEvent raise {
  let original = event.payload()
  let run_ref = original.run_ref()
  let stage_ref = original.stage_ref()
  let attempt_ref = original.attempt_ref()
  let correlation_ref = original.correlation_ref()
  let causation_ref = original.causation_ref()
  let idempotency_ref = Some(
    envelope_idempotency_override.unwrap_or(event.idempotency_key()),
  )
  let previous_digest = previous
  let envelope = @contracts.WireEnvelope::new(
    original.contract_id(),
    original.contract_version().text(),
    original.envelope_id(),
    original.envelope_kind(),
    original.subject(),
    original.schema(),
    original.payload(),
    original.producer_id(),
    original.producer_version().text(),
    [
      for value in original.artifacts() => value
    ],
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
    extensions=[ for value in original.extensions() => value ],
  )
  let previous_event_digest = previous
  @storage.WorkflowEvent::new(
    event.record_version().text(),
    event.schema_version().text(),
    event.workflow(),
    event.event_ref().id(),
    sequence,
    sequence,
    event.idempotency_key(),
    envelope,
    [
      for value in event.evidence() => value
    ],
    previous_event_digest?,
  )
}

///|
fn sg_unrelated_prelude(
  workflow : @contracts.RecordRef,
) -> @storage.WorkflowEvent raise {
  let subject = wb_ref("subject", "sg-unrelated-prelude")
  let envelope = @contracts.WireEnvelope::new(
    "neutral.fixture",
    "1.0.0",
    "sg-unrelated-prelude-event",
    "unrelated.prelude",
    subject,
    try! @contracts.SchemaRef::new(
      "neutral.fixture",
      "1.0.0",
      "unrelated.prelude",
      "1.0.0",
      @contracts.sha256_digest(b"sg-unrelated-prelude-schema").text(),
    ),
    b"unrelated-prelude",
    "neutral-fixture",
    "1.0.0",
    [],
    [],
    run_ref=workflow,
    idempotency_ref="sg-unrelated-prelude-key",
  )
  @storage.WorkflowEvent::new(
    "1.0.0",
    "1.0.0",
    workflow,
    "sg-unrelated-prelude-event",
    1L,
    1L,
    "sg-unrelated-prelude-key",
    envelope,
    [],
  )
}

///|
test "FLOW-7 semantic V2 rejects a self-consistent chain bound to a foreign policy" {
  let policy = @governance.GovernancePolicy::new(
    "sg-policy",
    "1.0.0",
    "1.0.0",
    "1.0.0",
    ["authority-ref"],
    ["named-human-reviewer"],
    1,
    1,
    [@governance.Approved, @governance.Rejected, @governance.ChangesRequested],
  )
  let foreign_policy = @governance.GovernancePolicy::new(
    "sg-foreign-policy",
    "1.0.0",
    "1.0.0",
    "1.0.0",
    ["authority-ref"],
    ["named-human-reviewer"],
    1,
    1,
    [@governance.Approved, @governance.Rejected, @governance.ChangesRequested],
  )
  let workflow = wb_ref("workflow", "sg-workflow")
  let evidence = [wb_evidence("sg-evidence")]
  let criterion = wb_ref("criterion", "sg-criterion")
  let criteria = [criterion]
  let attachment = @governance.EvidenceAttachment::new(
    policy,
    workflow,
    "sg-attachment",
    "1.0.0",
    evidence,
    wb_ref("criterion-set", "sg-purpose"),
    1L,
  )
  let mut projection = @governance.GovernanceProjection::new(policy, workflow)
  let events : Array[@storage.WorkflowEvent] = []
  let event1 = @governance.prepare_event(
    projection,
    "sg-event-1",
    @governance.GovernanceAction::evidence_attached(attachment, "sg-key-1"),
  )
  projection = projection.apply_event(event1)
  events.push(event1)
  let authority_request = @governance.AuthorityRequest::new(
    policy,
    workflow,
    "sg-authority-request",
    "1.0.0",
    attachment,
    sg_envelope(
      "sg-authority-subject",
      "authority-subject",
      wb_ref("subject", "sg-authority-subject"),
      evidence,
    ),
    criteria,
    evidence,
    10L,
    Some(1000L),
    2L,
    "sg-key-2",
  )
  let event2 = @governance.prepare_event(
    projection,
    "sg-event-2",
    @governance.GovernanceAction::authority_requested(authority_request),
  )
  projection = projection.apply_event(event2)
  events.push(event2)
  let authority = wb_ref("authority-ref", "sg-authority")
  let grant = @governance.AuthorityDecision::grant(
    policy,
    workflow,
    "sg-grant",
    "1.0.0",
    authority_request,
    sg_envelope("sg-authority-proof", "authority-proof", authority, []),
    authority,
    20L,
    2L,
  )
  let event3 = @governance.prepare_event(
    projection,
    "sg-event-3",
    @governance.GovernanceAction::authority_decided(grant, "sg-key-3"),
  )
  projection = projection.apply_event(event3)
  events.push(event3)
  let subject = wb_ref("subject", "sg-governed")
  let review_request = @governance.ReviewRequest::new(
    policy,
    workflow,
    "sg-review-request",
    "1.0.0",
    authority_request,
    grant,
    criteria,
    evidence,
    sg_envelope("sg-review-subject", "review-subject", subject, evidence),
    30L,
    4L,
    "sg-key-4",
  )
  let event4 = @governance.prepare_event(
    projection,
    "sg-event-4",
    @governance.GovernanceAction::review_requested(review_request),
  )
  projection = projection.apply_event(event4)
  events.push(event4)
  let reviewer = wb_ref("named-human-reviewer", "sg-reviewer")
  let review_decision = @governance.ReviewDecision::new(
    policy,
    workflow,
    "sg-review-decision",
    "1.0.0",
    review_request,
    reviewer,
    sg_envelope("sg-review-proof", "review-proof", reviewer, []),
    @governance.Approved,
    [@governance.CriterionFinding::new(criterion, @governance.Satisfied)],
    evidence,
    [],
    40L,
    5L,
  )
  let event5 = @governance.prepare_event(
    projection,
    "sg-event-5",
    @governance.GovernanceAction::review_decision_recorded(
      review_decision, "sg-key-5",
    ),
  )
  projection = projection.apply_event(event5)
  events.push(event5)
  let receipt = @governance.ReviewReceipt::bind(
    projection, "sg-receipt", "1.0.0", 50L,
  )
  let event6 = @governance.prepare_event(
    projection,
    "sg-event-6",
    @governance.GovernanceAction::review_receipt_bound(receipt, "sg-key-6"),
  )
  projection = projection.apply_event(event6)
  events.push(event6)
  let summary : DecodedGovernanceSummary = {
    semantic_v2: true,
    workflow,
    policy_ref: policy.policy_ref(),
    policy_bytes: policy.canonical_bytes(),
    authority_request_ref: authority_request.request_ref(),
    authority_grant_ref: grant.decision_ref(),
    authority_ref: grant.authority_ref(),
    authority_expires_at: authority_request.expires_at(),
    review_request_ref: review_request.request_ref(),
    review_decision_ref: review_decision.decision_ref(),
    reviewer_ref: review_decision.reviewer_ref(),
    review_receipt_ref: receipt.receipt_ref(),
    governed_subject: subject,
    governed_subject_digest: review_request.subject().envelope_digest(),
    projection_digest: projection.state_digest(),
    authoritative_replay_digest: strict_replay_digest(workflow, events[:]),
    authority_request_bytes: authority_request.canonical_bytes(),
    authority_grant_bytes: grant.canonical_bytes(),
    review_request_bytes: review_request.canonical_bytes(),
    review_decision_bytes: review_decision.canonical_bytes(),
    review_receipt_bytes: receipt.canonical_bytes(),
    canonical: b"self-consistent-forged-binding",
  }
  ignore(require_governance_prefix(summary, events))
  let prelude = sg_unrelated_prelude(workflow)
  let shifted : Array[@storage.WorkflowEvent] = [prelude]
  let mut shifted_previous = prelude.event_ref().digest()
  for index, event in events {
    let value = sg_clone_position(
      event,
      index.to_int64() + 2L,
      Some(shifted_previous),
    )
    shifted.push(value)
    shifted_previous = value.event_ref().digest()
  }
  ignore(require_governance_prefix(summary, shifted))

  let reordered_source = [
    events[0],
    events[2],
    events[1],
    events[3],
    events[4],
    events[5],
  ]
  let reordered : Array[@storage.WorkflowEvent] = [prelude]
  let mut reordered_previous = prelude.event_ref().digest()
  for index, event in reordered_source {
    let value = sg_clone_position(
      event,
      index.to_int64() + 2L,
      Some(reordered_previous),
    )
    reordered.push(value)
    reordered_previous = value.event_ref().digest()
  }
  try require_governance_prefix(summary, reordered) catch {
    GovernanceViolation(field="strict_governance_event_catalog") => ()
    _ => fail("unexpected governance reorder rejection")
  } noraise {
    _ => fail("accepted reordered semantic governance records")
  }

  let interleaved : Array[@storage.WorkflowEvent] = [prelude]
  let mut interleaved_previous = prelude.event_ref().digest()
  for index, event in events {
    if index == 3 {
      let unrelated = sg_clone_position(prelude, 5L, Some(interleaved_previous))
      interleaved.push(unrelated)
      interleaved_previous = unrelated.event_ref().digest()
    }
    let value = sg_clone_position(
      event,
      interleaved.length().to_int64() + 1L,
      Some(interleaved_previous),
    )
    interleaved.push(value)
    interleaved_previous = value.event_ref().digest()
  }
  try require_governance_prefix(summary, interleaved) catch {
    GovernanceViolation(field="strict_governance_event_interleaving") => ()
    _ => fail("unexpected governance interleaving rejection")
  } noraise {
    _ => fail("accepted interleaved semantic governance records")
  }

  let duplicated = shifted.copy()
  duplicated.insert(3, shifted[2])
  try require_governance_prefix(summary, duplicated) catch {
    IdentityMismatch(field="strict_governance_prefix_record") => ()
    _ => fail("unexpected duplicate governance record rejection")
  } noraise {
    _ => fail("accepted duplicate semantic governance record")
  }

  let wrapper_tamper = shifted.copy()
  wrapper_tamper[2] = sg_clone_position(
    shifted[2],
    shifted[2].sequence(),
    shifted[2].previous_event_digest(),
    envelope_idempotency_override="sg-wrapper-tamper",
  )
  try require_governance_prefix(summary, wrapper_tamper) catch {
    GovernanceViolation(field="strict_governance_transport_binding") => ()
    _ => fail("unexpected governance wrapper-tamper rejection")
  } noraise {
    _ => fail("accepted semantic governance wrapper tamper")
  }
  let foreign_summary = {
    ..summary,
    policy_ref: foreign_policy.policy_ref(),
    policy_bytes: foreign_policy.canonical_bytes(),
  }
  try require_governance_prefix(foreign_summary, events) catch {
    GovernanceViolation(field="strict_governance_semantics") => ()
    _ => fail("unexpected semantic V2 foreign-policy rejection")
  } noraise {
    _ => fail("accepted self-consistent governance chain under foreign policy")
  }
  let substituted_subject = {
    ..summary,
    governed_subject: wb_ref("subject", "sg-substituted-subject"),
  }
  try require_governance_prefix(substituted_subject, events) catch {
    GovernanceViolation(field="strict_governance_summary_binding") => ()
    _ => fail("unexpected semantic V2 subject-substitution rejection")
  } noraise {
    _ => fail("accepted substituted governed subject in semantic summary")
  }
  let substituted_expiry = { ..summary, authority_expires_at: Some(999L) }
  try require_governance_prefix(substituted_expiry, events) catch {
    GovernanceViolation(field="strict_governance_summary_binding") => ()
    _ => fail("unexpected semantic V2 expiry-substitution rejection")
  } noraise {
    _ => fail("accepted substituted authority expiry in semantic summary")
  }

  // Exercise an actual MF6AGOV2 byte substitution through all downstream
  // self-addressed layers before strict replay rejects the semantic mismatch.
  let store = @storage.MemoryStore::new()
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        workflow,
        0L,
        "sg-governance-command",
        events,
        [],
      ),
    ),
  )
  let governance_replay = store.replay(workflow)
  let binding = GovernanceBinding::new_strict_v2(
    policy, governance_replay, authority_request, grant, review_request, review_decision,
    receipt,
  )
  let decoded_binding = decode_governance_summary(binding.canonical_bytes())
  let forged_subject = wb_ref("subject", "sg-byte-substituted-subject")
  let forged_summary = { ..decoded_binding, governed_subject: forged_subject }
  let forged_bytes = sg_encode_summary(forged_summary)
  let redecoded_forgery = decode_governance_summary(forged_bytes)
  assert_true(redecoded_forgery.governed_subject == forged_subject)
  let forged_binding = {
    ..binding,
    governed_subject: forged_subject,
    canonical: forged_bytes,
    binding_digest: @contracts.sha256_digest(forged_bytes),
  }
  let empty = EffectsProjection::new(workflow, policy.policy_ref())
  let governance_only = fold_committed_effects_bytes(empty, governance_replay)
  let requested = sg_envelope(
    "sg-forged-requested-work", "requested-work", forged_subject, evidence,
  )
  let attempt = AttemptRegistration::new(
    "sg-forged-attempt",
    "1.0.0",
    workflow,
    event6,
    1L,
    requested,
    evidence,
    forged_binding,
    60L,
    "sg-forged-attempt-key",
    event6.event_ref().digest(),
  )
  let attempt_event = prepare_attempt_registration_event(
    governance_only, "sg-forged-attempt-event", attempt,
  )
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        workflow,
        6L,
        "sg-forged-attempt-command",
        [attempt_event],
        [],
      ),
    ),
  )
  try fold_committed_effects_bytes(empty, store.replay(workflow)) catch {
    GovernanceViolation(field="strict_governance_summary_binding") => ()
    _ => fail("unexpected downstream-rehashed MF6AGOV2 rejection")
  } noraise {
    _ => fail("accepted downstream-rehashed MF6AGOV2 subject substitution")
  }
}
