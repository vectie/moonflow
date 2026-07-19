///|
test "FLOW-7A native filesystem restart matches memory authoritative projection" {
  let fixture = orchestration_fixture("native-parity")
  let initial_catalog = catalog([], [], [])
  let absent = projection(fixture, initial_catalog)
  let schedule = ScheduleIntent::new(
    "schedule-native",
    "1.0.0",
    fixture.workflow,
    fixture.policy.policy_ref(),
    fixture.intent.governance().governed_subject(),
    fixture.intent.governance(),
    fixture.intent,
    fixture.effects,
    100L,
    Some(200L),
    fixture.evidence,
    fixture.intent.intent_ref(),
    "schedule-native-key",
    previous_digest=absent.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_schedule_event(absent, "schedule-native-event", schedule),
    "schedule-native-command",
  )
  let after_schedule = projection(fixture, catalog([schedule], [], []))
  let clock = ClockInput::new(
    "clock-native",
    "1.0.0",
    fixture.workflow,
    100L,
    fixture_ref("clock-source", "native-source"),
    fixture.evidence,
    schedule.schedule_ref(),
    "clock-native-key",
    previous_digest=after_schedule.last_event_digest().unwrap(),
  )
  commit_orchestration_event(
    fixture.store,
    fixture.workflow,
    prepare_clock_event(after_schedule, "clock-native-event", clock),
    "clock-native-command",
  )
  let memory = projection(fixture, catalog([schedule], [clock], []))
  let memory_replay = fixture.store.replay(fixture.workflow)
  let root = flow7_native_fixture_root()
  let relative = flow7_native_fixture_relative()
  let filesystem = @storage.FileSystemStore::open(root, relative)
  assert_eq(filesystem.head(fixture.workflow).event_count(), 0L)
  ignore(
    filesystem.commit(
      @storage.CommitRequest::new(
        "1.0.0",
        "1.0.0",
        fixture.workflow,
        0L,
        "flow7a-native-complete-history",
        [
          for event in memory_replay.events() => event
        ],
        [
          for intent in memory_replay.intents() => intent
        ],
      ),
    ),
  )
  let restarted = @storage.FileSystemStore::open(root, relative)
  let replay = restarted.replay(fixture.workflow)
  let effects = @effects.fold_authoritative_replay(
    @effects.EffectsProjection::new(
      fixture.workflow,
      fixture.policy.policy_ref(),
    ),
    replay,
    @effects.ReplayCatalog::new(
      [fixture.attempt],
      [fixture.intent],
      [],
      [],
      [],
      [],
    ),
  )
  let recovered = fold_orchestration_replay(
    OrchestrationProjection::new(fixture.workflow, fixture.policy.policy_ref()),
    replay,
    catalog([schedule], [clock], []),
    effects,
  )
  assert_true(recovered.canonical_bytes() == memory.canonical_bytes())
  assert_true(recovered.state_digest() == memory.state_digest())
  assert_true(replay.replay_digest() == memory_replay.replay_digest())
  assert_true(recovered.state() is DueUnclaimed)
}
