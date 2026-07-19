///|
#borrow(status)
extern "c" fn flow7_native_temporary_root(status : Ref[Int]) -> Bytes = "moonflow_storage_native_temporary_root"

///|
extern "c" fn flow7_native_unique_suffix() -> Bytes = "moonflow_storage_native_unique_suffix"

///|
fn flow7_native_fixture_root() -> String {
  let status = Ref(0)
  let bytes = flow7_native_temporary_root(status)
  if status.val != 0 {
    abort("temporary root unavailable")
  }
  try! @utf8.decode(bytes)
}

///|
fn flow7_native_fixture_relative() -> String {
  try! @utf8.decode(flow7_native_unique_suffix())
}

///|
struct Flow7NativeRestartOracle {
  workflow : @contracts.RecordRef
  projection_canonical : Bytes
  projection_digest : @contracts.ContentDigest
  lease_owner : @contracts.RecordRef
  receipt_canonical : Bytes
  receipt_ref : @contracts.RecordRef
  receipt_digest : @contracts.ContentDigest
}

///|
fn flow7_write_fresh_filesystem_history(
  root : String,
  relative : String,
) -> Flow7NativeRestartOracle raise {
  let (_, _, schedule, registered, claim, claimed) = flow7_durable_fixture()
  let writer = @storage.FileSystemStore::open(root, relative)
  assert_eq(writer.head(schedule.workflow()).event_count(), 0L)
  let empty = writer.replay(schedule.workflow())
  assert_eq(empty.head().revision(), 0L)
  ignore(
    commit_orchestration_v2(
      writer,
      flow7_prepare_initial_work_fixture(empty, registered, "flow7-v2-native"),
    ),
  )
  let scheduled = flow7_fold_root_bound_fixture(
    writer.replay(schedule.workflow()),
  )
  ignore(
    commit_orchestration_v2(
      writer,
      prepare_lease_claimed_v2(
        scheduled,
        "flow7-v2-native-lease-event",
        claim.idempotency_key(),
        "flow7-v2-native-lease-command",
        claimed,
      ),
    ),
  )
  let committed = flow7_fold_root_bound_fixture(
    writer.replay(schedule.workflow()),
  )
  guard committed.committed_lease_authority_receipt() is Some(receipt) else {
    fail("expected writer receipt")
  }
  {
    workflow: schedule.workflow(),
    projection_canonical: committed.canonical_bytes(),
    projection_digest: committed.state_digest(),
    lease_owner: receipt.owner(),
    receipt_canonical: receipt.canonical_bytes(),
    receipt_ref: receipt.receipt_ref(),
    receipt_digest: receipt.digest(),
  }
}

///|
test "FLOW-7 V2 fresh filesystem store replays after a real writer restart" {
  let root = flow7_native_fixture_root()
  let relative = flow7_native_fixture_relative()
  // The write helper owns and drops the writer store, fixture records,
  // projection, and receipt. Recovery receives only a fresh store, workflow
  // identity, and immutable canonical oracle values.
  let oracle = flow7_write_fresh_filesystem_history(root, relative)
  let restarted = @storage.FileSystemStore::open(root, relative)
  let recovered = flow7_fold_root_bound_fixture(
    restarted.replay(oracle.workflow),
  )
  assert_true(recovered.canonical_bytes() == oracle.projection_canonical)
  assert_true(recovered.state_digest() == oracle.projection_digest)
  assert_eq(recovered.schedule_count(), 1)
  assert_eq(recovered.lease_count(), 1)
  assert_eq(recovered.epoch_floor(), 1L)
  assert_eq(recovered.fencing_floor(), 1L)
  assert_true(recovered.lease_owner() == Some(oracle.lease_owner))
  guard recovered.committed_lease_authority_receipt() is Some(recovered_receipt) else {
    fail("expected restarted receipt")
  }
  assert_true(recovered_receipt.canonical_bytes() == oracle.receipt_canonical)
  assert_true(recovered_receipt.receipt_ref() == oracle.receipt_ref)
  assert_true(recovered_receipt.digest() == oracle.receipt_digest)
  recovered_receipt.validate_current(recovered, 10L)
}

///|
struct Flow7NativeLifecycleOracle {
  workflow : @contracts.RecordRef
  projection_canonical : Bytes
  projection_digest : @contracts.ContentDigest
  sequence : Int64
  revision : Int64
}

///|
fn flow7_write_filesystem_to_terminal(
  root : String,
  relative : String,
) -> @contracts.RecordRef raise {
  let fixture = flow7_lifecycle_fixture("flow7-native-lifecycle")
  let writer = @storage.FileSystemStore::open(root, relative)
  let empty = writer.replay(fixture.schedule.workflow())
  ignore(
    commit_orchestration_v2(
      writer,
      flow7_prepare_initial_work_fixture(
        empty,
        fixture.registration,
        "flow7-native-lifecycle",
      ),
    ),
  )
  let scheduled = flow7_fold_root_bound_fixture(
    writer.replay(fixture.schedule.workflow()),
  )
  ignore(
    commit_orchestration_v2(
      writer,
      prepare_lease_claimed_v2(
        scheduled,
        "flow7-native-lifecycle-claim-event",
        fixture.claim.idempotency_key(),
        "flow7-native-lifecycle-claim-command",
        fixture.claimed,
      ),
    ),
  )
  let claimed = flow7_fold_root_bound_fixture(
    writer.replay(fixture.schedule.workflow()),
  )
  let initial_receipt = claimed.committed_lease_authority_receipt().unwrap()
  let renewal_authorization = flow7_lifecycle_active_authorization(
    "flow7-native-lifecycle-renewal",
    claimed,
    fixture.registration,
    initial_receipt,
    RenewLeaseV2,
    Some(6L),
    12L,
  )
  let renewal = LeaseRenewalV2::new(
    "flow7-native-lifecycle-renewal",
    fixture.registration,
    initial_receipt,
    renewal_authorization,
  )
  ignore(
    commit_orchestration_v2(
      writer,
      prepare_lease_renewed_v2(
        claimed,
        "flow7-native-lifecycle-renewal-event",
        renewal.idempotency_key(),
        "flow7-native-lifecycle-renewal-command",
        renewal,
      ),
    ),
  )
  let renewed = flow7_fold_root_bound_fixture(
    writer.replay(fixture.schedule.workflow()),
  )
  let renewed_receipt = renewed.committed_lease_authority_receipt().unwrap()
  let release_authorization = flow7_lifecycle_active_authorization(
    "flow7-native-lifecycle-release",
    renewed,
    fixture.registration,
    renewed_receipt,
    ReleaseLeaseV2,
    None,
    13L,
  )
  let release = LeaseReleaseV2::new(
    "flow7-native-lifecycle-release",
    fixture.registration,
    renewed_receipt,
    release_authorization,
  )
  ignore(
    commit_orchestration_v2(
      writer,
      prepare_lease_released_v2(
        renewed,
        "flow7-native-lifecycle-release-event",
        release.idempotency_key(),
        "flow7-native-lifecycle-release-command",
        release,
      ),
    ),
  )
  fixture.schedule.workflow()
}

///|
fn flow7_recover_terminal_and_reclaim(
  root : String,
  relative : String,
  workflow : @contracts.RecordRef,
) -> Unit raise {
  let terminal_restart = @storage.FileSystemStore::open(root, relative)
  let released = flow7_fold_root_bound_fixture(
    terminal_restart.replay(workflow),
  )
  let recovered_registration = released
    .committed_schedule_registration()
    .unwrap()
  let terminal_receipt = released.committed_lease_terminal_receipt().unwrap()
  let reclaim_owner = flow7_v2_ref(
    "owner", "native-reclaim-owner", b"native-reclaim-owner",
  )
  let reclaim_authorization = flow7_lifecycle_terminal_authorization(
    "flow7-native-lifecycle-reclaim", released, recovered_registration, terminal_receipt,
    reclaim_owner, 5L, 2L, 2L, 14L,
  )
  let reclaim = LeaseReclaimV2::new(
    "flow7-native-lifecycle-reclaim", recovered_registration, terminal_receipt, reclaim_authorization,
  )
  ignore(
    commit_orchestration_v2(
      terminal_restart,
      prepare_lease_reclaimed_v2(
        released,
        "flow7-native-lifecycle-reclaim-event",
        reclaim.idempotency_key(),
        "flow7-native-lifecycle-reclaim-command",
        reclaim,
      ),
    ),
  )
}

///|
fn flow7_write_full_filesystem_lifecycle(
  root : String,
  relative : String,
) -> Flow7NativeLifecycleOracle raise {
  // The terminal writer phase owns and drops every fixture, registration,
  // release, and proof object. Only the workflow identity crosses the restart.
  let workflow = flow7_write_filesystem_to_terminal(root, relative)
  flow7_recover_terminal_and_reclaim(root, relative, workflow)
  // Reopen again after reclaim and reconstruct expiry authority from durable
  // projection handles only.
  let successor_restart = @storage.FileSystemStore::open(root, relative)
  let reclaimed = flow7_fold_root_bound_fixture(
    successor_restart.replay(workflow),
  )
  let recovered_registration = reclaimed
    .committed_schedule_registration()
    .unwrap()
  let reclaim_receipt = reclaimed.committed_lease_authority_receipt().unwrap()
  let expiry_authorization = flow7_lifecycle_active_authorization(
    "flow7-native-lifecycle-expiry",
    reclaimed,
    recovered_registration,
    reclaim_receipt,
    ExpireLeaseV2,
    None,
    19L,
  )
  let expiry = LeaseExpiryV2::new(
    "flow7-native-lifecycle-expiry", recovered_registration, reclaim_receipt, expiry_authorization,
  )
  ignore(
    commit_orchestration_v2(
      successor_restart,
      prepare_lease_expired_v2(
        reclaimed,
        "flow7-native-lifecycle-expiry-event",
        expiry.idempotency_key(),
        "flow7-native-lifecycle-expiry-command",
        expiry,
      ),
    ),
  )
  let terminal = flow7_fold_root_bound_fixture(
    successor_restart.replay(workflow),
  )
  {
    workflow,
    projection_canonical: terminal.canonical_bytes(),
    projection_digest: terminal.state_digest(),
    sequence: terminal.sequence(),
    revision: terminal.revision(),
  }
}

///|
test "FLOW-7 V2 fresh filesystem full lease lifecycle is byte-identical after restart" {
  let root = flow7_native_fixture_root()
  let relative = flow7_native_fixture_relative()
  let oracle = flow7_write_full_filesystem_lifecycle(root, relative)
  let restarted = @storage.FileSystemStore::open(root, relative)
  let recovered = flow7_fold_root_bound_fixture(
    restarted.replay(oracle.workflow),
  )
  assert_true(recovered.canonical_bytes() == oracle.projection_canonical)
  assert_true(recovered.state_digest() == oracle.projection_digest)
  assert_eq(recovered.sequence(), oracle.sequence)
  assert_eq(recovered.revision(), oracle.revision)
  assert_eq(recovered.lease_count(), 2)
  assert_eq(recovered.epoch_floor(), 2L)
  assert_eq(recovered.fencing_floor(), 2L)
  assert_true(!recovered.has_active_lease())
  assert_true(recovered.has_terminal_lease())
  assert_true(recovered.committed_lease_authority_receipt() is None)
}
