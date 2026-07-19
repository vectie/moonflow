///|
fn phase1c_b_native_require_restart_race(
  label : String,
  prefix : @storage.ReplayResult,
  candidate : LifecycleCommitCandidateV2,
  candidate_governance : @storage.ReplayResult,
  cancellation : LifecycleCommitCandidateV2,
  cancellation_governance : @storage.ReplayResult,
  candidate_reason : LifecycleRaceLossReasonV2,
) -> Unit raise {
  for candidate_first in [true, false] {
    let root = phase1b_native_fixture_root()
    let work_relative = phase1b_native_fixture_relative()
    let governance_relative = phase1b_native_fixture_relative()
    let work_writer = @storage.FileSystemStore::open(root, work_relative)
    let governance_writer = @storage.FileSystemStore::open(
      root, governance_relative,
    )
    let actual_governance = if candidate_first {
      candidate_governance
    } else {
      cancellation_governance
    }
    phase1b_copy_replay_to_filesystem(prefix, work_writer)
    phase1b_copy_replay_to_filesystem(actual_governance, governance_writer)
    let activation = work_writer.activate_guarded_workflow(
      candidate.request.workflow(),
      [governance_writer],
      [
        for head_guard in candidate.guarded_request.guards() => {
          head_guard.workflow()
        }
      ],
    )
    let first_restart = @storage.RegistryBoundFileSystemStore::new(
      @storage.FileSystemStore::open(root, work_relative),
      activation,
    )
    let winner = if candidate_first {
      commit_lifecycle_candidate_v2(first_restart, candidate)
    } else {
      commit_lifecycle_candidate_v2(first_restart, cancellation)
    }
    guard winner is LifecycleCommittedV2(committed) else {
      fail("filesystem race winner missing: " + label)
    }
    let second_restart = @storage.RegistryBoundFileSystemStore::new(
      @storage.FileSystemStore::open(root, work_relative),
      activation,
    )
    let loser = if candidate_first {
      commit_lifecycle_candidate_v2(second_restart, cancellation)
    } else {
      commit_lifecycle_candidate_v2(second_restart, candidate)
    }
    let filesystem_replay = second_restart.replay(prefix.workflow())
    committed.validate_replay_binding(filesystem_replay)

    let memory = phase1c_b_combined_memory_store(prefix, actual_governance)
    let memory_winner = if candidate_first {
      phase1c_b_commit_memory(memory, candidate)
    } else {
      phase1c_b_commit_memory(memory, cancellation)
    }
    guard memory_winner is LifecycleCommittedV2(memory_committed) else {
      fail("memory parity winner missing: " + label)
    }
    let memory_loser = if candidate_first {
      phase1c_b_commit_memory(memory, cancellation)
    } else {
      phase1c_b_commit_memory(memory, candidate)
    }
    assert_true(
      committed.canonical_bytes() == memory_committed.canonical_bytes(),
    )
    assert_true(committed.digest() == memory_committed.digest())
    if candidate_governance.replay_digest() ==
      cancellation_governance.replay_digest() {
      guard loser is LifecycleLostV2(loss) &&
        memory_loser is LifecycleLostV2(memory_loss) else {
        fail("work-head race loser missing: " + label)
      }
      let expected_reason = if candidate_first {
        candidate_reason
      } else {
        LostToCancellationRequestV2
      }
      assert_true(loss.reason() == expected_reason)
      loss.validate_replay_binding(filesystem_replay)
      loss.validate_current(filesystem_replay)
      assert_true(loss.canonical_bytes() == memory_loss.canonical_bytes())
      assert_true(loss.digest() == memory_loss.digest())
    } else {
      guard loser is LifecycleStaleGovernanceV2(stale) &&
        memory_loser is LifecycleStaleGovernanceV2(memory_stale) else {
        fail("governance-head race loser missing: " + label)
      }
      stale.validate_current(actual_governance)
      memory_stale.validate_current(actual_governance)
      assert_true(stale.canonical_bytes() == memory_stale.canonical_bytes())
      assert_true(stale.digest() == memory_stale.digest())
    }
    assert_true(
      filesystem_replay.replay_digest() ==
      memory.replay(prefix.workflow()).replay_digest(),
    )
  }
}

///|
test "FLOW-7 Phase1C-B filesystem restart parity covers lifecycle race families" {
  let claim_fixture = phase1b_fixture(
    suffix="phase1c-b-native-claim",
    expires_at=Some(100L),
  )
  let claim_prefix = claim_fixture.work_store.replay(
    claim_fixture.registration.workflow(),
  )
  let (claim, _) = phase1c_b_lease_claim_candidate(
    claim_fixture, "native-claim",
  )
  let claim_cancellation = prepare_lifecycle_cancellation_candidate_v2(
    claim_fixture.current,
    claim_fixture.request,
  )
  phase1c_b_native_require_restart_race(
    "lease-claim",
    claim_prefix,
    claim,
    claim_fixture.governance.store.replay(
      claim_fixture.current.root_binding.governance_stream_ref(),
    ),
    claim_cancellation,
    claim_fixture.governance.store.replay(
      claim_fixture.current.root_binding.governance_stream_ref(),
    ),
    LostToLeaseClaimV2,
  )

  let reconciliation = phase1c_b_reconciliation("native")
  let reconciliation_current = fold_governed_closed_loop_v2(
    reconciliation.fixture.empty_effects,
    reconciliation.request_prefix,
    reconciliation.governance_replay,
  )
  let reconciliation_cancellation = phase1c_b_prepare_cancellation(
    reconciliation_current,
    reconciliation.fixture.empty_effects,
    reconciliation.request_prefix,
    reconciliation.fixture.registration,
    reconciliation.fixture.intent.governance().governed_subject(),
    "native-reconciliation",
  )
  phase1c_b_native_require_restart_race(
    "reconciliation-request",
    reconciliation.request_prefix,
    reconciliation.request_candidate,
    reconciliation.governance_replay,
    lifecycle_candidate_from_prepared_cancellation_v22(
      reconciliation_cancellation.prepared,
      reconciliation_cancellation.current,
    ),
    reconciliation_cancellation.governance_replay,
    LostToReconciliationRequestV2,
  )
  let resolution_current = fold_governed_closed_loop_v2(
    reconciliation.fixture.empty_effects,
    reconciliation.resolution_prefix,
    reconciliation.governance_replay,
  )
  let resolution_cancellation = phase1c_b_prepare_cancellation(
    resolution_current,
    reconciliation.fixture.empty_effects,
    reconciliation.resolution_prefix,
    reconciliation.fixture.registration,
    reconciliation.fixture.intent.governance().governed_subject(),
    "native-reconciliation-resolution",
  )
  phase1c_b_native_require_restart_race(
    "reconciliation-resolution",
    reconciliation.resolution_prefix,
    reconciliation.resolution_candidate,
    reconciliation.governance_replay,
    lifecycle_candidate_from_prepared_cancellation_v22(
      resolution_cancellation.prepared,
      resolution_cancellation.current,
    ),
    resolution_cancellation.governance_replay,
    LostToReconciliationResolutionV2,
  )

  let retry = phase1c_b_atomic_retry("native")
  let retry_prefix = retry.outcome.fixture.work_store.replay(
    retry.outcome.fixture.registration.workflow(),
  )
  let retry_cancellation = phase1c_b_prepare_cancellation(
    retry.outcome.current,
    retry.outcome.fixture.empty_effects,
    retry_prefix,
    retry.outcome.fixture.registration,
    retry.outcome.fixture.intent.governance().governed_subject(),
    "native-retry",
  )
  phase1c_b_native_require_restart_race(
    "atomic-retry",
    retry_prefix,
    retry.candidate,
    retry.outcome.governance_replay,
    lifecycle_candidate_from_prepared_cancellation_v22(
      retry_cancellation.prepared,
      retry_cancellation.current,
    ),
    retry_cancellation.governance_replay,
    LostToAtomicRetryCommitV2,
  )

  let lease = phase1c_b_lease_lifecycle("native")
  let lease_cancellation = phase1c_b_prepare_cancellation(
    lease.expiry_current,
    lease.fixture.empty_effects,
    lease.expiry_prefix,
    lease.fixture.registration,
    lease.fixture.registration
    .schedule()
    .admission()
    .governance()
    .governed_subject(),
    "native-expiry",
  )
  phase1c_b_native_require_restart_race(
    "lease-expiry",
    lease.expiry_prefix,
    lease.expiry_candidate,
    lease.governance_replay,
    lifecycle_candidate_from_prepared_cancellation_v22(
      lease_cancellation.prepared,
      lease_cancellation.current,
    ),
    lease_cancellation.governance_replay,
    LostToLeaseExpiryV2,
  )
  let reclaim_cancellation = phase1c_b_prepare_cancellation(
    lease.reclaim_current,
    lease.fixture.empty_effects,
    lease.reclaim_prefix,
    lease.fixture.registration,
    lease.fixture.registration
    .schedule()
    .admission()
    .governance()
    .governed_subject(),
    "native-reclaim",
  )
  phase1c_b_native_require_restart_race(
    "lease-reclaim",
    lease.reclaim_prefix,
    lease.reclaim_candidate,
    lease.governance_replay,
    lifecycle_candidate_from_prepared_cancellation_v22(
      reclaim_cancellation.prepared,
      reclaim_cancellation.current,
    ),
    reclaim_cancellation.governance_replay,
    LostToLeaseReclaimV2,
  )
}

///|
test "FLOW-7 Phase1C-B filesystem historical loss survives later append" {
  let fixture = phase1b_fixture(
    suffix="phase1c-b-native-history",
    expires_at=Some(100L),
  )
  let prefix = fixture.work_store.replay(fixture.registration.workflow())
  let (claim, _) = phase1c_b_lease_claim_candidate(fixture, "native-history")
  let cancellation = prepare_lifecycle_cancellation_candidate_v2(
    fixture.current,
    fixture.request,
  )
  let root = phase1b_native_fixture_root()
  let work_relative = phase1b_native_fixture_relative()
  let governance_relative = phase1b_native_fixture_relative()
  let governance_replay = fixture.governance.store.replay(
    fixture.current.root_binding.governance_stream_ref(),
  )
  phase1b_copy_replay_to_filesystem(
    prefix,
    @storage.FileSystemStore::open(root, work_relative),
  )
  phase1b_copy_replay_to_filesystem(
    governance_replay,
    @storage.FileSystemStore::open(root, governance_relative),
  )
  let work = @storage.FileSystemStore::open(root, work_relative)
  let governance = @storage.FileSystemStore::open(root, governance_relative)
  let activation = work.activate_guarded_workflow(
    claim.request.workflow(),
    [governance],
    [
      for head_guard in claim.guarded_request.guards() => head_guard.workflow()
    ],
  )
  let winner_restart = @storage.RegistryBoundFileSystemStore::new(
    @storage.FileSystemStore::open(root, work_relative),
    activation,
  )
  ignore(commit_lifecycle_candidate_v2(winner_restart, claim))
  let loser_restart = @storage.RegistryBoundFileSystemStore::new(
    @storage.FileSystemStore::open(root, work_relative),
    activation,
  )
  guard commit_lifecycle_candidate_v2(loser_restart, cancellation)
    is LifecycleLostV2(first_loss) else {
    fail("filesystem historical first loss missing")
  }
  let claimed = fold_governed_closed_loop_v2(
    fixture.empty_effects,
    loser_restart.replay(fixture.registration.workflow()),
    fixture.governance.store.replay(
      fixture.current.root_binding.governance_stream_ref(),
    ),
  )
  guard claimed.committed_lease_authority_receipt_v2() is Some(lease_receipt) else {
    fail("filesystem historical lease receipt missing")
  }
  let release = LeaseReleaseV2::new(
    "phase1c-b-native-history-release",
    fixture.registration,
    lease_receipt,
    flow7_lifecycle_active_authorization(
      "phase1c-b-native-history-release",
      claimed.work.orchestration(),
      fixture.registration,
      lease_receipt,
      ReleaseLeaseV2,
      None,
      12L,
    ),
  )
  let authorization = claimed.authorize_lease_settlement_v2(
    "lease.release",
    release.record_ref(),
  )
  let release_request = prepare_guarded_lease_released_v2(
    claimed,
    authorization,
    "phase1c-b-native-history-release-event",
    release.idempotency_key(),
    "phase1c-b-native-history-release-command",
    release,
  )
  guard loser_restart.guarded_commit(
      phase1c_b_guarded_test_request(claimed, release_request),
    )
    is @storage.GuardedCommitSucceeded(_) else {
    fail("filesystem historical guarded release missing")
  }
  let append_restart = @storage.RegistryBoundFileSystemStore::new(
    @storage.FileSystemStore::open(root, work_relative),
    activation,
  )
  let replay = append_restart.replay(fixture.registration.workflow())
  first_loss.validate_replay_binding(replay)
  try first_loss.validate_current(replay) catch {
    RecoveryViolation(field="lifecycle_race_receipt_not_current") => ()
    error =>
      fail("unexpected filesystem historical currentness: \{to_repr(error)}")
  } noraise {
    _ => fail("filesystem historical loss remained current")
  }
  guard commit_lifecycle_candidate_v2(append_restart, cancellation)
    is LifecycleLostV2(duplicate_loss) else {
    fail("filesystem historical duplicate loss missing")
  }
  assert_true(first_loss.canonical_bytes() == duplicate_loss.canonical_bytes())
  assert_true(first_loss.digest() == duplicate_loss.digest())
}
