///|
pub struct ExternalIdempotencyEntry {
  key : String
  intent_ref : @contracts.RecordRef
  intent_digest : @contracts.ContentDigest
  receipt_ref : @contracts.RecordRef?
  outcome : ExternalOutcome?
}

///|
pub fn ExternalIdempotencyEntry::key(self : ExternalIdempotencyEntry) -> String {
  self.key
}

///|
pub fn ExternalIdempotencyEntry::intent_ref(
  self : ExternalIdempotencyEntry,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn ExternalIdempotencyEntry::outcome(
  self : ExternalIdempotencyEntry,
) -> ExternalOutcome? {
  self.outcome
}

///|
pub struct ExternalIdempotencyRegistry {
  record_version : @contracts.Version
  entries : ReadOnlyArray[ExternalIdempotencyEntry]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn registry_from_entries(
  entries : Array[ExternalIdempotencyEntry],
) -> ExternalIdempotencyRegistry {
  let writer = EffectsWriter::new()
  try! writer.bytes(b"MF6AIDR1")
  try! writer.string(effects_record_version)
  try! writer.count(entries.length())
  for entry in entries {
    try! writer.string(entry.key)
    try! write_ref(writer, entry.intent_ref)
    try! writer.string(entry.intent_digest.text())
    try! write_optional_ref(writer, entry.receipt_ref)
    try! writer.optional_string(entry.outcome.map(value => value.tag()))
  }
  let canonical = writer.finish()
  {
    record_version: effects_version(),
    entries: ReadOnlyArray::from_array(entries.copy()),
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn ExternalIdempotencyRegistry::entries(
  self : ExternalIdempotencyRegistry,
) -> ReadOnlyArray[ExternalIdempotencyEntry] {
  self.entries
}

///|
pub fn ExternalIdempotencyRegistry::canonical_bytes(
  self : ExternalIdempotencyRegistry,
) -> Bytes {
  self.canonical
}

///|
pub fn ExternalIdempotencyRegistry::state_digest(
  self : ExternalIdempotencyRegistry,
) -> @contracts.ContentDigest {
  self.digest
}

///|
/// Immutable decoding catalog. Values have no authority until exact canonical
/// payloads and bindings are found in an authoritative FLOW-4A replay.
pub struct ReplayCatalog {
  registrations : ReadOnlyArray[AttemptRegistration]
  intents : ReadOnlyArray[EffectIntent]
  observations : ReadOnlyArray[DispatchObservation]
  receipts : ReadOnlyArray[EffectReceipt]
  reconciliation_requests : ReadOnlyArray[ReconciliationRequest]
  reconciliations : ReadOnlyArray[ReconciliationRecord]
}

///|
pub fn ReplayCatalog::new(
  registrations : Array[AttemptRegistration],
  intents : Array[EffectIntent],
  observations : Array[DispatchObservation],
  receipts : Array[EffectReceipt],
  reconciliation_requests : Array[ReconciliationRequest],
  reconciliations : Array[ReconciliationRecord],
) -> ReplayCatalog {
  {
    registrations: ReadOnlyArray::from_array(registrations.copy()),
    intents: ReadOnlyArray::from_array(intents.copy()),
    observations: ReadOnlyArray::from_array(observations.copy()),
    receipts: ReadOnlyArray::from_array(receipts.copy()),
    reconciliation_requests: ReadOnlyArray::from_array(
      reconciliation_requests.copy(),
    ),
    reconciliations: ReadOnlyArray::from_array(reconciliations.copy()),
  }
}

///|
pub struct EffectsProjection {
  projection_version : @contracts.Version
  workflow : @contracts.RecordRef
  policy_ref : @contracts.RecordRef
  sequence : Int64
  revision : Int64
  last_event_digest : @contracts.ContentDigest?
  attempts : ReadOnlyArray[AttemptRegistration]
  intents : ReadOnlyArray[EffectIntent]
  eligible : ReadOnlyArray[DispatchEligibleIntent]
  observations : ReadOnlyArray[DispatchObservation]
  receipts : ReadOnlyArray[EffectReceipt]
  receipt_event_refs : ReadOnlyArray[@contracts.RecordRef]
  reconciliation_requests : ReadOnlyArray[ReconciliationRequest]
  reconciliation_request_event_refs : ReadOnlyArray[@contracts.RecordRef]
  reconciliations : ReadOnlyArray[ReconciliationRecord]
  reconciliation_event_refs : ReadOnlyArray[@contracts.RecordRef]
  registry : ExternalIdempotencyRegistry
  replay_digest : @contracts.ContentDigest?
  strict_replay : @storage.ReplayResult?
  strict_snapshot_digest : @contracts.ContentDigest?
  canonical : Bytes
  state_digest : @contracts.ContentDigest
}

///|
fn projection_canonical(
  workflow : @contracts.RecordRef,
  policy_ref : @contracts.RecordRef,
  sequence : Int64,
  revision : Int64,
  last_event_digest : @contracts.ContentDigest?,
  attempts : ArrayView[AttemptRegistration],
  intents : ArrayView[EffectIntent],
  eligible : ArrayView[DispatchEligibleIntent],
  observations : ArrayView[DispatchObservation],
  receipts : ArrayView[EffectReceipt],
  requests : ArrayView[ReconciliationRequest],
  reconciliations : ArrayView[ReconciliationRecord],
  registry : ExternalIdempotencyRegistry,
  replay_digest : @contracts.ContentDigest?,
  strict_snapshot_digest : @contracts.ContentDigest?,
) -> Bytes {
  let writer = EffectsWriter::new()
  try! writer.bytes(b"MF6APRJ1")
  try! writer.string(effects_record_version)
  try! write_ref(writer, workflow)
  try! write_ref(writer, policy_ref)
  writer.int64(sequence)
  writer.int64(revision)
  try! writer.optional_string(last_event_digest.map(value => value.text()))
  try! writer.count(attempts.length())
  for value in attempts {
    try! writer.bytes(value.canonical_bytes())
  }
  try! writer.count(intents.length())
  for value in intents {
    try! writer.bytes(value.canonical_bytes())
  }
  try! writer.count(eligible.length())
  for value in eligible {
    try! write_ref(writer, value.intent().intent_ref())
  }
  try! writer.count(observations.length())
  for value in observations {
    try! writer.bytes(value.canonical_bytes())
  }
  try! writer.count(receipts.length())
  for value in receipts {
    try! writer.bytes(value.canonical_bytes())
  }
  try! writer.count(requests.length())
  for value in requests {
    try! writer.bytes(value.canonical_bytes())
  }
  try! writer.count(reconciliations.length())
  for value in reconciliations {
    try! writer.bytes(value.canonical_bytes())
  }
  try! writer.bytes(registry.canonical_bytes())
  try! writer.optional_string(replay_digest.map(value => value.text()))
  match strict_snapshot_digest {
    None => ()
    Some(value) => {
      try! writer.bytes(b"MF6/STRICT-RETRY-PROJECTION-V2")
      try! writer.string(value.text())
    }
  }
  writer.finish()
}

///|
fn build_projection(
  workflow : @contracts.RecordRef,
  policy_ref : @contracts.RecordRef,
  sequence : Int64,
  revision : Int64,
  last_event_digest : @contracts.ContentDigest?,
  attempts : Array[AttemptRegistration],
  intents : Array[EffectIntent],
  eligible : Array[DispatchEligibleIntent],
  observations : Array[DispatchObservation],
  receipts : Array[EffectReceipt],
  receipt_event_refs : Array[@contracts.RecordRef],
  requests : Array[ReconciliationRequest],
  request_event_refs : Array[@contracts.RecordRef],
  reconciliations : Array[ReconciliationRecord],
  reconciliation_event_refs : Array[@contracts.RecordRef],
  registry : ExternalIdempotencyRegistry,
  replay_digest : @contracts.ContentDigest?,
  strict_replay : @storage.ReplayResult?,
  strict_snapshot_digest : @contracts.ContentDigest?,
) -> EffectsProjection {
  let canonical = projection_canonical(
    workflow, policy_ref, sequence, revision, last_event_digest, attempts, intents,
    eligible, observations, receipts, requests, reconciliations, registry, replay_digest,
    strict_snapshot_digest,
  )
  {
    projection_version: effects_version(),
    workflow,
    policy_ref,
    sequence,
    revision,
    last_event_digest,
    attempts: ReadOnlyArray::from_array(attempts.copy()),
    intents: ReadOnlyArray::from_array(intents.copy()),
    eligible: ReadOnlyArray::from_array(eligible.copy()),
    observations: ReadOnlyArray::from_array(observations.copy()),
    receipts: ReadOnlyArray::from_array(receipts.copy()),
    receipt_event_refs: ReadOnlyArray::from_array(receipt_event_refs.copy()),
    reconciliation_requests: ReadOnlyArray::from_array(requests.copy()),
    reconciliation_request_event_refs: ReadOnlyArray::from_array(
      request_event_refs.copy(),
    ),
    reconciliations: ReadOnlyArray::from_array(reconciliations.copy()),
    reconciliation_event_refs: ReadOnlyArray::from_array(
      reconciliation_event_refs.copy(),
    ),
    registry,
    replay_digest,
    strict_replay,
    strict_snapshot_digest,
    canonical,
    state_digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub fn EffectsProjection::new(
  workflow : @contracts.RecordRef,
  policy_ref : @contracts.RecordRef,
) -> EffectsProjection {
  build_projection(
    workflow,
    policy_ref,
    0L,
    0L,
    None,
    [],
    [],
    [],
    [],
    [],
    [],
    [],
    [],
    [],
    [],
    registry_from_entries([]),
    None,
    None,
    None,
  )
}

///|
pub fn EffectsProjection::workflow(
  self : EffectsProjection,
) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn EffectsProjection::sequence(self : EffectsProjection) -> Int64 {
  self.sequence
}

///|
pub fn EffectsProjection::revision(self : EffectsProjection) -> Int64 {
  self.revision
}

///|
pub fn EffectsProjection::last_event_digest(
  self : EffectsProjection,
) -> @contracts.ContentDigest? {
  self.last_event_digest
}

///|
pub fn EffectsProjection::attempts(
  self : EffectsProjection,
) -> ReadOnlyArray[AttemptRegistration] {
  self.attempts
}

///|
pub fn EffectsProjection::intents(
  self : EffectsProjection,
) -> ReadOnlyArray[EffectIntent] {
  self.intents
}

///|
fn EffectsProjection::dispatch_eligible_intents(
  self : EffectsProjection,
) -> ReadOnlyArray[DispatchEligibleIntent] {
  self.eligible
}

///|
pub fn EffectsProjection::registry(
  self : EffectsProjection,
) -> ExternalIdempotencyRegistry {
  self.registry
}

///|
pub fn EffectsProjection::canonical_bytes(self : EffectsProjection) -> Bytes {
  self.canonical
}

///|
pub fn EffectsProjection::state_digest(
  self : EffectsProjection,
) -> @contracts.ContentDigest {
  self.state_digest
}

///|
fn EffectsProjection::require_next_attempt(
  self : EffectsProjection,
  registration : AttemptRegistration,
) -> Unit raise EffectsError {
  if registration.workflow() != self.workflow ||
    registration.governance().policy_ref() != self.policy_ref {
    raise IdentityMismatch(field="attempt_projection_binding")
  }
  for prior in self.attempts {
    if same_record_identity(prior.attempt_ref(), registration.attempt_ref()) {
      if prior == registration {
        return
      }
      raise IdempotencyConflict(key=registration.idempotency_key())
    }
    if prior.idempotency_key() == registration.idempotency_key() {
      raise IdempotencyConflict(key=registration.idempotency_key())
    }
    if prior.attempt_ordinal() >= registration.attempt_ordinal() {
      raise OrderingViolation(field="attempt_ordinal")
    }
  }
  match
    (
      registration.retry_of_intent_ref(),
      registration.retry_eligibility_receipt(),
      registration.retry_plan(),
    ) {
    (None, None, None) => ()
    (Some(prior_intent), Some(receipt), Some(plan)) => {
      receipt.validate_current(self)
      if receipt.source_intent_ref() != prior_intent {
        raise RetryEligibilityViolation(field="retry_attempt_source_binding")
      }
      if plan.receipt_ref() != receipt.receipt_ref() ||
        plan.prefix_sequence() != self.sequence ||
        plan.prefix_revision() != self.revision ||
        plan.prefix_head_digest() != self.last_event_digest.unwrap() ||
        plan.prefix_replay_digest() != self.replay_digest.unwrap() {
        raise RetryEligibilityViolation(field="retry_attempt_plan_current")
      }
      match self.strict_replay {
        Some(_) => {
          let snapshot = self.require_strict_retry_snapshot(
            "retry_attempt_requires_strict_replay",
          )
          guard first(snapshot.intents, value => {
              value.intent_ref == prior_intent
            })
            is Some(prior) else {
            raise RetryEligibilityViolation(
              field="retry_attempt_foreign_source",
            )
          }
          guard first(snapshot.attempts, value => {
              value.attempt_ref == prior.attempt_ref
            })
            is Some(prior_attempt) else {
            raise RetryEligibilityViolation(field="retry_attempt_prior_missing")
          }
          if prior.attempt_ref == registration.attempt_ref() {
            raise IdentityMismatch(field="retry_attempt_identity_reuse")
          }
          if registration.attempt_ordinal() !=
            prior_attempt.attempt_ordinal + 1L {
            raise OrderingViolation(field="retry_attempt_ordinal")
          }
        }
        None => {
          guard first(self.intents, value => value.intent_ref() == prior_intent)
            is Some(prior) else {
            raise RetryEligibilityViolation(
              field="retry_attempt_foreign_source",
            )
          }
          guard first(self.attempts, value => {
              value.attempt_ref() == prior.attempt_ref()
            })
            is Some(prior_attempt) else {
            raise RetryEligibilityViolation(field="retry_attempt_prior_missing")
          }
          if prior.attempt_ref() == registration.attempt_ref() {
            raise IdentityMismatch(field="retry_attempt_identity_reuse")
          }
          if registration.attempt_ordinal() !=
            prior_attempt.attempt_ordinal() + 1L {
            raise OrderingViolation(field="retry_attempt_ordinal")
          }
        }
      }
    }
    _ => raise RetryEligibilityViolation(field="retry_attempt_receipt_pair")
  }
}

///|
fn EffectsProjection::require_intent(
  self : EffectsProjection,
  intent : EffectIntent,
) -> Unit raise EffectsError {
  if intent.workflow() != self.workflow {
    raise IdentityMismatch(field="intent_projection_workflow")
  }
  if !self.attempts.any(value => value.attempt_ref() == intent.attempt_ref()) {
    raise OrderingViolation(field="intent_before_attempt")
  }
  for prior in self.intents {
    if same_record_identity(prior.intent_ref(), intent.intent_ref()) {
      if prior == intent {
        return
      }
      raise IdempotencyConflict(key=intent.external_idempotency_key())
    }
    if prior.external_idempotency_key() == intent.external_idempotency_key() {
      raise IdempotencyConflict(key=intent.external_idempotency_key())
    }
    match (prior.fencing(), intent.fencing()) {
      (Some(old), Some(next)) if old.fence_ref() == next.fence_ref() &&
        (
          next.lease_epoch() < old.lease_epoch() ||
          next.fencing_token() <= old.fencing_token()
        ) => raise FencingViolation(field="stale_fencing_binding")
      _ => ()
    }
  }
}

///|
pub fn EffectsProjection::state_for(
  self : EffectsProjection,
  intent_ref : @contracts.RecordRef,
) -> ReconciliationState raise EffectsError {
  guard self.intents.any(value => value.intent_ref() == intent_ref) else {
    raise IdentityMismatch(field="unknown_intent")
  }
  match first(self.reconciliations, value => value.intent_ref() == intent_ref) {
    Some(value) =>
      match value.resolution() {
        ReconciledSucceeded => ReconciledSuccessState
        ReconciledFailed => ReconciledFailureState
        ReconciledNotApplied => ReconciledNotAppliedRetryEligible
      }
    None =>
      match
        first(self.reconciliation_requests, value => {
          value.intent_ref() == intent_ref
        }) {
        Some(_) => ReconciliationRequestedState
        None =>
          match
            first(self.receipts, value => value.intent_ref() == intent_ref) {
            Some(value) =>
              match value.outcome() {
                Succeeded => KnownSuccess
                Failed => KnownFailure
                Unknown => UnknownOutcomeRequiresReconciliation
              }
            None =>
              if self.observations.any(value => value.intent_ref() == intent_ref) {
                DispatchObservationPending
              } else {
                DurableIntentDispatchEligible
              }
          }
      }
  }
}

///|
pub fn EffectsProjection::retry_eligible(
  self : EffectsProjection,
  intent_ref : @contracts.RecordRef,
) -> Bool {
  try self.state_for(intent_ref) catch {
    _ => false
  } noraise {
    state => state == ReconciledNotAppliedRetryEligible
  }
}
