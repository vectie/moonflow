///|
fn strict_replay_digest(
  workflow : @contracts.RecordRef,
  events : ArrayView[@storage.WorkflowEvent],
) -> @contracts.ContentDigest {
  let writer = EffectsWriter::new()
  try! writer.string("1.0.0")
  let ref_writer = EffectsWriter::new()
  try! write_ref(ref_writer, workflow)
  try! writer.bytes(ref_writer.finish())
  try! writer.count(events.length())
  for event in events {
    try! writer.bytes(event.canonical_bytes())
  }
  @contracts.sha256_digest(writer.finish())
}

///|
fn build_strict_snapshot(
  workflow : @contracts.RecordRef,
  policy_ref : @contracts.RecordRef,
  events : Array[@storage.WorkflowEvent],
  attempts : Array[DecodedAttemptRecord],
  intents : Array[DecodedIntentRecord],
  observations : Array[DecodedObservationRecord],
  receipts : Array[DecodedReceiptRecord],
  receipt_event_refs : Array[@contracts.RecordRef],
  requests : Array[DecodedReconciliationRequestRecord],
  request_event_refs : Array[@contracts.RecordRef],
  reconciliations : Array[DecodedReconciliationRecord],
  reconciliation_event_refs : Array[@contracts.RecordRef],
  consumed_event_refs : Array[@contracts.RecordRef],
  matched_outbox_refs : Array[@contracts.RecordRef],
) -> StrictRetrySnapshot {
  let sequence = events.length().to_int64()
  let revision = sequence
  let last_event_digest = events.last().map(value => value.event_ref().digest())
  let replay_digest = strict_replay_digest(workflow, events)
  let writer = EffectsWriter::new()
  try! writer.bytes(b"MF6/STRICT-RETRY-SNAPSHOT-V2/2.0.0")
  try! write_ref(writer, workflow)
  try! write_ref(writer, policy_ref)
  writer.int64(sequence)
  writer.int64(revision)
  try! writer.optional_string(last_event_digest.map(value => value.text()))
  try! writer.string(replay_digest.text())
  try! writer.count(attempts.length())
  for value in attempts {
    try! writer.bytes(value.canonical)
  }
  try! writer.count(intents.length())
  for value in intents {
    try! writer.bytes(value.canonical)
  }
  try! writer.count(observations.length())
  for value in observations {
    try! writer.bytes(value.canonical)
  }
  try! writer.count(receipts.length())
  for index, value in receipts {
    try! writer.bytes(value.canonical)
    try! write_ref(writer, receipt_event_refs[index])
  }
  try! writer.count(requests.length())
  for index, value in requests {
    try! writer.bytes(value.canonical)
    try! write_ref(writer, request_event_refs[index])
  }
  try! writer.count(reconciliations.length())
  for index, value in reconciliations {
    try! writer.bytes(value.canonical)
    try! write_ref(writer, reconciliation_event_refs[index])
  }
  try! writer.count(consumed_event_refs.length())
  for value in consumed_event_refs {
    try! write_ref(writer, value)
  }
  try! writer.count(matched_outbox_refs.length())
  for value in matched_outbox_refs {
    try! write_ref(writer, value)
  }
  let canonical = writer.finish()
  {
    workflow,
    policy_ref,
    sequence,
    revision,
    last_event_digest,
    replay_digest,
    attempts: ReadOnlyArray::from_array(attempts.copy()),
    intents: ReadOnlyArray::from_array(intents.copy()),
    observations: ReadOnlyArray::from_array(observations.copy()),
    receipts: ReadOnlyArray::from_array(receipts.copy()),
    receipt_event_refs: ReadOnlyArray::from_array(receipt_event_refs.copy()),
    requests: ReadOnlyArray::from_array(requests.copy()),
    request_event_refs: ReadOnlyArray::from_array(request_event_refs.copy()),
    reconciliations: ReadOnlyArray::from_array(reconciliations.copy()),
    reconciliation_event_refs: ReadOnlyArray::from_array(
      reconciliation_event_refs.copy(),
    ),
    consumed_event_refs: ReadOnlyArray::from_array(consumed_event_refs.copy()),
    matched_outbox_refs: ReadOnlyArray::from_array(matched_outbox_refs.copy()),
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
fn strict_projection(
  snapshot : StrictRetrySnapshot,
  replay : @storage.ReplayResult?,
) -> EffectsProjection {
  build_projection(
    snapshot.workflow,
    snapshot.policy_ref,
    snapshot.sequence,
    snapshot.revision,
    snapshot.last_event_digest,
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
    Some(snapshot.replay_digest),
    replay,
    Some(snapshot.digest),
  )
}

///|
fn StrictRetrySnapshot::state_for(
  self : StrictRetrySnapshot,
  intent_ref : @contracts.RecordRef,
) -> ReconciliationState raise EffectsError {
  if !self.intents.any(value => value.intent_ref == intent_ref) {
    raise IdentityMismatch(field="strict_unknown_intent")
  }
  match first(self.reconciliations, value => value.intent_ref == intent_ref) {
    Some(value) =>
      match value.resolution {
        ReconciledSucceeded => ReconciledSuccessState
        ReconciledFailed => ReconciledFailureState
        ReconciledNotApplied => ReconciledNotAppliedRetryEligible
      }
    None =>
      if self.requests.any(value => value.intent_ref == intent_ref) {
        ReconciliationRequestedState
      } else {
        match first(self.receipts, value => value.intent_ref == intent_ref) {
          Some(value) =>
            match value.outcome {
              Succeeded => KnownSuccess
              Failed => KnownFailure
              Unknown => UnknownOutcomeRequiresReconciliation
            }
          None =>
            if self.observations.any(value => value.intent_ref == intent_ref) {
              DispatchObservationPending
            } else {
              DurableIntentDispatchEligible
            }
        }
      }
  }
}

///|
fn StrictRetrySnapshot::retry_lineage(
  self : StrictRetrySnapshot,
  source_intent_ref : @contracts.RecordRef,
) -> RetryLineageV2 raise EffectsError {
  let reverse_intents : Array[DecodedIntentRecord] = []
  let reverse_attempts : Array[DecodedAttemptRecord] = []
  let mut cursor = source_intent_ref
  while true {
    if reverse_intents.any(value => value.intent_ref == cursor) {
      raise RetryEligibilityViolation(field="strict_retry_lineage_cycle")
    }
    guard first(self.intents, value => value.intent_ref == cursor)
      is Some(intent) else {
      raise RetryEligibilityViolation(field="strict_retry_lineage_intent")
    }
    guard first(self.attempts, value => value.attempt_ref == intent.attempt_ref)
      is Some(attempt) else {
      raise RetryEligibilityViolation(field="strict_retry_lineage_attempt")
    }
    reverse_intents.push(intent)
    reverse_attempts.push(attempt)
    match attempt.retry_of_intent_ref {
      Some(prior) => cursor = prior
      None => break
    }
  }
  let writer = EffectsWriter::new()
  try! writer.bytes(b"MF6/RETRY-LINEAGE-V2/2.0.0")
  try! writer.count(reverse_intents.length())
  let mut index = reverse_intents.length()
  while index > 0 {
    index = index - 1
    try! write_ref(writer, reverse_intents[index].intent_ref)
    try! write_ref(writer, reverse_attempts[index].attempt_ref)
  }
  let root_index = reverse_intents.length() - 1
  let attempt_count = reverse_intents.length().to_int64()
  {
    root_intent_ref: reverse_intents[root_index].intent_ref,
    root_attempt_ref: reverse_attempts[root_index].attempt_ref,
    source_intent_ref,
    source_attempt_ref: reverse_attempts[0].attempt_ref,
    attempt_count,
    retry_count: attempt_count - 1L,
    retry_ordinal: attempt_count - 1L,
    digest: @contracts.sha256_digest(writer.finish()),
  }
}

///|
fn StrictRetrySnapshot::require_receipt_current(
  self : StrictRetrySnapshot,
  receipt : CommittedRetryEligibilityReceiptV2,
) -> Unit raise EffectsError {
  receipt.require_integrity()
  let projection = strict_projection(self, None)
  if receipt.workflow() != self.workflow ||
    receipt.projection_sequence != self.sequence ||
    receipt.projection_revision() != self.revision ||
    receipt.projection_head_digest != self.last_event_digest.unwrap() ||
    receipt.projection_replay_digest != self.replay_digest ||
    receipt.projection_state_digest() != projection.state_digest() {
    raise RetryEligibilityViolation(field="strict_retry_receipt_projection")
  }
  if self.attempts.any(value => {
      value.retry_of_intent_ref == Some(receipt.source_intent_ref())
    }) {
    raise RetryEligibilityViolation(field="strict_retry_receipt_consumed")
  }
  let lineage = self.retry_lineage(receipt.source_intent_ref())
  if lineage.root_intent_ref != receipt.root_intent_ref() ||
    lineage.root_attempt_ref != receipt.root_attempt_ref() ||
    lineage.source_attempt_ref != receipt.source_attempt_ref() ||
    lineage.digest != receipt.lineage_digest() ||
    lineage.attempt_count != receipt.attempt_count() ||
    lineage.retry_count != receipt.retry_count() ||
    lineage.retry_ordinal != receipt.retry_ordinal() {
    raise RetryEligibilityViolation(field="strict_retry_receipt_lineage")
  }
  if receipt.cause_key() == retry_cause_terminal_failed_v2 {
    guard self.receipts.search_by(value => {
        value.receipt_ref == receipt.source_record_ref() &&
        value.intent_ref == receipt.source_intent_ref() &&
        value.outcome == Failed &&
        value.observed_at == receipt.source_observed_at()
      })
      is Some(index) else {
      raise RetryEligibilityViolation(field="strict_retry_failed_source")
    }
    if self.receipt_event_refs[index] != receipt.source_event_ref() {
      raise RetryEligibilityViolation(field="strict_retry_failed_event")
    }
  } else if receipt.cause_key() == retry_cause_reconciled_not_applied_v2 {
    guard self.reconciliations.search_by(value => {
        value.reconciliation_ref == receipt.source_record_ref() &&
        value.intent_ref == receipt.source_intent_ref() &&
        value.resolution == ReconciledNotApplied &&
        value.reconciled_at == receipt.source_observed_at()
      })
      is Some(index) else {
      raise RetryEligibilityViolation(
        field="strict_retry_reconciliation_source",
      )
    }
    if self.reconciliation_event_refs[index] != receipt.source_event_ref() {
      raise RetryEligibilityViolation(field="strict_retry_reconciliation_event")
    }
    guard receipt.unknown_receipt_ref is Some(unknown_ref) else {
      raise RetryEligibilityViolation(field="strict_retry_unknown_ref")
    }
    guard receipt.unknown_receipt_digest is Some(unknown_digest) else {
      raise RetryEligibilityViolation(field="strict_retry_unknown_digest")
    }
    guard receipt.unknown_receipt_event_ref is Some(unknown_event_ref) else {
      raise RetryEligibilityViolation(field="strict_retry_unknown_event")
    }
    guard receipt.reconciliation_request_ref is Some(request_ref) else {
      raise RetryEligibilityViolation(field="strict_retry_request_ref")
    }
    guard receipt.reconciliation_request_digest is Some(request_digest) else {
      raise RetryEligibilityViolation(field="strict_retry_request_digest")
    }
    guard receipt.reconciliation_request_event_ref is Some(request_event_ref) else {
      raise RetryEligibilityViolation(field="strict_retry_request_event")
    }
    if unknown_ref.digest() != unknown_digest ||
      request_ref.digest() != request_digest ||
      self.reconciliations[index].request_ref != request_ref {
      raise DigestMismatch(field="strict_retry_reconciliation_chain")
    }
    guard self.requests.search_by(value => {
        value.request_ref == request_ref &&
        value.intent_ref == receipt.source_intent_ref() &&
        value.unknown_receipt_ref == unknown_ref
      })
      is Some(request_index) else {
      raise RetryEligibilityViolation(field="strict_retry_request_source")
    }
    if self.request_event_refs[request_index] != request_event_ref {
      raise RetryEligibilityViolation(field="strict_retry_request_event")
    }
    guard self.receipts.search_by(value => {
        value.receipt_ref == unknown_ref &&
        value.intent_ref == receipt.source_intent_ref() &&
        value.outcome == Unknown
      })
      is Some(receipt_index) else {
      raise RetryEligibilityViolation(field="strict_retry_unknown_source")
    }
    if self.receipt_event_refs[receipt_index] != unknown_event_ref {
      raise RetryEligibilityViolation(field="strict_retry_unknown_event")
    }
  } else {
    raise RetryEligibilityViolation(field="strict_retry_receipt_cause")
  }
}

///|
fn normalize_governance_events(
  workflow : @contracts.RecordRef,
  events : Array[@storage.WorkflowEvent],
) -> Array[@storage.WorkflowEvent] raise EffectsError {
  let normalized : Array[@storage.WorkflowEvent] = []
  let mut previous : @contracts.ContentDigest? = None
  for index, event in events {
    let original = event.payload()
    let stage_ref = original.stage_ref()
    let attempt_ref = original.attempt_ref()
    let correlation_ref = original.correlation_ref()
    let causation_ref = original.causation_ref()
    let previous_digest = previous
    let envelope = @contracts.WireEnvelope::new(
      original.contract_id(),
      original.contract_version().text(),
      original.envelope_id(),
      original.envelope_kind(),
      original.subject(),
      original.schema(),
      original.payload(),
      original.producer_id(),
      original.producer_version().text(),
      [
        for artifact in original.artifacts() => artifact
      ],
      [
        for evidence in original.evidence() => evidence
      ],
      run_ref=workflow,
      stage_ref?,
      attempt_ref?,
      correlation_ref?,
      causation_ref?,
      idempotency_ref=event.idempotency_key(),
      previous_digest?,
      extensions=[ for extension in original.extensions() => extension ],
    ) catch {
      _ => raise GovernanceViolation(field="strict_governance_normalization")
    }
    let position = index.to_int64() + 1L
    let previous_event_digest = previous
    let normalized_event = @storage.WorkflowEvent::new(
      event.record_version().text(),
      event.schema_version().text(),
      workflow,
      event.event_ref().id(),
      position,
      position,
      event.idempotency_key(),
      envelope,
      [
        for evidence in event.evidence() => evidence
      ],
      previous_event_digest?,
    ) catch {
      _ => raise GovernanceViolation(field="strict_governance_normalization")
    }
    normalized.push(normalized_event)
    previous = Some(normalized_event.event_ref().digest())
  }
  normalized
}

///|
fn require_governance_prefix(
  summary : DecodedGovernanceSummary,
  events : Array[@storage.WorkflowEvent],
) -> Array[@contracts.RecordRef] raise EffectsError {
  let refs = [
    (
      "AuthorityRequested",
      summary.authority_request_ref,
      summary.authority_request_bytes,
    ),
    (
      "AuthorityGranted",
      summary.authority_grant_ref,
      summary.authority_grant_bytes,
    ),
    (
      "ReviewRequested",
      summary.review_request_ref,
      summary.review_request_bytes,
    ),
    (
      "ReviewDecisionRecorded",
      summary.review_decision_ref,
      summary.review_decision_bytes,
    ),
    (
      "ReviewReceiptBound",
      summary.review_receipt_ref,
      summary.review_receipt_bytes,
    ),
  ]
  for pair in refs {
    let matches = events.filter(event => {
      event.payload().envelope_kind() == pair.0 &&
      event.payload().subject() == pair.1 &&
      event.payload().payload() == pair.2
    })
    if matches.length() != 1 {
      raise IdentityMismatch(field="strict_governance_prefix_record")
    }
  }
  guard events.search_by(event => {
      event.payload().subject() == summary.review_receipt_ref
    })
    is Some(index) else {
    raise GovernanceViolation(field="strict_governance_prefix_receipt")
  }
  let governance_events = events[:index + 1].filter(event => {
    match event.payload().envelope_kind() {
      "EvidenceAttached"
      | "AuthorityRequested"
      | "AuthorityGranted"
      | "ReviewRequested"
      | "ReviewDecisionRecorded"
      | "ReviewReceiptBound" => true
      _ => false
    }
  })
  if governance_events.length() != 6 ||
    governance_events[0].payload().envelope_kind() != "EvidenceAttached" ||
    governance_events[1].payload().subject() != summary.authority_request_ref ||
    governance_events[2].payload().subject() != summary.authority_grant_ref ||
    governance_events[3].payload().subject() != summary.review_request_ref ||
    governance_events[4].payload().subject() != summary.review_decision_ref ||
    governance_events[5].payload().subject() != summary.review_receipt_ref {
    raise GovernanceViolation(field="strict_governance_event_catalog")
  }
  for event in governance_events {
    let envelope = event.payload()
    if event.workflow() != summary.workflow ||
      envelope.run_ref() != Some(summary.workflow) ||
      envelope.envelope_id() != event.event_ref().id() ||
      envelope.idempotency_ref() != Some(event.idempotency_key()) ||
      envelope.previous_digest() != event.previous_event_digest() ||
      !same_evidence(event.evidence(), envelope.evidence()) {
      raise GovernanceViolation(field="strict_governance_transport_binding")
    }
  }
  guard events.search_by(event => {
      event.payload().envelope_kind() == "EvidenceAttached"
    })
    is Some(first_governance_index) else {
    raise GovernanceViolation(field="strict_governance_event_catalog")
  }
  if index - first_governance_index + 1 != 6 {
    raise GovernanceViolation(field="strict_governance_event_interleaving")
  }
  let normalized_governance = normalize_governance_events(
    summary.workflow,
    governance_events,
  )
  if strict_replay_digest(summary.workflow, normalized_governance) !=
    summary.authoritative_replay_digest {
    raise GovernanceViolation(field="strict_governance_prefix_digest")
  }
  if summary.semantic_v2 {
    let policy = try
      @governance.GovernancePolicy::decode(
        summary.policy_ref,
        summary.policy_bytes,
      )
    catch {
      _ => raise GovernanceViolation(field="strict_governance_policy")
    } noraise {
      value => value
    }
    let mut governance = @governance.GovernanceProjection::new(
      policy,
      summary.workflow,
    )
    for event in normalized_governance {
      governance = try governance.apply_event(event) catch {
        _ => raise GovernanceViolation(field="strict_governance_semantics")
      } noraise {
        value => value
      }
    }
    guard governance.receipt() is Some(receipt) else {
      raise GovernanceViolation(field="strict_governance_receipt_missing")
    }
    guard governance.authority_request_record() is Some(authority_request) else {
      raise GovernanceViolation(
        field="strict_governance_authority_request_missing",
      )
    }
    guard governance.authority_decision_record() is Some(authority_decision) else {
      raise GovernanceViolation(
        field="strict_governance_authority_decision_missing",
      )
    }
    guard governance.review_request_record() is Some(review_request) else {
      raise GovernanceViolation(
        field="strict_governance_review_request_missing",
      )
    }
    guard governance.review_decision_record() is Some(review_decision) else {
      raise GovernanceViolation(
        field="strict_governance_review_decision_missing",
      )
    }
    let review_subject = review_request.subject()
    if policy.policy_ref() != summary.policy_ref ||
      governance.workflow() != summary.workflow ||
      authority_request.request_ref() != summary.authority_request_ref ||
      authority_request.expires_at() != summary.authority_expires_at ||
      authority_decision.decision_ref() != summary.authority_grant_ref ||
      authority_decision.authority_ref() != summary.authority_ref ||
      review_request.request_ref() != summary.review_request_ref ||
      review_subject.subject() != summary.governed_subject ||
      review_subject.envelope_digest() != summary.governed_subject_digest ||
      review_decision.decision_ref() != summary.review_decision_ref ||
      review_decision.reviewer_ref() != summary.reviewer_ref {
      raise GovernanceViolation(field="strict_governance_summary_binding")
    }
    if governance.authority_status() != @governance.AuthorityGrantedStatus ||
      governance.review_status() !=
      @governance.ReviewReceiptBoundStatus(@governance.Approved) ||
      receipt.receipt_ref() != summary.review_receipt_ref ||
      governance.state_digest() != summary.projection_digest {
      raise GovernanceViolation(field="strict_governance_projection")
    }
  }
  governance_events.map(event => event.event_ref())
}

///|
fn strict_effect_event_kind(kind : String) -> Bool {
  kind == "attempt.registered.v1" ||
  kind == "effect.intent.requested.v1" ||
  kind == "effect.dispatch.observed.v1" ||
  kind == "effect.receipt.recorded.v1" ||
  kind == "effect.outcome.unknown.v1" ||
  kind == "effect.reconciliation.requested.v1" ||
  kind == "effect.reconciliation.resolved.v1"
}

///|
fn known_effect_payload(bytes : Bytes) -> Bool {
  try EffectsReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    tag =>
      tag == b"MF6AATT1" ||
      tag == b"MF6AINT1" ||
      tag == b"MF6ADOB1" ||
      tag == b"MF6AERC1" ||
      tag == b"MF6ARRQ1" ||
      tag == b"MF6ARSL1"
  }
}

///|
fn peek_intent_ref(
  bytes : Bytes,
  tag : Bytes,
  version_fields : Int,
  field : String,
) -> @contracts.RecordRef raise EffectsError {
  let reader = EffectsReader::new(bytes)
  if reader.read_bytes() != tag {
    raise MalformedRecord(field~)
  }
  for _ in 0..<version_fields {
    ignore(reader.read_string())
  }
  ignore(reader.read_string())
  reader.read_ref()
}

///|
/// Rebuild the retry-authoritative effects view from committed bytes only.
/// No ReplayCatalog, fixture object, or caller-decoded domain record participates.
fn strict_retry_snapshot_from_replay(
  empty : EffectsProjection,
  replay : @storage.ReplayResult,
) -> StrictRetrySnapshot raise EffectsError {
  if replay.workflow() != empty.workflow {
    raise IdentityMismatch(field="strict_replay_workflow")
  }
  let events : Array[@storage.WorkflowEvent] = []
  let attempts : Array[DecodedAttemptRecord] = []
  let intents : Array[DecodedIntentRecord] = []
  let observations : Array[DecodedObservationRecord] = []
  let receipts : Array[DecodedReceiptRecord] = []
  let receipt_event_refs : Array[@contracts.RecordRef] = []
  let requests : Array[DecodedReconciliationRequestRecord] = []
  let request_event_refs : Array[@contracts.RecordRef] = []
  let reconciliations : Array[DecodedReconciliationRecord] = []
  let reconciliation_event_refs : Array[@contracts.RecordRef] = []
  let consumed_event_refs : Array[@contracts.RecordRef] = []
  let matched_outbox_refs : Array[@contracts.RecordRef] = []
  for event in replay.events() {
    if event.workflow() != empty.workflow {
      raise IdentityMismatch(field="strict_effect_event_workflow")
    }
    let envelope = event.payload()
    let kind = envelope.envelope_kind()
    let payload = envelope.payload()
    match kind {
      "attempt.registered.v1" => {
        guard envelope.attempt_ref() is Some(expected_attempt_ref) else {
          raise IdentityMismatch(field="strict_attempt_envelope_ref")
        }
        let value = decode_attempt_record_strict(
          expected_attempt_ref.id(),
          payload,
        )
        if value.attempt_ref != expected_attempt_ref ||
          value.workflow != empty.workflow ||
          value.governance.policy_ref != empty.policy_ref {
          raise IdentityMismatch(field="strict_attempt_projection_binding")
        }
        let governance_refs = require_governance_prefix(
          value.governance,
          events,
        )
        for governance_ref in governance_refs {
          if !consumed_event_refs.any(existing => existing == governance_ref) {
            consumed_event_refs.push(governance_ref)
          }
        }
        if !events.any(prior => prior.event_ref() == value.causal_event_ref) {
          raise OrderingViolation(field="strict_attempt_causal_event")
        }
        if attempts.any(prior => {
            prior.attempt_ref == value.attempt_ref ||
            prior.idempotency_key == value.idempotency_key ||
            prior.attempt_ordinal >= value.attempt_ordinal
          }) {
          raise OrderingViolation(field="strict_attempt_order")
        }
        match
          (value.retry_of_intent_ref, value.retry_receipt, value.retry_plan) {
          (None, None, None) => ()
          (Some(source), Some(receipt), Some(plan)) => {
            let prefix = build_strict_snapshot(
              empty.workflow,
              empty.policy_ref,
              events,
              attempts,
              intents,
              observations,
              receipts,
              receipt_event_refs,
              requests,
              request_event_refs,
              reconciliations,
              reconciliation_event_refs,
              consumed_event_refs,
              matched_outbox_refs,
            )
            prefix.require_receipt_current(receipt)
            if plan.prefix_sequence() != prefix.sequence ||
              plan.prefix_revision() != prefix.revision ||
              plan.prefix_head_digest() != prefix.last_event_digest.unwrap() ||
              plan.prefix_replay_digest() != prefix.replay_digest {
              raise RetryEligibilityViolation(field="strict_retry_plan_prefix")
            }
            guard first(intents, prior => prior.intent_ref == source)
              is Some(source_intent) else {
              raise RetryEligibilityViolation(field="strict_retry_source")
            }
            guard first(attempts, prior => {
                prior.attempt_ref == source_intent.attempt_ref
              })
              is Some(source_attempt) else {
              raise RetryEligibilityViolation(
                field="strict_retry_source_attempt",
              )
            }
            if value.attempt_ordinal != source_attempt.attempt_ordinal + 1L {
              raise OrderingViolation(field="strict_retry_attempt_ordinal")
            }
          }
          _ => raise RetryEligibilityViolation(field="strict_retry_pair")
        }
        require_event_binding(
          event,
          kind,
          value.governance.governed_subject,
          value.attempt_ref,
          value.idempotency_key,
          value.idempotency_key,
          value.causal_event_ref.id(),
          value.previous_digest,
          value.evidence,
        )
        attempts.push(value)
      }
      "effect.intent.requested.v1" => {
        guard envelope.attempt_ref() is Some(attempt_ref) else {
          raise IdentityMismatch(field="strict_intent_attempt_ref")
        }
        guard first(attempts, value => value.attempt_ref == attempt_ref)
          is Some(attempt) else {
          raise OrderingViolation(field="strict_intent_before_attempt")
        }
        let value = decode_intent_record_strict(payload, attempt)
        if intents.any(prior => {
            prior.intent_ref == value.intent_ref ||
            prior.external_idempotency_key == value.external_idempotency_key
          }) {
          raise IdempotencyConflict(key=value.external_idempotency_key)
        }
        require_event_binding(
          event,
          kind,
          value.governed_subject,
          value.attempt_ref,
          "effect-event/\{value.external_idempotency_key}",
          value.external_idempotency_key,
          value.attempt_ref.id(),
          value.previous_digest,
          value.evidence,
        )
        let matching = replay
          .intents()
          .filter(outbox => {
            outbox.causative_event() == event.event_ref() &&
            outbox.workflow() == value.workflow
          })
        if matching.length() != 1 ||
          matching[0].idempotency_key() != value.external_idempotency_key ||
          matching[0].payload() != value.effect_request ||
          !same_evidence(matching[0].evidence(), value.evidence) {
          raise OutboxAtomicityViolation(field="strict_event_outbox_binding")
        }
        let atomic_batches = replay
          .committed_batches()
          .filter(batch => {
            batch.event_refs().length() == 1 &&
            batch.event_refs()[0] == event.event_ref() &&
            batch.intent_refs().length() == 1 &&
            batch.intent_refs()[0] == matching[0].intent_ref()
          })
        if atomic_batches.length() != 1 {
          raise OutboxAtomicityViolation(
            field="strict_event_outbox_commit_boundary",
          )
        }
        matched_outbox_refs.push(matching[0].intent_ref())
        intents.push(value)
      }
      "effect.dispatch.observed.v1" => {
        let intent_ref = peek_intent_ref(
          payload, b"MF6ADOB1", 1, "strict_observation",
        )
        guard first(intents, value => value.intent_ref == intent_ref)
          is Some(intent) else {
          raise OrderingViolation(field="strict_observation_before_intent")
        }
        let value = decode_observation_record_strict(
          event.idempotency_key(),
          payload,
          intent,
        )
        let prefix = build_strict_snapshot(
          empty.workflow,
          empty.policy_ref,
          events,
          attempts,
          intents,
          observations,
          receipts,
          receipt_event_refs,
          requests,
          request_event_refs,
          reconciliations,
          reconciliation_event_refs,
          consumed_event_refs,
          matched_outbox_refs,
        )
        if prefix.state_for(intent_ref) != DurableIntentDispatchEligible {
          raise InvalidState(field="strict_observation_state")
        }
        require_event_binding(
          event,
          kind,
          intent.governed_subject,
          intent.attempt_ref,
          value.observation_ref.id(),
          value.observation_ref.id(),
          intent.intent_ref.id(),
          event.previous_event_digest().unwrap(),
          value.evidence,
        )
        observations.push(value)
      }
      "effect.receipt.recorded.v1" | "effect.outcome.unknown.v1" => {
        let intent_ref = peek_intent_ref(
          payload, b"MF6AERC1", 2, "strict_receipt",
        )
        guard first(intents, value => value.intent_ref == intent_ref)
          is Some(intent) else {
          raise OrderingViolation(field="strict_receipt_before_intent")
        }
        let value = decode_receipt_record_strict(
          event.idempotency_key(),
          payload,
          intent,
        )
        if (kind == "effect.outcome.unknown.v1" && value.outcome != Unknown) ||
          (kind == "effect.receipt.recorded.v1" && value.outcome == Unknown) {
          raise OutcomeConflict(field="strict_receipt_kind")
        }
        let prefix = build_strict_snapshot(
          empty.workflow,
          empty.policy_ref,
          events,
          attempts,
          intents,
          observations,
          receipts,
          receipt_event_refs,
          requests,
          request_event_refs,
          reconciliations,
          reconciliation_event_refs,
          consumed_event_refs,
          matched_outbox_refs,
        )
        if prefix.state_for(intent_ref) != DispatchObservationPending {
          raise InvalidState(field="strict_receipt_state")
        }
        require_event_binding(
          event,
          kind,
          intent.governed_subject,
          intent.attempt_ref,
          value.receipt_ref.id(),
          value.receipt_ref.id(),
          intent.intent_ref.id(),
          event.previous_event_digest().unwrap(),
          value.evidence,
        )
        receipts.push(value)
        receipt_event_refs.push(event.event_ref())
      }
      "effect.reconciliation.requested.v1" => {
        let intent_ref = peek_intent_ref(
          payload, b"MF6ARRQ1", 1, "strict_request",
        )
        guard first(intents, value => value.intent_ref == intent_ref)
          is Some(intent) else {
          raise ReconciliationViolation(field="strict_request_intent")
        }
        guard first(receipts, value => {
            value.intent_ref == intent_ref && value.outcome == Unknown
          })
          is Some(unknown) else {
          raise ReconciliationViolation(field="strict_request_unknown")
        }
        let value = decode_reconciliation_request_strict(
          event.idempotency_key(),
          payload,
          intent,
          unknown,
        )
        let prefix = build_strict_snapshot(
          empty.workflow,
          empty.policy_ref,
          events,
          attempts,
          intents,
          observations,
          receipts,
          receipt_event_refs,
          requests,
          request_event_refs,
          reconciliations,
          reconciliation_event_refs,
          consumed_event_refs,
          matched_outbox_refs,
        )
        if prefix.state_for(intent_ref) != UnknownOutcomeRequiresReconciliation {
          raise ReconciliationViolation(field="strict_request_state")
        }
        require_event_binding(
          event,
          kind,
          intent.governed_subject,
          intent.attempt_ref,
          value.request_ref.id(),
          value.request_ref.id(),
          intent.intent_ref.id(),
          event.previous_event_digest().unwrap(),
          value.evidence,
        )
        requests.push(value)
        request_event_refs.push(event.event_ref())
      }
      "effect.reconciliation.resolved.v1" => {
        let intent_ref = peek_intent_ref(
          payload, b"MF6ARSL1", 1, "strict_resolution",
        )
        guard first(intents, value => value.intent_ref == intent_ref)
          is Some(intent) else {
          raise ReconciliationViolation(field="strict_resolution_intent")
        }
        let request_reader = EffectsReader::new(payload)
        ignore(request_reader.read_bytes())
        ignore(request_reader.read_string())
        ignore(request_reader.read_string())
        ignore(request_reader.read_ref())
        let request_ref = request_reader.read_ref()
        guard first(requests, value => value.request_ref == request_ref)
          is Some(request) else {
          raise ReconciliationViolation(field="strict_resolution_request")
        }
        let value = decode_reconciliation_record_strict(
          event.idempotency_key(),
          payload,
          intent,
          request,
        )
        let prefix = build_strict_snapshot(
          empty.workflow,
          empty.policy_ref,
          events,
          attempts,
          intents,
          observations,
          receipts,
          receipt_event_refs,
          requests,
          request_event_refs,
          reconciliations,
          reconciliation_event_refs,
          consumed_event_refs,
          matched_outbox_refs,
        )
        if prefix.state_for(intent_ref) != ReconciliationRequestedState {
          raise ReconciliationViolation(field="strict_resolution_state")
        }
        require_event_binding(
          event,
          kind,
          intent.governed_subject,
          intent.attempt_ref,
          value.reconciliation_ref.id(),
          value.reconciliation_ref.id(),
          intent.intent_ref.id(),
          event.previous_event_digest().unwrap(),
          value.evidence,
        )
        reconciliations.push(value)
        reconciliation_event_refs.push(event.event_ref())
      }
      _ =>
        if known_effect_payload(payload) {
          raise MalformedRecord(field="strict_known_payload_unknown_wrapper")
        }
    }
    if strict_effect_event_kind(kind) {
      consumed_event_refs.push(event.event_ref())
    }
    events.push(event)
  }
  let head = replay.head()
  if head.sequence() != events.length().to_int64() ||
    head.revision() != events.length().to_int64() ||
    head.last_event_digest() !=
    events.last().map(value => value.event_ref().digest()) ||
    replay.replay_digest() != strict_replay_digest(empty.workflow, events) {
    raise RevisionMismatch(
      expected=events.length().to_int64(),
      actual=head.revision(),
    )
  }
  build_strict_snapshot(
    empty.workflow,
    empty.policy_ref,
    events,
    attempts,
    intents,
    observations,
    receipts,
    receipt_event_refs,
    requests,
    request_event_refs,
    reconciliations,
    reconciliation_event_refs,
    consumed_event_refs,
    matched_outbox_refs,
  )
}

///|
/// Rebuild the retry-authoritative effects view from committed bytes only.
/// No ReplayCatalog, fixture object, or caller-decoded domain record participates.
pub fn fold_committed_effects_bytes(
  empty : EffectsProjection,
  replay : @storage.ReplayResult,
) -> EffectsProjection raise EffectsError {
  let snapshot = strict_retry_snapshot_from_replay(empty, replay)
  strict_projection(snapshot, Some(replay))
}

///|
fn EffectsProjection::require_strict_retry_snapshot(
  self : EffectsProjection,
  field : String,
) -> StrictRetrySnapshot raise EffectsError {
  guard self.strict_replay is Some(replay) else {
    raise RetryEligibilityViolation(field~)
  }
  let snapshot = strict_retry_snapshot_from_replay(
    EffectsProjection::new(self.workflow, self.policy_ref),
    replay,
  )
  guard self.strict_snapshot_digest is Some(expected) &&
    snapshot.digest == expected else {
    raise DigestMismatch(field="strict_snapshot_digest")
  }
  snapshot
}

///|
/// Return the exact retry proposal reconstructed from committed attempt bytes.
/// This is available only on a projection produced by strict replay.
pub fn EffectsProjection::committed_retry_plan(
  self : EffectsProjection,
  attempt_ref : @contracts.RecordRef,
) -> @retry_authority.RetryPlanProposalV2? raise EffectsError {
  let snapshot = self.require_strict_retry_snapshot(
    "retry_plan_requires_strict_replay",
  )
  match first(snapshot.attempts, value => value.attempt_ref == attempt_ref) {
    None => None
    Some(value) => value.retry_plan
  }
}

///|
/// Exact event refs consumed by the strict effects/governance decoder.
pub fn EffectsProjection::strict_consumed_event_refs(
  self : EffectsProjection,
) -> ReadOnlyArray[@contracts.RecordRef] raise EffectsError {
  let snapshot = self.require_strict_retry_snapshot(
    "strict_coverage_requires_replay",
  )
  snapshot.consumed_event_refs
}

///|
/// Exact request-only outbox refs matched to consumed effect-intent events.
pub fn EffectsProjection::strict_matched_outbox_refs(
  self : EffectsProjection,
) -> ReadOnlyArray[@contracts.RecordRef] raise EffectsError {
  let snapshot = self.require_strict_retry_snapshot(
    "strict_coverage_requires_replay",
  )
  snapshot.matched_outbox_refs
}

///|
/// Return the exact request-only outbox record paired by strict replay with
/// one committed effect intent. This is inert provenance only: it cannot
/// prepare a write or cross an external-effect port.
pub fn EffectsProjection::strict_matched_outbox_ref_for(
  self : EffectsProjection,
  intent_ref : @contracts.RecordRef,
) -> @contracts.RecordRef raise EffectsError {
  let snapshot = self.require_strict_retry_snapshot(
    "strict_coverage_requires_replay",
  )
  guard snapshot.intents.search_by(value => value.intent_ref == intent_ref)
    is Some(index) else {
    raise IdentityMismatch(field="strict_unknown_intent")
  }
  if index >= snapshot.matched_outbox_refs.length() {
    raise OutboxAtomicityViolation(field="strict_event_outbox_binding")
  }
  snapshot.matched_outbox_refs[index]
}

///|
/// Opaque, inert dispatch target reconstructed from strict committed bytes.
/// It deliberately owns no port call and no state transition.
pub struct StrictDispatchTargetV2 {
  intent_ref : @contracts.RecordRef
  attempt_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  effect_request : @contracts.WireEnvelope
  external_idempotency_key : String
  outbox_ref : @contracts.RecordRef
  authoritative_replay_digest : @contracts.ContentDigest
  intent_canonical : Bytes
}

///|
pub fn EffectsProjection::strict_dispatch_target_v2(
  self : EffectsProjection,
  intent_ref : @contracts.RecordRef,
) -> StrictDispatchTargetV2 raise EffectsError {
  let snapshot = self.require_strict_retry_snapshot(
    "strict_dispatch_requires_replay",
  )
  guard snapshot.intents.search_by(value => value.intent_ref == intent_ref)
    is Some(index) else {
    raise IdentityMismatch(field="strict_unknown_intent")
  }
  if snapshot.state_for(intent_ref) != DurableIntentDispatchEligible {
    raise InvalidState(field="intent_not_dispatch_eligible")
  }
  if index >= snapshot.matched_outbox_refs.length() {
    raise OutboxAtomicityViolation(field="strict_event_outbox_binding")
  }
  let intent = snapshot.intents[index]
  {
    intent_ref: intent.intent_ref,
    attempt_ref: intent.attempt_ref,
    governed_subject: intent.governed_subject,
    effect_request: intent.effect_request,
    external_idempotency_key: intent.external_idempotency_key,
    outbox_ref: snapshot.matched_outbox_refs[index],
    authoritative_replay_digest: snapshot.replay_digest,
    intent_canonical: intent.canonical,
  }
}

///|
pub fn StrictDispatchTargetV2::intent_ref(
  self : StrictDispatchTargetV2,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn StrictDispatchTargetV2::attempt_ref(
  self : StrictDispatchTargetV2,
) -> @contracts.RecordRef {
  self.attempt_ref
}

///|
pub fn StrictDispatchTargetV2::governed_subject(
  self : StrictDispatchTargetV2,
) -> @contracts.RecordRef {
  self.governed_subject
}

///|
pub fn StrictDispatchTargetV2::effect_request(
  self : StrictDispatchTargetV2,
) -> @contracts.WireEnvelope {
  self.effect_request
}

///|
pub fn StrictDispatchTargetV2::external_idempotency_key(
  self : StrictDispatchTargetV2,
) -> String {
  self.external_idempotency_key
}

///|
pub fn StrictDispatchTargetV2::outbox_ref(
  self : StrictDispatchTargetV2,
) -> @contracts.RecordRef {
  self.outbox_ref
}

///|
pub fn StrictDispatchTargetV2::authoritative_replay_digest(
  self : StrictDispatchTargetV2,
) -> @contracts.ContentDigest {
  self.authoritative_replay_digest
}

///|
pub fn StrictDispatchTargetV2::intent_canonical_bytes(
  self : StrictDispatchTargetV2,
) -> Bytes {
  self.intent_canonical
}

///|
/// Opaque current state for one exact strictly replayed durable intent.
pub struct StrictIntentStateV2 {
  intent_ref : @contracts.RecordRef
  attempt_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  external_idempotency_key : String
  outbox_ref : @contracts.RecordRef
  state : ReconciliationState
  authoritative_replay_digest : @contracts.ContentDigest
  intent_canonical : Bytes
}

///|
pub fn EffectsProjection::strict_intent_state_v2(
  self : EffectsProjection,
  intent_ref : @contracts.RecordRef,
) -> StrictIntentStateV2 raise EffectsError {
  let snapshot = self.require_strict_retry_snapshot(
    "strict_intent_state_requires_replay",
  )
  guard snapshot.intents.search_by(value => value.intent_ref == intent_ref)
    is Some(index) else {
    raise IdentityMismatch(field="strict_unknown_intent")
  }
  if index >= snapshot.matched_outbox_refs.length() {
    raise OutboxAtomicityViolation(field="strict_event_outbox_binding")
  }
  let intent = snapshot.intents[index]
  {
    intent_ref: intent.intent_ref,
    attempt_ref: intent.attempt_ref,
    governed_subject: intent.governed_subject,
    external_idempotency_key: intent.external_idempotency_key,
    outbox_ref: snapshot.matched_outbox_refs[index],
    state: snapshot.state_for(intent_ref),
    authoritative_replay_digest: snapshot.replay_digest,
    intent_canonical: intent.canonical,
  }
}

///|
pub fn StrictIntentStateV2::intent_ref(
  self : StrictIntentStateV2,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn StrictIntentStateV2::attempt_ref(
  self : StrictIntentStateV2,
) -> @contracts.RecordRef {
  self.attempt_ref
}

///|
pub fn StrictIntentStateV2::governed_subject(
  self : StrictIntentStateV2,
) -> @contracts.RecordRef {
  self.governed_subject
}

///|
pub fn StrictIntentStateV2::external_idempotency_key(
  self : StrictIntentStateV2,
) -> String {
  self.external_idempotency_key
}

///|
pub fn StrictIntentStateV2::outbox_ref(
  self : StrictIntentStateV2,
) -> @contracts.RecordRef {
  self.outbox_ref
}

///|
pub fn StrictIntentStateV2::state(
  self : StrictIntentStateV2,
) -> ReconciliationState {
  self.state
}

///|
pub fn StrictIntentStateV2::authoritative_replay_digest(
  self : StrictIntentStateV2,
) -> @contracts.ContentDigest {
  self.authoritative_replay_digest
}

///|
pub fn StrictIntentStateV2::intent_canonical_bytes(
  self : StrictIntentStateV2,
) -> Bytes {
  self.intent_canonical
}

///|
/// Opaque, inert adapter target reconstructed from a committed attempt.
pub struct StrictAttemptTargetV2 {
  attempt_ref : @contracts.RecordRef
  requested_work : @contracts.WireEnvelope
  idempotency_key : String
  authoritative_replay_digest : @contracts.ContentDigest
  attempt_canonical : Bytes
}

///|
pub fn EffectsProjection::strict_attempt_target_v2(
  self : EffectsProjection,
  attempt_ref : @contracts.RecordRef,
) -> StrictAttemptTargetV2 raise EffectsError {
  let snapshot = self.require_strict_retry_snapshot(
    "strict_attempt_target_requires_replay",
  )
  guard first(snapshot.attempts, value => value.attempt_ref == attempt_ref)
    is Some(attempt) else {
    raise IdentityMismatch(field="strict_unknown_attempt")
  }
  {
    attempt_ref: attempt.attempt_ref,
    requested_work: attempt.requested_work,
    idempotency_key: attempt.idempotency_key,
    authoritative_replay_digest: snapshot.replay_digest,
    attempt_canonical: attempt.canonical,
  }
}

///|
pub fn StrictAttemptTargetV2::attempt_ref(
  self : StrictAttemptTargetV2,
) -> @contracts.RecordRef {
  self.attempt_ref
}

///|
pub fn StrictAttemptTargetV2::requested_work(
  self : StrictAttemptTargetV2,
) -> @contracts.WireEnvelope {
  self.requested_work
}

///|
pub fn StrictAttemptTargetV2::idempotency_key(
  self : StrictAttemptTargetV2,
) -> String {
  self.idempotency_key
}

///|
pub fn StrictAttemptTargetV2::authoritative_replay_digest(
  self : StrictAttemptTargetV2,
) -> @contracts.ContentDigest {
  self.authoritative_replay_digest
}

///|
pub fn StrictAttemptTargetV2::attempt_canonical_bytes(
  self : StrictAttemptTargetV2,
) -> Bytes {
  self.attempt_canonical
}

///|
/// Return the latest committed attempt and only the latest intent committed
/// for that exact attempt. Historical intents remain in replay but are never
/// paired with a newer retry attempt.
pub fn EffectsProjection::latest_attempt_intent_refs(
  self : EffectsProjection,
) -> (@contracts.RecordRef?, @contracts.RecordRef?) raise EffectsError {
  match self.strict_replay {
    Some(replay) => {
      let snapshot = strict_retry_snapshot_from_replay(
        EffectsProjection::new(self.workflow, self.policy_ref),
        replay,
      )
      for intent in snapshot.intents {
        if !snapshot.attempts.any(attempt => {
            attempt.attempt_ref == intent.attempt_ref
          }) {
          raise OrderingViolation(field="strict_intent_without_attempt")
        }
      }
      guard snapshot.attempts.last() is Some(attempt) else {
        if !snapshot.intents.is_empty() {
          raise OrderingViolation(field="strict_intent_without_attempt")
        }
        return (None, None)
      }
      let mut matching : @contracts.RecordRef? = None
      for intent in snapshot.intents {
        if intent.attempt_ref == attempt.attempt_ref {
          matching = Some(intent.intent_ref)
        }
      }
      (Some(attempt.attempt_ref), matching)
    }
    None => {
      for intent in self.intents {
        if !self.attempts.any(attempt => {
            attempt.attempt_ref() == intent.attempt_ref()
          }) {
          raise OrderingViolation(field="intent_without_attempt")
        }
      }
      guard self.attempts.last() is Some(attempt) else {
        if !self.intents.is_empty() {
          raise OrderingViolation(field="intent_without_attempt")
        }
        return (None, None)
      }
      let mut matching : @contracts.RecordRef? = None
      for intent in self.intents {
        if intent.attempt_ref() == attempt.attempt_ref() {
          matching = Some(intent.intent_ref())
        }
      }
      (Some(attempt.attempt_ref()), matching)
    }
  }
}

///|
/// Enumerate all committed intent identities from the authoritative replay.
/// This preserves historical intents even when the strict projection keeps
/// decoded domain records private.
pub fn EffectsProjection::committed_intent_refs(
  self : EffectsProjection,
) -> ReadOnlyArray[@contracts.RecordRef] raise EffectsError {
  match self.strict_replay {
    Some(replay) => {
      let snapshot = strict_retry_snapshot_from_replay(
        EffectsProjection::new(self.workflow, self.policy_ref),
        replay,
      )
      ReadOnlyArray::from_array(
        [
          for intent in snapshot.intents => intent.intent_ref
        ],
      )
    }
    None =>
      ReadOnlyArray::from_array(
        [
          for intent in self.intents => intent.intent_ref()
        ],
      )
  }
}

///|
/// Opaque identity for one fully decoded legacy observation/receipt event.
pub struct StrictLegacyTransitionIdentityV3 {
  event_ref : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
}

///|
/// Attribute every committed legacy dispatch observation or receipt to its
/// exact intent in one strict replay pass. The strict snapshot has already
/// fully decoded, canonicalized, and consumed every returned event.
pub fn EffectsProjection::strict_legacy_transition_catalog_v3(
  self : EffectsProjection,
) -> ReadOnlyArray[StrictLegacyTransitionIdentityV3] raise EffectsError {
  let snapshot = self.require_strict_retry_snapshot(
    "strict_legacy_transition_requires_replay",
  )
  guard self.strict_replay is Some(replay) else {
    raise RetryEligibilityViolation(
      field="strict_legacy_transition_requires_replay",
    )
  }
  let values : Array[StrictLegacyTransitionIdentityV3] = []
  for event in replay.events() {
    if snapshot.consumed_event_refs.any(value => value == event.event_ref()) {
      let intent_ref = match event.payload().envelope_kind() {
        "effect.dispatch.observed.v1" =>
          Some(
            peek_intent_ref(
              event.payload().payload(),
              b"MF6ADOB1",
              1,
              "strict_legacy_observation",
            ),
          )
        "effect.receipt.recorded.v1" | "effect.outcome.unknown.v1" =>
          Some(
            peek_intent_ref(
              event.payload().payload(),
              b"MF6AERC1",
              2,
              "strict_legacy_receipt",
            ),
          )
        _ => None
      }
      match intent_ref {
        None => ()
        Some(intent_ref) =>
          values.push({ event_ref: event.event_ref(), intent_ref })
      }
    }
  }
  ReadOnlyArray::from_array(values)
}

///|
pub fn StrictLegacyTransitionIdentityV3::event_ref(
  self : StrictLegacyTransitionIdentityV3,
) -> @contracts.RecordRef {
  self.event_ref
}

///|
pub fn StrictLegacyTransitionIdentityV3::intent_ref(
  self : StrictLegacyTransitionIdentityV3,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
/// Whether every committed attempt was bound to the semantic governance V2
/// record. Standalone strict effects replay keeps accepting frozen V1 records;
/// the aggregate closed loop requires this stronger binding.
pub fn EffectsProjection::strict_semantic_governance_v2(
  self : EffectsProjection,
) -> Bool {
  match self.strict_replay {
    None => false
    Some(_) => {
      let snapshot = try! self.require_strict_retry_snapshot(
        "strict_governance_requires_replay",
      )
      !snapshot.attempts.is_empty() &&
      !snapshot.attempts.any(value => !value.governance.semantic_v2)
    }
  }
}

///|
/// Return the exact retry eligibility receipt reconstructed from the same
/// committed attempt bytes as `committed_retry_plan`.
pub fn EffectsProjection::committed_retry_receipt_for_attempt(
  self : EffectsProjection,
  attempt_ref : @contracts.RecordRef,
) -> CommittedRetryEligibilityReceiptV2? raise EffectsError {
  let snapshot = self.require_strict_retry_snapshot(
    "retry_receipt_requires_strict_replay",
  )
  match first(snapshot.attempts, value => value.attempt_ref == attempt_ref) {
    None => None
    Some(value) => value.retry_receipt
  }
}
