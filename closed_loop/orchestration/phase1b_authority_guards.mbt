///|
let open_work_authority_kind_v22 = "orchestration-open-work-authority-v2"

///|
let inflight_resolution_authority_kind_v22 = "orchestration-inflight-resolution-authority-v2"

///|
fn write_current_governed_binding_v22(
  writer : OrchestrationWriter,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> Unit raise OrchestrationError {
  write_ref(writer, current.root_binding.workflow)
  write_ref(writer, current.root_binding.record_ref)
  write_ref(writer, current.root_binding.retry_policy_ref())
  writer.bytes(current.root_binding.retry_policy.canonical)
  write_ref(writer, current.root_binding.governance_stream_ref())
  write_ref(writer, current.root_binding.governance_policy_ref())
  writer.bytes(
    current.root_binding.cancellation_governance.governance_policy_bytes,
  )
  writer.int64(current.root_binding.valid_until_inclusive())
  writer.int64(current.work_sequence)
  writer.int64(current.work_revision)
  writer.string(current.work_head_digest.text())
  writer.string(current.work_effects_state_digest.text())
  writer.string(current.work_orchestration_state_digest.text())
  writer.string(current.work_replay_digest.text())
  writer.int64(current.governance_sequence)
  writer.int64(current.governance_revision)
  writer.optional_digest(current.governance_head_digest)
  writer.string(current.governance_state_digest.text())
  writer.string(current.governance_replay_digest.text())
}

///|
fn current_governed_guard_id_v22(
  prefix : String,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> String {
  "\{prefix}:\{current.root_binding.workflow.id()}:\{current.work_revision}"
}

///|
fn open_work_authority_signing_bytes_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/OPEN-WORK-AUTHORITY-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(current_governed_guard_id_v22("open", current))
  write_current_governed_binding_v22(writer, current)
  writer.finish()
}

///|
/// Opaque, replay-minted authority for new work at exactly one governed head.
pub struct OpenWorkAuthorityV2 {
  authority_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  work_revision : Int64
  work_head_digest : @contracts.ContentDigest
  work_replay_digest : @contracts.ContentDigest
  governance_revision : Int64
  governance_head_digest : @contracts.ContentDigest?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn CurrentGovernedClosedLoopProjectionV2::open_work_authority(
  self : CurrentGovernedClosedLoopProjectionV2,
) -> OpenWorkAuthorityV2 raise OrchestrationError {
  if !self.cancellation_authoritative {
    raise ReplayBindingViolation(
      field="cancellation_committed_governance_receipt_required",
    )
  }
  require_root_binding_matches_aggregate_v22(self.root_binding, self.work)
  if self.work.cancellation is Some(_) || self.work.work_terminal is Some(_) {
    raise CancellationPrecedenceViolation(
      field="open_work_authority_not_current",
    )
  }
  let canonical = open_work_authority_signing_bytes_v22(self)
  let digest = @contracts.sha256_digest(canonical)
  {
    authority_ref: self_ref_v22(
      open_work_authority_kind_v22,
      current_governed_guard_id_v22("open", self),
      digest,
    ),
    workflow: self.root_binding.workflow,
    work_revision: self.work_revision,
    work_head_digest: self.work_head_digest,
    work_replay_digest: self.work_replay_digest,
    governance_revision: self.governance_revision,
    governance_head_digest: self.governance_head_digest,
    canonical,
    digest,
  }
}

///|
pub fn OpenWorkAuthorityV2::validate_current(
  self : OpenWorkAuthorityV2,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> Unit raise OrchestrationError {
  let replayed = current.open_work_authority() catch {
    _ =>
      raise CancellationPrecedenceViolation(
        field="open_work_authority_not_current",
      )
  }
  if replayed.authority_ref != self.authority_ref ||
    replayed.canonical != self.canonical ||
    replayed.work_revision != self.work_revision ||
    replayed.work_head_digest != self.work_head_digest ||
    replayed.work_replay_digest != self.work_replay_digest ||
    replayed.governance_revision != self.governance_revision ||
    replayed.governance_head_digest != self.governance_head_digest {
    raise CancellationPrecedenceViolation(
      field="open_work_authority_not_current",
    )
  }
}

///|
fn inflight_resolution_authority_signing_bytes_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
  intent : @effects.StrictIntentStateV2,
  scope : String,
  target_ref : @contracts.RecordRef,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/INFLIGHT-RESOLUTION-AUTHORITY-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(
    current_governed_guard_id_v22(
      "resolve:\{scope}:\{intent.intent_ref().id()}:\{target_ref.id()}",
      current,
    ),
  )
  write_current_governed_binding_v22(writer, current)
  writer.string(scope)
  write_ref(writer, target_ref)
  write_ref(writer, intent.intent_ref())
  writer.bytes(intent.intent_canonical_bytes())
  write_ref(writer, intent.attempt_ref())
  writer.string(intent.external_idempotency_key())
  write_ref(writer, intent.governed_subject())
  write_ref(writer, intent.outbox_ref())
  writer.string(inflight_effect_state_tag_v22(intent.state()))
  writer.string(intent.authoritative_replay_digest().text())
  writer.finish()
}

///|
fn inflight_effect_state_tag_v22(
  state : @effects.ReconciliationState,
) -> String {
  match state {
    DurableIntentDispatchEligible => "dispatch-eligible"
    DispatchObservationPending => "dispatch-observation-pending"
    UnknownOutcomeRequiresReconciliation => "unknown-outcome"
    ReconciliationRequestedState => "reconciliation-requested"
    KnownSuccess => "known-success"
    KnownFailure => "known-failure"
    ReconciledSuccessState => "reconciled-success"
    ReconciledFailureState => "reconciled-failure"
    ReconciledNotAppliedRetryEligible => "reconciled-not-applied"
    RegisteredNoIntent => "registered-no-intent"
  }
}

///|
fn inflight_scope_allows_state_v22(
  scope : String,
  state : @effects.ReconciliationState,
) -> Bool {
  (scope == "dispatch.observe" && state == DurableIntentDispatchEligible) ||
  (scope == "receipt.record" && state == DispatchObservationPending) ||
  (
    scope == "reconciliation.request" &&
    state == UnknownOutcomeRequiresReconciliation
  ) ||
  (scope == "reconciliation.resolve" && state == ReconciliationRequestedState)
}

///|
/// Opaque, per-intent authority for recording already-existing external facts.
pub struct InFlightResolutionAuthorityV2 {
  authority_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  outbox_ref : @contracts.RecordRef
  external_idempotency_key : String
  scope : String
  target_ref : @contracts.RecordRef
  effect_state : @effects.ReconciliationState
  effects_state_digest : @contracts.ContentDigest
  work_revision : Int64
  work_head_digest : @contracts.ContentDigest
  governance_revision : Int64
  governance_head_digest : @contracts.ContentDigest?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn CurrentGovernedClosedLoopProjectionV2::inflight_resolution_authority(
  self : CurrentGovernedClosedLoopProjectionV2,
  intent_ref : @contracts.RecordRef,
  scope : String,
  target_ref : @contracts.RecordRef,
) -> InFlightResolutionAuthorityV2 raise OrchestrationError {
  self.require_legacy_intent_mutation_v22(intent_ref)
  if !self.cancellation_authoritative {
    raise ReplayBindingViolation(
      field="cancellation_committed_governance_receipt_required",
    )
  }
  require_root_binding_matches_aggregate_v22(self.root_binding, self.work)
  if self.work.work_terminal is Some(_) {
    raise CancellationPrecedenceViolation(field="inflight_resolution_scope")
  }
  let intent = self.work.effects.strict_intent_state_v2(intent_ref) catch {
    _ =>
      raise CancellationPrecedenceViolation(field="inflight_resolution_scope")
  }
  if !inflight_scope_allows_state_v22(scope, intent.state()) {
    raise CancellationPrecedenceViolation(field="inflight_resolution_scope")
  }
  let canonical = inflight_resolution_authority_signing_bytes_v22(
    self, intent, scope, target_ref,
  )
  let digest = @contracts.sha256_digest(canonical)
  let id = current_governed_guard_id_v22(
    "resolve:\{scope}:\{intent_ref.id()}:\{target_ref.id()}",
    self,
  )
  {
    authority_ref: self_ref_v22(
      inflight_resolution_authority_kind_v22, id, digest,
    ),
    workflow: self.root_binding.workflow,
    intent_ref,
    outbox_ref: intent.outbox_ref(),
    external_idempotency_key: intent.external_idempotency_key(),
    scope,
    target_ref,
    effect_state: intent.state(),
    effects_state_digest: self.work_effects_state_digest,
    work_revision: self.work_revision,
    work_head_digest: self.work_head_digest,
    governance_revision: self.governance_revision,
    governance_head_digest: self.governance_head_digest,
    canonical,
    digest,
  }
}

///|
pub fn InFlightResolutionAuthorityV2::validate_current(
  self : InFlightResolutionAuthorityV2,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> Unit raise OrchestrationError {
  let replayed = current.inflight_resolution_authority(
    self.intent_ref,
    self.scope,
    self.target_ref,
  ) catch {
    _ =>
      raise ReplayBindingViolation(
        field="inflight_resolution_authority_not_current",
      )
  }
  if replayed.authority_ref != self.authority_ref ||
    replayed.canonical != self.canonical ||
    replayed.outbox_ref != self.outbox_ref ||
    replayed.external_idempotency_key != self.external_idempotency_key ||
    replayed.effect_state != self.effect_state ||
    replayed.effects_state_digest != self.effects_state_digest ||
    replayed.work_revision != self.work_revision ||
    replayed.work_head_digest != self.work_head_digest ||
    replayed.governance_revision != self.governance_revision ||
    replayed.governance_head_digest != self.governance_head_digest {
    raise ReplayBindingViolation(
      field="inflight_resolution_authority_not_current",
    )
  }
}

///|
let open_work_operation_kind_v22 = "orchestration-open-work-operation-authorization-v2"

///|
fn allowed_open_work_scope_v22(scope : String) -> Bool {
  scope == "attempt.register" ||
  scope == "effect.intent.commit" ||
  scope == "effect.dispatch" ||
  scope == "lease.claim" ||
  scope == "lease.renew" ||
  scope == "lease.reclaim" ||
  scope == "retry.request" ||
  scope == "retry.commit"
}

///|
/// Opaque target-bound authorization derived from one current open guard.
pub struct OpenWorkOperationAuthorizationV2 {
  authorization_ref : @contracts.RecordRef
  open_authority_ref : @contracts.RecordRef
  scope : String
  target_ref : @contracts.RecordRef
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn CurrentGovernedClosedLoopProjectionV2::authorize_open_work_operation(
  self : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  scope : String,
  target_ref : @contracts.RecordRef,
) -> OpenWorkOperationAuthorizationV2 raise OrchestrationError {
  open.validate_current(self)
  if !allowed_open_work_scope_v22(scope) {
    raise CancellationPrecedenceViolation(field="open_work_authority_scope")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/OPEN-WORK-OPERATION-AUTHORIZATION-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(scope)
  write_ref(writer, target_ref)
  write_ref(writer, open.authority_ref)
  writer.bytes(open.canonical)
  write_current_governed_binding_v22(writer, self)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  let id = "\{scope}:\{target_ref.id()}:\{self.work_revision}"
  {
    authorization_ref: self_ref_v22(open_work_operation_kind_v22, id, digest),
    open_authority_ref: open.authority_ref,
    scope,
    target_ref,
    canonical,
    digest,
  }
}

///|
fn OpenWorkOperationAuthorizationV2::require_current_scope(
  self : OpenWorkOperationAuthorizationV2,
  current : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  scope : String,
  target_ref : @contracts.RecordRef,
) -> Unit raise OrchestrationError {
  let replayed = current.authorize_open_work_operation(open, scope, target_ref)
  if replayed.authorization_ref != self.authorization_ref ||
    replayed.canonical != self.canonical ||
    self.open_authority_ref != open.authority_ref ||
    self.scope != scope ||
    self.target_ref != target_ref {
    raise CancellationPrecedenceViolation(field="open_work_authority_scope")
  }
}

///|
let guarded_dispatch_authority_kind_v22 = "orchestration-guarded-dispatch-authorization-v2"

///|
/// Exact committed-intent/outbox authority at one governed current head.
pub struct GuardedDispatchAuthorizationV2 {
  authorization_ref : @contracts.RecordRef
  open_authority_ref : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  outbox_ref : @contracts.RecordRef
  external_idempotency_key : String
  work_revision : Int64
  work_head_digest : @contracts.ContentDigest
  work_replay_digest : @contracts.ContentDigest
  governance_revision : Int64
  governance_head_digest : @contracts.ContentDigest?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn guarded_dispatch_signing_bytes_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  target : @effects.StrictDispatchTargetV2,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/GUARDED-DISPATCH-AUTHORIZATION-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  write_current_governed_binding_v22(writer, current)
  write_ref(writer, open.authority_ref)
  writer.bytes(open.canonical)
  write_ref(writer, target.intent_ref())
  writer.bytes(target.intent_canonical_bytes())
  write_ref(writer, target.attempt_ref())
  write_ref(writer, target.governed_subject())
  writer.bytes(@contracts.encode_wire_envelope(target.effect_request()))
  writer.string(target.external_idempotency_key())
  write_ref(writer, target.outbox_ref())
  writer.string(target.authoritative_replay_digest().text())
  writer.finish()
}

///|
pub fn CurrentGovernedClosedLoopProjectionV2::guarded_dispatch_authorization(
  self : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  intent_ref : @contracts.RecordRef,
) -> GuardedDispatchAuthorizationV2 raise OrchestrationError {
  open.validate_current(self)
  let target = self.work.effects.strict_dispatch_target_v2(intent_ref) catch {
    _ => raise ReplayBindingViolation(field="guarded_dispatch_target")
  }
  let canonical = guarded_dispatch_signing_bytes_v22(self, open, target)
  let digest = @contracts.sha256_digest(canonical)
  let id = "dispatch:\{intent_ref.id()}:\{self.work_revision}"
  {
    authorization_ref: self_ref_v22(
      guarded_dispatch_authority_kind_v22, id, digest,
    ),
    open_authority_ref: open.authority_ref,
    intent_ref,
    outbox_ref: target.outbox_ref(),
    external_idempotency_key: target.external_idempotency_key(),
    work_revision: self.work_revision,
    work_head_digest: self.work_head_digest,
    work_replay_digest: self.work_replay_digest,
    governance_revision: self.governance_revision,
    governance_head_digest: self.governance_head_digest,
    canonical,
    digest,
  }
}

///|
fn GuardedDispatchAuthorizationV2::require_current(
  self : GuardedDispatchAuthorizationV2,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> @effects.StrictDispatchTargetV2 raise OrchestrationError {
  let open = current.open_work_authority() catch {
    _ =>
      raise CancellationPrecedenceViolation(
        field="guarded_dispatch_authority_not_current",
      )
  }
  let replayed = current.guarded_dispatch_authorization(open, self.intent_ref) catch {
    _ =>
      raise CancellationPrecedenceViolation(
        field="guarded_dispatch_authority_not_current",
      )
  }
  if replayed.authorization_ref != self.authorization_ref ||
    replayed.open_authority_ref != self.open_authority_ref ||
    replayed.intent_ref != self.intent_ref ||
    replayed.outbox_ref != self.outbox_ref ||
    replayed.external_idempotency_key != self.external_idempotency_key ||
    replayed.work_revision != self.work_revision ||
    replayed.work_head_digest != self.work_head_digest ||
    replayed.work_replay_digest != self.work_replay_digest ||
    replayed.governance_revision != self.governance_revision ||
    replayed.governance_head_digest != self.governance_head_digest ||
    replayed.canonical != self.canonical ||
    replayed.digest != self.digest {
    raise CancellationPrecedenceViolation(
      field="guarded_dispatch_authority_not_current",
    )
  }
  current.work.effects.strict_dispatch_target_v2(self.intent_ref) catch {
    _ =>
      raise CancellationPrecedenceViolation(
        field="guarded_dispatch_authority_not_current",
      )
  }
}

///|
/// Opaque call envelope. Only `dispatch_guarded_effect_v2` can construct it,
/// immediately after revalidating the governed head.
pub struct GuardedDispatchCallV2 {
  target : @effects.StrictDispatchTargetV2
  authorization_ref : @contracts.RecordRef
}

///|
/// Opaque inert fact returned by the guarded dispatcher. It binds the exact
/// observation to the dispatch authorization and frozen governed prefix.
pub struct GuardedDispatchObservationV2 {
  observation : @effects.DispatchObservation
  dispatch_authorization_ref : @contracts.RecordRef
  dispatch_authorization_bytes : Bytes
  intent_ref : @contracts.RecordRef
  outbox_ref : @contracts.RecordRef
  external_idempotency_key : String
  work_revision : Int64
  work_head_digest : @contracts.ContentDigest
  work_replay_digest : @contracts.ContentDigest
  governance_revision : Int64
  governance_head_digest : @contracts.ContentDigest?
}

///|
pub fn GuardedDispatchCallV2::target(
  self : GuardedDispatchCallV2,
) -> @effects.StrictDispatchTargetV2 {
  self.target
}

///|
/// The only external-effect port owned by the governed orchestration layer.
pub(open) trait GuardedEffectDispatcherPortV2 {
  fn dispatch_guarded_effect(Self, GuardedDispatchCallV2) -> @effects.DispatchObservation raise
}

///|
/// Revalidate immediately before the external port invocation. This function
/// does not persist the returned observation; that is a separate in-flight
/// fact transition. The external idempotency key is exact and mandatory.
/// Multi-worker single-consumer claiming is intentionally deferred to Phase 2;
/// this authority is replayable while its exact governed head remains current.
pub fn[P : GuardedEffectDispatcherPortV2] dispatch_guarded_effect_v2(
  port : P,
  current : CurrentGovernedClosedLoopProjectionV2,
  authorization : GuardedDispatchAuthorizationV2,
) -> GuardedDispatchObservationV2 raise OrchestrationError {
  // V2 remains in the public interface solely so historical integrations can
  // still compile and historical records can still replay. Its replayable
  // authorization can never establish one-shot dispatch ownership, so Phase 2
  // retires the execution path unconditionally before inspecting the supplied
  // projection, authorization, or provider port.
  ignore(port)
  ignore(current)
  ignore(authorization)
  raise RecoveryViolation(field="guarded_dispatch_v2_retired_phase2")
}

///|
let guarded_attempt_authority_kind_v22 = "orchestration-guarded-attempt-authorization-v2"

///|
/// Exact committed-attempt adapter authority at one open governed head.
pub struct GuardedAttemptAuthorizationV2 {
  authorization_ref : @contracts.RecordRef
  open_authority_ref : @contracts.RecordRef
  attempt_ref : @contracts.RecordRef
  work_revision : Int64
  work_head_digest : @contracts.ContentDigest
  work_replay_digest : @contracts.ContentDigest
  governance_revision : Int64
  governance_head_digest : @contracts.ContentDigest?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn CurrentGovernedClosedLoopProjectionV2::guarded_attempt_authorization(
  self : CurrentGovernedClosedLoopProjectionV2,
  open : OpenWorkAuthorityV2,
  attempt_ref : @contracts.RecordRef,
) -> GuardedAttemptAuthorizationV2 raise OrchestrationError {
  open.validate_current(self)
  let target = self.work.effects.strict_attempt_target_v2(attempt_ref) catch {
    _ => raise ReplayBindingViolation(field="guarded_attempt_target")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/GUARDED-ATTEMPT-AUTHORIZATION-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  write_current_governed_binding_v22(writer, self)
  write_ref(writer, open.authority_ref)
  writer.bytes(open.canonical)
  write_ref(writer, target.attempt_ref())
  writer.bytes(target.attempt_canonical_bytes())
  writer.bytes(@contracts.encode_wire_envelope(target.requested_work()))
  writer.string(target.idempotency_key())
  writer.string(target.authoritative_replay_digest().text())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  let id = "attempt:\{attempt_ref.id()}:\{self.work_revision}"
  {
    authorization_ref: self_ref_v22(
      guarded_attempt_authority_kind_v22, id, digest,
    ),
    open_authority_ref: open.authority_ref,
    attempt_ref,
    work_revision: self.work_revision,
    work_head_digest: self.work_head_digest,
    work_replay_digest: self.work_replay_digest,
    governance_revision: self.governance_revision,
    governance_head_digest: self.governance_head_digest,
    canonical,
    digest,
  }
}

///|
fn GuardedAttemptAuthorizationV2::require_current(
  self : GuardedAttemptAuthorizationV2,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> @effects.StrictAttemptTargetV2 raise OrchestrationError {
  let open = current.open_work_authority() catch {
    _ =>
      raise CancellationPrecedenceViolation(
        field="guarded_attempt_authority_not_current",
      )
  }
  let replayed = current.guarded_attempt_authorization(open, self.attempt_ref) catch {
    _ =>
      raise CancellationPrecedenceViolation(
        field="guarded_attempt_authority_not_current",
      )
  }
  if replayed.authorization_ref != self.authorization_ref ||
    replayed.open_authority_ref != self.open_authority_ref ||
    replayed.attempt_ref != self.attempt_ref ||
    replayed.work_revision != self.work_revision ||
    replayed.work_head_digest != self.work_head_digest ||
    replayed.work_replay_digest != self.work_replay_digest ||
    replayed.governance_revision != self.governance_revision ||
    replayed.governance_head_digest != self.governance_head_digest ||
    replayed.canonical != self.canonical ||
    replayed.digest != self.digest {
    raise CancellationPrecedenceViolation(
      field="guarded_attempt_authority_not_current",
    )
  }
  current.work.effects.strict_attempt_target_v2(self.attempt_ref) catch {
    _ =>
      raise CancellationPrecedenceViolation(
        field="guarded_attempt_authority_not_current",
      )
  }
}

///|
/// Opaque adapter call, constructed only after current-head validation.
pub struct GuardedAttemptCallV2 {
  target : @effects.StrictAttemptTargetV2
  authorization_ref : @contracts.RecordRef
}

///|
pub fn GuardedAttemptCallV2::target(
  self : GuardedAttemptCallV2,
) -> @effects.StrictAttemptTargetV2 {
  self.target
}

///|
pub(open) trait GuardedAttemptAdapterPortV2 {
  fn observe_guarded_attempt(Self, GuardedAttemptCallV2) -> @effects.AttemptObservation raise
}

///|
/// Adapter execution is separate from durable attempt registration. The
/// returned value is inert and prepares no event, outbox, or commit request.
pub fn[P : GuardedAttemptAdapterPortV2] observe_guarded_attempt_v2(
  port : P,
  current : CurrentGovernedClosedLoopProjectionV2,
  authorization : GuardedAttemptAuthorizationV2,
) -> @effects.AttemptObservation raise OrchestrationError {
  let target = authorization.require_current(current)
  let observation = port.observe_guarded_attempt({
    target,
    authorization_ref: authorization.authorization_ref,
  }) catch {
    _ => raise RecoveryViolation(field="guarded_attempt_port")
  }
  if observation.attempt_ref() != target.attempt_ref() {
    raise ReplayBindingViolation(field="guarded_attempt_observation")
  }
  observation
}
