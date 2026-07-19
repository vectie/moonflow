///|
/// Closed implementation categories for reviewed lifecycle batches. The public
/// facade owns the nominal API and translates these values explicitly.
pub(all) enum LifecycleBatchKind {
  CancellationRequest
  LeaseClaim
  SucceededTerminal
  FailedNonRetryableTerminal
  FailedRetryExhaustedTerminal
  FailedCancellationStoppedRetryTerminal
  CancelledBeforeEffectIntentTerminal
  CancelledAfterReconciledNotAppliedTerminal
  ReconciliationRequest
  ReconciliationResolution
  AtomicRetryCommit
  LeaseExpiry
  LeaseReclaim
  OtherDurableAdvance
} derive(Eq, Debug)

///|
/// Stable implementation reason derived from the complete winning batch.
pub(all) enum LifecycleLossKind {
  CancellationCommitted
  ClaimCommitted
  SucceededTerminalCommitted
  FailedNonRetryableTerminalCommitted
  FailedRetryExhaustedTerminalCommitted
  FailedCancellationStoppedRetryTerminalCommitted
  CancelledBeforeEffectIntentTerminalCommitted
  CancelledAfterReconciledNotAppliedTerminalCommitted
  ReconciliationRequestCommitted
  ReconciliationResolutionCommitted
  RetryCommitted
  LeaseExpiryCommitted
  LeaseReclaimCommitted
  OtherDurableAdvanceCommitted
} derive(Eq, Debug)

///|
fn exact_kinds(
  actual : ArrayView[String],
  expected : ArrayView[String],
) -> Bool {
  if actual.length() != expected.length() {
    return false
  }
  for index in 0..<actual.length() {
    if actual[index] != expected[index] {
      return false
    }
  }
  true
}

///|
/// Classify a complete committed batch. `terminal_outcome` is supplied only
/// after the facade has strictly decoded the terminal record.
pub fn classify_lifecycle_batch(
  kinds : ArrayView[String],
  terminal_outcome : String?,
) -> LifecycleBatchKind {
  if exact_kinds(kinds, ["work.cancellation.requested.v2"]) {
    return CancellationRequest
  }
  if exact_kinds(kinds, ["work.cancellation.requested.v2", "work.terminal.v2"]) &&
    terminal_outcome == Some("cancelled_before_effect_intent_v2") {
    return CancellationRequest
  }
  if exact_kinds(kinds, ["lease.claimed.v2"]) {
    return LeaseClaim
  }
  if exact_kinds(kinds, ["effect.reconciliation.requested.v1"]) {
    return ReconciliationRequest
  }
  if exact_kinds(kinds, ["effect.reconciliation.resolved.v1"]) {
    return ReconciliationResolution
  }
  if exact_kinds(kinds, ["lease.expired.v2"]) {
    return LeaseExpiry
  }
  if exact_kinds(kinds, ["lease.reclaimed.v2"]) {
    return LeaseReclaim
  }
  if exact_kinds(kinds, ["attempt.registered.v1", "schedule.registered.v2"]) {
    return AtomicRetryCommit
  }
  if exact_kinds(kinds, ["work.terminal.v2"]) {
    return match terminal_outcome {
      Some("succeeded_v2") => SucceededTerminal
      Some("failed_non_retryable_v2") => FailedNonRetryableTerminal
      Some("failed_retry_exhausted_v2") => FailedRetryExhaustedTerminal
      Some("failed_cancellation_stopped_retry_v2") =>
        FailedCancellationStoppedRetryTerminal
      Some("cancelled_before_effect_intent_v2") =>
        CancelledBeforeEffectIntentTerminal
      Some("cancelled_after_reconciled_not_applied_v2") =>
        CancelledAfterReconciledNotAppliedTerminal
      _ => OtherDurableAdvance
    }
  }
  OtherDurableAdvance
}

///|
pub fn loss_for_winner(kind : LifecycleBatchKind) -> LifecycleLossKind {
  match kind {
    CancellationRequest => CancellationCommitted
    LeaseClaim => ClaimCommitted
    SucceededTerminal => SucceededTerminalCommitted
    FailedNonRetryableTerminal => FailedNonRetryableTerminalCommitted
    FailedRetryExhaustedTerminal => FailedRetryExhaustedTerminalCommitted
    FailedCancellationStoppedRetryTerminal =>
      FailedCancellationStoppedRetryTerminalCommitted
    CancelledBeforeEffectIntentTerminal =>
      CancelledBeforeEffectIntentTerminalCommitted
    CancelledAfterReconciledNotAppliedTerminal =>
      CancelledAfterReconciledNotAppliedTerminalCommitted
    ReconciliationRequest => ReconciliationRequestCommitted
    ReconciliationResolution => ReconciliationResolutionCommitted
    AtomicRetryCommit => RetryCommitted
    LeaseExpiry => LeaseExpiryCommitted
    LeaseReclaim => LeaseReclaimCommitted
    OtherDurableAdvance => OtherDurableAdvanceCommitted
  }
}

///|
/// Deterministic command-order key used by property tests. It deliberately
/// consumes an explicit recorded seed and never reads ambient time/randomness.
pub fn recorded_order_key(seed : Int64, ordinal : Int) -> Int64 {
  hash_mod(@utf8.encode("phase1c-b:\{seed}:\{ordinal}"), 2147483647L).unwrap()
}
