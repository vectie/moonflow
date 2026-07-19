///|
fn phase1b_lineage_proposal_from_replay(
  ready : Flow7RetryReadyFixture,
  replay : @storage.ReplayResult,
  suffix : String,
) -> CancellationProposalV2 raise {
  let aggregate = fold_closed_loop_v2(ready.empty_effects, replay) catch {
    OrchestrationError::ReplayBindingViolation(field~) =>
      fail("lineage aggregate: " + field)
    _ => fail("lineage aggregate")
  }
  let root = fold_initial_work_receipt_v22(ready.empty_effects, replay) catch {
    OrchestrationError::ReplayBindingViolation(field~) =>
      fail("lineage root: " + field)
    _ => fail("lineage root")
  }
  let registration = ScheduleRegisteredV2::decode(
    replay.events()[0].payload().subject().id(),
    replay.events()[0].payload().payload(),
  )
  let subject = registration.schedule().admission().planned().subject()
  if subject !=
    registration.schedule().admission().governance().governed_subject() {
    fail("lineage root subject/governance fixture mismatch")
  }
  CancellationProposalV2::new(
    suffix + "-proposal",
    root,
    aggregate,
    subject,
    flow7_v2_ref("reason", suffix + "-reason", @utf8.encode(suffix)),
    100L,
    [flow7_v2_evidence()],
    aggregate.prefix_event().unwrap().event_ref(),
    suffix + "-proposal-event-key",
    suffix + "-proposal-command-key",
  ) catch {
    OrchestrationError::ReplayBindingViolation(field~) =>
      fail("lineage proposal: " + field)
    _ => fail("lineage proposal")
  }
}

///|
fn phase1b_lineage_proposal(
  ready : Flow7RetryReadyFixture,
  suffix : String,
) -> CancellationProposalV2 raise {
  phase1b_lineage_proposal_from_replay(
    ready,
    ready.fixture.store.replay(ready.fixture.workflow),
    suffix,
  )
}

///|
fn phase1b_lineage_current_from_replay(
  ready : Flow7RetryReadyFixture,
  replay : @storage.ReplayResult,
) -> CurrentGovernedClosedLoopProjectionV2 raise {
  let root = fold_initial_work_receipt_v22(ready.empty_effects, replay)
  fold_governed_closed_loop_v2(
    ready.empty_effects,
    replay,
    @storage.MemoryStore::new().replay(root.governance_stream_ref()),
  )
}

///|
fn phase1b_lineage_current(
  ready : Flow7RetryReadyFixture,
) -> CurrentGovernedClosedLoopProjectionV2 raise {
  phase1b_lineage_current_from_replay(
    ready,
    ready.fixture.store.replay(ready.fixture.workflow),
  )
}

///|
fn phase1b_prepare_matching_retry_intent(
  ready : Flow7RetryReadyFixture,
  prepared : PreparedAtomicRetryV2,
  suffix : String,
) -> FixturePreparedEffectCommit raise {
  let replay = ready.fixture.store.replay(ready.fixture.workflow)
  let aggregate = fold_closed_loop_v2(ready.empty_effects, replay)
  let effect_state = @effects.fold_authoritative_replay(
    ready.empty_effects,
    replay,
    @effects.ReplayCatalog::new(
      [ready.fixture.attempt, prepared.attempt()],
      [ready.fixture.intent],
      [ready.observation],
      [ready.effect_receipt],
      [],
      [],
    ),
  )
  let requested = fixture_envelope(
    suffix + "-effect-request",
    "effect-request",
    ready.fixture.intent.governance().governed_subject(),
    @utf8.encode(suffix + "-effect-request"),
    evidence=[flow7_v2_evidence()],
  )
  let retry_intent = @effects.EffectIntent::new(
    suffix + "-intent",
    "1.0.0",
    prepared.attempt(),
    ready.fixture.intent.governance(),
    requested,
    [flow7_v2_evidence()],
    suffix + "-external-key",
    flow7_v2_ref(
      "capability",
      suffix + "-capability",
      @utf8.encode(suffix + "-capability"),
    ),
    suffix + "-capability-token",
    101L,
    prepared.attempt().attempt_ref(),
    aggregate.effects().last_event_digest().unwrap(),
    true,
    fencing=@effects.FencingBinding::new(
      ready.fixture.intent.fencing().unwrap().fence_ref(),
      2L,
      11L,
    ),
  )
  fixture_prepare_effect_commit(
    effect_state,
    suffix + "-intent-event",
    suffix + "-outbox",
    suffix + "-command",
    retry_intent,
  )
}

///|
test "FLOW-7 Phase1B retry attempt before its intent cannot inherit the old intent" {
  let ready = flow7_retry_ready_fixture("phase1b-lineage-gap", false)
  let prepared = flow7_prepare_ready_retry(ready, "phase1b-lineage-gap")
  ignore(ready.fixture.store.commit(prepared.request()))
  let proposal = phase1b_lineage_proposal(ready, "phase1b-lineage-gap")
  if proposal.source_attempt_ref() != Some(prepared.attempt().attempt_ref()) {
    fail(
      "unexpected source attempt: " +
      proposal.source_attempt_ref().map(value => value.id()).unwrap_or("none") +
      " expected " +
      prepared.attempt().attempt_ref().id(),
    )
  }
  assert_true(proposal.source_intent_ref() is None)
  let aggregate = fold_closed_loop_v2(
    ready.empty_effects,
    ready.fixture.store.replay(ready.fixture.workflow),
  )
  assert_true(
    aggregate
    .effects()
    .committed_intent_refs()
    .any(intent_ref => intent_ref == ready.fixture.intent.intent_ref()),
  )
  proposal.validate_current(phase1b_lineage_current(ready))
}

///|
test "FLOW-7 Phase1B pairs a retry intent to its attempt and rejects the pre-intent chain" {
  let ready = flow7_retry_ready_fixture("phase1b-lineage-rechain", false)
  let prepared = flow7_prepare_ready_retry(ready, "phase1b-lineage-rechain")
  ignore(ready.fixture.store.commit(prepared.request()))
  let before_intent = phase1b_lineage_proposal(
    ready, "phase1b-lineage-rechain-before",
  )
  let committed = phase1b_prepare_matching_retry_intent(
    ready, prepared, "phase1b-lineage-rechain",
  )
  let retry_intent = committed.effect_intent()
  ignore(ready.fixture.store.commit(committed.commit_request()))
  try before_intent.validate_current(phase1b_lineage_current(ready)) catch {
    OrchestrationError::ReplayBindingViolation(
      field="cancellation_source_lineage"
    ) => ()
    _ => fail("unexpected re-chained proposal mismatch error")
  } noraise {
    _ => fail("accepted a proposal frozen before the matching retry intent")
  }
  let after_intent = phase1b_lineage_proposal(
    ready, "phase1b-lineage-rechain-after",
  )
  assert_true(
    after_intent.source_attempt_ref() == Some(prepared.attempt().attempt_ref()),
  )
  assert_true(
    after_intent.source_intent_ref() == Some(retry_intent.intent_ref()),
  )
  after_intent.validate_current(phase1b_lineage_current(ready))
}
