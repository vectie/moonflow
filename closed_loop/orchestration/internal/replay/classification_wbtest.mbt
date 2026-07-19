///|
test "orchestration replay kinds are closed" {
  for
    kind in [
      "schedule.registered.v2", "lease.claimed.v2", "lease.renewed.v2", "lease.released.v2",
      "lease.expired.v2", "lease.reclaimed.v2", "work.cancellation.requested.v2",
      "work.terminal.v2",
    ] {
    assert_true(is_orchestration_event_kind_v2(kind))
  }
  assert_false(is_orchestration_event_kind_v2("effect.outcome.unknown.v1"))
  assert_false(is_orchestration_event_kind_v2("work.terminal.v3"))
}

///|
test "mixed admission prefix kinds are closed" {
  assert_true(is_verified_mixed_schedule_prefix_kind_v2("EvidenceAttached"))
  assert_true(
    is_verified_mixed_schedule_prefix_kind_v2(
      "effect.reconciliation.resolved.v1",
    ),
  )
  assert_false(is_verified_mixed_schedule_prefix_kind_v2("work.terminal.v2"))
  assert_false(is_verified_mixed_schedule_prefix_kind_v2("unknown"))
}

///|
test "replay positions distinguish genesis" {
  assert_true(is_genesis_position(0L, 0L, false))
  assert_false(is_genesis_position(1L, 0L, false))
  assert_false(is_genesis_position(0L, 0L, true))
}
