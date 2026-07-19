///|
fn flow7_receipt_projection(
  schedule : ScheduleIntentV2,
  registered : ScheduleRegisteredV2,
  claim : LeaseClaimV2,
  claimed : LeaseClaimedV2,
  prefix : String,
) -> OrchestrationProjectionV2 raise {
  let store = @storage.MemoryStore::new()
  ignore(
    flow7_commit_schedule_and_first_claim(
      store, schedule, registered, claim, claimed, prefix,
    ),
  )
  flow7_fold_root_bound_fixture(store.replay(schedule.workflow()))
}

///|
test "FLOW-7 V2 receipt is absent before claim and exact after committed claim" {
  let (_, _, schedule, registered, claim, claimed) = flow7_durable_fixture()
  let store = @storage.MemoryStore::new()
  let schedule_request = flow7_prepare_initial_work_fixture(
    store.replay(schedule.workflow()),
    registered,
    "flow7-receipt-exact",
  )
  ignore(commit_orchestration_v2(store, schedule_request))
  let scheduled = flow7_fold_root_bound_fixture(
    store.replay(schedule.workflow()),
  )
  assert_true(scheduled.committed_lease_authority_receipt() is None)
  let claim_request = prepare_lease_claimed_v2(
    scheduled,
    "flow7-receipt-exact-lease-event",
    claim.idempotency_key(),
    "flow7-receipt-exact-lease-command",
    claimed,
  )
  ignore(commit_orchestration_v2(store, claim_request))
  let committed = flow7_fold_root_bound_fixture(
    store.replay(schedule.workflow()),
  )
  guard committed.committed_lease_authority_receipt() is Some(receipt) else {
    fail("expected committed lease authority receipt")
  }
  let claim_event = claim_request.events()[0]
  assert_true(receipt.workflow() == schedule.workflow())
  assert_true(receipt.schedule_registration_ref() == registered.record_ref())
  assert_true(receipt.schedule_ref() == schedule.schedule_ref())
  assert_true(receipt.schedule_digest() == schedule.digest())
  assert_true(receipt.lease_claimed_ref() == claimed.record_ref())
  assert_true(receipt.lease_claimed_digest() == claimed.digest())
  assert_true(receipt.lease_state_ref() == claim.state_ref())
  assert_true(receipt.lease_state_digest() == claim.digest())
  assert_true(receipt.owner() == claim.owner())
  assert_eq(receipt.observed_at(), 10L)
  assert_eq(receipt.expires_at(), 20L)
  assert_eq(receipt.epoch(), 1L)
  assert_eq(receipt.fencing_token(), 1L)
  assert_true(receipt.committed_event_ref() == claim_event.event_ref())
  assert_true(
    receipt.committed_event_digest() == claim_event.event_ref().digest(),
  )
  assert_eq(receipt.projection_sequence(), committed.sequence())
  assert_eq(receipt.projection_revision(), committed.revision())
  assert_true(
    receipt.projection_head_digest() == committed.last_event_digest().unwrap(),
  )
  assert_true(receipt.semantic_projection_digest() == committed.state_digest())
  assert_true(
    @contracts.sha256_digest(receipt.canonical_bytes()) == receipt.digest(),
  )
  assert_true(receipt.receipt_ref().digest() == receipt.digest())
  receipt.validate_current(committed, 10L)
  receipt.validate_current(committed, 19L)
}

///|
test "FLOW-7 V2 exact lease command duplicate preserves receipt bytes" {
  let (_, _, schedule, registered, claim, claimed) = flow7_durable_fixture()
  let store = @storage.MemoryStore::new()
  ignore(
    flow7_commit_schedule_fixture(
      store, schedule, registered, "flow7-receipt-retry-schedule-event", "flow7-receipt-retry-schedule-command",
    ),
  )
  let scheduled = flow7_fold_root_bound_fixture(
    store.replay(schedule.workflow()),
  )
  let request = prepare_lease_claimed_v2(
    scheduled,
    "flow7-receipt-retry-lease-event",
    claim.idempotency_key(),
    "flow7-receipt-retry-lease-command",
    claimed,
  )
  let first_result = commit_orchestration_v2(store, request)
  let first_projection = flow7_fold_root_bound_fixture(
    store.replay(schedule.workflow()),
  )
  guard first_projection.committed_lease_authority_receipt()
    is Some(first_receipt) else {
    fail("expected first receipt")
  }
  let duplicate_result = commit_orchestration_v2(store, request)
  assert_true(duplicate_result == first_result)
  let duplicate_projection = flow7_fold_root_bound_fixture(
    store.replay(schedule.workflow()),
  )
  guard duplicate_projection.committed_lease_authority_receipt()
    is Some(duplicate_receipt) else {
    fail("expected duplicate-stable receipt")
  }
  assert_eq(duplicate_projection.revision(), 4L)
  assert_eq(duplicate_projection.lease_count(), 1)
  assert_true(
    duplicate_receipt.canonical_bytes() == first_receipt.canonical_bytes(),
  )
  assert_true(duplicate_receipt.receipt_ref() == first_receipt.receipt_ref())
  assert_true(duplicate_receipt.digest() == first_receipt.digest())
}

///|
test "FLOW-7 V2 CAS loser cannot mint loser lease authority" {
  let (admission, evidence, schedule, registered, winner_claim, winner) = flow7_durable_fixture()
  let store = @storage.MemoryStore::new()
  ignore(
    flow7_commit_schedule_fixture(
      store, schedule, registered, "flow7-receipt-cas-schedule-event", "flow7-receipt-cas-schedule-command",
    ),
  )
  let shared = flow7_fold_root_bound_fixture(store.replay(schedule.workflow()))
  assert_true(shared.committed_lease_authority_receipt() is None)
  let loser_claim = LeaseClaimV2::new(
    "flow7-receipt-cas-loser-claim",
    schedule,
    admission.admission,
    schedule.workflow(),
    flow7_v2_ref("owner", "flow7-receipt-cas-loser", b"flow7-receipt-cas-loser"),
    10L,
    0L,
    0L,
    1L,
    1L,
    "flow7-receipt-cas-loser-key",
    [evidence],
    flow7_v2_ref(
      "causation", "flow7-receipt-cas-loser", b"flow7-receipt-cas-loser",
    ),
  )
  let loser = LeaseClaimedV2::new(
    "flow7-receipt-cas-loser-claimed", registered, loser_claim,
  )
  let winner_request = prepare_lease_claimed_v2(
    shared,
    "flow7-receipt-cas-winner-event",
    winner_claim.idempotency_key(),
    "flow7-receipt-cas-winner-command",
    winner,
  )
  let loser_request = prepare_lease_claimed_v2(
    shared,
    "flow7-receipt-cas-loser-event",
    loser_claim.idempotency_key(),
    "flow7-receipt-cas-loser-command",
    loser,
  )
  ignore(commit_orchestration_v2(store, winner_request))
  try commit_orchestration_v2(store, loser_request) catch {
    @storage.OptimisticRevisionConflict(expected=3L, actual=4L, ..) => ()
    _ => fail("expected stale loser CAS rejection")
  } noraise {
    _ => fail("expected stale loser CAS rejection")
  }
  let recovered = flow7_fold_root_bound_fixture(
    store.replay(schedule.workflow()),
  )
  guard recovered.committed_lease_authority_receipt() is Some(receipt) else {
    fail("expected winner receipt")
  }
  assert_true(receipt.owner() == winner_claim.owner())
  assert_true(receipt.owner() != loser_claim.owner())
  assert_true(receipt.lease_claimed_ref() == winner.record_ref())
  receipt.validate_current(recovered, 10L)
}

///|
test "FLOW-7 V2 receipt rejects wrong projection revision semantic head and expiry" {
  let (admission, evidence, schedule, registered, claim, claimed) = flow7_durable_fixture()
  let committed = flow7_receipt_projection(
    schedule, registered, claim, claimed, "flow7-receipt-validation-base",
  )
  guard committed.committed_lease_authority_receipt() is Some(receipt) else {
    fail("expected validation receipt")
  }

  let wrong_workflow = flow7_v2_ref(
    "workflow", "flow7-receipt-wrong-workflow", b"flow7-receipt-wrong-workflow",
  )
  let wrong_workflow_store = @storage.MemoryStore::new()
  let wrong_projection = replay_orchestration_v2(
    wrong_workflow_store, wrong_workflow,
  )
  try receipt.validate_current(wrong_projection, 10L) catch {
    WorkflowMismatch(field="lease_authority_v2_projection_workflow") => ()
    _ => fail("expected exact wrong-projection error")
  } noraise {
    _ => fail("expected exact wrong-projection error")
  }

  let revision_store = @storage.MemoryStore::new()
  ignore(
    flow7_commit_schedule_fixture(
      revision_store, schedule, registered, "flow7-receipt-revision-schedule-event",
      "flow7-receipt-revision-schedule-command",
    ),
  )
  let wrong_revision = flow7_fold_root_bound_fixture(
    revision_store.replay(schedule.workflow()),
  )
  try receipt.validate_current(wrong_revision, 10L) catch {
    RevisionMismatch(expected=4L, actual=3L) => ()
    _ => fail("expected exact revision error")
  } noraise {
    _ => fail("expected exact revision error")
  }

  let changed_schedule = ScheduleIntentV2::new(
    "flow7-receipt-semantic-schedule",
    "2.0.0",
    admission.admission,
    schedule.workflow(),
    10L,
    Some(20L),
    [evidence],
    flow7_v2_ref(
      "causation", "flow7-receipt-semantic-schedule", b"flow7-receipt-semantic-schedule",
    ),
    "flow7-receipt-semantic-schedule-key",
  )
  let changed_registered = ScheduleRegisteredV2::new(
    "flow7-receipt-semantic-registration", changed_schedule,
  )
  let changed_claim = LeaseClaimV2::new(
    "flow7-receipt-semantic-claim",
    changed_schedule,
    admission.admission,
    schedule.workflow(),
    flow7_v2_ref(
      "owner", "flow7-receipt-semantic-owner", b"flow7-receipt-semantic-owner",
    ),
    10L,
    0L,
    0L,
    1L,
    1L,
    "flow7-receipt-semantic-claim-key",
    [evidence],
    flow7_v2_ref(
      "causation", "flow7-receipt-semantic-claim", b"flow7-receipt-semantic-claim",
    ),
  )
  let changed_claimed = LeaseClaimedV2::new(
    "flow7-receipt-semantic-claimed", changed_registered, changed_claim,
  )
  let wrong_semantic = flow7_receipt_projection(
    changed_schedule, changed_registered, changed_claim, changed_claimed, "flow7-receipt-validation-semantic",
  )
  assert_eq(wrong_semantic.revision(), committed.revision())
  assert_true(wrong_semantic.state_digest() != committed.state_digest())
  try receipt.validate_current(wrong_semantic, 10L) catch {
    DigestMismatch(field="lease_authority_v2_semantic_projection") => ()
    _ => fail("expected exact semantic digest error")
  } noraise {
    _ => fail("expected exact semantic digest error")
  }

  let wrong_head = flow7_receipt_projection(
    schedule, registered, claim, claimed, "flow7-receipt-validation-head",
  )
  assert_true(wrong_head.state_digest() == committed.state_digest())
  assert_true(wrong_head.last_event_digest() != committed.last_event_digest())
  try receipt.validate_current(wrong_head, 10L) catch {
    DigestMismatch(field="lease_authority_v2_projection_head") => ()
    _ => fail("expected exact projection-head error")
  } noraise {
    _ => fail("expected exact projection-head error")
  }

  try receipt.validate_current(committed, 20L) catch {
    AuthorityExpired(expires_at=20L, observed_at=20L) => ()
    _ => fail("expected exact expiry error")
  } noraise {
    _ => fail("expected exact expiry error")
  }
}
