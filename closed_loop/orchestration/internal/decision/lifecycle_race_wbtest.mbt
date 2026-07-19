///|
test "lifecycle batches require exact ordered shapes and terminal outcomes" {
  assert_true(
    classify_lifecycle_batch(["work.cancellation.requested.v2"], None) ==
    CancellationRequest,
  )
  assert_true(
    classify_lifecycle_batch(
      ["work.cancellation.requested.v2", "work.terminal.v2"],
      Some("cancelled_before_effect_intent_v2"),
    ) ==
    CancellationRequest,
  )
  assert_true(
    classify_lifecycle_batch(
      ["work.cancellation.requested.v2", "work.terminal.v2"],
      Some("succeeded_v2"),
    ) ==
    OtherDurableAdvance,
  )
  assert_true(
    classify_lifecycle_batch(
      ["attempt.registered.v1", "schedule.registered.v2"],
      None,
    ) ==
    AtomicRetryCommit,
  )
  assert_true(
    classify_lifecycle_batch(
      ["schedule.registered.v2", "attempt.registered.v1"],
      None,
    ) ==
    OtherDurableAdvance,
  )
  assert_true(
    classify_lifecycle_batch(
      ["attempt.registered.v1", "schedule.registered.v2", "lease.claimed.v2"],
      None,
    ) ==
    OtherDurableAdvance,
  )
  let terminal_cases = [
    ("succeeded_v2", SucceededTerminal),
    ("failed_non_retryable_v2", FailedNonRetryableTerminal),
    ("failed_retry_exhausted_v2", FailedRetryExhaustedTerminal),
    (
      "failed_cancellation_stopped_retry_v2",
      FailedCancellationStoppedRetryTerminal,
    ),
    ("cancelled_before_effect_intent_v2", CancelledBeforeEffectIntentTerminal),
    (
      "cancelled_after_reconciled_not_applied_v2",
      CancelledAfterReconciledNotAppliedTerminal,
    ),
  ]
  for pair in terminal_cases {
    let (outcome, expected) = pair
    assert_true(
      classify_lifecycle_batch(["work.terminal.v2"], Some(outcome)) == expected,
    )
  }
  assert_true(
    classify_lifecycle_batch(["work.terminal.v2"], None) == OtherDurableAdvance,
  )
  assert_true(
    classify_lifecycle_batch(["work.terminal.v2"], Some("future_terminal_v3")) ==
    OtherDurableAdvance,
  )
}

///|
test "recorded lifecycle race seeds deterministically cover both orders" {
  let mut saw_first = false
  let mut saw_second = false
  for seed in [3L, 7L, 19L, 31L, 73L, 211L] {
    let first = recorded_order_key(seed, 0)
    let second = recorded_order_key(seed, 1)
    assert_true(first == recorded_order_key(seed, 0))
    assert_true(second == recorded_order_key(seed, 1))
    assert_true(first != second)
    if first < second {
      saw_first = true
    } else {
      saw_second = true
    }
  }
  assert_true(saw_first)
  assert_true(saw_second)
}
