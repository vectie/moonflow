///|
/// Opaque open-head-bound retry scheduling proposal.
pub struct GuardedRetryScheduleRequestV2 {
  request : @retry_authority.RetryScheduleRequestV2
  authorization : OpenWorkOperationAuthorizationV2
}

///|
pub fn GuardedRetryScheduleRequestV2::request(
  self : GuardedRetryScheduleRequestV2,
) -> @retry_authority.RetryScheduleRequestV2 {
  self.request
}

///|
fn require_current_root_retry_policy_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
  policy : RetryPolicyV2,
) -> Unit raise OrchestrationError {
  let bound = current.root_binding.retry_policy
  if policy.policy_ref() != bound.retry_policy_ref ||
    policy.digest() != bound.retry_policy_digest ||
    policy.canonical_bytes() != bound.retry_policy_bytes {
    raise PolicyMismatch(field="root_retry_policy_binding")
  }
}

///|
pub fn prepare_guarded_retry_schedule_request_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
  policy : RetryPolicyV2,
  governance : @effects.GovernanceBinding,
  request_id : String,
  attempt_id : String,
  attempt_idempotency_key : String,
  requested_work : @contracts.WireEnvelope,
  logical_attempt_id : String,
  logical_attempt_version : String,
  logical_effect_id : String,
  logical_effect_version : String,
  artifact_digest : @contracts.ContentDigest,
  schedule_id : String,
  schedule_idempotency_key : String,
  schedule_deadline : Int64,
  admission_governance_deadline : Int64,
  admission_controls_deadline : Int64,
  command_idempotency_key : String,
) -> GuardedRetryScheduleRequestV2 raise {
  current.require_legacy_effect_protocol_v2()
  open.validate_current(current)
  require_current_root_retry_policy_v22(current, policy)
  let request = prepare_retry_schedule_request_v2(
    current.work,
    receipt,
    policy,
    governance,
    request_id,
    attempt_id,
    attempt_idempotency_key,
    requested_work,
    logical_attempt_id,
    logical_attempt_version,
    logical_effect_id,
    logical_effect_version,
    artifact_digest,
    schedule_id,
    schedule_idempotency_key,
    schedule_deadline,
    admission_governance_deadline,
    admission_controls_deadline,
    command_idempotency_key,
  )
  let authorization = current.authorize_open_work_operation(
    open,
    "retry.request",
    request.request_ref(),
  )
  { request, authorization }
}

///|
/// Opaque target-bound atomic retry append.
pub struct GuardedAtomicRetryV2 {
  prepared : PreparedAtomicRetryV2
  authorization : OpenWorkOperationAuthorizationV2
}

///|
pub fn GuardedAtomicRetryV2::plan(
  self : GuardedAtomicRetryV2,
) -> @retry_authority.RetryPlanProposalV2 {
  self.prepared.plan()
}

///|
pub fn GuardedAtomicRetryV2::attempt(
  self : GuardedAtomicRetryV2,
) -> @effects.AttemptRegistration {
  self.prepared.attempt()
}

///|
pub fn GuardedAtomicRetryV2::registration(
  self : GuardedAtomicRetryV2,
) -> ScheduleRegisteredV2 {
  self.prepared.registration()
}

///|
pub fn GuardedAtomicRetryV2::request(
  self : GuardedAtomicRetryV2,
) -> @storage.CommitRequest {
  self.prepared.request()
}

///|
pub fn prepare_guarded_atomic_retry_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  guarded_request : GuardedRetryScheduleRequestV2,
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
  policy : RetryPolicyV2,
  admission : AdmissionV2,
  governance : @effects.GovernanceBinding,
  plan_id : String,
  attempt_id : String,
  attempt_event_id : String,
  attempt_idempotency_key : String,
  requested_work : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  created_at : Int64,
  schedule_id : String,
  schedule_idempotency_key : String,
  schedule_deadline : Int64,
  schedule_event_id : String,
  registration_id : String,
  command_idempotency_key : String,
) -> GuardedAtomicRetryV2 raise {
  current.require_legacy_effect_protocol_v2()
  require_current_root_retry_policy_v22(current, policy)
  guarded_request.authorization.require_current_scope(
    current,
    open,
    "retry.request",
    guarded_request.request.request_ref(),
  )
  let prepared = prepare_atomic_retry_v2(
    current.work,
    receipt,
    policy,
    guarded_request.request,
    admission,
    governance,
    plan_id,
    attempt_id,
    attempt_event_id,
    attempt_idempotency_key,
    requested_work,
    evidence,
    created_at,
    schedule_id,
    schedule_idempotency_key,
    schedule_deadline,
    schedule_event_id,
    registration_id,
    command_idempotency_key,
  )
  let authorization = current.authorize_open_work_operation(
    open,
    "retry.commit",
    prepared.registration().record_ref(),
  )
  authorization.require_current_scope(
    current,
    open,
    "retry.commit",
    prepared.registration().record_ref(),
  )
  { prepared, authorization }
}
