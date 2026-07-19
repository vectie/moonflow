///|
fn phase2_native_copy_guarded_work_replay_v3(
  replay : @storage.ReplayResult,
  work_writer : @storage.FileSystemStore,
  governance_writer : @storage.FileSystemStore,
) -> @storage.RegistryBoundFileSystemStore raise {
  let mut bound : @storage.RegistryBoundFileSystemStore? = None
  for boundary in replay.committed_batches() {
    let events : Array[@storage.WorkflowEvent] = []
    for event_ref in boundary.event_refs() {
      guard replay.events().search_by(event => event.event_ref() == event_ref)
        is Some(index) else {
        fail("native guarded replay event missing")
      }
      events.push(replay.events()[index])
    }
    let intents : Array[@storage.OutboxIntent] = []
    for intent_ref in boundary.intent_refs() {
      guard replay
        .intents()
        .search_by(intent => intent.intent_ref() == intent_ref)
        is Some(index) else {
        fail("native guarded replay intent missing")
      }
      intents.push(replay.intents()[index])
    }
    let request = @storage.CommitRequest::new(
      replay.record_version().text(),
      replay.schema_version().text(),
      replay.workflow(),
      boundary.expected_revision(),
      boundary.command_idempotency_key(),
      events,
      intents,
    )
    if boundary.guards().is_empty() {
      if bound is Some(_) {
        fail("unguarded batch followed guarded native activation")
      }
      ignore(work_writer.commit(request))
    } else {
      if bound is None {
        let activation = work_writer.activate_guarded_workflow(
          replay.workflow(),
          [governance_writer],
          [
            for head_guard in boundary.guards() => head_guard.workflow()
          ],
        )
        bound = Some(
          @storage.RegistryBoundFileSystemStore::new(work_writer, activation),
        )
      }
      ignore(
        bound
        .unwrap()
        .guarded_commit(
          @storage.GuardedCommitRequest::new(
            request,
            [
              for head_guard in boundary.guards() => head_guard
            ],
          ),
        ),
      )
    }
  }
  guard bound is Some(value) else {
    fail("native guarded replay contained no activation boundary")
  }
  assert_true(
    value.replay(replay.workflow()).replay_digest() == replay.replay_digest(),
  )
  value
}

///|
priv struct Phase2NativeProviderSpyV3 {
  profile : ProviderRecoveryProfileV3
  work_store : @storage.RegistryBoundFileSystemStore
  governance_store : @storage.FileSystemStore
  empty_effects : @effects.EffectsProjection
  workflow : @contracts.RecordRef
  governance : @contracts.RecordRef
  calls : Ref[Int]
  durable_at_entry : Ref[Bool]
}

///|
impl GuardedEffectProviderPortV3 for Phase2NativeProviderSpyV3 with fn recovery_profile(
  self,
) {
  self.profile
}

///|
impl GuardedEffectProviderPortV3 for Phase2NativeProviderSpyV3 with fn create_guarded_effect(
  self,
  call,
) {
  let work = self.work_store.replay(self.workflow)
  let governance = self.governance_store.replay(self.governance)
  let current = fold_governed_recovery_v3(self.empty_effects, work, governance)
  guard current.current_claim_by_ref_v3(call.claim_ref()) is Some(claim) else {
    raise RecoveryViolation(field="phase2_native_spy_claim")
  }
  if work.replay_digest() != call.durable_work_replay_digest() ||
    claim.external_idempotency_key != call.external_idempotency_key() ||
    claim.fencing_token != call.fencing_token() ||
    current.state_for(claim.intent_ref) != @effects.RecoveryDispatchAttemptedV3 {
    raise RecoveryViolation(field="phase2_native_spy_durable_entry")
  }
  self.durable_at_entry.val = true
  self.calls.val = self.calls.val + 1
  ProviderCreateKnownSucceededV3(
    ProviderCreateEvidenceV3::new(
      "phase2-native-spy-provider",
      "phase2-native-spy-event",
      ProviderAppliedEvidenceV3,
      @contracts.sha256_digest(b"phase2-native-spy-body"),
      call.external_idempotency_key(),
      call.fencing_token(),
      13L,
    ),
  )
}

///|
test "Phase2 dispatch claim survives separate-root native restart" {
  let (fixture, _, work_replay, governance_replay) = phase2_active_pending_fixture(
    "native-restart",
  )
  let current = fold_governed_recovery_v3(
    fixture.empty_effects,
    work_replay,
    governance_replay,
  )
  let candidate = current.prepare_dispatch_claim_v3(
    fixture.intent.intent_ref(),
    "phase2-native-restart-claim",
    "phase2-native-restart-event",
    "phase2-native-restart-command",
    11L,
    12L,
    [
      for value in fixture.registration.schedule().evidence() => value
    ],
  )
  let root = phase1b_native_fixture_root()
  let work_relative = phase1b_native_fixture_relative()
  let governance_relative = phase1b_native_fixture_relative()
  let work_writer = @storage.FileSystemStore::open(root, work_relative)
  let governance_writer = @storage.FileSystemStore::open(
    root, governance_relative,
  )
  phase1b_copy_replay_to_filesystem(governance_replay, governance_writer)
  let first = phase2_native_copy_guarded_work_replay_v3(
    work_replay, work_writer, governance_writer,
  )
  guard commit_dispatch_claim_v3(first, candidate)
    is DispatchClaimFreshlyCommittedV3(first_receipt) else {
    fail("native dispatch claim was not freshly committed")
  }
  let restarted_work_store = @storage.FileSystemStore::open(root, work_relative)
  let restarted_governance_store = @storage.FileSystemStore::open(
    root, governance_relative,
  )
  let restarted_activation = restarted_work_store.activate_guarded_workflow(
    candidate.request.workflow(),
    [restarted_governance_store],
    [
      for head_guard in candidate.guarded_request.guards() => {
        head_guard.workflow()
      }
    ],
  )
  let restarted = @storage.RegistryBoundFileSystemStore::new(
    restarted_work_store, restarted_activation,
  )
  guard commit_dispatch_claim_v3(restarted, candidate)
    is DispatchClaimAlreadyCommittedV3(restarted_receipt) else {
    fail("native dispatch claim retry was not already committed")
  }
  assert_true(
    first_receipt.canonical_bytes() == restarted_receipt.canonical_bytes(),
  )
  let restarted_work = restarted.replay(fixture.registration.workflow())
  let restarted_governance = @storage.FileSystemStore::open(
    root, governance_relative,
  ).replay(fixture.current.root_binding.governance_stream_ref())
  let restarted_current = fold_governed_recovery_v3(
    fixture.empty_effects,
    restarted_work,
    restarted_governance,
  )
  first_receipt.validate_replay_binding(
    fixture.empty_effects,
    restarted_work,
    restarted_governance,
  )
  first_receipt.validate_current(restarted_current, 11L)
  assert_true(
    restarted_current.state_for(fixture.intent.intent_ref()) ==
    @effects.RecoveryDispatchAttemptedV3,
  )
}

///|
test "Phase2 guarded provider dispatch is durable across separate-root native restart" {
  let (fixture, _, memory_work, memory_governance) = phase2_active_pending_fixture(
    "native-guarded-dispatch",
  )
  let root = phase1b_native_fixture_root()
  let work_relative = phase1b_native_fixture_relative()
  let governance_relative = phase1b_native_fixture_relative()
  let work_writer = @storage.FileSystemStore::open(root, work_relative)
  let governance_writer = @storage.FileSystemStore::open(
    root, governance_relative,
  )
  phase1b_copy_replay_to_filesystem(memory_governance, governance_writer)
  let bound = phase2_native_copy_guarded_work_replay_v3(
    memory_work, work_writer, governance_writer,
  )
  let current = fold_governed_recovery_v3(
    fixture.empty_effects,
    bound.replay(fixture.registration.workflow()),
    governance_writer.replay(memory_governance.workflow()),
  )
  let profile = ProviderRecoveryProfileV3::new(
    "phase2-test-profile-native-guarded-dispatch", true, true, true, true,
  )
  let spy = Phase2NativeProviderSpyV3::{
    profile,
    work_store: bound,
    governance_store: governance_writer,
    empty_effects: fixture.empty_effects,
    workflow: fixture.registration.workflow(),
    governance: memory_governance.workflow(),
    calls: Ref(0),
    durable_at_entry: Ref(false),
  }
  let first_result = dispatch_guarded_effect_v3(
    bound,
    current,
    spy,
    fixture.intent.intent_ref(),
    "phase2-native-guarded-claim",
    "phase2-native-guarded-claim-event",
    "phase2-native-guarded-command",
    "phase2-native-guarded-observation",
    11L,
    12L,
    13L,
  )
  assert_true(first_result.observation_persisted())
  assert_eq(spy.calls.val, 1)
  assert_true(spy.durable_at_entry.val)
  let restarted_work = @storage.FileSystemStore::open(root, work_relative)
  let restarted_governance = @storage.FileSystemStore::open(
    root, governance_relative,
  )
  let activation = restarted_work.activate_guarded_workflow(
    fixture.registration.workflow(),
    [restarted_governance],
    [memory_governance.workflow()],
  )
  let restarted = @storage.RegistryBoundFileSystemStore::new(
    restarted_work, activation,
  )
  let retry_result = dispatch_guarded_effect_v3(
    restarted,
    current,
    spy,
    fixture.intent.intent_ref(),
    "phase2-native-guarded-claim",
    "phase2-native-guarded-claim-event",
    "phase2-native-guarded-command",
    "phase2-native-guarded-observation",
    11L,
    12L,
    13L,
  )
  assert_true(
    retry_result.disposition() == GuardedDispatchAlreadyCommittedQueryOnlyV3,
  )
  assert_eq(spy.calls.val, 1)
  let replayed = fold_governed_recovery_v3(
    fixture.empty_effects,
    restarted.replay(fixture.registration.workflow()),
    restarted_governance.replay(memory_governance.workflow()),
  )
  assert_true(
    replayed.state_for(fixture.intent.intent_ref()) ==
    @effects.RecoveryKnownSuccessV3,
  )
}
