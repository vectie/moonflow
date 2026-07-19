///|
/// Only exact known generic failures and reconciled not-applied may be eligible.
pub(all) enum RetryabilityDecision {
  KnownFailureClass(String)
  ReconciledNotApplied
  UnknownOutcome
  MissingReceipt
  ObservationTimeout
  ProcessCrash
  LeaseExpired
  ElapsedTimeOnly
} derive(Eq, Debug)

///|
pub struct RetryPolicy {
  record_version : @contracts.Version
  policy_ref : @contracts.RecordRef
  maximum_attempt_count : Int64
  maximum_retry_count : Int64
  base_delay : Int64
  maximum_delay : Int64
  backoff_numerator : Int64
  backoff_denominator : Int64
  jitter_range : Int64
  seed : @contracts.ContentDigest
  retryable_failure_classes : ReadOnlyArray[String]
  canonical : Bytes
}

///|
pub fn RetryPolicy::new(
  policy_id : String,
  policy_version : String,
  maximum_attempt_count : Int64,
  maximum_retry_count : Int64,
  base_delay : Int64,
  maximum_delay : Int64,
  backoff_numerator : Int64,
  backoff_denominator : Int64,
  jitter_range : Int64,
  seed : @contracts.ContentDigest,
  retryable_failure_classes : Array[String],
) -> RetryPolicy raise OrchestrationError {
  require_version(policy_version, "retry_policy")
  require_text(policy_id, "retry_policy_id")
  if maximum_attempt_count <= 0L || maximum_attempt_count > 10000L {
    raise RetryBoundViolation(field="maximum_attempt_count")
  }
  if maximum_retry_count < 0L || maximum_retry_count >= maximum_attempt_count {
    raise RetryBoundViolation(field="maximum_retry_count")
  }
  require_non_negative(base_delay, "base_delay")
  require_non_negative(maximum_delay, "maximum_delay")
  if base_delay > maximum_delay {
    raise RetryBoundViolation(field="base_delay_above_maximum")
  }
  if backoff_numerator <= 0L || backoff_denominator <= 0L {
    raise RetryBoundViolation(field="backoff_ratio")
  }
  require_non_negative(jitter_range, "jitter_range")
  if jitter_range > maximum_delay || jitter_range == int64_max {
    raise RetryBoundViolation(field="jitter_range")
  }
  let classes = retryable_failure_classes.copy()
  for index, value in classes {
    require_text(value, "retryable_failure_class")
    if classes[:index].any(prior => prior == value) {
      raise RetryClassificationViolation(field="duplicate_failure_class")
    }
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"MF7ARETRY1")
  writer.string(policy_version)
  writer.string(policy_id)
  writer.int64(maximum_attempt_count)
  writer.int64(maximum_retry_count)
  writer.int64(base_delay)
  writer.int64(maximum_delay)
  writer.int64(backoff_numerator)
  writer.int64(backoff_denominator)
  writer.int64(jitter_range)
  writer.string(seed.text())
  writer.count(classes.length())
  for value in classes {
    writer.string(value)
  }
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_version: orchestration_version(),
    policy_ref: self_ref("orchestration-retry-policy", policy_id, digest),
    maximum_attempt_count,
    maximum_retry_count,
    base_delay,
    maximum_delay,
    backoff_numerator,
    backoff_denominator,
    jitter_range,
    seed,
    retryable_failure_classes: ReadOnlyArray::from_array(classes),
    canonical,
  }
}

///|
pub fn RetryPolicy::policy_ref(self : RetryPolicy) -> @contracts.RecordRef {
  self.policy_ref
}

///|
pub fn RetryPolicy::maximum_attempt_count(self : RetryPolicy) -> Int64 {
  self.maximum_attempt_count
}

///|
pub fn RetryPolicy::maximum_retry_count(self : RetryPolicy) -> Int64 {
  self.maximum_retry_count
}

///|
pub fn RetryPolicy::seed(self : RetryPolicy) -> @contracts.ContentDigest {
  self.seed
}

///|
pub fn RetryPolicy::canonical_bytes(self : RetryPolicy) -> Bytes {
  self.canonical
}

///|
pub fn RetryPolicy::binding_digest(
  self : RetryPolicy,
) -> @contracts.ContentDigest {
  self.policy_ref.digest()
}

///|
pub fn RetryPolicy::allows(
  self : RetryPolicy,
  decision : RetryabilityDecision,
) -> Bool {
  match decision {
    KnownFailureClass(value) =>
      self.retryable_failure_classes.any(candidate => candidate == value)
    ReconciledNotApplied => true
    UnknownOutcome
    | MissingReceipt
    | ObservationTimeout
    | ProcessCrash
    | LeaseExpired
    | ElapsedTimeOnly => false
  }
}

///|
fn hex_value(value : UInt16) -> Int64 raise OrchestrationError {
  if value >= ('0' : UInt16) && value <= ('9' : UInt16) {
    (value.to_int() - ('0' : UInt16).to_int()).to_int64()
  } else if value >= ('a' : UInt16) && value <= ('f' : UInt16) {
    (value.to_int() - ('a' : UInt16).to_int() + 10).to_int64()
  } else {
    raise DigestMismatch(field="retry_hash_hex")
  }
}

///|
fn deterministic_jitter(
  policy : RetryPolicy,
  schedule_ref : @contracts.RecordRef,
  prior_attempt_ordinal : Int64,
) -> Int64 raise OrchestrationError {
  if policy.jitter_range == 0L {
    return 0L
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"MF7AJITTER1")
  writer.bytes(policy.canonical_bytes())
  write_ref(writer, schedule_ref)
  writer.int64(prior_attempt_ordinal)
  writer.string(policy.seed.text())
  let hex = @contracts.sha256_digest(writer.finish()).hex()
  let mut value = 0L
  for index in 0..<15 {
    value = value * 16L + hex_value(hex[index])
  }
  value % (policy.jitter_range + 1L)
}

///|
pub struct RetryTiming {
  prior_attempt_ordinal : Int64
  retry_ordinal : Int64
  nominal_delay : Int64
  jitter : Int64
  delay : Int64
  eligible_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn RetryTiming::compute(
  policy : RetryPolicy,
  schedule_ref : @contracts.RecordRef,
  prior_attempt_ordinal : Int64,
  prior_retry_count : Int64,
  clock : ClockInput,
) -> RetryTiming raise OrchestrationError {
  if prior_attempt_ordinal <= 0L ||
    prior_attempt_ordinal >= policy.maximum_attempt_count {
    raise RetryBoundViolation(field="attempt_ordinal")
  }
  if prior_retry_count < 0L || prior_retry_count >= policy.maximum_retry_count {
    raise RetryBoundViolation(field="retry_count")
  }
  let mut nominal = policy.base_delay
  for _ in 1L..<prior_attempt_ordinal {
    let product = checked_multiply_non_negative(
      nominal,
      policy.backoff_numerator,
      "retry_backoff_multiply",
    )
    nominal = product / policy.backoff_denominator
    if nominal >= policy.maximum_delay {
      nominal = policy.maximum_delay
      break
    }
  }
  let jitter = deterministic_jitter(policy, schedule_ref, prior_attempt_ordinal)
  let combined = checked_add_non_negative(nominal, jitter, "retry_delay")
  let delay = Int64::min(combined, policy.maximum_delay)
  let eligible_at = checked_add_non_negative(
    clock.logical_instant(),
    delay,
    "retry_eligible_at",
  )
  let writer = OrchestrationWriter::new()
  writer.bytes(b"MF7ATIMING1")
  writer.bytes(policy.canonical_bytes())
  write_ref(writer, schedule_ref)
  writer.int64(prior_attempt_ordinal)
  writer.int64(prior_retry_count + 1L)
  writer.int64(nominal)
  writer.int64(jitter)
  writer.int64(delay)
  writer.int64(eligible_at)
  writer.bytes(clock.canonical_bytes())
  let canonical = writer.finish()
  {
    prior_attempt_ordinal,
    retry_ordinal: prior_retry_count + 1L,
    nominal_delay: nominal,
    jitter,
    delay,
    eligible_at,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn RetryTiming::retry_ordinal(self : RetryTiming) -> Int64 {
  self.retry_ordinal
}

///|
pub fn RetryTiming::nominal_delay(self : RetryTiming) -> Int64 {
  self.nominal_delay
}

///|
pub fn RetryTiming::jitter(self : RetryTiming) -> Int64 {
  self.jitter
}

///|
pub fn RetryTiming::delay(self : RetryTiming) -> Int64 {
  self.delay
}

///|
pub fn RetryTiming::eligible_at(self : RetryTiming) -> Int64 {
  self.eligible_at
}

///|
pub fn RetryTiming::canonical_bytes(self : RetryTiming) -> Bytes {
  self.canonical
}

///|
pub fn RetryTiming::binding_digest(
  self : RetryTiming,
) -> @contracts.ContentDigest {
  self.digest
}
