///|
fn flow7_durable_fixture() -> (
  Flow7V2AdmissionFixture,
  @contracts.EvidenceRef,
  ScheduleIntentV2,
  ScheduleRegisteredV2,
  LeaseClaimV2,
  LeaseClaimedV2,
) raise OrchestrationError {
  let admission_fixture = flow7_v2_admission()
  let evidence = flow7_v2_evidence()
  let schedule = flow7_v2_schedule_intent(admission_fixture.admission, evidence)
  let registered = ScheduleRegisteredV2::new(
    "flow7-durable-registration", schedule,
  )
  let claim = LeaseClaimV2::new(
    "flow7-durable-claim",
    schedule,
    admission_fixture.admission,
    admission_fixture.admission.planned().workflow(),
    flow7_v2_ref("owner", "flow7-durable-owner", b"flow7-durable-owner"),
    10L,
    0L,
    0L,
    1L,
    1L,
    "flow7-durable-claim-idempotency",
    [evidence],
    flow7_v2_ref("causation", "flow7-durable-claim", b"flow7-durable-claim"),
  )
  let claimed = LeaseClaimedV2::new("flow7-durable-claimed", registered, claim)
  (admission_fixture, evidence, schedule, registered, claim, claimed)
}

///|
fn flow7_prepare_initial_work_fixture(
  replay : @storage.ReplayResult,
  registration : ScheduleRegisteredV2,
  prefix : String,
  retry_policy? : RetryPolicyV2,
) -> @storage.CommitRequest raise {
  let schedule = registration.schedule()
  let governance_policy = flow7_v2_governance_policy()
  let empty_effects = @effects.EffectsProjection::new(
    schedule.workflow(),
    governance_policy.policy_ref(),
  )
  let aggregate = fold_empty_closed_loop_v22(empty_effects, replay)
  let authorization = authorize_initial_work_v22(
    prefix + "-authorization",
    aggregate,
    registration,
    retry_policy.unwrap_or(flow7_v2_retry_policy()),
    governance_policy,
    flow7_v2_ref(
      "governance-stream",
      prefix + "-governance-stream",
      @utf8.encode(prefix + "-governance-stream"),
    ),
    20L,
    prefix + "-schedule-event",
    prefix + "-retry-binding",
    prefix + "-retry-event",
    prefix + "-retry-event-key",
    prefix + "-governance-binding",
    prefix + "-governance-event",
    prefix + "-governance-event-key",
    prefix + "-command",
  )
  prepare_initial_work_v22(authorization, registration)
}

///|
fn flow7_fold_root_bound_fixture(
  replay : @storage.ReplayResult,
) -> OrchestrationProjectionV2 raise {
  let policy = flow7_v2_governance_policy()
  fold_root_bound_orchestration_v22(
    @effects.EffectsProjection::new(replay.workflow(), policy.policy_ref()),
    replay,
  )
}

///|
test "FLOW-7 V2 durable lifecycle codecs round trip exactly" {
  let (_, _, schedule, registered, claim, claimed) = flow7_durable_fixture()
  let decoded_registered = ScheduleRegisteredV2::decode(
    registered.record_ref().id(),
    registered.canonical_bytes(),
  )
  assert_true(
    decoded_registered.canonical_bytes() == registered.canonical_bytes(),
  )
  assert_true(decoded_registered.digest() == registered.digest())
  assert_true(
    decoded_registered.schedule().canonical_bytes() ==
    schedule.canonical_bytes(),
  )
  let decoded_claim = LeaseClaimV2::decode(
    claim.state_ref().id(),
    schedule,
    0L,
    0L,
    claim.canonical_bytes(),
  )
  assert_true(decoded_claim.canonical_bytes() == claim.canonical_bytes())
  let decoded_claimed = LeaseClaimedV2::decode(
    claimed.record_ref().id(),
    registered,
    0L,
    0L,
    claimed.canonical_bytes(),
  )
  assert_true(decoded_claimed.canonical_bytes() == claimed.canonical_bytes())
  assert_true(decoded_claimed.digest() == claimed.digest())
  assert_true(decoded_claimed.epoch() == 1L)
  assert_true(decoded_claimed.fencing_token() == 1L)
}

///|
test "FLOW-7 V2 durable lifecycle codecs reject tamper truncate and trailing bytes" {
  let (_, _, _, registered, _, claimed) = flow7_durable_fixture()
  let registered_bytes = registered.canonical_bytes()
  let registered_last = registered_bytes.length() - 1
  let registered_replacement : Byte = if registered_bytes[registered_last] == 0 {
    1
  } else {
    0
  }
  let malformed_registered = [
    flow7_v2_replace_byte(
      registered_bytes, registered_last, registered_replacement,
    ),
    flow7_v2_proper_prefix(registered_bytes, registered_bytes.length() - 1),
    registered_bytes + b"x",
  ]
  for bytes in malformed_registered {
    try
      ScheduleRegisteredV2::decode(registered.record_ref().id(), bytes)
    catch {
      MalformedInput(field=_) | DigestMismatch(field=_) => ()
      _ => fail("expected strict schedule-registration decode rejection")
    } noraise {
      _ => fail("expected strict schedule-registration decode rejection")
    }
  }
  let claimed_bytes = claimed.canonical_bytes()
  let claimed_last = claimed_bytes.length() - 1
  let claimed_replacement : Byte = if claimed_bytes[claimed_last] == 0 {
    1
  } else {
    0
  }
  let malformed_claimed = [
    flow7_v2_replace_byte(claimed_bytes, claimed_last, claimed_replacement),
    flow7_v2_proper_prefix(claimed_bytes, claimed_bytes.length() - 1),
    claimed_bytes + b"x",
  ]
  for bytes in malformed_claimed {
    try
      LeaseClaimedV2::decode(
        claimed.record_ref().id(),
        registered,
        0L,
        0L,
        bytes,
      )
    catch {
      MalformedInput(field=_) | DigestMismatch(field=_) => ()
      _ => fail("expected strict lease-claimed decode rejection")
    } noraise {
      _ => fail("expected strict lease-claimed decode rejection")
    }
  }
}

///|
fn flow7_durable_test_schema(kind : String) -> @contracts.SchemaRef {
  try! @contracts.SchemaRef::new(
    "closed-loop.orchestration",
    "1.0.0",
    kind,
    "1.0.0",
    @contracts.sha256_digest(@utf8.encode("closed-loop.orchestration/{kind}/1")).text(),
  )
}

///|
fn flow7_durable_test_event(
  event_id : String,
  event_key : String,
  workflow : @contracts.RecordRef,
  kind : String,
  subject : @contracts.RecordRef,
  payload : Bytes,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  sequence : Int64,
  revision : Int64,
  previous_digest : @contracts.ContentDigest?,
) -> @storage.WorkflowEvent raise {
  let envelope = @contracts.WireEnvelope::new(
    "closed-loop.orchestration",
    "1.0.0",
    event_id,
    kind,
    subject,
    flow7_durable_test_schema(kind),
    payload,
    "orchestration-protocol",
    "1.0.0",
    [],
    evidence,
    run_ref=workflow,
    correlation_ref=workflow.id(),
    causation_ref=causation.id(),
    idempotency_ref=event_key,
    previous_digest?,
  )
  let previous_event_digest = previous_digest
  @storage.WorkflowEvent::new(
    "1.0.0",
    "1.0.0",
    workflow,
    event_id,
    sequence,
    revision,
    event_key,
    envelope,
    evidence,
    previous_event_digest?,
  )
}

///|
test "FLOW-7 V2 command retry is stable and a physical duplicate is rejected" {
  let (admission, evidence, schedule, registered, _, _) = flow7_durable_fixture()
  let store = @storage.MemoryStore::new()
  let empty = store.replay(schedule.workflow())
  let request = flow7_prepare_initial_work_fixture(
    empty, registered, "flow7-durable",
  )
  let committed = commit_orchestration_v2(store, request)
  let after_schedule = flow7_fold_root_bound_fixture(
    store.replay(schedule.workflow()),
  )
  assert_eq(after_schedule.schedule_count(), 1)
  assert_eq(after_schedule.revision(), 3L)
  let semantic_digest = after_schedule.state_digest()
  let duplicate_result = commit_orchestration_v2(store, request)
  assert_true(duplicate_result == committed)
  let after_exact_command_retry = flow7_fold_root_bound_fixture(
    store.replay(schedule.workflow()),
  )
  assert_eq(after_exact_command_retry.schedule_count(), 1)
  assert_eq(after_exact_command_retry.revision(), 3L)
  assert_true(after_exact_command_retry.state_digest() == semantic_digest)
  let changed_schedule = ScheduleIntentV2::new(
    "flow7-durable-changed-command-schedule",
    "2.0.0",
    admission.admission,
    schedule.workflow(),
    10L,
    Some(20L),
    [evidence],
    flow7_v2_ref(
      "causation", "flow7-durable-changed-command-schedule", b"flow7-durable-changed-command-schedule",
    ),
    "flow7-durable-changed-command-payload-key",
  )
  let changed_registration = ScheduleRegisteredV2::new(
    "flow7-durable-changed-command-registration", changed_schedule,
  )
  let changed_request = flow7_prepare_initial_work_fixture(
    empty, changed_registration, "flow7-durable",
  )
  try commit_orchestration_v2(store, changed_request) catch {
    @storage.IdempotencyConflict(key="flow7-durable-command") => ()
    _ => fail("expected changed command content to conflict")
  } noraise {
    _ => fail("expected changed command content to conflict")
  }
  assert_eq(store.head(schedule.workflow()).revision(), 3L)
  let first_event = request.events()[2]
  let duplicate_event = flow7_durable_test_event(
    "flow7-durable-physical-schedule-duplicate",
    "flow7-durable-physical-schedule-duplicate-key",
    schedule.workflow(),
    "schedule.registered.v2",
    registered.record_ref(),
    registered.canonical_bytes(),
    [
      for value in schedule.evidence() => value
    ],
    schedule.causation_ref(),
    4L,
    4L,
    Some(first_event.event_ref().digest()),
  )
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        schedule.workflow(),
        3L,
        "flow7-durable-physical-schedule-duplicate-command",
        [duplicate_event],
        [],
      ),
    ),
  )
  let duplicate_replay = store.replay(schedule.workflow())
  try fold_orchestration_v2(duplicate_replay) catch {
    IdempotencyConflict(key="flow7-durable-physical-schedule-duplicate-key") =>
      ()
    _ => fail("expected physical duplicate payload/event key rejection")
  } noraise {
    _ => fail("expected physical duplicate payload/event key rejection")
  }
}

///|
test "FLOW-7 V2 two workers have one CAS winner and stale fencing is absent" {
  let (admission, evidence, schedule, registered, winner_claim, winner) = flow7_durable_fixture()
  let store = @storage.MemoryStore::new()
  let empty = store.replay(schedule.workflow())
  ignore(
    commit_orchestration_v2(
      store,
      flow7_prepare_initial_work_fixture(empty, registered, "flow7-cas"),
    ),
  )
  let shared = flow7_fold_root_bound_fixture(store.replay(schedule.workflow()))
  let loser_claim = LeaseClaimV2::new(
    "flow7-cas-loser-claim",
    schedule,
    admission.admission,
    schedule.workflow(),
    flow7_v2_ref("owner", "flow7-cas-loser", b"flow7-cas-loser"),
    10L,
    0L,
    0L,
    1L,
    1L,
    "flow7-cas-loser-claim-key",
    [evidence],
    flow7_v2_ref("causation", "flow7-cas-loser", b"flow7-cas-loser"),
  )
  let loser = LeaseClaimedV2::new(
    "flow7-cas-loser-claimed", registered, loser_claim,
  )
  let winner_request = prepare_lease_claimed_v2(
    shared,
    "flow7-cas-winner-event",
    winner_claim.idempotency_key(),
    "flow7-cas-winner-command",
    winner,
  )
  let loser_request = prepare_lease_claimed_v2(
    shared,
    "flow7-cas-loser-event",
    loser_claim.idempotency_key(),
    "flow7-cas-loser-command",
    loser,
  )
  ignore(commit_orchestration_v2(store, winner_request))
  try commit_orchestration_v2(store, loser_request) catch {
    @storage.OptimisticRevisionConflict(expected=3L, actual=4L, ..) => ()
    _ => fail("expected one stale worker to lose storage CAS")
  } noraise {
    _ => fail("expected one stale worker to lose storage CAS")
  }
  let recovered = flow7_fold_root_bound_fixture(
    store.replay(schedule.workflow()),
  )
  assert_eq(recovered.lease_count(), 1)
  assert_true(recovered.lease_owner() == Some(winner_claim.owner()))
  assert_eq(recovered.epoch_floor(), 1L)
  assert_eq(recovered.fencing_floor(), 1L)
  try
    prepare_lease_claimed_v2(
      recovered,
      "flow7-cas-stale-event",
      loser_claim.idempotency_key(),
      "flow7-cas-stale-command",
      loser,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected stale lease/fencing projection rejection")
  }
  let unchanged = flow7_fold_root_bound_fixture(
    store.replay(schedule.workflow()),
  )
  assert_eq(unchanged.lease_count(), 1)
  assert_true(unchanged.lease_owner() == Some(winner_claim.owner()))
}

///|
test "FLOW-7 V2 replay rejects lease before exact schedule registration" {
  let (_, _, schedule, _, claim, claimed) = flow7_durable_fixture()
  let store = @storage.MemoryStore::new()
  let lease_event = flow7_durable_test_event(
    "flow7-before-schedule-lease-event",
    claim.idempotency_key(),
    schedule.workflow(),
    "lease.claimed.v2",
    claimed.record_ref(),
    claimed.canonical_bytes(),
    [
      for value in claim.evidence() => value
    ],
    claim.causation(),
    1L,
    1L,
    None,
  )
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        schedule.workflow(),
        0L,
        "flow7-before-schedule-command",
        [lease_event],
        [],
      ),
    ),
  )
  let invalid_replay = store.replay(schedule.workflow())
  try fold_orchestration_v2(invalid_replay) catch {
    ReplayBindingViolation(field="lease_claimed_v2_registration_missing") => ()
    _ => fail("expected replay to reject lease without earlier registration")
  } noraise {
    _ => fail("expected replay to reject lease without earlier registration")
  }
}

///|
test "FLOW-7 V2 orphan one-event schedule cannot prepare public lease work" {
  let (_, _, schedule, registered, claim, claimed) = flow7_durable_fixture()
  let event = flow7_durable_test_event(
    "flow7-orphan-schedule-event",
    schedule.idempotency_key(),
    schedule.workflow(),
    "schedule.registered.v2",
    registered.record_ref(),
    registered.canonical_bytes(),
    [
      for value in schedule.evidence() => value
    ],
    schedule.causation_ref(),
    1L,
    1L,
    None,
  )
  let store = @storage.MemoryStore::new()
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        schedule.workflow(),
        0L,
        "flow7-orphan-schedule-command",
        [event],
        [],
      ),
    ),
  )
  let orphan = fold_orchestration_v2(store.replay(schedule.workflow()))
  assert_eq(orphan.schedule_count(), 1)
  try
    prepare_lease_claimed_v2(
      orphan,
      "flow7-orphan-claim-event",
      claim.idempotency_key(),
      "flow7-orphan-claim-command",
      claimed,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("orphan one-event schedule prepared public lease work")
  }
}

///|
fn flow7_commit_schedule_fixture(
  store : @storage.MemoryStore,
  schedule : ScheduleIntentV2,
  registered : ScheduleRegisteredV2,
  event_id : String,
  command_key : String,
) -> @storage.WorkflowEvent raise {
  let request = flow7_prepare_initial_work_fixture(
    store.replay(schedule.workflow()),
    registered,
    event_id + "-" + command_key,
  )
  ignore(commit_orchestration_v2(store, request))
  request.events()[2]
}

///|
test "FLOW-7 V2 first schedule previous digest is bound in prepare and raw replay" {
  let (admission, evidence, schedule, _, _, _) = flow7_durable_fixture()
  let wrong_previous = @contracts.sha256_digest(
    b"flow7-first-schedule-wrong-previous",
  )
  let malformed_schedule = ScheduleIntentV2::new(
    "flow7-first-previous-schedule",
    "2.0.0",
    admission.admission,
    schedule.workflow(),
    10L,
    Some(20L),
    [evidence],
    flow7_v2_ref(
      "causation", "flow7-first-previous-schedule", b"flow7-first-previous-schedule",
    ),
    "flow7-first-previous-payload-key",
    previous_digest=wrong_previous,
  )
  let malformed_registration = ScheduleRegisteredV2::new(
    "flow7-first-previous-registration", malformed_schedule,
  )
  let prepare_store = @storage.MemoryStore::new()
  try
    flow7_prepare_initial_work_fixture(
      prepare_store.replay(malformed_schedule.workflow()),
      malformed_registration,
      "flow7-first-previous-prepare",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected prepare to reject a non-empty first previous digest")
  }
  let raw_store = @storage.MemoryStore::new()
  let raw_event = flow7_durable_test_event(
    "flow7-first-previous-raw-event",
    malformed_schedule.idempotency_key(),
    malformed_schedule.workflow(),
    "schedule.registered.v2",
    malformed_registration.record_ref(),
    malformed_registration.canonical_bytes(),
    [evidence],
    malformed_schedule.causation_ref(),
    1L,
    1L,
    None,
  )
  ignore(
    raw_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        malformed_schedule.workflow(),
        0L,
        "flow7-first-previous-raw-command",
        [raw_event],
        [],
      ),
    ),
  )
  let replay = raw_store.replay(malformed_schedule.workflow())
  try fold_orchestration_v2(replay) catch {
    DigestMismatch(field="schedule_registered_v2_previous_digest") => ()
    _ => fail("expected exact first schedule previous-digest error")
  } noraise {
    _ => fail("expected exact first schedule previous-digest error")
  }
}

///|
test "FLOW-7 V2 later schedule validates digest then rejects non-genesis admission" {
  let (admission, evidence, schedule, registered, _, _) = flow7_durable_fixture()
  let wrong_store = @storage.MemoryStore::new()
  let first = flow7_commit_schedule_fixture(
    wrong_store, schedule, registered, "flow7-later-wrong-first-event", "flow7-later-wrong-first-command",
  )
  let wrong_later = ScheduleIntentV2::new(
    "flow7-later-wrong-schedule",
    "2.0.0",
    admission.admission,
    schedule.workflow(),
    10L,
    Some(20L),
    [evidence],
    flow7_v2_ref(
      "causation", "flow7-later-wrong-schedule", b"flow7-later-wrong-schedule",
    ),
    "flow7-later-wrong-payload-key",
    previous_digest=@contracts.sha256_digest(b"wrong-later-previous"),
  )
  let wrong_registration = ScheduleRegisteredV2::new(
    "flow7-later-wrong-registration", wrong_later,
  )
  let wrong_event = flow7_durable_test_event(
    "flow7-later-wrong-event",
    wrong_later.idempotency_key(),
    schedule.workflow(),
    "schedule.registered.v2",
    wrong_registration.record_ref(),
    wrong_registration.canonical_bytes(),
    [evidence],
    wrong_later.causation_ref(),
    first.sequence() + 1L,
    first.revision() + 1L,
    Some(first.event_ref().digest()),
  )
  ignore(
    wrong_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        schedule.workflow(),
        first.revision(),
        "flow7-later-wrong-command",
        [wrong_event],
        [],
      ),
    ),
  )
  let wrong_replay = wrong_store.replay(schedule.workflow())
  try fold_orchestration_v2(wrong_replay) catch {
    DigestMismatch(field="schedule_registered_v2_previous_digest") => ()
    _ => fail("expected exact later schedule previous-digest error")
  } noraise {
    _ => fail("expected exact later schedule previous-digest error")
  }

  let multiple_store = @storage.MemoryStore::new()
  let first_again = flow7_commit_schedule_fixture(
    multiple_store, schedule, registered, "flow7-later-multiple-first-event", "flow7-later-multiple-first-command",
  )
  let correct_later = ScheduleIntentV2::new(
    "flow7-later-correct-schedule",
    "2.0.0",
    admission.admission,
    schedule.workflow(),
    10L,
    Some(20L),
    [evidence],
    flow7_v2_ref(
      "causation", "flow7-later-correct-schedule", b"flow7-later-correct-schedule",
    ),
    "flow7-later-correct-payload-key",
    previous_digest=first_again.event_ref().digest(),
  )
  let correct_registration = ScheduleRegisteredV2::new(
    "flow7-later-correct-registration", correct_later,
  )
  let correct_event = flow7_durable_test_event(
    "flow7-later-correct-event",
    correct_later.idempotency_key(),
    schedule.workflow(),
    "schedule.registered.v2",
    correct_registration.record_ref(),
    correct_registration.canonical_bytes(),
    [evidence],
    correct_later.causation_ref(),
    first_again.sequence() + 1L,
    first_again.revision() + 1L,
    Some(first_again.event_ref().digest()),
  )
  ignore(
    multiple_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        schedule.workflow(),
        first_again.revision(),
        "flow7-later-correct-command",
        [correct_event],
        [],
      ),
    ),
  )
  let multiple_replay = multiple_store.replay(schedule.workflow())
  try fold_orchestration_v2(multiple_replay) catch {
    ReplayBindingViolation(field="schedule_registered_v2_non_genesis") => ()
    _ => fail("expected exact non-genesis schedule admission error")
  } noraise {
    _ => fail("expected exact non-genesis schedule admission error")
  }

  let identity_store = @storage.MemoryStore::new()
  let identity_first = flow7_commit_schedule_fixture(
    identity_store, schedule, registered, "flow7-later-identity-first-event", "flow7-later-identity-first-command",
  )
  let identity_schedule = ScheduleIntentV2::new(
    "flow7-later-identity-schedule",
    "2.0.0",
    admission.admission,
    schedule.workflow(),
    10L,
    Some(20L),
    [evidence],
    flow7_v2_ref(
      "causation", "flow7-later-identity-schedule", b"flow7-later-identity-schedule",
    ),
    "flow7-later-identity-payload-key",
    previous_digest=identity_first.event_ref().digest(),
  )
  let identity_registration = ScheduleRegisteredV2::new(
    registered.record_ref().id(),
    identity_schedule,
  )
  let identity_event = flow7_durable_test_event(
    "flow7-later-identity-event",
    identity_schedule.idempotency_key(),
    schedule.workflow(),
    "schedule.registered.v2",
    identity_registration.record_ref(),
    identity_registration.canonical_bytes(),
    [evidence],
    identity_schedule.causation_ref(),
    identity_first.sequence() + 1L,
    identity_first.revision() + 1L,
    Some(identity_first.event_ref().digest()),
  )
  ignore(
    identity_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        schedule.workflow(),
        identity_first.revision(),
        "flow7-later-identity-command",
        [identity_event],
        [],
      ),
    ),
  )
  let identity_replay = identity_store.replay(schedule.workflow())
  try fold_orchestration_v2(identity_replay) catch {
    ReplayBindingViolation(field="schedule_registered_v2_non_genesis") => ()
    _ => fail("expected exact non-genesis schedule admission error")
  } noraise {
    _ => fail("expected exact non-genesis schedule admission error")
  }
}

///|
test "FLOW-7 V2 payload and event idempotency keys are exact-bound" {
  let (_, _, schedule, registered, claim, claimed) = flow7_durable_fixture()
  let prepare_store = @storage.MemoryStore::new()
  let first = flow7_commit_schedule_fixture(
    prepare_store, schedule, registered, "flow7-lease-key-schedule-event", "flow7-lease-key-schedule-command",
  )
  let scheduled = flow7_fold_root_bound_fixture(
    prepare_store.replay(schedule.workflow()),
  )
  try
    prepare_lease_claimed_v2(
      scheduled, "flow7-lease-key-mismatch-prepare-event", "flow7-lease-key-mismatch",
      "flow7-lease-key-mismatch-command", claimed,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected lease prepare key mismatch rejection")
  }
  let wrong_event_key = "flow7-lease-raw-wrong-event-key"
  let raw_lease = flow7_durable_test_event(
    "flow7-lease-raw-wrong-key-event",
    wrong_event_key,
    schedule.workflow(),
    "lease.claimed.v2",
    claimed.record_ref(),
    claimed.canonical_bytes(),
    [
      for value in claim.evidence() => value
    ],
    claim.causation(),
    4L,
    4L,
    Some(first.event_ref().digest()),
  )
  ignore(
    prepare_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        schedule.workflow(),
        3L,
        "flow7-lease-raw-wrong-key-command",
        [raw_lease],
        [],
      ),
    ),
  )
  let replay = prepare_store.replay(schedule.workflow())
  try fold_orchestration_v2(replay) catch {
    IdempotencyConflict(key="flow7-lease-raw-wrong-event-key") => ()
    _ => fail("expected exact lease payload/event key error")
  } noraise {
    _ => fail("expected exact lease payload/event key error")
  }
}

///|
fn flow7_find_unique_bytes(haystack : Bytes, needle : Bytes) -> Int {
  if needle.is_empty() || needle.length() > haystack.length() {
    abort("invalid FLOW-7 raw test needle")
  }
  let mut found = -1
  let limit = haystack.length() - needle.length()
  for start = 0; start <= limit; start = start + 1 {
    let mut matches = true
    for index = 0; index < needle.length(); index = index + 1 {
      if haystack[start + index] != needle[index] {
        matches = false
      }
    }
    if matches {
      if found >= 0 {
        abort("FLOW-7 raw test needle is not unique")
      }
      found = start
    }
  }
  if found < 0 {
    abort("FLOW-7 raw test needle not found")
  }
  found
}

///|
fn flow7_replace_equal_bytes(
  source : Bytes,
  offset : Int,
  replacement : Bytes,
) -> Bytes {
  let mut result = source
  for index = 0; index < replacement.length(); index = index + 1 {
    result = flow7_v2_replace_byte(result, offset + index, replacement[index])
  }
  result
}

///|
fn flow7_replace_small_positive_int64(
  source : Bytes,
  offset : Int,
  value : Int,
) -> Bytes {
  if value <= 0 || value > 255 {
    abort("FLOW-7 raw test integer out of range")
  }
  let mut result = source
  for index = 0; index < 7; index = index + 1 {
    result = flow7_v2_replace_byte(result, offset + index, 0)
  }
  flow7_v2_replace_byte(result, offset + 7, value.to_byte())
}

///|
fn flow7_raw_stale_claimed_payload(
  claimed : LeaseClaimedV2,
  original_claim_key : String,
  claimed_id : String,
  claim_key : String,
  next_epoch : Int,
  next_fencing_token : Int,
) -> Bytes {
  let original_id = @utf8.encode(claimed.record_ref().id())
  let replacement_id = @utf8.encode(claimed_id)
  let original_key = @utf8.encode(original_claim_key)
  let replacement_key = @utf8.encode(claim_key)
  if replacement_id.length() != original_id.length() ||
    replacement_key.length() != original_key.length() {
    abort("FLOW-7 raw test replacement length mismatch")
  }
  let initial = claimed.canonical_bytes()
  let id_offset = flow7_find_unique_bytes(initial, original_id)
  let with_id = flow7_replace_equal_bytes(initial, id_offset, replacement_id)
  let key_offset = flow7_find_unique_bytes(with_id, original_key)
  let with_key = flow7_replace_equal_bytes(with_id, key_offset, replacement_key)
  let with_epoch = flow7_replace_small_positive_int64(
    with_key,
    key_offset - 20,
    next_epoch,
  )
  flow7_replace_small_positive_int64(
    with_epoch,
    key_offset - 12,
    next_fencing_token,
  )
}

///|
fn flow7_raw_claimed_subject(
  claimed : LeaseClaimedV2,
  claimed_id : String,
  payload : Bytes,
) -> @contracts.RecordRef {
  try! @contracts.RecordRef::new(
    claimed.record_ref().kind(),
    claimed_id,
    claimed.record_ref().version().text(),
    @contracts.sha256_digest(payload).text(),
  )
}

///|
fn flow7_commit_schedule_and_first_claim(
  store : @storage.MemoryStore,
  schedule : ScheduleIntentV2,
  registered : ScheduleRegisteredV2,
  claim : LeaseClaimV2,
  claimed : LeaseClaimedV2,
  prefix : String,
) -> @storage.WorkflowEvent raise {
  ignore(
    flow7_commit_schedule_fixture(
      store,
      schedule,
      registered,
      prefix + "-schedule-event",
      prefix + "-schedule-command",
    ),
  )
  let scheduled = flow7_fold_root_bound_fixture(
    store.replay(schedule.workflow()),
  )
  let request = prepare_lease_claimed_v2(
    scheduled,
    prefix + "-lease-event",
    claim.idempotency_key(),
    prefix + "-lease-command",
    claimed,
  )
  ignore(commit_orchestration_v2(store, request))
  request.events()[0]
}

///|
fn flow7_commit_raw_stale_claim(
  store : @storage.MemoryStore,
  schedule : ScheduleIntentV2,
  claimed : LeaseClaimedV2,
  claim : LeaseClaimV2,
  previous : @storage.WorkflowEvent,
  claimed_id : String,
  claim_key : String,
  next_epoch : Int,
  next_fencing_token : Int,
) -> Unit raise {
  let head = store.head(schedule.workflow())
  let payload = flow7_raw_stale_claimed_payload(
    claimed,
    claim.idempotency_key(),
    claimed_id,
    claim_key,
    next_epoch,
    next_fencing_token,
  )
  let subject = flow7_raw_claimed_subject(claimed, claimed_id, payload)
  let event = flow7_durable_test_event(
    claimed_id + "-event",
    claim_key,
    schedule.workflow(),
    "lease.claimed.v2",
    subject,
    payload,
    [
      for value in claim.evidence() => value
    ],
    claim.causation(),
    head.sequence() + 1L,
    head.revision() + 1L,
    Some(previous.event_ref().digest()),
  )
  ignore(
    store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        schedule.workflow(),
        head.revision(),
        claimed_id + "-command",
        [event],
        [],
      ),
    ),
  )
}

///|
test "FLOW-7 V2 raw replay rejects stale epoch fencing and both exactly" {
  let (_, _, schedule, registered, claim, claimed) = flow7_durable_fixture()

  let epoch_store = @storage.MemoryStore::new()
  let epoch_previous = flow7_commit_schedule_and_first_claim(
    epoch_store, schedule, registered, claim, claimed, "flow7-stale-epoch",
  )
  flow7_commit_raw_stale_claim(
    epoch_store, schedule, claimed, claim, epoch_previous, "flow7-stale-epoch-001",
    "flow7-stale-epoch-raw-key-00000", 1, 2,
  )
  let epoch_replay = epoch_store.replay(schedule.workflow())
  try fold_orchestration_v2(epoch_replay) catch {
    LeaseEpochViolation(expected_greater_than=1L, actual=1L) => ()
    _ => fail("expected exact stale epoch replay error")
  } noraise {
    _ => fail("expected exact stale epoch replay error")
  }

  let fencing_store = @storage.MemoryStore::new()
  let fencing_previous = flow7_commit_schedule_and_first_claim(
    fencing_store, schedule, registered, claim, claimed, "flow7-stale-fence",
  )
  flow7_commit_raw_stale_claim(
    fencing_store, schedule, claimed, claim, fencing_previous, "flow7-stale-fence-001",
    "flow7-stale-fence-raw-key-00000", 2, 1,
  )
  let fencing_replay = fencing_store.replay(schedule.workflow())
  try fold_orchestration_v2(fencing_replay) catch {
    FencingViolation(expected_greater_than=1L, actual=1L) => ()
    _ => fail("expected exact stale fencing replay error")
  } noraise {
    _ => fail("expected exact stale fencing replay error")
  }

  let both_store = @storage.MemoryStore::new()
  let both_previous = flow7_commit_schedule_and_first_claim(
    both_store, schedule, registered, claim, claimed, "flow7-stale-both",
  )
  flow7_commit_raw_stale_claim(
    both_store, schedule, claimed, claim, both_previous, "flow7-stale-both--001",
    "flow7-stale-both--raw-key-00000", 1, 1,
  )
  let both_replay = both_store.replay(schedule.workflow())
  try fold_orchestration_v2(both_replay) catch {
    LeaseEpochViolation(expected_greater_than=1L, actual=1L) => ()
    _ => fail("expected stale epoch to win deterministic error ordering")
  } noraise {
    _ => fail("expected stale epoch to win deterministic error ordering")
  }
}

///|
fn flow7_reject_initial_controls(
  prefix : String,
  missing_capability : Bool,
  expected_field : String,
) -> Unit raise {
  let admission = if missing_capability {
    flow7_v2_admission(include_capability=false)
  } else {
    flow7_v2_admission(include_evidence=false)
  }
  let evidence = if admission.admission.controls().evidence().is_empty() {
    []
  } else {
    [flow7_v2_evidence()]
  }
  let schedule = ScheduleIntentV2::new(
    prefix + "-schedule",
    "2.0.0",
    admission.admission,
    admission.admission.planned().workflow(),
    10L,
    Some(20L),
    evidence,
    flow7_v2_ref(
      "causation",
      prefix + "-schedule",
      @utf8.encode(prefix + "-schedule"),
    ),
    prefix + "-schedule-key",
  )
  let registration = ScheduleRegisteredV2::new(
    prefix + "-registration",
    schedule,
  )

  let prepare_store = @storage.MemoryStore::new()
  try
    flow7_prepare_initial_work_fixture(
      prepare_store.replay(schedule.workflow()),
      registration,
      prefix + "-prepare",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected initial controls prepare rejection: " + prefix)
  }

  let raw_store = @storage.MemoryStore::new()
  let event = flow7_durable_test_event(
    prefix + "-raw-event",
    schedule.idempotency_key(),
    schedule.workflow(),
    "schedule.registered.v2",
    registration.record_ref(),
    registration.canonical_bytes(),
    evidence,
    schedule.causation_ref(),
    1L,
    1L,
    None,
  )
  ignore(
    raw_store.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        schedule.workflow(),
        0L,
        prefix + "-raw-command",
        [event],
        [],
      ),
    ),
  )
  let replay = raw_store.replay(schedule.workflow())
  try fold_orchestration_v2(replay) catch {
    EffectProofMismatch(field~) => assert_eq(field, expected_field)
    EvidenceMismatch(field~) => assert_eq(field, expected_field)
    _ => fail("unexpected initial controls raw-fold error: " + prefix)
  } noraise {
    _ => fail("expected initial controls raw-fold rejection: " + prefix)
  }
}

///|
test "FLOW-7 V2 initial schedule rejects missing capability and evidence in prepare and raw fold" {
  flow7_reject_initial_controls(
    "flow7-initial-missing-capability", true, "schedule_registered_v2_capability",
  )
  flow7_reject_initial_controls(
    "flow7-initial-missing-evidence", false, "schedule_registered_v2_evidence_empty",
  )
}
