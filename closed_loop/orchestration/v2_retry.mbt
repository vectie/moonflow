///|
pub struct RetryPolicyV2 {
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
  digest : @contracts.ContentDigest
}

///|
pub fn RetryPolicyV2::new(
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
) -> RetryPolicyV2 raise OrchestrationError {
  require_version_v2(policy_version, "retry_policy_v2")
  require_text(policy_id, "retry_policy_v2_id")
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
    if value != "terminal_failed" && value != "reconciled_not_applied" {
      raise RetryClassificationViolation(field="unsupported_failure_class")
    }
    if classes[:index].any(prior => prior == value) {
      raise RetryClassificationViolation(field="duplicate_failure_class")
    }
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/RETRY-POLICY-V2/2.0.0")
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
    policy_ref: self_ref_v2("orchestration-retry-policy-v2", policy_id, digest),
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
    digest,
  }
}

///|
pub fn RetryPolicyV2::decode(
  expected_id : String,
  bytes : Bytes,
) -> RetryPolicyV2 raise OrchestrationError {
  require_text(expected_id, "retry_policy_v2_id")
  let reader = OrchestrationReader::new(bytes)
  let tag = reader.read_bytes()
  if tag != b"FLOW7/RETRY-POLICY-V2/2.0.0" {
    raise MalformedInput(field="retry_policy_v2_tag")
  }
  let policy_version = reader.read_string()
  require_version_v2(policy_version, "retry_policy_v2")
  let policy_id = reader.read_string()
  if policy_id != expected_id {
    raise IdentityMismatch(field="retry_policy_v2_id")
  }
  let maximum_attempt_count = reader.read_int64()
  let maximum_retry_count = reader.read_int64()
  let base_delay = reader.read_int64()
  let maximum_delay = reader.read_int64()
  let backoff_numerator = reader.read_int64()
  let backoff_denominator = reader.read_int64()
  let jitter_range = reader.read_int64()
  let seed_text = reader.read_string()
  let seed = @contracts.ContentDigest::parse(seed_text) catch {
    _ => raise MalformedInput(field="retry_policy_v2_seed")
  }
  if seed.text() != seed_text {
    raise MalformedInput(field="retry_policy_v2_seed")
  }
  let class_count = reader.read_count()
  if class_count > 10000 {
    raise MalformedInput(field="retry_policy_v2_class_count")
  }
  let retryable_failure_classes : Array[String] = Array::new(
    capacity=class_count,
  )
  for index = 0; index < class_count; index = index + 1 {
    retryable_failure_classes.push(reader.read_string())
  }
  reader.require_end()
  let policy = RetryPolicyV2::new(
    policy_id, policy_version, maximum_attempt_count, maximum_retry_count, base_delay,
    maximum_delay, backoff_numerator, backoff_denominator, jitter_range, seed, retryable_failure_classes,
  )
  if policy.canonical_bytes() != bytes {
    raise DigestMismatch(field="retry_policy_v2_canonical")
  }
  policy
}

///|
pub fn RetryPolicyV2::policy_ref(self : RetryPolicyV2) -> @contracts.RecordRef {
  self.policy_ref
}

///|
pub fn RetryPolicyV2::maximum_attempt_count(self : RetryPolicyV2) -> Int64 {
  self.maximum_attempt_count
}

///|
pub fn RetryPolicyV2::maximum_retry_count(self : RetryPolicyV2) -> Int64 {
  self.maximum_retry_count
}

///|
pub fn RetryPolicyV2::canonical_bytes(self : RetryPolicyV2) -> Bytes {
  self.canonical
}

///|
pub fn RetryPolicyV2::digest(self : RetryPolicyV2) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn RetryPolicyV2::allows(
  self : RetryPolicyV2,
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
) -> Bool {
  let attempt_count = receipt.attempt_count()
  let retry_count = receipt.retry_count()
  if attempt_count < 0L ||
    retry_count < 0L ||
    attempt_count >= self.maximum_attempt_count ||
    retry_count >= self.maximum_retry_count {
    return false
  }
  self.retryable_failure_classes.any(item => item == receipt.cause_key())
}

///|
fn checked_add_v2(
  left : Int64,
  right : Int64,
  field : String,
) -> Int64 raise OrchestrationError {
  if right > int64_max - left {
    raise ArithmeticOverflow(field~)
  }
  left + right
}

///|
pub struct RetryTimingV2 {
  retry_ordinal : Int64
  nominal_delay : Int64
  jitter : Int64
  delay : Int64
  due_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn RetryTimingV2::compute(
  policy : RetryPolicyV2,
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
) -> RetryTimingV2 raise OrchestrationError {
  let attempt_count = receipt.attempt_count()
  let retry_count = receipt.retry_count()
  let retry_ordinal = receipt.retry_ordinal()
  let observed_at = receipt.source_observed_at()
  require_non_negative(observed_at, "observed_at")
  if retry_count != retry_ordinal {
    raise RetryBoundViolation(field="retry_count_ordinal_mismatch")
  }
  if !policy.allows(receipt) {
    if attempt_count < 0L ||
      retry_count < 0L ||
      attempt_count >= policy.maximum_attempt_count ||
      retry_count >= policy.maximum_retry_count {
      raise RetryBoundViolation(field="retry_counters")
    }
    raise RetryClassificationViolation(field="retry_eligibility")
  }
  if retry_ordinal >= policy.maximum_retry_count {
    raise RetryBoundViolation(field="retry_ordinal")
  }
  let nominal_delay = match
    @decision.retry_nominal_delay(
      policy.base_delay,
      policy.maximum_delay,
      policy.backoff_numerator,
      policy.backoff_denominator,
      retry_ordinal,
    ) {
    NominalDelay(value) => value
    InvalidInput => raise RetryBoundViolation(field="retry_backoff_input")
    NumeratorOverflow =>
      raise ArithmeticOverflow(field="retry_backoff_numerator")
    DenominatorOverflow =>
      raise ArithmeticOverflow(field="retry_backoff_denominator")
    OrdinalOverflow => raise ArithmeticOverflow(field="retry_ordinal_loop")
  }
  let jitter = if policy.jitter_range == 0L {
    0L
  } else {
    let writer = OrchestrationWriter::new()
    writer.bytes(b"FLOW7/RETRY-JITTER-V2/2.0.0")
    writer.string(policy.seed.text())
    writer.string(receipt.digest().text())
    writer.int64(retry_ordinal)
    match @decision.hash_mod(writer.finish(), policy.jitter_range + 1L) {
      Some(value) => value
      None => raise RetryBoundViolation(field="jitter_modulus")
    }
  }
  let delay = checked_add_v2(nominal_delay, jitter, "retry_delay")
  let due_at = checked_add_v2(observed_at, delay, "retry_due_at")
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/RETRY-TIMING-V2/2.0.0")
  let policy_ref = policy.policy_ref()
  writer.string(policy_ref.kind())
  writer.string(policy_ref.id())
  writer.string(policy_ref.digest().text())
  writer.string(policy.digest().text())
  write_ref(writer, receipt.receipt_ref())
  writer.string(receipt.digest().text())
  writer.string(receipt.cause_key())
  writer.int64(attempt_count)
  writer.int64(retry_count)
  writer.int64(retry_ordinal)
  writer.int64(observed_at)
  writer.int64(nominal_delay)
  writer.int64(jitter)
  writer.int64(delay)
  writer.int64(due_at)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  { retry_ordinal, nominal_delay, jitter, delay, due_at, canonical, digest }
}

///|
pub fn RetryTimingV2::decode(
  policy : RetryPolicyV2,
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
  bytes : Bytes,
) -> RetryTimingV2 raise OrchestrationError {
  let timing = RetryTimingV2::compute(policy, receipt)
  if timing.canonical_bytes() != bytes {
    raise DigestMismatch(field="retry_timing_v2_canonical")
  }
  timing
}

///|
pub fn RetryTimingV2::retry_ordinal(self : RetryTimingV2) -> Int64 {
  self.retry_ordinal
}

///|
pub fn RetryTimingV2::nominal_delay(self : RetryTimingV2) -> Int64 {
  self.nominal_delay
}

///|
pub fn RetryTimingV2::jitter(self : RetryTimingV2) -> Int64 {
  self.jitter
}

///|
pub fn RetryTimingV2::delay(self : RetryTimingV2) -> Int64 {
  self.delay
}

///|
pub fn RetryTimingV2::due_at(self : RetryTimingV2) -> Int64 {
  self.due_at
}

///|
pub fn RetryTimingV2::canonical_bytes(self : RetryTimingV2) -> Bytes {
  self.canonical
}

///|
pub fn RetryTimingV2::digest(self : RetryTimingV2) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn RetryTimingV2::authorized_at(
  self : RetryTimingV2,
  not_before : Int64,
  deadline : Int64?,
) -> Bool {
  @decision.is_authorized_at(self.due_at, not_before, deadline)
}

///|
/// Proof-only schedule binding: no catalog or effects projection is accepted.
pub struct ScheduleIntentV2 {
  schedule_ref : @contracts.RecordRef
  admission : AdmissionV2
  workflow : @contracts.RecordRef
  not_before : Int64
  deadline : Int64?
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation_ref : @contracts.RecordRef
  previous_digest : @contracts.ContentDigest?
  idempotency_key : String
  retry_policy : RetryPolicyV2?
  retry_plan : @retry_authority.RetryPlanProposalV2?
  retry_attempt_ref : @contracts.RecordRef?
  retry_attempt_event_ref : @contracts.RecordRef?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn ScheduleIntentV2::new(
  schedule_id : String,
  schedule_version : String,
  admission : AdmissionV2,
  workflow : @contracts.RecordRef,
  not_before : Int64,
  deadline : Int64?,
  evidence : Array[@contracts.EvidenceRef],
  causation_ref : @contracts.RecordRef,
  idempotency_key : String,
  previous_digest? : @contracts.ContentDigest,
  retry_policy? : RetryPolicyV2,
  retry_plan? : @retry_authority.RetryPlanProposalV2,
  retry_attempt_ref? : @contracts.RecordRef,
  retry_attempt_event_ref? : @contracts.RecordRef,
) -> ScheduleIntentV2 raise OrchestrationError {
  require_version_v2(schedule_version, "schedule_intent_v2")
  require_text(schedule_id, "schedule_id")
  require_text(idempotency_key, "schedule_idempotency_key")
  require_non_negative(not_before, "not_before")
  match deadline {
    Some(value) => {
      require_non_negative(value, "deadline")
      if value < not_before {
        raise ScheduleStateViolation(field="deadline_before_not_before")
      }
    }
    None => ()
  }
  if admission.planned().workflow() != workflow {
    raise WorkflowMismatch(field="schedule_workflow")
  }
  if !admission.governance().accepts(not_before) {
    raise AuthorityExpired(
      expires_at=admission.governance().valid_until_inclusive(),
      observed_at=not_before,
    )
  }
  if !admission.controls().accepts(not_before) {
    raise AuthorityExpired(
      expires_at=admission.controls().deadline_inclusive(),
      observed_at=not_before,
    )
  }
  match deadline {
    Some(value) if !admission.governance().accepts(value) =>
      raise AuthorityExpired(
        expires_at=admission.governance().valid_until_inclusive(),
        observed_at=value,
      )
    Some(value) if !admission.controls().accepts(value) =>
      raise AuthorityExpired(
        expires_at=admission.controls().deadline_inclusive(),
        observed_at=value,
      )
    _ => ()
  }
  let snapshot = evidence.copy()
  let required_evidence = admission.controls().evidence()
  if snapshot.length() != required_evidence.length() {
    raise EvidenceMismatch(field="schedule_evidence_count")
  }
  for index, item in snapshot {
    let required = required_evidence[index]
    if item.record() != required.evidence_ref() {
      raise EvidenceMismatch(field="schedule_evidence_record")
    }
    if item.observed_digest() != required.evidence_digest() {
      raise EvidenceMismatch(field="schedule_evidence_digest")
    }
    if snapshot[:index].any(prior => prior.record() == item.record()) {
      raise EvidenceMismatch(field="duplicate_evidence_record")
    }
  }
  match (retry_policy, retry_plan, retry_attempt_ref, retry_attempt_event_ref) {
    (None, None, None, None) => ()
    (Some(policy), Some(plan), Some(attempt_ref), Some(attempt_event_ref)) => {
      let expected_schedule_request = try
        @retry_authority.retry_child_schedule_request_ref_v2(
          schedule_id,
          workflow,
          not_before,
          idempotency_key,
          plan.requested_work_digest(),
        )
      catch {
        _ => raise ScheduleStateViolation(field="retry_schedule_request")
      } noraise {
        value => value
      }
      if attempt_ref.kind() != "effect-attempt" ||
        plan.workflow() != workflow ||
        plan.policy_ref() != policy.policy_ref() ||
        plan.policy_digest() != policy.digest() ||
        plan.policy_bytes() != policy.canonical_bytes() ||
        plan.due_at() != not_before ||
        plan.admission_ref() != admission.proof_ref() ||
        plan.admission_digest() != admission.proof_digest() ||
        plan.admission_bytes() != admission.proof_bytes() ||
        plan.admission_governance_deadline() !=
        admission.governance().valid_until_inclusive() ||
        plan.admission_controls_deadline() !=
        admission.controls().deadline_inclusive() ||
        plan.requested_work_ref() != admission.planned().requested_work_ref() ||
        plan.requested_work_digest() !=
        admission.planned().requested_work_digest() ||
        plan.schedule_request_ref() != expected_schedule_request ||
        plan.schedule_idempotency_key() != idempotency_key ||
        deadline != Some(plan.admission_deadline()) ||
        causation_ref != attempt_event_ref ||
        previous_digest != Some(attempt_event_ref.digest()) {
        raise ScheduleStateViolation(field="retry_schedule_plan_binding")
      }
    }
    _ => raise ScheduleStateViolation(field="retry_schedule_plan_quad")
  }
  let writer = OrchestrationWriter::new()
  let is_retry = retry_plan is Some(_)
  if is_retry {
    writer.bytes(b"FLOW7/SCHEDULE-INTENT-V2/2.1.0")
  } else {
    writer.bytes(b"FLOW7/SCHEDULE-INTENT-V2/2.0.0")
  }
  writer.string(schedule_version)
  writer.string(schedule_id)
  writer.string(admission.proof_ref().id())
  writer.bytes(admission.proof_bytes())
  write_ref(writer, workflow)
  writer.int64(not_before)
  writer.optional_int64(deadline)
  write_evidence(writer, snapshot)
  write_ref(writer, causation_ref)
  writer.optional_digest(previous_digest)
  writer.string(idempotency_key)
  match retry_policy {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      writer.string(value.policy_ref().id())
      writer.bytes(value.canonical_bytes())
    }
  }
  match (retry_plan, retry_attempt_ref, retry_attempt_event_ref) {
    (None, None, None) => ()
    (Some(plan), Some(attempt_ref), Some(attempt_event_ref)) => {
      writer.byte(1)
      write_ref(writer, plan.plan_ref())
      writer.string(plan.digest().text())
      writer.bytes(plan.canonical_bytes())
      write_ref(writer, attempt_ref)
      write_ref(writer, attempt_event_ref)
    }
    _ => raise ScheduleStateViolation(field="retry_schedule_plan_triplet")
  }
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    schedule_ref: self_ref_v2("orchestration-schedule-v2", schedule_id, digest),
    admission,
    workflow,
    not_before,
    deadline,
    evidence: ReadOnlyArray::from_array(snapshot),
    causation_ref,
    previous_digest,
    idempotency_key,
    retry_policy,
    retry_plan,
    retry_attempt_ref,
    retry_attempt_event_ref,
    canonical,
    digest,
  }
}

///|
pub fn ScheduleIntentV2::decode(
  expected_schedule_id : String,
  bytes : Bytes,
) -> ScheduleIntentV2 raise OrchestrationError {
  require_text(expected_schedule_id, "schedule_id")
  let reader = OrchestrationReader::new(bytes)
  let canonical_tag = reader.read_bytes()
  if canonical_tag != b"FLOW7/SCHEDULE-INTENT-V2/2.0.0" &&
    canonical_tag != b"FLOW7/SCHEDULE-INTENT-V2/2.1.0" {
    raise MalformedInput(field="schedule_intent_v2_tag")
  }
  let is_retry = canonical_tag == b"FLOW7/SCHEDULE-INTENT-V2/2.1.0"
  let schedule_version = reader.read_string()
  require_version_v2(schedule_version, "schedule_intent_v2")
  let schedule_id = reader.read_string()
  if schedule_id != expected_schedule_id {
    raise IdentityMismatch(field="schedule_id")
  }
  let proof_id = reader.read_string()
  let proof_bytes = reader.read_bytes()
  let admission = AdmissionV2::decode(proof_id, proof_bytes)
  let workflow = reader.read_ref()
  let not_before = reader.read_int64()
  let deadline = reader.read_optional_int64()
  let evidence = reader.read_evidence()
  let causation_ref = reader.read_ref()
  let previous_digest = reader.read_optional_digest()
  let idempotency_key = reader.read_string()
  let retry_policy : RetryPolicyV2? = match reader.read_byte() {
    0 => None
    1 => {
      let policy_id = reader.read_string()
      let policy_bytes = reader.read_bytes()
      Some(RetryPolicyV2::decode(policy_id, policy_bytes))
    }
    _ => raise MalformedInput(field="schedule_retry_policy_marker")
  }
  let (retry_plan, retry_attempt_ref, retry_attempt_event_ref) = if !is_retry {
    (None, None, None)
  } else {
    match reader.read_byte() {
      1 => {
        let plan_ref = reader.read_ref()
        let plan_digest = reader.read_digest()
        if plan_ref.digest() != plan_digest {
          raise DigestMismatch(field="schedule_retry_plan_digest")
        }
        let plan = @retry_authority.RetryPlanProposalV2::decode(
          plan_ref,
          reader.read_bytes(),
        ) catch {
          _ => raise MalformedInput(field="schedule_retry_plan")
        }
        (Some(plan), Some(reader.read_ref()), Some(reader.read_ref()))
      }
      _ => raise MalformedInput(field="schedule_retry_plan_marker")
    }
  }
  reader.require_end()
  let decoded = ScheduleIntentV2::new(
    schedule_id,
    schedule_version,
    admission,
    workflow,
    not_before,
    deadline,
    evidence,
    causation_ref,
    idempotency_key,
    previous_digest?,
    retry_policy?,
    retry_plan?,
    retry_attempt_ref?,
    retry_attempt_event_ref?,
  )
  if decoded.canonical_bytes() != bytes {
    raise DigestMismatch(field="schedule_intent_v2_canonical")
  }
  decoded
}

///|
pub fn ScheduleIntentV2::schedule_ref(
  self : ScheduleIntentV2,
) -> @contracts.RecordRef {
  self.schedule_ref
}

///|
pub fn ScheduleIntentV2::admission(self : ScheduleIntentV2) -> AdmissionV2 {
  self.admission
}

///|
pub fn ScheduleIntentV2::workflow(
  self : ScheduleIntentV2,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn ScheduleIntentV2::not_before(self : ScheduleIntentV2) -> Int64 {
  self.not_before
}

///|
pub fn ScheduleIntentV2::deadline(self : ScheduleIntentV2) -> Int64? {
  self.deadline
}

///|
pub fn ScheduleIntentV2::evidence(
  self : ScheduleIntentV2,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn ScheduleIntentV2::causation_ref(
  self : ScheduleIntentV2,
) -> @contracts.RecordRef {
  self.causation_ref
}

///|
pub fn ScheduleIntentV2::previous_digest(
  self : ScheduleIntentV2,
) -> @contracts.ContentDigest? {
  self.previous_digest
}

///|
pub fn ScheduleIntentV2::idempotency_key(self : ScheduleIntentV2) -> String {
  self.idempotency_key
}

///|
pub fn ScheduleIntentV2::retry_policy(
  self : ScheduleIntentV2,
) -> RetryPolicyV2? {
  self.retry_policy
}

///|
pub fn ScheduleIntentV2::retry_plan(
  self : ScheduleIntentV2,
) -> @retry_authority.RetryPlanProposalV2? {
  self.retry_plan
}

///|
pub fn ScheduleIntentV2::retry_attempt_ref(
  self : ScheduleIntentV2,
) -> @contracts.RecordRef? {
  self.retry_attempt_ref
}

///|
pub fn ScheduleIntentV2::retry_attempt_event_ref(
  self : ScheduleIntentV2,
) -> @contracts.RecordRef? {
  self.retry_attempt_event_ref
}

///|
pub fn ScheduleIntentV2::canonical_bytes(self : ScheduleIntentV2) -> Bytes {
  self.canonical
}

///|
pub fn ScheduleIntentV2::digest(
  self : ScheduleIntentV2,
) -> @contracts.ContentDigest {
  self.digest
}
