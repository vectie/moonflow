///|
fn phase1b_test_envelope(
  id : String,
  kind : String,
  subject : @contracts.RecordRef,
  payload : Bytes,
  evidence : Array[@contracts.EvidenceRef],
) -> @contracts.WireEnvelope {
  let schema = try! @contracts.SchemaRef::new(
    "closed-loop.test",
    "1.0.0",
    kind,
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode("phase1b:\{kind}")).text(),
  )
  try! @contracts.WireEnvelope::new(
    "closed-loop.test",
    "1.0.0",
    id,
    kind,
    subject,
    schema,
    payload,
    "phase1b-test",
    "1.0.0",
    [],
    evidence,
  )
}

///|
priv struct Phase1bGovernanceChain {
  store : @storage.MemoryStore
  events : ReadOnlyArray[@storage.WorkflowEvent]
  pre_receipt_projection : @governance.GovernanceProjection
}

///|
fn phase1b_governance_chain(
  policy : @governance.GovernancePolicy,
  stream : @contracts.RecordRef,
  proposal : CancellationProposalV2,
  evidence : Array[@contracts.EvidenceRef],
  suffix : String,
  expires_at? : Int64? = Some(19L),
  bound_at? : Int64 = 15L,
  review_outcome? : @governance.ReviewOutcome = @governance.Approved,
  bind_receipt? : Bool = true,
) -> Phase1bGovernanceChain raise {
  let criterion = phase1a_wb_ref(
    "criterion",
    "phase1b-criterion-\{suffix}",
    @utf8.encode(suffix),
  )
  let authority = phase1a_wb_ref(
    "authority",
    "phase1b-authority-\{suffix}",
    @utf8.encode(suffix),
  )
  let reviewer = phase1a_wb_ref(
    "reviewer",
    "phase1b-reviewer-\{suffix}",
    @utf8.encode(suffix),
  )
  let attachment = @governance.EvidenceAttachment::new(
    policy,
    stream,
    "phase1b-attachment-\{suffix}",
    "1.0.0",
    evidence,
    proposal.record_ref(),
    1L,
  )
  let mut projection = @governance.GovernanceProjection::new(policy, stream)
  let events : Array[@storage.WorkflowEvent] = []
  let event1 = @governance.prepare_event(
    projection,
    "phase1b-evidence-event-\{suffix}",
    @governance.GovernanceAction::evidence_attached(
      attachment,
      "phase1b-evidence-key-\{suffix}",
    ),
  )
  events.push(event1)
  projection = projection.apply_event(event1)
  let authority_request = @governance.AuthorityRequest::new(
    policy,
    stream,
    "phase1b-authority-request-\{suffix}",
    "1.0.0",
    attachment,
    proposal.governance_subject(),
    [criterion],
    evidence,
    11L,
    expires_at,
    2L,
    "phase1b-authority-request-key-\{suffix}",
  )
  let event2 = @governance.prepare_event(
    projection,
    "phase1b-authority-request-event-\{suffix}",
    @governance.GovernanceAction::authority_requested(authority_request),
  )
  events.push(event2)
  projection = projection.apply_event(event2)
  let authority_grant = @governance.AuthorityDecision::grant(
    policy,
    stream,
    "phase1b-authority-grant-\{suffix}",
    "1.0.0",
    authority_request,
    phase1b_test_envelope(
      "phase1b-authority-attestation-\{suffix}",
      "authority-attestation",
      authority,
      b"approved",
      evidence,
    ),
    authority,
    12L,
    2L,
  )
  let event3 = @governance.prepare_event(
    projection,
    "phase1b-authority-grant-event-\{suffix}",
    @governance.GovernanceAction::authority_decided(
      authority_grant,
      "phase1b-authority-grant-key-\{suffix}",
    ),
  )
  events.push(event3)
  projection = projection.apply_event(event3)
  let review_request = @governance.ReviewRequest::new(
    policy,
    stream,
    "phase1b-review-request-\{suffix}",
    "1.0.0",
    authority_request,
    authority_grant,
    [criterion],
    evidence,
    proposal.governance_subject(),
    13L,
    4L,
    "phase1b-review-request-key-\{suffix}",
  )
  let event4 = @governance.prepare_event(
    projection,
    "phase1b-review-request-event-\{suffix}",
    @governance.GovernanceAction::review_requested(review_request),
  )
  events.push(event4)
  projection = projection.apply_event(event4)
  let review_decision = @governance.ReviewDecision::new(
    policy,
    stream,
    "phase1b-review-decision-\{suffix}",
    "1.0.0",
    review_request,
    reviewer,
    phase1b_test_envelope(
      "phase1b-reviewer-attestation-\{suffix}",
      "reviewer-attestation",
      reviewer,
      b"approved",
      evidence,
    ),
    review_outcome,
    [
      @governance.CriterionFinding::new(
        criterion,
        match review_outcome {
          @governance.Approved => @governance.Satisfied
          @governance.Rejected => @governance.Unsatisfied
          @governance.ChangesRequested => @governance.NeedsRevision
        },
      ),
    ],
    evidence,
    [],
    14L,
    5L,
  )
  let event5 = @governance.prepare_event(
    projection,
    "phase1b-review-decision-event-\{suffix}",
    @governance.GovernanceAction::review_decision_recorded(
      review_decision,
      "phase1b-review-decision-key-\{suffix}",
    ),
  )
  events.push(event5)
  projection = projection.apply_event(event5)
  if review_outcome == @governance.Approved && bind_receipt {
    let review_receipt = @governance.ReviewReceipt::bind(
      projection,
      "phase1b-review-receipt-\{suffix}",
      "1.0.0",
      bound_at,
    )
    let event6 = @governance.prepare_event(
      projection,
      "phase1b-review-receipt-event-\{suffix}",
      @governance.GovernanceAction::review_receipt_bound(
        review_receipt,
        "phase1b-review-receipt-key-\{suffix}",
      ),
    )
    events.push(event6)
  }
  let store = @storage.MemoryStore::new()
  ignore(
    store.commit(
      @governance.prepare_governance_commit(
        @governance.GovernanceProjection::new(policy, stream),
        "phase1b-governance-command-\{suffix}",
        events,
        [],
      ),
    ),
  )
  {
    store,
    events: ReadOnlyArray::from_array(events),
    pre_receipt_projection: projection,
  }
}

///|
priv struct Phase1bFixture {
  work_store : @storage.MemoryStore
  governance : Phase1bGovernanceChain
  empty_effects : @effects.EffectsProjection
  registration : ScheduleRegisteredV2
  proposal : CancellationProposalV2
  current : CurrentGovernedClosedLoopProjectionV2
  receipt : CommittedCancellationGovernanceReceiptV2
  authorization : CancellationAuthorizationV2
  request : CancellationRequestV2
}

///|
priv struct Phase1bPendingFixture {
  work_store : @storage.MemoryStore
  governance : Phase1bGovernanceChain
  empty_effects : @effects.EffectsProjection
  registration : ScheduleRegisteredV2
  attempt : @effects.AttemptRegistration
  intent : @effects.EffectIntent
  current : CurrentGovernedClosedLoopProjectionV2
  request : CancellationRequestV2
}

///|
fn phase1b_pending_fixture(
  suffix : String,
  retry_policy? : RetryPolicyV2,
) -> Phase1bPendingFixture raise {
  let initial = match retry_policy {
    Some(value) => phase1a_wb_initial_with_retry_policy(value)
    None => phase1a_wb_initial()
  }
  let policy = phase1a_wb_policy()
  let effects_fixture = try
    orchestration_fixture_with_governance_version(
      "phase1b-pending-" + suffix,
      true,
      workflow_override=initial.registration.workflow(),
      policy_override=policy,
      authority_kind="authority",
      reviewer_kind="reviewer",
      root_registration=initial.registration,
      governed_subject_override=initial.registration
        .schedule()
        .admission()
        .governance()
        .governed_subject(),
      retry_policy_override?=retry_policy,
    )
  catch {
    error => fail("pending effects fixture: \{to_repr(error)}")
  } noraise {
    value => value
  }
  let work_store = effects_fixture.store
  let empty_effects = @effects.EffectsProjection::new(
    initial.registration.workflow(),
    policy.policy_ref(),
  )
  let replay = work_store.replay(initial.registration.workflow())
  let root = fold_initial_work_receipt_v22(empty_effects, replay)
  let work = fold_closed_loop_v2(empty_effects, replay)
  let evidence = [
    for value in initial.registration.schedule().evidence() => value
  ]
  let proposal = CancellationProposalV2::new(
    "phase1b-pending-proposal-" + suffix,
    root,
    work,
    initial.registration.schedule().admission().governance().governed_subject(),
    phase1a_wb_ref(
      "reason",
      "phase1b-pending-reason-" + suffix,
      @utf8.encode(suffix),
    ),
    10L,
    evidence,
    phase1a_wb_ref(
      "causation",
      "phase1b-pending-causation-" + suffix,
      @utf8.encode(suffix),
    ),
    "phase1b-pending-proposal-event-key-" + suffix,
    "phase1b-pending-proposal-command-key-" + suffix,
  )
  let governance = try
    phase1b_governance_chain(
      policy,
      root.governance_stream_ref(),
      proposal,
      evidence,
      "pending-" + suffix,
    )
  catch {
    error => fail("pending cancellation governance: \{to_repr(error)}")
  } noraise {
    value => value
  }
  let current = fold_governed_closed_loop_v2(
    empty_effects,
    replay,
    governance.store.replay(root.governance_stream_ref()),
  )
  let receipt = current.committed_cancellation_governance_receipt(proposal)
  let authorization = CancellationAuthorizationV2::from_committed_governance(
    "phase1b-pending-authorization-" + suffix,
    receipt,
    proposal,
    current,
  )
  let request = CancellationRequestV2::new(
    "phase1b-pending-request-" + suffix,
    proposal,
    authorization,
  )
  {
    work_store,
    governance,
    empty_effects,
    registration: initial.registration,
    attempt: effects_fixture.attempt,
    intent: effects_fixture.intent,
    current,
    request,
  }
}

///|
priv struct Phase1bDispatchPort {
  observation : @effects.DispatchObservation
  calls : Ref[Int]
}

///|
impl GuardedEffectDispatcherPortV2 for Phase1bDispatchPort with fn dispatch_guarded_effect(
  self,
  call,
) {
  assert_true(call.target().intent_ref() == self.observation.intent_ref())
  self.calls.val = self.calls.val + 1
  self.observation
}

///|
/// Historical V2 fact fixture for replay/terminal regression tests. This is
/// test-only inert data: it never invokes a provider and cannot be imported by
/// production code. V2 execution itself is permanently retired in Phase 2.
fn phase1b_legacy_guarded_observation_fixture_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  authorization : GuardedDispatchAuthorizationV2,
  observation : @effects.DispatchObservation,
) -> GuardedDispatchObservationV2 {
  GuardedDispatchObservationV2::{
    observation,
    dispatch_authorization_ref: authorization.authorization_ref,
    dispatch_authorization_bytes: authorization.canonical,
    intent_ref: authorization.intent_ref,
    outbox_ref: authorization.outbox_ref,
    external_idempotency_key: authorization.external_idempotency_key,
    work_revision: current.work_revision,
    work_head_digest: current.work_head_digest,
    work_replay_digest: current.work_replay_digest,
    governance_revision: current.governance_revision,
    governance_head_digest: current.governance_head_digest,
  }
}

///|
fn phase1b_fixture(
  suffix? : String = "base",
  expires_at? : Int64? = Some(19L),
  bound_at? : Int64 = 15L,
) -> Phase1bFixture raise {
  let initial = phase1a_wb_initial()
  let policy = phase1a_wb_policy()
  let work_store = @storage.MemoryStore::new()
  ignore(
    work_store.commit(
      prepare_initial_work_v22(initial.authorization, initial.registration),
    ),
  )
  let empty_effects = @effects.EffectsProjection::new(
    initial.registration.workflow(),
    policy.policy_ref(),
  )
  let work_replay = work_store.replay(initial.registration.workflow())
  let root = fold_initial_work_receipt_v22(empty_effects, work_replay)
  let work = fold_closed_loop_v2(empty_effects, work_replay)
  let evidence = [
    for value in initial.registration.schedule().evidence() => value
  ]
  let proposal = CancellationProposalV2::new(
    "phase1b-proposal-\{suffix}",
    root,
    work,
    initial.registration.schedule().admission().governance().governed_subject(),
    phase1a_wb_ref("reason", "phase1b-reason-\{suffix}", @utf8.encode(suffix)),
    10L,
    evidence,
    phase1a_wb_ref(
      "causation",
      "phase1b-causation-\{suffix}",
      @utf8.encode(suffix),
    ),
    "phase1b-proposal-event-key-\{suffix}",
    "phase1b-proposal-command-key-\{suffix}",
  )
  let governance = phase1b_governance_chain(
    policy,
    root.governance_stream_ref(),
    proposal,
    evidence,
    suffix,
    expires_at~,
    bound_at~,
  )
  let current = fold_governed_closed_loop_v2(
    empty_effects,
    work_replay,
    governance.store.replay(root.governance_stream_ref()),
  )
  let receipt = current.committed_cancellation_governance_receipt(proposal)
  let authorization = CancellationAuthorizationV2::from_committed_governance(
    "phase1b-authorization-\{suffix}",
    receipt,
    proposal,
    current,
  )
  let request = CancellationRequestV2::new(
    "phase1b-request-\{suffix}",
    proposal,
    authorization,
  )
  {
    work_store,
    governance,
    empty_effects,
    registration: initial.registration,
    proposal,
    current,
    receipt,
    authorization,
    request,
  }
}

///|
fn phase1b_contains_bytes(source : Bytes, needle : Bytes) -> Bool {
  if needle.is_empty() || source.length() < needle.length() {
    return false
  }
  for offset in 0..<=(source.length() - needle.length()) {
    let mut equal = true
    for index in 0..<needle.length() {
      if source[offset + index] != needle[index] {
        equal = false
      }
    }
    if equal {
      return true
    }
  }
  false
}

///|
fn phase1b_append_byte(source : Bytes, value : Byte) -> Bytes {
  let values = source.to_array()
  values.push(value)
  Bytes::from_array(values)
}

///|
fn phase1b_replace_bytes(
  source : Bytes,
  needle : Bytes,
  replacement : Bytes,
) -> Bytes {
  if needle.length() != replacement.length() || needle.is_empty() {
    abort("phase1b replacement length mismatch")
  }
  let values = source.to_array()
  let mut found = false
  for offset in 0..<=(source.length() - needle.length()) {
    let mut equal = true
    for index in 0..<needle.length() {
      if source[offset + index] != needle[index] {
        equal = false
      }
    }
    if equal && !found {
      for index in 0..<replacement.length() {
        values[offset + index] = replacement[index]
      }
      found = true
    }
  }
  if !found {
    abort("phase1b replacement bytes missing")
  }
  Bytes::from_array(values)
}

///|
fn phase1b_readdress(
  original : @contracts.RecordRef,
  bytes : Bytes,
) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(
    original.kind(),
    original.id(),
    original.version().text(),
    @contracts.sha256_digest(bytes).text(),
  )
}

///|
fn phase1b_terminal_option_offsets(bytes : Bytes) -> (Int, Int) raise {
  let reader = OrchestrationReader::new(bytes)
  ignore(reader.read_bytes())
  for _ in 0..<3 {
    ignore(reader.read_string())
  }
  ignore(reader.read_digest())
  ignore(reader.read_ref())
  ignore(reader.read_ref())
  ignore(reader.read_digest())
  ignore(reader.read_ref())
  ignore(reader.read_digest())
  ignore(reader.read_optional_ref())
  ignore(reader.read_optional_ref())
  ignore(read_phase1b_record_v22(reader))
  ignore(read_phase1b_record_v22(reader))
  let cancellation_offset = reader.offset
  if reader.read_int64() != 1L {
    fail("terminal cancellation option fixture drift")
  }
  ignore(read_phase1b_record_v22(reader))
  let retry_offset = reader.offset
  if reader.read_int64() != 0L {
    fail("terminal retry option fixture drift")
  }
  (cancellation_offset, retry_offset)
}

///|
fn phase1b_replace_int64_marker(
  source : Bytes,
  offset : Int,
  marker : Byte,
) -> Bytes {
  let values = source.to_array()
  values[offset + 7] = marker
  Bytes::from_array(values)
}

///|
fn phase1b_clone_replay_to_memory(
  replay : @storage.ReplayResult,
) -> @storage.MemoryStore raise {
  let store = @storage.MemoryStore::new()
  phase1b_append_replay_to_memory(store, replay)
  store
}

///|
fn phase1b_append_replay_to_memory(
  store : @storage.MemoryStore,
  replay : @storage.ReplayResult,
) -> Unit raise {
  for batch in replay.committed_batches() {
    let events : Array[@storage.WorkflowEvent] = []
    for event_ref in batch.event_refs() {
      guard replay.events().search_by(event => event.event_ref() == event_ref)
        is Some(index) else {
        fail("clone replay event missing")
      }
      events.push(replay.events()[index])
    }
    let intents : Array[@storage.OutboxIntent] = []
    for intent_ref in batch.intent_refs() {
      guard replay
        .intents()
        .search_by(intent => intent.intent_ref() == intent_ref)
        is Some(index) else {
        fail("clone replay intent missing")
      }
      intents.push(replay.intents()[index])
    }
    ignore(
      store.commit(
        @storage.CommitRequest::new(
          "1.0.0",
          "1.0.0",
          replay.workflow(),
          batch.expected_revision(),
          batch.command_idempotency_key(),
          events,
          intents,
        ),
      ),
    )
  }
}

///|
fn phase1b_expect_codec_rejected(
  label : String,
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
  current : CurrentGovernedClosedLoopProjectionV2,
  case_name : String,
) -> Unit raise {
  try {
    if label == "proposal" {
      ignore(decode_cancellation_proposal_v22_strict(expected_ref, bytes))
    } else if label == "receipt" {
      ignore(
        decode_committed_cancellation_governance_receipt_v22(
          expected_ref, bytes, current,
        ),
      )
    } else if label == "authorization" {
      ignore(
        decode_cancellation_authorization_v22(expected_ref, bytes, current),
      )
    } else {
      ignore(decode_cancellation_request_v22(expected_ref, bytes, current))
    }
  } catch {
    _ => ()
  } noraise {
    _ => fail("accepted \{label} codec \{case_name}")
  }
}

///|
fn phase1b_clone_governance_event(
  source : @storage.WorkflowEvent,
  event_id : String,
  idempotency_key : String,
  sequence : Int64,
  previous_event : @storage.WorkflowEvent?,
) -> @storage.WorkflowEvent raise {
  let original = source.payload()
  let run_ref = original.run_ref()
  let stage_ref = original.stage_ref()
  let attempt_ref = original.attempt_ref()
  let correlation_ref = original.correlation_ref()
  let causation_ref = previous_event.map(value => value.event_ref().id())
  let previous_digest = previous_event.map(value => value.event_ref().digest())
  let envelope = @contracts.WireEnvelope::new(
    original.contract_id(),
    original.contract_version().text(),
    event_id,
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
    idempotency_ref=idempotency_key,
    previous_digest?,
    extensions=[ for value in original.extensions() => value ],
  )
  @storage.WorkflowEvent::new(
    source.record_version().text(),
    source.schema_version().text(),
    source.workflow(),
    event_id,
    sequence,
    sequence,
    idempotency_key,
    envelope,
    [
      for value in source.evidence() => value
    ],
    previous_event_digest?=previous_digest,
  )
}

///|
fn phase1b_rechained_governance_replay(
  stream : @contracts.RecordRef,
  templates : ArrayView[@storage.WorkflowEvent],
  suffix : String,
  tampered_key_at? : Int = -1,
) -> @storage.ReplayResult raise {
  let events : Array[@storage.WorkflowEvent] = []
  for index, source in templates {
    let base_key = source.idempotency_key()
    let duplicate_key = events.any(event => event.idempotency_key() == base_key)
    let idempotency_key = if index == tampered_key_at {
      base_key + "-tampered"
    } else if duplicate_key {
      base_key + "-duplicate-\{index}"
    } else {
      base_key
    }
    events.push(
      phase1b_clone_governance_event(
        source,
        "phase1b-rechained-\{suffix}-\{index}",
        idempotency_key,
        index.to_int64() + 1L,
        events.last(),
      ),
    )
  }
  let store = @storage.MemoryStore::new()
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        stream,
        0L,
        "phase1b-rechained-command-\{suffix}",
        events,
        [],
      ),
    ),
  )
  store.replay(stream)
}

///|
fn phase1b_unrelated_governance_template(
  stream : @contracts.RecordRef,
) -> @storage.WorkflowEvent raise {
  let subject = phase1a_wb_ref(
    "unrelated", "phase1b-unrelated-subject", b"unrelated",
  )
  @storage.WorkflowEvent::new(
    "1.0.0",
    "1.0.0",
    stream,
    "phase1b-unrelated-template",
    1L,
    1L,
    "phase1b-unrelated-key",
    phase1b_test_envelope(
      "phase1b-unrelated-template",
      "Unrelated",
      subject,
      b"unrelated",
      [],
    ),
    [],
  )
}

///|
fn phase1b_denied_governance_replay(
  fixture : Phase1bFixture,
) -> @storage.ReplayResult raise {
  let policy = phase1a_wb_policy()
  let stream = fixture.receipt.governance_stream_ref
  let mut projection = @governance.GovernanceProjection::new(policy, stream)
  let events : Array[@storage.WorkflowEvent] = []
  for index in 0..<2 {
    let event = fixture.governance.events[index]
    events.push(event)
    projection = projection.apply_event(event)
  }
  guard projection.authority_request_record() is Some(authority_request) else {
    fail("missing authority request for denied replay")
  }
  let authority = phase1a_wb_ref(
    "authority", "phase1b-denied-authority", b"denied-authority",
  )
  let evidence = [ for value in fixture.proposal.evidence() => value ]
  let denial = @governance.AuthorityDecision::deny(
    policy,
    stream,
    "phase1b-authority-denial",
    "1.0.0",
    authority_request,
    phase1b_test_envelope(
      "phase1b-authority-denial-attestation", "authority-attestation", authority,
      b"denied", evidence,
    ),
    authority,
    12L,
    2L,
  )
  let denied_event = @governance.prepare_event(
    projection,
    "phase1b-authority-denied-event",
    @governance.GovernanceAction::authority_decided(
      denial, "phase1b-authority-denied-key",
    ),
  )
  events.push(denied_event)
  let store = @storage.MemoryStore::new()
  ignore(
    store.commit(
      @governance.prepare_governance_commit(
        @governance.GovernanceProjection::new(policy, stream),
        "phase1b-denied-command",
        events,
        [],
      ),
    ),
  )
  store.replay(stream)
}

///|
fn phase1b_expect_governance_replay_rejected(
  fixture : Phase1bFixture,
  replay : @storage.ReplayResult,
  label : String,
) -> Unit raise {
  try
    fold_governed_closed_loop_v2(
      fixture.empty_effects,
      fixture.work_store.replay(fixture.registration.workflow()),
      replay,
    )
  catch {
    ReplayBindingViolation(field="cancellation_governance_event_membership") =>
      ()
    _ => fail("unexpected \{label} governance replay error")
  } noraise {
    _ => fail("accepted \{label} governance replay")
  }
}

///|
test "FLOW-7 Phase1B governed receipt authorization request is replay-only and cycle-free" {
  let fixture = phase1b_fixture()
  fixture.receipt.validate_current(fixture.current)
  assert_eq(fixture.receipt.observed_at(), 15L)
  assert_eq(fixture.receipt.effective_valid_until_inclusive(), 18L)
  assert_eq(fixture.receipt.deadline_exclusive(), 19L)
  assert_eq(fixture.authorization.observed_at(), 15L)
  assert_eq(fixture.authorization.effective_valid_until_inclusive(), 18L)
  assert_eq(fixture.authorization.deadline_exclusive(), 19L)
  assert_true(fixture.request.proposal_ref() == fixture.proposal.record_ref())
  assert_true(
    fixture.request.authorization_ref() == fixture.authorization.record_ref(),
  )
  assert_false(
    phase1b_contains_bytes(
      fixture.authorization.canonical_bytes(),
      @utf8.encode(fixture.request.record_ref().id()),
    ),
  )
  assert_false(
    phase1b_contains_bytes(
      fixture.proposal.canonical_bytes(),
      @utf8.encode(fixture.authorization.record_ref().id()),
    ),
  )
  let replayed_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    fixture.governance.store.replay(fixture.receipt.governance_stream_ref),
  )
  let replayed_receipt = replayed_current.committed_cancellation_governance_receipt(
    fixture.proposal,
  )
  let replayed_authorization = CancellationAuthorizationV2::from_committed_governance(
    "phase1b-authorization-base",
    replayed_receipt,
    fixture.proposal,
    replayed_current,
  )
  assert_true(
    replayed_receipt.canonical_bytes() == fixture.receipt.canonical_bytes(),
  )
  assert_true(
    replayed_authorization.canonical_bytes() ==
    fixture.authorization.canonical_bytes(),
  )
}

///|
test "FLOW-7 Phase1B cross-stream subject and governance membership are exact" {
  let fixture = phase1b_fixture(suffix="membership")
  let subject = fixture.proposal.governance_subject()
  assert_eq(subject.contract_id(), orchestration_contract_id)
  assert_eq(subject.contract_version().text(), orchestration_record_version)
  assert_eq(subject.producer_id(), orchestration_producer_id)
  assert_eq(subject.producer_version().text(), orchestration_record_version)
  assert_eq(subject.envelope_kind(), "cancellation.proposal.v2")
  assert_true(subject.subject() == fixture.proposal.governed_subject())
  assert_true(subject.run_ref() == Some(fixture.proposal.workflow()))
  assert_eq(subject.correlation_ref(), Some(fixture.proposal.workflow().id()))
  assert_eq(subject.causation_ref(), Some(fixture.proposal.causation.id()))
  assert_eq(
    subject.idempotency_ref(),
    Some(fixture.proposal.event_idempotency_key()),
  )
  assert_true(
    subject.previous_digest() ==
    Some(fixture.proposal.prefix_event_ref().digest()),
  )
  assert_true(same_evidence(subject.evidence(), fixture.proposal.evidence()))
  assert_true(
    fixture.receipt.governance_stream_ref ==
    fixture.current.root_binding.governance_stream_ref(),
  )
  assert_true(
    fixture.receipt.governance_policy_ref ==
    fixture.current.root_binding.governance_policy_ref(),
  )
  assert_eq(fixture.current.root_binding.valid_until_inclusive(), 20L)

  let original = [ for event in fixture.governance.events => event ]
  let reordered = [
    original[0],
    original[2],
    original[1],
    original[3],
    original[4],
    original[5],
  ]
  phase1b_expect_governance_replay_rejected(
    fixture,
    phase1b_rechained_governance_replay(
      fixture.receipt.governance_stream_ref,
      reordered,
      "reordered",
    ),
    "reordered",
  )
  let duplicated = [
    original[0],
    original[1],
    original[1],
    original[2],
    original[3],
    original[4],
    original[5],
  ]
  phase1b_expect_governance_replay_rejected(
    fixture,
    phase1b_rechained_governance_replay(
      fixture.receipt.governance_stream_ref,
      duplicated,
      "duplicated",
    ),
    "duplicated",
  )
  let unrelated = phase1b_unrelated_governance_template(
    fixture.receipt.governance_stream_ref,
  )
  let interleaved = [
    original[0],
    original[1],
    unrelated,
    original[2],
    original[3],
    original[4],
    original[5],
  ]
  phase1b_expect_governance_replay_rejected(
    fixture,
    phase1b_rechained_governance_replay(
      fixture.receipt.governance_stream_ref,
      interleaved,
      "interleaved",
    ),
    "interleaved",
  )
  let later = [
    original[0],
    original[1],
    original[2],
    original[3],
    original[4],
    original[5],
    unrelated,
  ]
  phase1b_expect_governance_replay_rejected(
    fixture,
    phase1b_rechained_governance_replay(
      fixture.receipt.governance_stream_ref,
      later,
      "later",
    ),
    "later",
  )
  phase1b_expect_governance_replay_rejected(
    fixture,
    phase1b_rechained_governance_replay(
      fixture.receipt.governance_stream_ref,
      original,
      "wrapper-tamper",
      tampered_key_at=1,
    ),
    "wrapper-tampered",
  )
}

///|
test "FLOW-7 Phase1B denied non-approved and policy-substituted governance mint no authority" {
  let fixture = phase1b_fixture(suffix="governance-negative")
  let work_replay = fixture.work_store.replay(fixture.registration.workflow())
  let denied = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    work_replay,
    phase1b_denied_governance_replay(fixture),
  )
  try denied.committed_cancellation_governance_receipt(fixture.proposal) catch {
    ReplayBindingViolation(field="cancellation_governance_event_membership") =>
      ()
    _ => fail("unexpected denied-governance receipt error")
  } noraise {
    _ => fail("minted cancellation authority from denied governance")
  }
  let policy = phase1a_wb_policy()
  let evidence = [ for value in fixture.proposal.evidence() => value ]
  let rejected_chain = phase1b_governance_chain(
    policy,
    fixture.receipt.governance_stream_ref,
    fixture.proposal,
    evidence,
    "rejected",
    review_outcome=@governance.Rejected,
  )
  let rejected = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    work_replay,
    rejected_chain.store.replay(fixture.receipt.governance_stream_ref),
  )
  try
    rejected.committed_cancellation_governance_receipt(fixture.proposal)
  catch {
    ReplayBindingViolation(field="cancellation_governance_event_membership") =>
      ()
    _ => fail("unexpected rejected-review receipt error")
  } noraise {
    _ => fail("minted cancellation authority from rejected review")
  }
  let substituted_policy = @governance.GovernancePolicy::new(
    "phase1b-substituted-policy",
    "1.0.0",
    "1.0.0",
    "1.0.0",
    ["authority"],
    ["reviewer"],
    1,
    1,
    [@governance.Approved],
  )
  let substituted_chain = phase1b_governance_chain(
    substituted_policy,
    fixture.receipt.governance_stream_ref,
    fixture.proposal,
    evidence,
    "policy-substitution",
  )
  phase1b_expect_governance_replay_rejected(
    fixture,
    substituted_chain.store.replay(fixture.receipt.governance_stream_ref),
    "policy-substituted",
  )
}

///|
test "FLOW-7 Phase1B private codecs reject tamper trailing truncation and wrong refs" {
  let fixture = phase1b_fixture(suffix="codec")
  let proposal = decode_cancellation_proposal_v22_strict(
    fixture.proposal.record_ref(),
    fixture.proposal.canonical_bytes(),
  )
  assert_true(proposal.canonical_bytes() == fixture.proposal.canonical_bytes())
  let receipt = decode_committed_cancellation_governance_receipt_v22(
    fixture.receipt.record_ref(),
    fixture.receipt.canonical_bytes(),
    fixture.current,
  )
  assert_true(receipt.canonical_bytes() == fixture.receipt.canonical_bytes())
  let authorization = decode_cancellation_authorization_v22(
    fixture.authorization.record_ref(),
    fixture.authorization.canonical_bytes(),
    fixture.current,
  )
  assert_true(
    authorization.canonical_bytes() == fixture.authorization.canonical_bytes(),
  )
  let request = decode_cancellation_request_v22(
    fixture.request.record_ref(),
    fixture.request.canonical_bytes(),
    fixture.current,
  )
  assert_true(request.canonical_bytes() == fixture.request.canonical_bytes())
  let proposal_trailing = phase1b_append_byte(
    fixture.proposal.canonical_bytes(),
    b'X',
  )
  try
    decode_cancellation_proposal_v22_strict(
      fixture.proposal.record_ref(),
      proposal_trailing,
    )
  catch {
    MalformedInput(field="trailing_bytes") => ()
    _ => fail("unexpected proposal trailing-byte error")
  } noraise {
    _ => fail("accepted proposal trailing byte")
  }
  let proposal_bytes = fixture.proposal.canonical_bytes()
  try
    decode_cancellation_proposal_v22_strict(
      fixture.proposal.record_ref(),
      proposal_bytes[:proposal_bytes.length() - 1].to_owned(),
    )
  catch {
    MalformedInput(field~) if field.has_prefix("truncated") => ()
    MalformedInput(field="length_exceeds_record") => ()
    MalformedInput(field="unexpected_end") => ()
    MalformedInput(field="invalid_utf8") => ()
    _ => fail("unexpected proposal truncation error")
  } noraise {
    _ => fail("accepted truncated proposal")
  }
  let proposal_tamper = phase1a_replace_occurrence(
    fixture.proposal.canonical_bytes(),
    b"FLOW7/CANCELLATION-PROPOSAL-V2/2.2.0",
    0,
    b'X',
  )
  try
    decode_cancellation_proposal_v22_strict(
      fixture.proposal.record_ref(),
      proposal_tamper,
    )
  catch {
    MalformedInput(field="cancellation_proposal_tag") => ()
    _ => fail("unexpected proposal tag error")
  } noraise {
    _ => fail("accepted proposal tag tamper")
  }
  for
    item in [
      (
        fixture.receipt.record_ref(),
        phase1b_append_byte(fixture.receipt.canonical_bytes(), b'X'),
        "receipt",
      ),
      (
        fixture.authorization.record_ref(),
        phase1b_append_byte(fixture.authorization.canonical_bytes(), b'X'),
        "authorization",
      ),
      (
        fixture.request.record_ref(),
        phase1b_append_byte(fixture.request.canonical_bytes(), b'X'),
        "request",
      ),
    ] {
    let (expected_ref, bytes, label) = item
    try {
      if label == "receipt" {
        ignore(
          decode_committed_cancellation_governance_receipt_v22(
            expected_ref,
            bytes,
            fixture.current,
          ),
        )
      } else if label == "authorization" {
        ignore(
          decode_cancellation_authorization_v22(
            expected_ref,
            bytes,
            fixture.current,
          ),
        )
      } else {
        ignore(
          decode_cancellation_request_v22(expected_ref, bytes, fixture.current),
        )
      }
    } catch {
      MalformedInput(field="trailing_bytes") => ()
      _ => fail("unexpected \{label} trailing-byte error")
    } noraise {
      _ => fail("accepted \{label} trailing byte")
    }
  }
  guard fixture.current.governance.evidence_attachment_record()
    is Some(attachment) else {
    fail("missing committed evidence attachment")
  }
  let nested_tamper = phase1a_replace_occurrence(
    fixture.receipt.canonical_bytes(),
    attachment.canonical_bytes(),
    0,
    b'X',
  )
  let nested_tamper_ref = self_ref_v22(
    fixture.receipt.record_ref().kind(),
    fixture.receipt.record_ref().id(),
    @contracts.sha256_digest(nested_tamper),
  )
  try
    decode_committed_cancellation_governance_receipt_v22(
      nested_tamper_ref,
      nested_tamper,
      fixture.current,
    )
  catch {
    ReplayBindingViolation(field="cancellation_governance_receipt_self_address") =>
      ()
    _ => fail("unexpected nested-governance tamper error")
  } noraise {
    _ => fail("accepted nested governance bytes under recomputed outer ref")
  }
  let wrong_ref = phase1a_wb_ref(
    fixture.receipt.record_ref().kind(),
    "phase1b-wrong-receipt",
    b"wrong",
  )
  try
    decode_committed_cancellation_governance_receipt_v22(
      wrong_ref,
      fixture.receipt.canonical_bytes(),
      fixture.current,
    )
  catch {
    ReplayBindingViolation(field="cancellation_governance_receipt_self_address") =>
      ()
    _ => fail("unexpected receipt wrong-ref error")
  } noraise {
    _ => fail("accepted wrong receipt ref")
  }
}

///|
test "FLOW-7 Phase1B strict codecs reject every framing identity and nesting class" {
  let fixture = phase1b_fixture(suffix="codec-a")
  let other = phase1b_fixture(suffix="codec-b")
  let substituted_registration = ScheduleRegisteredV2::new(
    "phase1a-wb-registratioX",
    fixture.registration.schedule(),
  )
  let records = [
    (
      "proposal",
      fixture.proposal.record_ref(),
      fixture.proposal.canonical_bytes(),
      other.proposal.canonical_bytes(),
      b"FLOW7/CANCELLATION-PROPOSAL-V2/2.2.0",
      fixture.proposal.root_registration_bytes,
      substituted_registration.canonical_bytes(),
    ),
    (
      "receipt",
      fixture.receipt.record_ref(),
      fixture.receipt.canonical_bytes(),
      other.receipt.canonical_bytes(),
      b"FLOW7/COMMITTED-CANCELLATION-GOVERNANCE-RECEIPT-V2/2.2.0",
      fixture.proposal.canonical_bytes(),
      other.proposal.canonical_bytes(),
    ),
    (
      "authorization",
      fixture.authorization.record_ref(),
      fixture.authorization.canonical_bytes(),
      other.authorization.canonical_bytes(),
      b"FLOW7/CANCELLATION-AUTHORIZATION-V2/2.2.0",
      fixture.receipt.canonical_bytes(),
      other.receipt.canonical_bytes(),
    ),
    (
      "request",
      fixture.request.record_ref(),
      fixture.request.canonical_bytes(),
      other.request.canonical_bytes(),
      b"FLOW7/CANCELLATION-REQUEST-V2/2.2.0",
      fixture.authorization.canonical_bytes(),
      other.authorization.canonical_bytes(),
    ),
  ]
  for record in records {
    let (label, record_ref, bytes, other_bytes, tag, nested, other_nested) = record
    phase1b_expect_codec_rejected(
      label,
      record_ref,
      phase1a_replace_occurrence(bytes, tag, 0, b'X'),
      fixture.current,
      "invalid tag",
    )
    phase1b_expect_codec_rejected(
      label,
      record_ref,
      phase1a_replace_occurrence(bytes, b"2.2.0", 1, b'9'),
      fixture.current,
      "unsupported version",
    )
    let invalid_length = bytes.to_array()
    invalid_length[0] = 0x80
    phase1b_expect_codec_rejected(
      label,
      record_ref,
      Bytes::from_array(invalid_length),
      fixture.current,
      "length bound",
    )
    phase1b_expect_codec_rejected(
      label,
      record_ref,
      bytes[:bytes.length() - 1].to_owned(),
      fixture.current,
      "truncation",
    )
    phase1b_expect_codec_rejected(
      label,
      record_ref,
      phase1b_append_byte(bytes, b'X'),
      fixture.current,
      "trailing bytes",
    )
    let wrong_ref = @contracts.RecordRef::new(
      record_ref.kind(),
      record_ref.id(),
      record_ref.version().text(),
      @contracts.sha256_digest(other_bytes).text(),
    )
    phase1b_expect_codec_rejected(
      label,
      wrong_ref,
      bytes,
      fixture.current,
      "same-id digest collision",
    )
    phase1b_expect_codec_rejected(
      label,
      @contracts.RecordRef::new(
        "wrong-" + record_ref.kind(),
        record_ref.id(),
        record_ref.version().text(),
        record_ref.digest().text(),
      ),
      bytes,
      fixture.current,
      "wrong kind",
    )
    phase1b_expect_codec_rejected(
      label,
      @contracts.RecordRef::new(
        record_ref.kind(),
        "wrong-" + record_ref.id(),
        record_ref.version().text(),
        record_ref.digest().text(),
      ),
      bytes,
      fixture.current,
      "wrong id",
    )
    phase1b_expect_codec_rejected(
      label,
      @contracts.RecordRef::new(
        record_ref.kind(),
        record_ref.id(),
        "9.9.9",
        record_ref.digest().text(),
      ),
      bytes,
      fixture.current,
      "wrong version",
    )
    let substituted = phase1b_replace_bytes(bytes, nested, other_nested)
    let substituted_ref = @contracts.RecordRef::new(
      record_ref.kind(),
      record_ref.id(),
      record_ref.version().text(),
      @contracts.sha256_digest(substituted).text(),
    )
    phase1b_expect_codec_rejected(
      label,
      substituted_ref,
      substituted,
      fixture.current,
      "nested substitution",
    )
  }
}

///|
test "FLOW-7 Phase1B recomputed proposal bytes reject mismatched attempt and old intent lineage" {
  let fixture = phase1b_fixture(suffix="recomputed-source-lineage")
  let latest_attempt_ref = phase1a_wb_ref(
    fixture.proposal.root_attempt_ref.kind(),
    "phase1b-recomputed-latest-attempt",
    b"phase1b-recomputed-latest-attempt",
  )
  let old_intent_ref = fixture.proposal.root_intent_ref
  let recomputed = build_cancellation_proposal_v22(
    fixture.proposal.proposal_ref.id(),
    fixture.proposal.workflow,
    fixture.proposal.root_registration_ref,
    fixture.proposal.root_registration_bytes,
    fixture.proposal.root_schedule_ref,
    fixture.proposal.root_requested_work_ref,
    fixture.proposal.root_requested_work_digest,
    fixture.proposal.root_attempt_ref,
    fixture.proposal.root_attempt_digest,
    fixture.proposal.root_intent_ref,
    fixture.proposal.root_intent_digest,
    Some(latest_attempt_ref),
    Some(latest_attempt_ref.digest()),
    Some(old_intent_ref),
    Some(old_intent_ref.digest()),
    fixture.proposal.governed_subject,
    fixture.proposal.reason_ref,
    fixture.proposal.observed_at,
    [
      for value in fixture.proposal.evidence => value
    ],
    fixture.proposal.causation,
    fixture.proposal.prefix_event_ref,
    fixture.proposal.prefix_sequence,
    fixture.proposal.prefix_revision,
    fixture.proposal.prefix_replay_digest,
    fixture.proposal.event_idempotency_key,
    fixture.proposal.command_idempotency_key,
  )
  assert_true(recomputed.record_ref() != fixture.proposal.record_ref())
  assert_true(
    recomputed.prefix_event_ref() == fixture.proposal.prefix_event_ref(),
  )
  let decoded = decode_cancellation_proposal_v22_strict(
    recomputed.record_ref(),
    recomputed.canonical_bytes(),
  )
  assert_true(decoded.record_ref() == recomputed.record_ref())
  assert_true(decoded.source_attempt_ref() == Some(latest_attempt_ref))
  assert_true(decoded.source_intent_ref() == Some(old_intent_ref))
  try decoded.validate_current(fixture.current) catch {
    OrchestrationError::ReplayBindingViolation(
      field="cancellation_source_lineage"
    ) => ()
    _ => fail("unexpected recomputed proposal lineage error")
  } noraise {
    _ => fail("accepted recomputed proposal with mismatched source lineage")
  }
}

///|
test "FLOW-7 Phase1B stale governance and work heads invalidate receipt" {
  let fixture = phase1b_fixture(suffix="stale")
  let policy = phase1a_wb_policy()
  let evidence = [ for value in fixture.proposal.evidence() => value ]
  let alternate = phase1b_governance_chain(
    policy,
    fixture.receipt.governance_stream_ref,
    fixture.proposal,
    evidence,
    "stale-alternate",
  )
  let alternate_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    alternate.store.replay(fixture.receipt.governance_stream_ref),
  )
  try fixture.receipt.validate_current(alternate_current) catch {
    ReplayBindingViolation(field="cancellation_governance_receipt_not_current") =>
      ()
    _ => fail("unexpected stale governance receipt error")
  } noraise {
    _ => fail("accepted receipt at a different governance head")
  }
  try
    CancellationAuthorizationV2::from_committed_governance(
      "phase1b-stale-governance-authorization",
      fixture.receipt,
      fixture.proposal,
      alternate_current,
    )
  catch {
    ReplayBindingViolation(field="cancellation_governance_receipt_not_current") =>
      ()
    _ => fail("unexpected stale governance authorization error")
  } noraise {
    _ => fail("minted authorization from a stale governance receipt")
  }
  let registration = fixture.registration
  let schedule = registration.schedule()
  let claim = LeaseClaimV2::new(
    "phase1b-stale-claim",
    schedule,
    schedule.admission(),
    schedule.workflow(),
    phase1a_wb_ref("owner", "phase1b-owner", b"owner"),
    1L,
    0L,
    0L,
    1L,
    1L,
    "phase1b-stale-claim-key",
    [
      for value in schedule.evidence() => value
    ],
    fixture.proposal.record_ref(),
  )
  let claimed = LeaseClaimedV2::new(
    "phase1b-stale-claimed", registration, claim,
  )
  let work_projection = fold_root_bound_orchestration_v22(
    fixture.empty_effects,
    fixture.work_store.replay(registration.workflow()),
  )
  ignore(
    fixture.work_store.commit(
      prepare_lease_claimed_v2(
        work_projection, "phase1b-stale-claim-event", "phase1b-stale-claim-key",
        "phase1b-stale-claim-command", claimed,
      ),
    ),
  )
  let changed_work_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(registration.workflow()),
    fixture.governance.store.replay(fixture.receipt.governance_stream_ref),
  )
  try fixture.receipt.validate_current(changed_work_current) catch {
    ReplayBindingViolation(field="cancellation_governance_receipt_not_current") =>
      ()
    _ => fail("unexpected stale work receipt error")
  } noraise {
    _ => fail("accepted receipt after work-head change")
  }
  try
    CancellationAuthorizationV2::from_committed_governance(
      "phase1b-stale-work-authorization",
      fixture.receipt,
      fixture.proposal,
      changed_work_current,
    )
  catch {
    ReplayBindingViolation(field="cancellation_governance_receipt_not_current") =>
      ()
    _ => fail("unexpected stale work authorization error")
  } noraise {
    _ => fail("minted authorization after the work head changed")
  }
}

///|
test "FLOW-7 Phase1B missing and substituted governance replays mint no receipt" {
  let fixture = phase1b_fixture(suffix="negative")
  let missing_store = @storage.MemoryStore::new()
  ignore(
    missing_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        fixture.receipt.governance_stream_ref,
        0L,
        "phase1b-missing-governance-command",
        [
          for index = 0; index < 5; index = index + 1 => {
            fixture.governance.events[index]
          }
        ],
        [],
      ),
    ),
  )
  let incomplete = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    missing_store.replay(fixture.receipt.governance_stream_ref),
  )
  try
    incomplete.committed_cancellation_governance_receipt(fixture.proposal)
  catch {
    ReplayBindingViolation(field="cancellation_governance_event_membership") =>
      ()
    _ => fail("unexpected incomplete-governance error")
  } noraise {
    _ => fail("minted receipt from five governance events")
  }
  let wrong_stream = phase1a_wb_ref(
    "governance-stream", "phase1b-wrong-stream", b"wrong-stream",
  )
  try
    fold_governed_closed_loop_v2(
      fixture.empty_effects,
      fixture.work_store.replay(fixture.registration.workflow()),
      @storage.MemoryStore::new().replay(wrong_stream),
    )
  catch {
    ReplayBindingViolation(field="cancellation_governance_stream_binding") => ()
    _ => fail("unexpected governance stream substitution error")
  } noraise {
    _ => fail("accepted caller-selected governance stream")
  }
  let mutated = CancellationProposalV2::new(
    "phase1b-mutated-proposal",
    fold_initial_work_receipt_v22(
      fixture.empty_effects,
      fixture.work_store.replay(fixture.registration.workflow()),
    ),
    fold_closed_loop_v2(
      fixture.empty_effects,
      fixture.work_store.replay(fixture.registration.workflow()),
    ),
    fixture.proposal.governed_subject(),
    phase1a_wb_ref("reason", "phase1b-mutated-reason", b"mutated"),
    10L,
    [
      for value in fixture.proposal.evidence() => value
    ],
    phase1a_wb_ref("causation", "phase1b-mutated", b"mutated"),
    "phase1b-mutated-event-key",
    "phase1b-mutated-command-key",
  )
  try
    CancellationRequestV2::new(
      "phase1b-mutated-request",
      mutated,
      fixture.authorization,
    )
  catch {
    ReplayBindingViolation(field="cancellation_request_composite_binding") => ()
    _ => fail("unexpected mutated proposal/request error")
  } noraise {
    _ => fail("accepted authorization for mutated proposal")
  }
}

///|
test "FLOW-7 Phase1B derives root-inclusive and request-exclusive deadlines exactly" {
  let absent = phase1b_fixture(
    suffix="deadline-absent",
    expires_at=None,
    bound_at=15L,
  )
  assert_eq(absent.receipt.effective_valid_until_inclusive(), 20L)
  assert_eq(absent.receipt.deadline_exclusive(), 21L)
  let inclusive = phase1b_fixture(
    suffix="deadline-inclusive",
    expires_at=None,
    bound_at=20L,
  )
  assert_eq(inclusive.receipt.observed_at(), 20L)
  assert_eq(inclusive.receipt.effective_valid_until_inclusive(), 20L)
  assert_eq(inclusive.receipt.deadline_exclusive(), 21L)
  let request_limited = phase1b_fixture(
    suffix="deadline-request-limited",
    expires_at=Some(19L),
    bound_at=18L,
  )
  assert_eq(request_limited.receipt.observed_at(), 18L)
  assert_eq(request_limited.receipt.effective_valid_until_inclusive(), 18L)
  assert_eq(request_limited.receipt.deadline_exclusive(), 19L)
  let root_limited_with_request = phase1b_fixture(
    suffix="deadline-root-limited-present-request",
    expires_at=Some(30L),
    bound_at=20L,
  )
  assert_eq(root_limited_with_request.receipt.observed_at(), 20L)
  assert_eq(
    root_limited_with_request.receipt.effective_valid_until_inclusive(),
    20L,
  )
  assert_eq(root_limited_with_request.receipt.deadline_exclusive(), 21L)
  try
    ignore(
      cancellation_authorization_times_v22(
        10L,
        11L,
        12L,
        13L,
        14L,
        15L,
        20L,
        Some(15L),
      ),
    )
  catch {
    OrchestrationError::AuthorityExpired(expires_at=15L, observed_at=15L) => ()
    error => raise error
  } noraise {
    _ => fail("accepted a committed governance time at request expiry")
  }
}

///|
test "FLOW-7 Phase1B governance binding equality mints no receipt or authorization" {
  let fixture = phase1b_fixture(suffix="governance-binding-equality-source")
  let policy = phase1a_wb_policy()
  let evidence = [ for value in fixture.proposal.evidence() => value ]
  let equality = phase1b_governance_chain(
    policy,
    fixture.receipt.governance_stream_ref,
    fixture.proposal,
    evidence,
    "governance-binding-equality",
    expires_at=Some(15L),
    bound_at=15L,
    bind_receipt=false,
  )
  assert_eq(equality.events.length(), 5)
  assert_true(equality.pre_receipt_projection.receipt() is None)
  try
    ignore(
      @governance.ReviewReceipt::bind(
        equality.pre_receipt_projection,
        "phase1b-governance-binding-equality-receipt",
        "1.0.0",
        15L,
      ),
    )
  catch {
    @governance.GovernanceError::ReceiptBindingFailure(
      field="authority_expired_at_binding"
    ) => ()
    error => raise error
  } noraise {
    _ => fail("accepted governance receipt binding at request expiry")
  }
  let equality_replay = equality.store.replay(
    fixture.receipt.governance_stream_ref,
  )
  assert_eq(equality_replay.events().length(), 5)
  let current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    equality_replay,
  )
  let mut receipt_minted = false
  let mut authorization_minted = false
  try {
    let receipt = current.committed_cancellation_governance_receipt(
      fixture.proposal,
    )
    receipt_minted = true
    ignore(
      CancellationAuthorizationV2::from_committed_governance(
        "phase1b-governance-binding-equality-authorization",
        receipt,
        fixture.proposal,
        current,
      ),
    )
    authorization_minted = true
  } catch {
    OrchestrationError::ReplayBindingViolation(
      field="cancellation_governance_event_membership"
    ) => ()
    error => raise error
  }
  assert_true(!receipt_minted)
  assert_true(!authorization_minted)
}

///|
test "FLOW-7 Phase1B.2 safe cancellation is exact and invalidates open work" {
  let fixture = try phase1b_fixture(suffix="safe-commit") catch {
    error => fail("safe fixture: \{to_repr(error)}")
  } noraise {
    value => value
  }
  let open = fixture.current.open_work_authority()
  open.validate_current(fixture.current)
  let prepared = try
    prepare_cancellation_v2(fixture.current, fixture.request)
  catch {
    error => fail("safe prepare: \{to_repr(error)}")
  } noraise {
    value => value
  }
  assert_true(
    prepared.terminal_outcome() == Some(CancelledBeforeEffectIntentV2),
  )
  assert_eq(prepared.commit_request().events().length(), 2)
  assert_eq(prepared.commit_request().intents().length(), 0)
  assert_eq(
    prepared.commit_request().events()[0].payload().envelope_kind(),
    "work.cancellation.requested.v2",
  )
  assert_eq(
    prepared.commit_request().events()[1].payload().envelope_kind(),
    "work.terminal.v2",
  )
  assert_eq(
    @contracts.sha256_digest(
      prepared.commit_request().events()[1].payload().payload(),
    ).text(),
    "sha256:3b3f76f39d6ff6c79335ad56dff72476fcccda2d0a3774f327f665f67f8b99b7",
  )
  ignore(fixture.work_store.commit(prepared.commit_request())) catch {
    error => fail("safe commit: \{to_repr(error)}")
  }
  let replayed = try
    fold_governed_closed_loop_v2(
      fixture.empty_effects,
      fixture.work_store.replay(fixture.registration.workflow()),
      fixture.governance.store.replay(fixture.receipt.governance_stream_ref),
    )
  catch {
    error => fail("safe replay: \{to_repr(error)}")
  } noraise {
    value => value
  }
  try open.validate_current(replayed) catch {
    CancellationPrecedenceViolation(field="open_work_authority_not_current") =>
      ()
    error => fail("unexpected stale-open error: \{to_repr(error)}")
  } noraise {
    _ => fail("safe cancellation must invalidate open work")
  }
  try replayed.open_work_authority() catch {
    CancellationPrecedenceViolation(field="open_work_authority_not_current") =>
      ()
    error => fail("unexpected terminal-open error: \{to_repr(error)}")
  } noraise {
    _ => fail("terminal work must not mint open authority")
  }
  guard replayed.committed_work_terminal_receipt() is Some(terminal) else {
    fail("safe cancellation must mint a replay-only terminal receipt")
  }
  terminal.validate_current(replayed)
  assert_true(terminal.outcome() == CancelledBeforeEffectIntentV2)
  let revision_before_conflict = fixture.work_store
    .head(fixture.registration.workflow())
    .revision()
  let replay_before_conflict = fixture.work_store.replay(
    fixture.registration.workflow(),
  )
  let terminal_event = prepared.commit_request().events()[1]
  let terminal_payload = terminal_event.payload()
  let changed_terminal_payload = @contracts.WireEnvelope::new(
    terminal_payload.contract_id(),
    terminal_payload.contract_version().text(),
    terminal_payload.envelope_id(),
    terminal_payload.envelope_kind(),
    terminal_payload.subject(),
    terminal_payload.schema(),
    phase1b_append_byte(terminal_payload.payload(), 0),
    terminal_payload.producer_id(),
    terminal_payload.producer_version().text(),
    [
      for value in terminal_payload.artifacts() => value
    ],
    [
      for value in terminal_payload.evidence() => value
    ],
    run_ref?=terminal_payload.run_ref(),
    stage_ref?=terminal_payload.stage_ref(),
    attempt_ref?=terminal_payload.attempt_ref(),
    correlation_ref?=terminal_payload.correlation_ref(),
    causation_ref?=terminal_payload.causation_ref(),
    idempotency_ref?=terminal_payload.idempotency_ref(),
    previous_digest?=terminal_payload.previous_digest(),
    extensions=[ for value in terminal_payload.extensions() => value ],
  )
  let changed_terminal_event = @storage.WorkflowEvent::new(
    terminal_event.record_version().text(),
    terminal_event.schema_version().text(),
    terminal_event.workflow(),
    terminal_event.event_ref().id(),
    terminal_event.sequence(),
    terminal_event.revision(),
    terminal_event.idempotency_key(),
    changed_terminal_payload,
    [
      for value in terminal_event.evidence() => value
    ],
    previous_event_digest?=terminal_event.previous_event_digest(),
  )
  let changed_same_key = @storage.CommitRequest::new(
    prepared.commit_request().record_version().text(),
    prepared.commit_request().schema_version().text(),
    prepared.commit_request().workflow(),
    prepared.commit_request().expected_revision(),
    prepared.commit_request().command_idempotency_key(),
    [prepared.commit_request().events()[0], changed_terminal_event],
    [],
  )
  try fixture.work_store.commit(changed_same_key) catch {
    @storage.StorageError::IdempotencyConflict(key~) =>
      assert_eq(key, prepared.commit_request().command_idempotency_key())
    error =>
      fail("unexpected changed safe-cancellation conflict: \{to_repr(error)}")
  } noraise {
    _ => fail("same command key accepted changed safe-cancellation bytes")
  }
  assert_eq(
    fixture.work_store.head(fixture.registration.workflow()).revision(),
    revision_before_conflict,
  )
  let replay_after_conflict = fixture.work_store.replay(
    fixture.registration.workflow(),
  )
  assert_true(
    replay_after_conflict.replay_digest() ==
    replay_before_conflict.replay_digest(),
  )
  assert_eq(
    replay_after_conflict.events().length(),
    replay_before_conflict.events().length(),
  )
  let after_conflict = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    replay_after_conflict,
    fixture.governance.store.replay(fixture.receipt.governance_stream_ref),
  )
  guard after_conflict.committed_work_terminal_receipt() is Some(after_terminal) else {
    fail("safe cancellation terminal receipt changed after conflict")
  }
  assert_true(after_terminal.record_ref() == terminal.record_ref())
  after_terminal.validate_current(after_conflict)
}

///|
test "FLOW-7 Phase1B.2 target-bound open scope rejects substitution" {
  let fixture = phase1b_fixture(suffix="scope-substitution")
  let schedule = fixture.registration.schedule()
  let claim = LeaseClaimV2::new(
    "phase1b-scope-claim",
    schedule,
    schedule.admission(),
    schedule.workflow(),
    phase1a_wb_ref("owner", "phase1b-scope-owner", b"owner"),
    1L,
    0L,
    0L,
    1L,
    1L,
    "phase1b-scope-claim-key",
    [
      for value in schedule.evidence() => value
    ],
    fixture.proposal.record_ref(),
  )
  let claimed = LeaseClaimedV2::new(
    "phase1b-scope-claimed",
    fixture.registration,
    claim,
  )
  let open = fixture.current.open_work_authority()
  let wrong = fixture.current.authorize_open_work_operation(
    open,
    "effect.intent.commit",
    claimed.record_ref(),
  )
  try
    ignore(
      prepare_guarded_lease_claimed_v2(
        fixture.current,
        open,
        wrong,
        "phase1b-scope-event",
        "phase1b-scope-claim-key",
        "phase1b-scope-command",
        claimed,
      ),
    )
  catch {
    CancellationPrecedenceViolation(field="open_work_authority_scope") => ()
    error => fail("unexpected scope-substitution error: \{to_repr(error)}")
  } noraise {
    _ => fail("accepted an effect-intent scope for a lease claim")
  }
}

///|
test "FLOW-7 Phase1B.2 pending cancellation preserves in-flight facts and blocks new work" {
  let fixture = phase1b_pending_fixture("dispatch-race")
  let open = fixture.current.open_work_authority()
  let dispatch_authorization = fixture.current.guarded_dispatch_authorization(
    open,
    fixture.intent.intent_ref(),
  )
  let evidence = [ for value in fixture.intent.evidence() => value ]
  let observation = @effects.DispatchObservation::new(
    "phase1b-pending-observation",
    fixture.intent,
    phase1b_test_envelope(
      "phase1b-pending-observation-envelope",
      "dispatch-observation",
      fixture.intent.governance().governed_subject(),
      b"external-dispatch-observed",
      evidence,
    ),
    11L,
    evidence,
  )
  let calls = Ref(0)
  let port = Phase1bDispatchPort::{ observation, calls }
  let guarded_observation = phase1b_legacy_guarded_observation_fixture_v2(
    fixture.current,
    dispatch_authorization,
    observation,
  )
  assert_eq(calls.val, 0)
  let prepared = prepare_cancellation_v2(fixture.current, fixture.request)
  assert_true(prepared.terminal_outcome() is None)
  assert_eq(prepared.commit_request().events().length(), 1)
  assert_eq(prepared.commit_request().intents().length(), 0)
  let first = fixture.work_store.commit(prepared.commit_request())
  let duplicate = fixture.work_store.commit(prepared.commit_request())
  assert_eq(first.workflow_revision(), duplicate.workflow_revision())
  let original_event = prepared.commit_request().events()[0]
  let original_payload = original_event.payload()
  let changed_payload = @contracts.WireEnvelope::new(
    original_payload.contract_id(),
    original_payload.contract_version().text(),
    original_payload.envelope_id(),
    original_payload.envelope_kind(),
    original_payload.subject(),
    original_payload.schema(),
    phase1b_append_byte(original_payload.payload(), 0),
    original_payload.producer_id(),
    original_payload.producer_version().text(),
    [
      for value in original_payload.artifacts() => value
    ],
    [
      for value in original_payload.evidence() => value
    ],
    run_ref?=original_payload.run_ref(),
    stage_ref?=original_payload.stage_ref(),
    attempt_ref?=original_payload.attempt_ref(),
    correlation_ref?=original_payload.correlation_ref(),
    causation_ref?=original_payload.causation_ref(),
    idempotency_ref?=original_payload.idempotency_ref(),
    previous_digest?=original_payload.previous_digest(),
    extensions=[ for value in original_payload.extensions() => value ],
  )
  let changed_event = @storage.WorkflowEvent::new(
    original_event.record_version().text(),
    original_event.schema_version().text(),
    original_event.workflow(),
    original_event.event_ref().id(),
    original_event.sequence(),
    original_event.revision(),
    original_event.idempotency_key(),
    changed_payload,
    [
      for value in original_event.evidence() => value
    ],
    previous_event_digest?=original_event.previous_event_digest(),
  )
  let changed_same_key = @storage.CommitRequest::new(
    prepared.commit_request().record_version().text(),
    prepared.commit_request().schema_version().text(),
    prepared.commit_request().workflow(),
    prepared.commit_request().expected_revision(),
    prepared.commit_request().command_idempotency_key(),
    [changed_event],
    [],
  )
  let revision_before_conflict = fixture.work_store
    .head(fixture.registration.workflow())
    .revision()
  try fixture.work_store.commit(changed_same_key) catch {
    @storage.StorageError::IdempotencyConflict(key~) =>
      assert_eq(key, prepared.commit_request().command_idempotency_key())
    error => fail("unexpected changed cancellation conflict: \{to_repr(error)}")
  } noraise {
    _ => fail("same command key accepted changed cancellation bytes")
  }
  assert_eq(
    fixture.work_store.head(fixture.registration.workflow()).revision(),
    revision_before_conflict,
  )
  let current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    fixture.governance.store.replay(
      fixture.current.root_binding.governance_stream_ref(),
    ),
  )
  assert_true(current.committed_work_terminal_receipt() is None)
  try dispatch_guarded_effect_v2(port, current, dispatch_authorization) catch {
    RecoveryViolation(field="guarded_dispatch_v2_retired_phase2") => ()
    error => fail("unexpected stale dispatch error: \{to_repr(error)}")
  } noraise {
    _ => fail("stale pre-cancellation dispatch authorization reached port")
  }
  assert_eq(calls.val, 0)
  let fact = prepare_guarded_dispatch_observation_v2(
    current, guarded_observation, "phase1b-pending-observation-event", "phase1b-pending-observation-command",
  )
  assert_eq(fact.events().length(), 1)
  assert_eq(fact.intents().length(), 0)
  let inflight = current.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "dispatch.observe",
    observation.observation_ref(),
  )
  inflight.validate_current(current)
  try
    current.inflight_resolution_authority(
      fixture.intent.intent_ref(),
      "receipt.record",
      observation.observation_ref(),
    )
  catch {
    CancellationPrecedenceViolation(field="inflight_resolution_scope") => ()
    error => fail("unexpected wrong-state error: \{to_repr(error)}")
  } noraise {
    _ => fail("minted receipt authority while dispatch observation is absent")
  }
  try
    prepare_guarded_effect_fact_commit_v22(
      current,
      inflight,
      "dispatch.observe",
      phase1a_wb_ref("wrong", "phase1b-wrong-target", b"wrong"),
      "phase1b-wrong-target-event",
      "effect.dispatch.observed.v1",
      "phase1b-wrong-target-command",
      observation.canonical_bytes(),
      evidence,
    )
  catch {
    CancellationPrecedenceViolation(field="inflight_resolution_scope") => ()
    error => fail("unexpected wrong-target error: \{to_repr(error)}")
  } noraise {
    _ => fail("in-flight authority accepted a substituted target")
  }
  for
    scope in [
      "lease.claim", "lease.renew", "lease.reclaim", "retry.request", "retry.commit",
    ] {
    try
      current.authorize_open_work_operation(
        open,
        scope,
        phase1a_wb_ref(
          "target",
          "phase1b-blocked-" + scope,
          @utf8.encode(scope),
        ),
      )
    catch {
      CancellationPrecedenceViolation(field="open_work_authority_not_current") =>
        ()
      error => fail("unexpected blocked new-work error: \{to_repr(error)}")
    } noraise {
      _ => fail("cancellation allowed new-work scope " + scope)
    }
  }
  ignore(fixture.work_store.commit(fact))
  let governance_replay = fixture.governance.store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  let observed_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  assert_true(
    (try! observed_current.work.effects.strict_intent_state_v2(
      fixture.intent.intent_ref(),
    )).state() ==
    @effects.DispatchObservationPending,
  )
  assert_true(
    (try! observed_current.work.effects.committed_effect_terminal_source_v2(
      fixture.intent.intent_ref(),
    ))
    is None,
  )
  try inflight.validate_current(observed_current) catch {
    ReplayBindingViolation(field="inflight_resolution_authority_not_current") =>
      ()
    error => fail("unexpected stale observation authority: \{to_repr(error)}")
  } noraise {
    _ => fail("observation authority survived its committed fact")
  }
  try
    observed_current.inflight_resolution_authority(
      fixture.intent.intent_ref(),
      "dispatch.observe",
      observation.observation_ref(),
    )
  catch {
    CancellationPrecedenceViolation(field="inflight_resolution_scope") => ()
    error => fail("unexpected post-observation state denial: \{to_repr(error)}")
  } noraise {
    _ => fail("observation state allowed a second dispatch fact")
  }
  try
    dispatch_guarded_effect_v2(port, observed_current, dispatch_authorization)
  catch {
    RecoveryViolation(field="guarded_dispatch_v2_retired_phase2") => ()
    error =>
      fail("unexpected post-observation dispatch denial: \{to_repr(error)}")
  } noraise {
    _ => fail("post-observation head reached the dispatcher")
  }
  assert_eq(calls.val, 0)
  let failure_store = phase1b_clone_replay_to_memory(
    fixture.work_store.replay(fixture.registration.workflow()),
  )
  let failed_receipt = @effects.EffectReceipt::new(
    "phase1b-pending-failed-receipt",
    "1.0.0",
    fixture.intent,
    phase1b_test_envelope(
      "phase1b-pending-failed-receipt-envelope",
      "dispatcher-receipt",
      fixture.intent.governance().governed_subject(),
      b"terminal-failed",
      evidence,
    ),
    @effects.Failed,
    12L,
    evidence,
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  let failed_authority = observed_current.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "receipt.record",
    failed_receipt.receipt_ref(),
  )
  ignore(
    failure_store.commit(
      prepare_guarded_effect_receipt_v2(
        observed_current, failed_authority, "phase1b-pending-failed-receipt-event",
        "phase1b-pending-failed-receipt-command", failed_receipt,
      ),
    ),
  )
  let failure_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    failure_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard failure_current.work.effects.committed_effect_terminal_source_v2(
      fixture.intent.intent_ref(),
    )
    is Some(failure_source) else {
    fail("known failure terminal source missing")
  }
  let failed_terminal = prepare_failed_work_terminal_v2(
    failure_current, failure_source,
  )
  assert_true(failed_terminal.outcome() == FailedCancellationStoppedRetryV2)
  ignore(failure_store.commit(failed_terminal.commit_request()))
  let stopped_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    failure_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard stopped_current.committed_work_terminal_receipt()
    is Some(stopped_receipt) else {
    fail("cancellation-stopped failure terminal missing")
  }
  assert_true(stopped_receipt.outcome() == FailedCancellationStoppedRetryV2)
  let unknown_receipt = @effects.EffectReceipt::new(
    "phase1b-pending-unknown-receipt",
    "1.0.0",
    fixture.intent,
    phase1b_test_envelope(
      "phase1b-pending-unknown-receipt-envelope",
      "dispatcher-receipt",
      fixture.intent.governance().governed_subject(),
      b"unknown-outcome",
      evidence,
    ),
    @effects.Unknown,
    12L,
    evidence,
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  let receipt_authority = observed_current.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "receipt.record",
    unknown_receipt.receipt_ref(),
  )
  let substituted_receipt = @effects.EffectReceipt::new(
    "phase1b-pending-substituted-receipt",
    "1.0.0",
    fixture.intent,
    phase1b_test_envelope(
      "phase1b-pending-substituted-receipt-envelope",
      "dispatcher-receipt",
      fixture.intent.governance().governed_subject(),
      b"substituted-unknown-outcome",
      evidence,
    ),
    @effects.Unknown,
    12L,
    evidence,
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  try
    prepare_guarded_effect_receipt_v2(
      observed_current, receipt_authority, "phase1b-pending-wrong-receipt-event",
      "phase1b-pending-wrong-receipt-command", substituted_receipt,
    )
  catch {
    CancellationPrecedenceViolation(field="inflight_resolution_scope") => ()
    error => fail("unexpected receipt target denial: \{to_repr(error)}")
  } noraise {
    _ => fail("receipt authority accepted a substituted receipt")
  }
  let receipt_commit = prepare_guarded_effect_receipt_v2(
    observed_current, receipt_authority, "phase1b-pending-unknown-receipt-event",
    "phase1b-pending-unknown-receipt-command", unknown_receipt,
  )
  ignore(fixture.work_store.commit(receipt_commit))
  let unknown_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  assert_true(
    (try! unknown_current.work.effects.strict_intent_state_v2(
      fixture.intent.intent_ref(),
    )).state() ==
    @effects.UnknownOutcomeRequiresReconciliation,
  )
  assert_true(
    (try! unknown_current.work.effects.committed_effect_terminal_source_v2(
      fixture.intent.intent_ref(),
    ))
    is None,
  )
  try receipt_authority.validate_current(unknown_current) catch {
    ReplayBindingViolation(field="inflight_resolution_authority_not_current") =>
      ()
    error => fail("unexpected stale receipt authority: \{to_repr(error)}")
  } noraise {
    _ => fail("receipt authority survived its committed fact")
  }
  try
    unknown_current.inflight_resolution_authority(
      fixture.intent.intent_ref(),
      "receipt.record",
      unknown_receipt.receipt_ref(),
    )
  catch {
    CancellationPrecedenceViolation(field="inflight_resolution_scope") => ()
    error => fail("unexpected post-receipt state denial: \{to_repr(error)}")
  } noraise {
    _ => fail("unknown outcome allowed a second receipt")
  }
  try
    dispatch_guarded_effect_v2(port, unknown_current, dispatch_authorization)
  catch {
    RecoveryViolation(field="guarded_dispatch_v2_retired_phase2") => ()
    error => fail("unexpected post-receipt dispatch denial: \{to_repr(error)}")
  } noraise {
    _ => fail("post-receipt head reached the dispatcher")
  }
  assert_eq(calls.val, 0)
  let reconciliation_request = @effects.ReconciliationRequest::new(
    "phase1b-pending-reconciliation-request",
    fixture.intent,
    unknown_receipt,
    13L,
    evidence,
  )
  let reconciliation_request_authority = unknown_current.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "reconciliation.request",
    reconciliation_request.request_ref(),
  )
  let substituted_request = @effects.ReconciliationRequest::new(
    "phase1b-pending-substituted-reconciliation-request",
    fixture.intent,
    unknown_receipt,
    13L,
    evidence,
  )
  try
    prepare_guarded_reconciliation_request_v2(
      unknown_current, reconciliation_request_authority, "phase1b-pending-wrong-reconciliation-request-event",
      "phase1b-pending-wrong-reconciliation-request-command", substituted_request,
    )
  catch {
    CancellationPrecedenceViolation(field="inflight_resolution_scope") => ()
    error =>
      fail("unexpected reconciliation-request target denial: \{to_repr(error)}")
  } noraise {
    _ => fail("reconciliation-request authority accepted a substituted target")
  }
  ignore(
    fixture.work_store.commit(
      prepare_guarded_reconciliation_request_v2(
        unknown_current, reconciliation_request_authority, "phase1b-pending-reconciliation-request-event",
        "phase1b-pending-reconciliation-request-command", reconciliation_request,
      ),
    ),
  )
  let requested_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  assert_true(
    (try! requested_current.work.effects.strict_intent_state_v2(
      fixture.intent.intent_ref(),
    )).state() ==
    @effects.ReconciliationRequestedState,
  )
  assert_true(
    (try! requested_current.work.effects.committed_effect_terminal_source_v2(
      fixture.intent.intent_ref(),
    ))
    is None,
  )
  try
    reconciliation_request_authority.validate_current(requested_current)
  catch {
    ReplayBindingViolation(field="inflight_resolution_authority_not_current") =>
      ()
    error =>
      fail(
        "unexpected stale reconciliation-request authority: \{to_repr(error)}",
      )
  } noraise {
    _ => fail("reconciliation-request authority survived its committed fact")
  }
  try
    requested_current.inflight_resolution_authority(
      fixture.intent.intent_ref(),
      "reconciliation.request",
      reconciliation_request.request_ref(),
    )
  catch {
    CancellationPrecedenceViolation(field="inflight_resolution_scope") => ()
    error => fail("unexpected post-request state denial: \{to_repr(error)}")
  } noraise {
    _ => fail("pending reconciliation allowed a second request")
  }
  try
    dispatch_guarded_effect_v2(port, requested_current, dispatch_authorization)
  catch {
    RecoveryViolation(field="guarded_dispatch_v2_retired_phase2") => ()
    error => fail("unexpected post-request dispatch denial: \{to_repr(error)}")
  } noraise {
    _ => fail("post-request head reached the dispatcher")
  }
  assert_eq(calls.val, 0)
  let reconciled_success_store = phase1b_clone_replay_to_memory(
    fixture.work_store.replay(fixture.registration.workflow()),
  )
  let reconciled_success = @effects.ReconciliationRecord::new(
    "phase1b-pending-reconciled-success",
    fixture.intent,
    reconciliation_request,
    @effects.ReconciledSucceeded,
    phase1b_test_envelope(
      "phase1b-pending-reconciled-success-envelope",
      "reconciliation-observation",
      fixture.intent.governance().governed_subject(),
      b"succeeded",
      evidence,
    ),
    14L,
    evidence,
  )
  let reconciled_success_authority = requested_current.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "reconciliation.resolve",
    reconciled_success.reconciliation_ref(),
  )
  ignore(
    reconciled_success_store.commit(
      prepare_guarded_reconciliation_resolution_v2(
        requested_current, reconciled_success_authority, "phase1b-pending-reconciled-success-event",
        "phase1b-pending-reconciled-success-command", reconciled_success,
      ),
    ),
  )
  let reconciled_success_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    reconciled_success_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard reconciled_success_current.work.effects.committed_effect_terminal_source_v2(
      fixture.intent.intent_ref(),
    )
    is Some(reconciled_success_source) else {
    fail("reconciled success terminal source missing")
  }
  assert_true(
    reconciled_success_source.state() == @effects.ReconciledSuccessState,
  )
  let reconciled_success_terminal = prepare_succeeded_work_terminal_v2(
    reconciled_success_current, reconciled_success_source,
  )
  assert_true(reconciled_success_terminal.outcome() == SucceededV2)
  ignore(
    reconciled_success_store.commit(
      reconciled_success_terminal.commit_request(),
    ),
  )
  let reconciled_success_terminal_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    reconciled_success_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard reconciled_success_terminal_current.committed_work_terminal_receipt()
    is Some(reconciled_success_receipt) else {
    fail("reconciled success terminal missing")
  }
  assert_true(reconciled_success_receipt.outcome() == SucceededV2)
  let resolution = @effects.ReconciliationRecord::new(
    "phase1b-pending-reconciliation-resolution",
    fixture.intent,
    reconciliation_request,
    @effects.ReconciledNotApplied,
    phase1b_test_envelope(
      "phase1b-pending-reconciliation-resolution-envelope",
      "reconciliation-observation",
      fixture.intent.governance().governed_subject(),
      b"not-applied",
      evidence,
    ),
    14L,
    evidence,
  )
  let resolution_authority = requested_current.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "reconciliation.resolve",
    resolution.reconciliation_ref(),
  )
  let substituted_resolution = @effects.ReconciliationRecord::new(
    "phase1b-pending-substituted-reconciliation-resolution",
    fixture.intent,
    reconciliation_request,
    @effects.ReconciledNotApplied,
    phase1b_test_envelope(
      "phase1b-pending-substituted-reconciliation-resolution-envelope",
      "reconciliation-observation",
      fixture.intent.governance().governed_subject(),
      b"substituted-not-applied",
      evidence,
    ),
    14L,
    evidence,
  )
  try
    prepare_guarded_reconciliation_resolution_v2(
      requested_current, resolution_authority, "phase1b-pending-wrong-resolution-event",
      "phase1b-pending-wrong-resolution-command", substituted_resolution,
    )
  catch {
    CancellationPrecedenceViolation(field="inflight_resolution_scope") => ()
    error => fail("unexpected resolution target denial: \{to_repr(error)}")
  } noraise {
    _ => fail("resolution authority accepted a substituted target")
  }
  ignore(
    fixture.work_store.commit(
      prepare_guarded_reconciliation_resolution_v2(
        requested_current, resolution_authority, "phase1b-pending-reconciliation-resolution-event",
        "phase1b-pending-reconciliation-resolution-command", resolution,
      ),
    ),
  )
  let resolved_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  assert_true(
    (try! resolved_current.work.effects.strict_intent_state_v2(
      fixture.intent.intent_ref(),
    )).state() ==
    @effects.ReconciledNotAppliedRetryEligible,
  )
  assert_true(resolved_current.committed_work_terminal_receipt() is None)
  try resolution_authority.validate_current(resolved_current) catch {
    ReplayBindingViolation(field="inflight_resolution_authority_not_current") =>
      ()
    error => fail("unexpected stale resolution authority: \{to_repr(error)}")
  } noraise {
    _ => fail("resolution authority survived its committed fact")
  }
  for
    scope in [
      "dispatch.observe", "receipt.record", "reconciliation.request", "reconciliation.resolve",
    ] {
    try
      resolved_current.inflight_resolution_authority(
        fixture.intent.intent_ref(),
        scope,
        resolution.reconciliation_ref(),
      )
    catch {
      CancellationPrecedenceViolation(field="inflight_resolution_scope") => ()
      error => fail("unexpected resolved-state denial: \{to_repr(error)}")
    } noraise {
      _ => fail("resolved state minted in-flight scope " + scope)
    }
  }
  try
    dispatch_guarded_effect_v2(port, resolved_current, dispatch_authorization)
  catch {
    RecoveryViolation(field="guarded_dispatch_v2_retired_phase2") => ()
    error => fail("unexpected resolved dispatch denial: \{to_repr(error)}")
  } noraise {
    _ => fail("resolved head reached the dispatcher")
  }
  assert_eq(calls.val, 0)
  let restarted_store = phase1b_clone_replay_to_memory(
    fixture.work_store.replay(fixture.registration.workflow()),
  )
  let restarted_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    restarted_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  assert_true(
    restarted_store.replay(fixture.registration.workflow()).replay_digest() ==
    fixture.work_store.replay(fixture.registration.workflow()).replay_digest(),
  )
  assert_true(
    restarted_current.work.effects.state_digest() ==
    resolved_current.work.effects.state_digest(),
  )
  try
    restarted_current.inflight_resolution_authority(
      fixture.intent.intent_ref(),
      "reconciliation.resolve",
      resolution.reconciliation_ref(),
    )
  catch {
    CancellationPrecedenceViolation(field="inflight_resolution_scope") => ()
    error => fail("unexpected restart resolution denial: \{to_repr(error)}")
  } noraise {
    _ => fail("restart reminted completed resolution authority")
  }
  guard resolved_current.work.effects.committed_effect_terminal_source_v2(
      fixture.intent.intent_ref(),
    )
    is Some(source) else {
    fail("reconciled-not-applied terminal source missing")
  }
  source.validate_current(resolved_current.work.effects)
  assert_true(
    source.source_event_bytes() ==
    fixture.work_store
    .replay(fixture.registration.workflow())
    .events()
    .last()
    .unwrap()
    .canonical_bytes(),
  )
  let terminal_prepared = prepare_cancelled_after_reconciled_not_applied_work_terminal_v2(
    resolved_current, source,
  )
  assert_true(
    terminal_prepared.outcome() == CancelledAfterReconciledNotAppliedV2,
  )
  assert_eq(terminal_prepared.commit_request().events().length(), 1)
  assert_eq(terminal_prepared.commit_request().intents().length(), 0)
  let first_terminal = fixture.work_store.commit(
    terminal_prepared.commit_request(),
  )
  let duplicate_terminal = fixture.work_store.commit(
    terminal_prepared.commit_request(),
  )
  assert_eq(
    first_terminal.workflow_revision(),
    duplicate_terminal.workflow_revision(),
  )
  let terminal_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard terminal_current.committed_work_terminal_receipt()
    is Some(terminal_receipt) else {
    fail("reconciled-not-applied terminal receipt missing")
  }
  assert_true(
    terminal_receipt.outcome() == CancelledAfterReconciledNotAppliedV2,
  )
  terminal_receipt.validate_current(terminal_current)
  let restarted_terminal_store = phase1b_clone_replay_to_memory(
    fixture.work_store.replay(fixture.registration.workflow()),
  )
  let restarted_terminal = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    restarted_terminal_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard restarted_terminal.committed_work_terminal_receipt()
    is Some(restarted_receipt) else {
    fail("restart lost reconciled-not-applied terminal")
  }
  assert_true(restarted_receipt.record_ref() == terminal_receipt.record_ref())
}

///|
test "FLOW-7 Phase1B.3 success terminal is source-derived replayable and idempotent" {
  let fixture = phase1b_pending_fixture("success-terminal")
  let governance_replay = fixture.governance.store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  let evidence = [ for value in fixture.intent.evidence() => value ]
  let observation = @effects.DispatchObservation::new(
    "phase1b-success-observation",
    fixture.intent,
    phase1b_test_envelope(
      "phase1b-success-observation-envelope",
      "dispatch-observation",
      fixture.intent.governance().governed_subject(),
      b"success-dispatch-observed",
      evidence,
    ),
    11L,
    evidence,
  )
  let calls = Ref(0)
  let port = Phase1bDispatchPort::{ observation, calls }
  let open = fixture.current.open_work_authority()
  let dispatch_authorization = fixture.current.guarded_dispatch_authorization(
    open,
    fixture.intent.intent_ref(),
  )
  let guarded_observation = phase1b_legacy_guarded_observation_fixture_v2(
    fixture.current,
    dispatch_authorization,
    observation,
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_dispatch_observation_v2(
        fixture.current,
        guarded_observation,
        "phase1b-success-observation-event",
        "phase1b-success-observation-command",
      ),
    ),
  )
  let observed_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  let success_receipt = @effects.EffectReceipt::new(
    "phase1b-success-receipt",
    "1.0.0",
    fixture.intent,
    phase1b_test_envelope(
      "phase1b-success-receipt-envelope",
      "dispatcher-receipt",
      fixture.intent.governance().governed_subject(),
      b"succeeded",
      evidence,
    ),
    @effects.Succeeded,
    12L,
    evidence,
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  let receipt_authority = observed_current.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "receipt.record",
    success_receipt.receipt_ref(),
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_effect_receipt_v2(
        observed_current, receipt_authority, "phase1b-success-receipt-event", "phase1b-success-receipt-command",
        success_receipt,
      ),
    ),
  )
  let success_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard success_current.work.effects.committed_effect_terminal_source_v2(
      fixture.intent.intent_ref(),
    )
    is Some(source) else {
    fail("success terminal source missing")
  }
  source.validate_current(success_current.work.effects)
  assert_true(source.state() == @effects.KnownSuccess)
  let prepared = prepare_succeeded_work_terminal_v2(success_current, source)
  assert_true(prepared.outcome() == SucceededV2)
  assert_eq(prepared.commit_request().events().length(), 1)
  assert_eq(prepared.commit_request().intents().length(), 0)
  let first = fixture.work_store.commit(prepared.commit_request())
  let duplicate = fixture.work_store.commit(prepared.commit_request())
  assert_eq(first.workflow_revision(), duplicate.workflow_revision())
  let terminal_current = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard terminal_current.committed_work_terminal_receipt()
    is Some(terminal_receipt) else {
    fail("success terminal receipt missing")
  }
  assert_true(terminal_receipt.outcome() == SucceededV2)
  terminal_receipt.validate_current(terminal_current)
  let restarted_store = phase1b_clone_replay_to_memory(
    fixture.work_store.replay(fixture.registration.workflow()),
  )
  let restarted = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    restarted_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard restarted.committed_work_terminal_receipt() is Some(restarted_receipt) else {
    fail("restart lost success terminal")
  }
  assert_true(restarted_receipt.record_ref() == terminal_receipt.record_ref())
  let terminal_event = prepared.commit_request().events()[0]
  let late_event = prepare_phase1b_work_event_v22(
    fixture.registration.workflow(),
    terminal_current.work_sequence + 1L,
    terminal_current.work_revision + 1L,
    terminal_current.work_head_digest,
    "phase1b-late-second-terminal-event",
    work_terminal_event_kind_v22,
    terminal_event.payload().subject(),
    terminal_event.payload().payload(),
    fixture.intent.governance().governed_subject(),
    [
      for value in terminal_event.evidence() => value
    ],
    source.source_record_ref(),
    "phase1b-late-second-terminal-key",
  )
  ignore(
    fixture.work_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        fixture.registration.workflow(),
        terminal_current.work_revision,
        "phase1b-late-second-terminal-command",
        [late_event],
        [],
      ),
    ),
  )
  try
    fold_governed_closed_loop_v2(
      fixture.empty_effects,
      fixture.work_store.replay(fixture.registration.workflow()),
      governance_replay,
    )
  catch {
    CancellationPrecedenceViolation(field="late_event_after_work_terminal") =>
      ()
    error => fail("unexpected late terminal error: \{to_repr(error)}")
  } noraise {
    _ => fail("accepted a second event after success terminal")
  }
}

///|
test "FLOW-7 Phase1B.3 not-applied exhausts only without cancellation at exact bound" {
  let retry_policy = RetryPolicyV2::new(
    "flow7-retry-policy-attempt-one",
    "2.0.0",
    1L,
    0L,
    10L,
    1000L,
    2L,
    1L,
    31L,
    @contracts.sha256_digest(b"flow7-v2-retry-seed-attempt-one"),
    ["terminal_failed", "reconciled_not_applied"],
  )
  let fixture = phase1b_pending_fixture("not-applied-exhausted", retry_policy~)
  let governance_replay = fixture.governance.store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  let evidence = [ for value in fixture.intent.evidence() => value ]
  let observation = @effects.DispatchObservation::new(
    "phase1b-exhausted-observation",
    fixture.intent,
    phase1b_test_envelope(
      "phase1b-exhausted-observation-envelope",
      "dispatch-observation",
      fixture.intent.governance().governed_subject(),
      b"external-dispatch-observed",
      evidence,
    ),
    11L,
    evidence,
  )
  let calls = Ref(0)
  let port = Phase1bDispatchPort::{ observation, calls }
  let open = fixture.current.open_work_authority()
  let dispatch_authorization = fixture.current.guarded_dispatch_authorization(
    open,
    fixture.intent.intent_ref(),
  )
  let guarded_observation = phase1b_legacy_guarded_observation_fixture_v2(
    fixture.current,
    dispatch_authorization,
    observation,
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_dispatch_observation_v2(
        fixture.current,
        guarded_observation,
        "phase1b-exhausted-observation-event",
        "phase1b-exhausted-observation-command",
      ),
    ),
  )
  let observed = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  let unknown_receipt = @effects.EffectReceipt::new(
    "phase1b-exhausted-unknown-receipt",
    "1.0.0",
    fixture.intent,
    phase1b_test_envelope(
      "phase1b-exhausted-unknown-receipt-envelope",
      "dispatcher-receipt",
      fixture.intent.governance().governed_subject(),
      b"unknown-outcome",
      evidence,
    ),
    @effects.Unknown,
    12L,
    evidence,
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  let receipt_authority = observed.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "receipt.record",
    unknown_receipt.receipt_ref(),
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_effect_receipt_v2(
        observed, receipt_authority, "phase1b-exhausted-unknown-receipt-event", "phase1b-exhausted-unknown-receipt-command",
        unknown_receipt,
      ),
    ),
  )
  let unknown = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  let request = @effects.ReconciliationRequest::new(
    "phase1b-exhausted-reconciliation-request",
    fixture.intent,
    unknown_receipt,
    13L,
    evidence,
  )
  let request_authority = unknown.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "reconciliation.request",
    request.request_ref(),
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_reconciliation_request_v2(
        unknown, request_authority, "phase1b-exhausted-reconciliation-request-event",
        "phase1b-exhausted-reconciliation-request-command", request,
      ),
    ),
  )
  let requested = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  let resolution = @effects.ReconciliationRecord::new(
    "phase1b-exhausted-reconciliation-resolution",
    fixture.intent,
    request,
    @effects.ReconciledNotApplied,
    phase1b_test_envelope(
      "phase1b-exhausted-reconciliation-resolution-envelope",
      "reconciliation-observation",
      fixture.intent.governance().governed_subject(),
      b"not-applied",
      evidence,
    ),
    14L,
    evidence,
  )
  let resolution_authority = requested.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "reconciliation.resolve",
    resolution.reconciliation_ref(),
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_reconciliation_resolution_v2(
        requested, resolution_authority, "phase1b-exhausted-reconciliation-resolution-event",
        "phase1b-exhausted-reconciliation-resolution-command", resolution,
      ),
    ),
  )
  let resolved = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  assert_true(resolved.work.cancellation is None)
  guard resolved.work.effects.committed_retry_eligibility_receipt(
      fixture.intent.intent_ref(),
    )
    is Some(retry_receipt) else {
    fail("exact not-applied retry receipt missing")
  }
  retry_receipt.validate_current(resolved.work.effects)
  assert_eq(retry_receipt.cause_key(), "reconciled_not_applied")
  assert_eq(retry_receipt.attempt_count(), 1L)
  let prepared = try
    prepare_retry_exhausted_work_terminal_v2(resolved, retry_receipt)
  catch {
    error => fail("not-applied exhausted prepare: \{to_repr(error)}")
  } noraise {
    value => value
  }
  assert_true(prepared.outcome() == FailedRetryExhaustedV2)
  assert_eq(prepared.commit_request().events().length(), 1)
  assert_eq(prepared.commit_request().intents().length(), 0)
  ignore(fixture.work_store.commit(prepared.commit_request()))
  let terminal = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard terminal.committed_work_terminal_receipt() is Some(receipt) else {
    fail("not-applied exhaustion terminal receipt missing")
  }
  assert_true(receipt.outcome() == FailedRetryExhaustedV2)
  receipt.validate_current(terminal)
}

///|
test "FLOW-7 Phase1B.3 known failure exhaustion uses exact retry proof" {
  let retry_policy = RetryPolicyV2::new(
    "flow7-known-failure-exhausted-policy",
    "2.0.0",
    1L,
    0L,
    10L,
    1000L,
    2L,
    1L,
    31L,
    @contracts.sha256_digest(b"flow7-known-failure-exhausted-seed"),
    ["terminal_failed"],
  )
  let fixture = phase1b_pending_fixture(
    "known-failure-exhausted",
    retry_policy~,
  )
  let governance_replay = fixture.governance.store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  let evidence = [ for value in fixture.intent.evidence() => value ]
  let observation = @effects.DispatchObservation::new(
    "phase1b-known-failure-observation",
    fixture.intent,
    phase1b_test_envelope(
      "phase1b-known-failure-observation-envelope",
      "dispatch-observation",
      fixture.intent.governance().governed_subject(),
      b"external-dispatch-observed",
      evidence,
    ),
    11L,
    evidence,
  )
  let calls = Ref(0)
  let open = fixture.current.open_work_authority()
  let dispatch_authorization = fixture.current.guarded_dispatch_authorization(
    open,
    fixture.intent.intent_ref(),
  )
  let guarded = phase1b_legacy_guarded_observation_fixture_v2(
    fixture.current,
    dispatch_authorization,
    observation,
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_dispatch_observation_v2(
        fixture.current,
        guarded,
        "phase1b-known-failure-observation-event",
        "phase1b-known-failure-observation-command",
      ),
    ),
  )
  let observed = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  let failed_receipt = @effects.EffectReceipt::new(
    "phase1b-known-failure-receipt",
    "1.0.0",
    fixture.intent,
    phase1b_test_envelope(
      "phase1b-known-failure-receipt-envelope",
      "dispatcher-receipt",
      fixture.intent.governance().governed_subject(),
      b"terminal-failed",
      evidence,
    ),
    @effects.Failed,
    12L,
    evidence,
    observed_fencing=fixture.intent.fencing().unwrap(),
  )
  let receipt_authority = observed.inflight_resolution_authority(
    fixture.intent.intent_ref(),
    "receipt.record",
    failed_receipt.receipt_ref(),
  )
  ignore(
    fixture.work_store.commit(
      prepare_guarded_effect_receipt_v2(
        observed, receipt_authority, "phase1b-known-failure-receipt-event", "phase1b-known-failure-receipt-command",
        failed_receipt,
      ),
    ),
  )
  let failed = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard failed.work.effects.committed_retry_eligibility_receipt(
      fixture.intent.intent_ref(),
    )
    is Some(retry_receipt) else {
    fail("known-failure retry proof missing")
  }
  let prepared = prepare_retry_exhausted_work_terminal_v2(failed, retry_receipt)
  assert_true(prepared.outcome() == FailedRetryExhaustedV2)
  ignore(fixture.work_store.commit(prepared.commit_request()))
  let terminal = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    fixture.work_store.replay(fixture.registration.workflow()),
    governance_replay,
  )
  guard terminal.committed_work_terminal_receipt() is Some(receipt) else {
    fail("known-failure exhaustion terminal missing")
  }
  assert_true(receipt.outcome() == FailedRetryExhaustedV2)
  receipt.validate_current(terminal)
}

///|
test "FLOW-7 Phase1B.3 failure policy classification is exact and counter-bound" {
  let policy = phase1a_wb_retry_policy()
  let excluded = RetryPolicyV2::new(
    "phase1b-excluded-failure-policy",
    "2.0.0",
    5L,
    4L,
    1L,
    10L,
    1L,
    1L,
    0L,
    @contracts.sha256_digest(b"phase1b-excluded-failure-seed"),
    [],
  )
  assert_true(
    classify_failure_policy_v22(excluded, "terminal_failed", 5L, 4L, true) ==
    FailedNonRetryableV2,
  )
  assert_true(
    classify_failure_policy_v22(policy, "terminal_failed", 5L, 0L, false) ==
    FailedRetryExhaustedV2,
  )
  assert_true(
    classify_failure_policy_v22(policy, "terminal_failed", 1L, 4L, true) ==
    FailedRetryExhaustedV2,
  )
  assert_true(
    classify_failure_policy_v22(policy, "terminal_failed", 1L, 0L, true) ==
    FailedCancellationStoppedRetryV2,
  )
  try
    ignore(
      classify_failure_policy_v22(policy, "terminal_failed", 1L, 0L, false),
    )
  catch {
    CancellationPrecedenceViolation(field="work_terminal_retry_still_open") =>
      ()
    error => fail("unexpected under-bound failure error: \{to_repr(error)}")
  } noraise {
    _ => fail("under-bound retryable failure terminalized without cancellation")
  }
  for counts in [(6L, 0L), (1L, 5L)] {
    try
      ignore(
        classify_failure_policy_v22(
          policy,
          "terminal_failed",
          counts.0,
          counts.1,
          true,
        ),
      )
    catch {
      RetryBoundViolation(field="work_terminal_failure_counter") => ()
      error => fail("unexpected over-bound failure error: \{to_repr(error)}")
    } noraise {
      _ => fail("over-bound failure counters were accepted")
    }
  }
}

///|
test "FLOW-7 Phase1B.2 active lease cancellation allows exact release or expiry settlement" {
  let initial = phase1a_wb_initial()
  let policy = phase1a_wb_policy()
  let store = @storage.MemoryStore::new()
  ignore(
    store.commit(
      prepare_initial_work_v22(initial.authorization, initial.registration),
    ),
  )
  let empty_effects = @effects.EffectsProjection::new(
    initial.registration.workflow(),
    policy.policy_ref(),
  )
  let root_replay = store.replay(initial.registration.workflow())
  let root_work = fold_closed_loop_v2(empty_effects, root_replay)
  let schedule = initial.registration.schedule()
  let claim = LeaseClaimV2::new(
    "phase1b-active-lease-claim",
    schedule,
    schedule.admission(),
    schedule.workflow(),
    phase1a_wb_ref("owner", "phase1b-active-owner", b"owner"),
    10L,
    0L,
    0L,
    1L,
    1L,
    "phase1b-active-lease-claim-key",
    [
      for value in schedule.evidence() => value
    ],
    initial.registration.record_ref(),
  )
  let claimed = LeaseClaimedV2::new(
    "phase1b-active-lease-claimed",
    initial.registration,
    claim,
  )
  ignore(
    commit_orchestration_v2(
      store,
      prepare_lease_claimed_v2(
        root_work.orchestration,
        "phase1b-active-lease-event",
        claim.idempotency_key(),
        "phase1b-active-lease-command",
        claimed,
      ),
    ),
  )
  let replay = store.replay(schedule.workflow())
  let root = fold_initial_work_receipt_v22(empty_effects, replay)
  let work = fold_closed_loop_v2(empty_effects, replay)
  guard work.orchestration.committed_lease_authority_receipt()
    is Some(component_receipt) else {
    fail("active lease component receipt missing")
  }
  let evidence = [ for value in schedule.evidence() => value ]
  let proposal = CancellationProposalV2::new(
    "phase1b-active-lease-proposal",
    root,
    work,
    schedule.admission().governance().governed_subject(),
    phase1a_wb_ref("reason", "phase1b-active-lease-reason", b"reason"),
    10L,
    evidence,
    phase1a_wb_ref("causation", "phase1b-active-causation", b"cause"),
    "phase1b-active-proposal-event-key",
    "phase1b-active-proposal-command-key",
  )
  let governance = phase1b_governance_chain(
    policy,
    root.governance_stream_ref(),
    proposal,
    evidence,
    "active-lease",
  )
  let current = fold_governed_closed_loop_v2(
    empty_effects,
    replay,
    governance.store.replay(root.governance_stream_ref()),
  )
  guard current.committed_lease_authority_receipt_v2()
    is Some(aggregate_receipt) else {
    fail("aggregate lease receipt missing before cancellation")
  }
  aggregate_receipt.validate_governed_current_v2(current, 10L)
  let governance_receipt = current.committed_cancellation_governance_receipt(
    proposal,
  )
  let authorization = CancellationAuthorizationV2::from_committed_governance(
    "phase1b-active-authorization", governance_receipt, proposal, current,
  )
  let request = CancellationRequestV2::new(
    "phase1b-active-request", proposal, authorization,
  )
  let prepared = prepare_cancellation_v2(current, request)
  assert_true(prepared.terminal_outcome() is None)
  assert_eq(prepared.commit_request().events().length(), 1)
  assert_eq(prepared.commit_request().intents().length(), 0)
  assert_eq(
    prepared.commit_request().events()[0].payload().envelope_kind(),
    "work.cancellation.requested.v2",
  )
  ignore(store.commit(prepared.commit_request()))
  let cancelled = try
    fold_governed_closed_loop_v2(
      empty_effects,
      store.replay(schedule.workflow()),
      governance.store.replay(root.governance_stream_ref()),
    )
  catch {
    error => fail("active cancellation replay: \{to_repr(error)}")
  } noraise {
    value => value
  }
  assert_true(cancelled.committed_lease_authority_receipt_v2() is None)
  assert_true(cancelled.committed_work_terminal_receipt() is None)
  assert_true(
    cancelled.work.orchestration.committed_lease_authority_receipt() is Some(_),
  )
  try component_receipt.validate_governed_current_v2(cancelled, 10L) catch {
    CancellationPrecedenceViolation(
      field="lease_authority_v2_not_governed_current"
    ) => ()
    error => fail("unexpected stale lease receipt error: \{to_repr(error)}")
  } noraise {
    _ => fail("historical lease receipt remained aggregate-current")
  }
  guard cancelled.work.orchestration.committed_lease_authority_receipt()
    is Some(settlement_receipt) else {
    fail("cancellation-head component receipt missing")
  }
  assert_true(
    settlement_receipt.receipt_ref() != component_receipt.receipt_ref(),
  )
  let lifecycle_request = LeaseLifecycleRequestV2::for_active(
    "phase1b-active-release-request",
    ReleaseLeaseV2,
    initial.registration,
    settlement_receipt,
    None,
    "phase1b-active-release-key",
    phase1a_wb_ref(
      "causation", "phase1b-active-release-causation", b"release-causation",
    ),
  )
  guard cancelled.work.prefix_event() is Some(cancellation_head) else {
    fail("cancellation head missing for lease settlement")
  }
  let lifecycle_admission = flow7_lifecycle_operation_admission(
    "phase1b-active-release",
    lifecycle_request,
    cancellation_head.event_ref(),
    cancelled.work.orchestration.sequence(),
    cancelled.work.orchestration.revision(),
    10L,
  )
  let release_lifecycle_authorization = LeaseLifecycleAuthorizationV2::for_active(
    lifecycle_request,
    lifecycle_admission,
    cancelled.work.orchestration,
    settlement_receipt,
  )
  let release = LeaseReleaseV2::new(
    "phase1b-active-release",
    initial.registration,
    settlement_receipt,
    release_lifecycle_authorization,
  )
  let substituted_release = LeaseReleaseV2::new(
    "phase1b-active-release-substituted",
    initial.registration,
    settlement_receipt,
    release_lifecycle_authorization,
  )
  let expiry_request = LeaseLifecycleRequestV2::for_active(
    "phase1b-active-expiry-request",
    ExpireLeaseV2,
    initial.registration,
    settlement_receipt,
    None,
    "phase1b-active-expiry-key",
    phase1a_wb_ref(
      "causation", "phase1b-active-expiry-causation", b"expiry-causation",
    ),
  )
  let expiry_admission = flow7_lifecycle_operation_admission(
    "phase1b-active-expiry",
    expiry_request,
    cancellation_head.event_ref(),
    cancelled.work.orchestration.sequence(),
    cancelled.work.orchestration.revision(),
    settlement_receipt.expires_at(),
  )
  let expiry_lifecycle_authorization = LeaseLifecycleAuthorizationV2::for_active(
    expiry_request,
    expiry_admission,
    cancelled.work.orchestration,
    settlement_receipt,
  )
  let expiry = LeaseExpiryV2::new(
    "phase1b-active-expiry",
    initial.registration,
    settlement_receipt,
    expiry_lifecycle_authorization,
  )
  let expiry_settlement = cancelled.authorize_lease_settlement_v2(
    "lease.expire",
    expiry.record_ref(),
  )
  let expiry_commit = prepare_guarded_lease_expired_v2(
    cancelled,
    expiry_settlement,
    "phase1b-active-expiry-event",
    expiry.idempotency_key(),
    "phase1b-active-expiry-command",
    expiry,
  )
  assert_eq(expiry_commit.events().length(), 1)
  assert_eq(expiry_commit.intents().length(), 0)
  let expiry_store = phase1b_clone_replay_to_memory(
    store.replay(schedule.workflow()),
  )
  ignore(expiry_store.commit(expiry_commit))
  let expired = fold_governed_closed_loop_v2(
    empty_effects,
    expiry_store.replay(schedule.workflow()),
    governance.store.replay(root.governance_stream_ref()),
  )
  assert_true(expired.committed_work_terminal_receipt() is None)
  assert_true(expired.committed_lease_authority_receipt_v2() is None)
  assert_true(expired.work.orchestration.has_terminal_lease())
  assert_eq(
    expired.work.orchestration.epoch_floor(),
    cancelled.work.orchestration.epoch_floor(),
  )
  assert_eq(
    expired.work.orchestration.fencing_floor(),
    cancelled.work.orchestration.fencing_floor(),
  )
  try expired.open_work_authority() catch {
    CancellationPrecedenceViolation(field="open_work_authority_not_current") =>
      ()
    error => fail("unexpected expired open-work error: \{to_repr(error)}")
  } noraise {
    _ => fail("expiry settlement reopened cancelled work")
  }
  let settlement = cancelled.authorize_lease_settlement_v2(
    "lease.release",
    release.record_ref(),
  )
  try
    prepare_guarded_lease_released_v2(
      cancelled,
      settlement,
      "phase1b-active-substituted-release-event",
      substituted_release.idempotency_key(),
      "phase1b-active-substituted-release-command",
      substituted_release,
    )
  catch {
    CancellationPrecedenceViolation(
      field="lease_settlement_authority_not_current"
    ) => ()
    error => fail("unexpected settlement target error: \{to_repr(error)}")
  } noraise {
    _ => fail("settlement authority accepted a substituted release target")
  }
  let settlement_request = try
    prepare_guarded_lease_released_v2(
      cancelled,
      settlement,
      "phase1b-active-release-event",
      release.idempotency_key(),
      "phase1b-active-release-command",
      release,
    )
  catch {
    error => fail("active release settlement prepare: \{to_repr(error)}")
  } noraise {
    value => value
  }
  assert_eq(settlement_request.events().length(), 1)
  assert_eq(settlement_request.intents().length(), 0)
  ignore(store.commit(settlement_request))
  let settled = try
    fold_governed_closed_loop_v2(
      empty_effects,
      store.replay(schedule.workflow()),
      governance.store.replay(root.governance_stream_ref()),
    )
  catch {
    error => fail("active release settlement replay: \{to_repr(error)}")
  } noraise {
    value => value
  }
  assert_true(settled.committed_lease_authority_receipt_v2() is None)
  assert_true(
    settled.work.orchestration.committed_lease_authority_receipt() is None,
  )
  assert_true(settled.work.orchestration.has_terminal_lease())
  assert_eq(
    settled.work.orchestration.epoch_floor(),
    cancelled.work.orchestration.epoch_floor(),
  )
  assert_eq(
    settled.work.orchestration.fencing_floor(),
    cancelled.work.orchestration.fencing_floor(),
  )
  try
    prepare_guarded_lease_released_v2(
      settled,
      settlement,
      "phase1b-active-stale-release-event",
      release.idempotency_key(),
      "phase1b-active-stale-release-command",
      release,
    )
  catch {
    ScheduleStateViolation(field="lease_settlement_no_active") => ()
    error => fail("unexpected stale settlement error: \{to_repr(error)}")
  } noraise {
    _ => fail("stale settlement authority was reusable after release")
  }
}

///|
test "FLOW-7 Phase1B.2 terminal source prefix and batch tamper are rejected" {
  let fixture = phase1b_fixture(suffix="terminal-tamper")
  let prepared = prepare_cancellation_v2(fixture.current, fixture.request)
  let request_event = prepared.commit_request().events()[0]
  let terminal_event = prepared.commit_request().events()[1]
  let terminal_ref = terminal_event.payload().subject()
  let terminal_bytes = terminal_event.payload().payload()
  ignore(decode_work_terminal_record_v22(terminal_ref, terminal_bytes))
  let (cancellation_option_offset, retry_option_offset) = phase1b_terminal_option_offsets(
    terminal_bytes,
  )
  let cancellation_option_tamper = phase1b_replace_int64_marker(
    terminal_bytes, cancellation_option_offset, 2,
  )
  try
    decode_work_terminal_record_v22(
      phase1b_readdress(terminal_ref, cancellation_option_tamper),
      cancellation_option_tamper,
    )
  catch {
    MalformedInput(field="work_terminal_v22_cancellation_option") => ()
    error => fail("unexpected cancellation option error: \{to_repr(error)}")
  } noraise {
    _ => fail("accepted invalid cancellation option marker")
  }
  let retry_option_tamper = phase1b_replace_int64_marker(
    terminal_bytes, retry_option_offset, 2,
  )
  try
    decode_work_terminal_record_v22(
      phase1b_readdress(terminal_ref, retry_option_tamper),
      retry_option_tamper,
    )
  catch {
    MalformedInput(field="work_terminal_v22_retry_policy_option") => ()
    error => fail("unexpected retry option error: \{to_repr(error)}")
  } noraise {
    _ => fail("accepted invalid retry-policy option marker")
  }
  let terminal_id_tamper = phase1a_replace_occurrence(
    terminal_bytes, b"safe-terminal", 0, b'f',
  )
  let forged_terminal_ref = @contracts.RecordRef::new(
    terminal_ref.kind(),
    "\{fixture.request.request_ref.id()}:fafe-terminal",
    terminal_ref.version().text(),
    @contracts.sha256_digest(terminal_id_tamper).text(),
  )
  try
    decode_work_terminal_record_v22(forged_terminal_ref, terminal_id_tamper)
  catch {
    ReplayBindingViolation(field="work_record_byte_binding") => ()
    error => fail("unexpected terminal id error: \{to_repr(error)}")
  } noraise {
    _ => fail("accepted self-consistent noncanonical terminal id")
  }
  let event_key_tamper = phase1a_replace_occurrence(
    terminal_bytes,
    @utf8.encode(fixture.proposal.event_idempotency_key + ":safe-terminal"),
    0,
    b'X',
  )
  try
    decode_work_terminal_record_v22(
      phase1b_readdress(terminal_ref, event_key_tamper),
      event_key_tamper,
    )
  catch {
    ReplayBindingViolation(field="work_record_byte_binding") => ()
    error => fail("unexpected terminal event-key error: \{to_repr(error)}")
  } noraise {
    _ => fail("accepted self-consistent noncanonical terminal event key")
  }
  let tag_tamper = phase1a_replace_occurrence(
    terminal_bytes, b"FLOW7/WORK-TERMINAL-V2/2.2.0", 0, b'X',
  )
  try
    decode_work_terminal_record_v22(
      phase1b_readdress(terminal_ref, tag_tamper),
      tag_tamper,
    )
  catch {
    MalformedInput(field="work_terminal_v22_tag") => ()
    error => fail("unexpected terminal tag error: \{to_repr(error)}")
  } noraise {
    _ => fail("accepted re-addressed terminal tag tamper")
  }
  let source_tamper = phase1a_replace_occurrence(
    terminal_bytes,
    @utf8.encode(fixture.request.request_ref.id()),
    1,
    b'X',
  )
  try
    decode_work_terminal_record_v22(
      phase1b_readdress(terminal_ref, source_tamper),
      source_tamper,
    )
  catch {
    ReplayBindingViolation(field="work_record_byte_binding") => ()
    error => fail("unexpected terminal source error: \{to_repr(error)}")
  } noraise {
    _ => fail("accepted re-addressed terminal source tamper")
  }
  let prefix_text = fixture.proposal.prefix_event_ref.digest().text()
  let prefix_needle = @utf8.encode(prefix_text)
  let replacement = if prefix_needle[0] == b'0' { b'1' } else { b'0' }
  let prefix_tamper = phase1a_replace_occurrence(
    terminal_bytes, prefix_needle, 0, replacement,
  )
  try
    decode_work_terminal_record_v22(
      phase1b_readdress(terminal_ref, prefix_tamper),
      prefix_tamper,
    )
  catch {
    ReplayBindingViolation(field="work_record_byte_binding") => ()
    error => fail("unexpected terminal prefix error: \{to_repr(error)}")
  } noraise {
    _ => fail("accepted re-addressed terminal prefix tamper")
  }
  let source_event_bytes_tamper = phase1a_replace_occurrence(
    terminal_bytes,
    request_event.canonical_bytes(),
    0,
    b'X',
  )
  let source_event_tamper_ref = phase1b_readdress(
    terminal_ref, source_event_bytes_tamper,
  )
  ignore(
    decode_work_terminal_record_v22(
      source_event_tamper_ref, source_event_bytes_tamper,
    ),
  )
  let source_event_tamper_event = prepare_phase1b_work_event_v22(
    fixture.registration.workflow(),
    terminal_event.sequence(),
    terminal_event.revision(),
    request_event.event_ref().digest(),
    source_event_tamper_ref.id(),
    work_terminal_event_kind_v22,
    source_event_tamper_ref,
    source_event_bytes_tamper,
    fixture.proposal.governed_subject,
    [
      for value in terminal_event.evidence() => value
    ],
    fixture.request.request_ref,
    terminal_event.idempotency_key(),
  )
  let source_event_tamper_store = @storage.MemoryStore::new()
  ignore(
    source_event_tamper_store.commit(
      prepare_initial_work_v22(
        phase1a_wb_initial().authorization,
        fixture.registration,
      ),
    ),
  )
  ignore(
    source_event_tamper_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        fixture.registration.workflow(),
        source_event_tamper_store
        .head(fixture.registration.workflow())
        .revision(),
        prepared.commit_request().command_idempotency_key(),
        [request_event, source_event_tamper_event],
        [],
      ),
    ),
  )
  try
    fold_governed_closed_loop_v2(
      fixture.empty_effects,
      source_event_tamper_store.replay(fixture.registration.workflow()),
      fixture.governance.store.replay(fixture.receipt.governance_stream_ref),
    )
  catch {
    ReplayBindingViolation(field="work_terminal_source") => ()
    error => fail("unexpected source-event-bytes tamper: \{to_repr(error)}")
  } noraise {
    _ => fail("accepted re-addressed terminal source-event bytes tamper")
  }
  let split = @storage.MemoryStore::new()
  let root_request = prepare_initial_work_v22(
    phase1a_wb_initial().authorization,
    fixture.registration,
  )
  ignore(split.commit(root_request))
  ignore(
    split.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        fixture.registration.workflow(),
        split.head(fixture.registration.workflow()).revision(),
        "phase1b-split-request-command",
        [request_event],
        [],
      ),
    ),
  )
  ignore(
    split.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        fixture.registration.workflow(),
        split.head(fixture.registration.workflow()).revision(),
        "phase1b-split-terminal-command",
        [terminal_event],
        [],
      ),
    ),
  )
  try
    fold_governed_closed_loop_v2(
      fixture.empty_effects,
      split.replay(fixture.registration.workflow()),
      fixture.governance.store.replay(fixture.receipt.governance_stream_ref),
    )
  catch {
    ReplayBindingViolation(field="work_batch_boundary_shape") => ()
    error => fail("unexpected split batch error: \{to_repr(error)}")
  } noraise {
    _ => fail("accepted cancellation request and terminal split across batches")
  }
}

///|
test "FLOW-7 Phase1B.2 readdressed governance chain cannot mint cancellation authority" {
  let fixture = phase1b_fixture(suffix="forged-governance")
  let original = [ for event in fixture.governance.events => event ]
  let forged = phase1b_rechained_governance_replay(
    fixture.receipt.governance_stream_ref,
    original,
    "forged-governance",
  )
  phase1b_expect_governance_replay_rejected(
    fixture, forged, "readdressed governance",
  )
}

///|
test "FLOW-7 Phase1B.2 persisted self-addressed forged chain remains untrusted" {
  let fixture = phase1b_pending_fixture("forged-persisted-chain")
  let proposal = fixture.request.proposal
  let authorization = fixture.request.authorization
  let receipt = authorization.governance_receipt
  let forged_receipt_bytes = phase1b_append_byte(receipt.canonical_bytes(), 0)
  let forged_receipt_ref = phase1b_readdress(
    receipt.record_ref(),
    forged_receipt_bytes,
  )
  let authorization_writer = OrchestrationWriter::new()
  authorization_writer.bytes(b"FLOW7/CANCELLATION-AUTHORIZATION-V2/2.2.0")
  authorization_writer.string(orchestration_record_version_v22)
  authorization_writer.string(authorization.record_ref().id())
  write_phase1b_record_v22(
    authorization_writer,
    proposal.record_ref(),
    proposal.canonical_bytes(),
  )
  write_phase1b_record_v22(
    authorization_writer, forged_receipt_ref, forged_receipt_bytes,
  )
  write_ref(authorization_writer, proposal.workflow)
  write_ref(authorization_writer, proposal.governed_subject)
  write_ref(authorization_writer, receipt.governance_stream_ref)
  authorization_writer.int64(receipt.work_sequence)
  authorization_writer.int64(receipt.work_revision)
  authorization_writer.string(receipt.work_head_digest.text())
  authorization_writer.string(receipt.work_replay_digest.text())
  authorization_writer.int64(receipt.governance_sequence)
  authorization_writer.int64(receipt.governance_revision)
  authorization_writer.string(receipt.governance_head_digest.text())
  authorization_writer.string(receipt.governance_replay_digest.text())
  authorization_writer.int64(receipt.observed_at)
  authorization_writer.int64(receipt.effective_valid_until_inclusive)
  authorization_writer.int64(receipt.deadline_exclusive)
  let forged_authorization_bytes = authorization_writer.finish()
  let forged_authorization_ref = phase1b_readdress(
    authorization.record_ref(),
    forged_authorization_bytes,
  )
  let request_writer = OrchestrationWriter::new()
  request_writer.bytes(b"FLOW7/CANCELLATION-REQUEST-V2/2.2.0")
  request_writer.string(orchestration_record_version_v22)
  request_writer.string(fixture.request.record_ref().id())
  write_phase1b_record_v22(
    request_writer,
    proposal.record_ref(),
    proposal.canonical_bytes(),
  )
  write_phase1b_record_v22(
    request_writer, forged_authorization_ref, forged_authorization_bytes,
  )
  let forged_request_bytes = request_writer.finish()
  let forged_request_ref = phase1b_readdress(
    fixture.request.record_ref(),
    forged_request_bytes,
  )
  let forged_event = prepare_phase1b_work_event_v22(
    proposal.workflow,
    fixture.current.work_sequence + 1L,
    fixture.current.work_revision + 1L,
    fixture.current.work_head_digest,
    forged_request_ref.id(),
    "work.cancellation.requested.v2",
    forged_request_ref,
    forged_request_bytes,
    proposal.governed_subject,
    [
      for value in proposal.evidence => value
    ],
    proposal.causation,
    proposal.event_idempotency_key,
  )
  let forged_store = phase1b_clone_replay_to_memory(
    fixture.work_store.replay(fixture.registration.workflow()),
  )
  ignore(
    forged_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        fixture.registration.workflow(),
        fixture.current.work_revision,
        proposal.command_idempotency_key,
        [forged_event],
        [],
      ),
    ),
  )
  let forged_replay = forged_store.replay(fixture.registration.workflow())
  let untrusted = fold_closed_loop_v2(fixture.empty_effects, forged_replay) catch {
    ReplayBindingViolation(field~) => fail("forged generic fold: " + field)
    error => fail("forged generic fold other: \{to_repr(error)}")
  }
  guard untrusted.cancellation is Some(candidate) else {
    fail("generic replay did not retain the forged cancellation candidate")
  }
  assert_true(candidate.request_ref == forged_request_ref)
  assert_true(candidate.authorization_ref == forged_authorization_ref)
  assert_true(candidate.authorization_bytes == forged_authorization_bytes)
  assert_true(untrusted.work_terminal is None)
  let mut governed_returned = false
  let mut open_minted = false
  let mut inflight_minted = false
  let mut terminal_minted = false
  try {
    let governed = fold_governed_closed_loop_v2(
      fixture.empty_effects,
      forged_replay,
      fixture.governance.store.replay(receipt.governance_stream_ref),
    )
    governed_returned = true
    terminal_minted = governed.committed_work_terminal_receipt() is Some(_)
    try {
      ignore(governed.open_work_authority())
      open_minted = true
    } catch {
      _ => ()
    }
    try {
      ignore(
        governed.inflight_resolution_authority(
          proposal.root_intent_ref,
          "dispatch.observe",
          forged_request_ref,
        ),
      )
      inflight_minted = true
    } catch {
      _ => ()
    }
  } catch {
    _ => ()
  }
  assert_true(!governed_returned)
  assert_true(!open_minted)
  assert_true(!inflight_minted)
  assert_true(!terminal_minted)
}
