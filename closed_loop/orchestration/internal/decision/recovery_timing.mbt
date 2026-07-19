///|
/// Closed result for deterministic recovery timing. The facade translates
/// these values into stable orchestration errors and never accepts a caller-
/// supplied due instant.
pub(all) enum RecoveryTimingResult {
  RecoveryDueAt(Int64)
  RecoveryTimingInvalidInput
  RecoveryTimingDelayOverflow
  RecoveryTimingJitterOverflow
  RecoveryTimingInstantOverflow
} derive(Eq, Debug)

///|
/// Compute one replay-derived recovery due instant. `attempt_ordinal` is
/// one-based; the first retry uses the base delay. Jitter is deterministic and
/// symmetric in `[-jitter_range, +jitter_range]`.
pub fn recovery_due_at(
  base_instant : Int64,
  base_delay : Int64,
  maximum_delay : Int64,
  backoff_numerator : Int64,
  backoff_denominator : Int64,
  attempt_ordinal : Int64,
  jitter_range : Int64,
  jitter_material : Bytes,
) -> RecoveryTimingResult {
  if base_instant < 0L || attempt_ordinal <= 0L || jitter_range < 0L {
    return RecoveryTimingInvalidInput
  }
  let delay = match
    retry_nominal_delay(
      base_delay,
      maximum_delay,
      backoff_numerator,
      backoff_denominator,
      attempt_ordinal - 1L,
    ) {
    NominalDelay(value) => value
    InvalidInput => return RecoveryTimingInvalidInput
    NumeratorOverflow | DenominatorOverflow | OrdinalOverflow =>
      return RecoveryTimingDelayOverflow
  }
  let doubled = match @base.checked_multiply_non_negative(jitter_range, 2L) {
    Value(value) => value
    Negative => return RecoveryTimingInvalidInput
    Overflow => return RecoveryTimingJitterOverflow
  }
  let span = match @base.checked_add_non_negative(doubled, 1L) {
    Value(value) => value
    Negative => return RecoveryTimingInvalidInput
    Overflow => return RecoveryTimingJitterOverflow
  }
  guard hash_mod(jitter_material, span) is Some(bucket) else {
    return RecoveryTimingInvalidInput
  }
  let jitter = bucket - jitter_range
  let delayed = match @base.checked_add_non_negative(base_instant, delay) {
    Value(value) => value
    Negative => return RecoveryTimingInvalidInput
    Overflow => return RecoveryTimingInstantOverflow
  }
  if jitter >= 0L {
    match @base.checked_add_non_negative(delayed, jitter) {
      Value(value) => RecoveryDueAt(value)
      Negative => RecoveryTimingInvalidInput
      Overflow => RecoveryTimingInstantOverflow
    }
  } else {
    let magnitude = 0L - jitter
    if delayed < magnitude {
      RecoveryTimingInvalidInput
    } else {
      RecoveryDueAt(delayed - magnitude)
    }
  }
}

///|
/// Compute the immutable elapsed-time deadline from the original dispatch
/// point of no return.
pub fn recovery_deadline(
  dispatch_started_at : Int64,
  maximum_elapsed : Int64,
) -> RecoveryTimingResult {
  if dispatch_started_at < 0L || maximum_elapsed < 0L {
    return RecoveryTimingInvalidInput
  }
  match @base.checked_add_non_negative(dispatch_started_at, maximum_elapsed) {
    Value(value) => RecoveryDueAt(value)
    Negative => RecoveryTimingInvalidInput
    Overflow => RecoveryTimingInstantOverflow
  }
}
