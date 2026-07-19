///|
pub(all) enum OutcomeObservationKindV1 {
  OutcomeObservedV1
  OutcomeMissingV1
  OutcomeLateV1
  OutcomeConflictingV1
  OutcomeCorrectedV1
} derive(Eq, Debug)

///|
fn OutcomeObservationKindV1::wire(self : OutcomeObservationKindV1) -> String {
  match self {
    OutcomeObservedV1 => "observed"
    OutcomeMissingV1 => "missing"
    OutcomeLateV1 => "late"
    OutcomeConflictingV1 => "conflicting"
    OutcomeCorrectedV1 => "corrected"
  }
}

///|
fn write_optional_envelope_v1(
  writer : OrchestrationWriter,
  value : @contracts.WireEnvelope?,
) -> Unit raise OrchestrationError {
  match value {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      writer.bytes(value.canonical_bytes())
    }
  }
}

///|
fn write_refs_v1(
  writer : OrchestrationWriter,
  values : ArrayView[@contracts.RecordRef],
) -> Unit raise OrchestrationError {
  writer.count(values.length())
  for value in values {
    write_ref(writer, value)
  }
}

///|
fn copy_unique_refs_v1(
  values : Array[@contracts.RecordRef],
  field : String,
) -> ReadOnlyArray[@contracts.RecordRef] raise OrchestrationError {
  for index, value in values {
    for prior in 0..<index {
      if values[prior] == value {
        raise IdentityMismatch(field~)
      }
    }
  }
  ReadOnlyArray::from_array(values.copy())
}

///|
/// One immutable outcome fact. Missing, late, conflict, and correction are
/// retained as history rather than overwriting earlier facts.
pub struct OutcomeObservationV1 {
  observation_ref : @contracts.RecordRef
  delivery_receipt_ref : @contracts.RecordRef
  sequence : Int64
  previous_observation_ref : @contracts.RecordRef?
  kind : OutcomeObservationKindV1
  payload : @contracts.WireEnvelope?
  expected_at : Int64?
  source_observed_at : Int64?
  late_for_ref : @contracts.RecordRef?
  correction_of_ref : @contracts.RecordRef?
  conflicts_with : ReadOnlyArray[@contracts.RecordRef]
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  recorded_at : Int64
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub struct OutcomeHistoryV1 {
  history_ref : @contracts.RecordRef
  delivery_receipt_ref : @contracts.RecordRef
  observations : ReadOnlyArray[OutcomeObservationV1]
  head_ref : @contracts.RecordRef?
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn outcome_history_bytes_v1(
  delivery_receipt_ref : @contracts.RecordRef,
  observations : ArrayView[OutcomeObservationV1],
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/OUTCOME-HISTORY-V1/1.0.0")
  writer.string("1.0.0")
  write_ref(writer, delivery_receipt_ref)
  writer.count(observations.length())
  for observation in observations {
    write_ref(writer, observation.observation_ref)
    writer.bytes(observation.canonical)
  }
  writer.finish()
}

///|
pub fn OutcomeHistoryV1::empty(
  delivery : GovernedDeliveryReceiptV1,
) -> OutcomeHistoryV1 raise OrchestrationError {
  let observations : Array[OutcomeObservationV1] = []
  let canonical = outcome_history_bytes_v1(delivery.record_ref(), observations)
  let digest = @contracts.sha256_digest(canonical)
  {
    history_ref: self_ref(
      "orchestration-outcome-history-v1",
      delivery.record_ref().id(),
      digest,
    ),
    delivery_receipt_ref: delivery.record_ref(),
    observations: ReadOnlyArray::from_array(observations),
    head_ref: None,
    canonical,
    digest,
  }
}

///|
fn OutcomeHistoryV1::contains_observation_ref(
  self : OutcomeHistoryV1,
  value : @contracts.RecordRef,
) -> Bool {
  self.observations.any(observation => observation.observation_ref == value)
}

///|
fn validate_outcome_shape_v1(
  history : OutcomeHistoryV1,
  kind : OutcomeObservationKindV1,
  payload : @contracts.WireEnvelope?,
  expected_at : Int64?,
  source_observed_at : Int64?,
  late_for_ref : @contracts.RecordRef?,
  correction_of_ref : @contracts.RecordRef?,
  conflicts_with : ArrayView[@contracts.RecordRef],
  recorded_at : Int64,
) -> Unit raise OrchestrationError {
  match expected_at {
    Some(value) => require_non_negative(value, "outcome_expected_at_v1")
    None => ()
  }
  match source_observed_at {
    Some(value) => {
      require_non_negative(value, "outcome_source_observed_at_v1")
      if value > recorded_at {
        raise OrderingViolation(field="outcome_source_observed_at_v1")
      }
    }
    None => ()
  }
  match kind {
    OutcomeObservedV1 =>
      if payload is None ||
        expected_at is Some(_) ||
        late_for_ref is Some(_) ||
        correction_of_ref is Some(_) ||
        !conflicts_with.is_empty() {
        raise MalformedInput(field="outcome_observed_shape_v1")
      }
    OutcomeMissingV1 =>
      if payload is Some(_) ||
        expected_at is None ||
        source_observed_at is Some(_) ||
        correction_of_ref is Some(_) ||
        late_for_ref is Some(_) ||
        !conflicts_with.is_empty() {
        raise MalformedInput(field="outcome_missing_shape_v1")
      }
    OutcomeLateV1 => {
      guard expected_at is Some(expected) else {
        raise MalformedInput(field="outcome_late_expected_at_v1")
      }
      guard late_for_ref is Some(missing_ref) else {
        raise MalformedInput(field="outcome_late_missing_ref_v1")
      }
      if payload is None ||
        correction_of_ref is Some(_) ||
        !conflicts_with.is_empty() ||
        recorded_at <= expected {
        raise MalformedInput(field="outcome_late_shape_v1")
      }
      guard history.observations.search_by(observation => {
          observation.observation_ref == missing_ref
        })
        is Some(missing_index) else {
        raise IdentityMismatch(field="outcome_late_missing_history_v1")
      }
      let missing = history.observations[missing_index]
      if missing.kind != OutcomeMissingV1 ||
        missing.expected_at != Some(expected) {
        raise IdentityMismatch(field="outcome_late_missing_history_v1")
      }
    }
    OutcomeConflictingV1 => {
      if payload is None ||
        conflicts_with.is_empty() ||
        late_for_ref is Some(_) ||
        correction_of_ref is Some(_) {
        raise MalformedInput(field="outcome_conflicting_shape_v1")
      }
      for value in conflicts_with {
        if !history.contains_observation_ref(value) {
          raise IdentityMismatch(field="outcome_conflict_history_v1")
        }
      }
    }
    OutcomeCorrectedV1 => {
      guard correction_of_ref is Some(corrected) else {
        raise MalformedInput(field="outcome_correction_target_v1")
      }
      if payload is None ||
        !conflicts_with.is_empty() ||
        late_for_ref is Some(_) ||
        !history.contains_observation_ref(corrected) {
        raise IdentityMismatch(field="outcome_correction_history_v1")
      }
    }
  }
}

///|
fn OutcomeHistoryV1::append_internal(
  self : OutcomeHistoryV1,
  observation_id : String,
  kind : OutcomeObservationKindV1,
  payload : @contracts.WireEnvelope?,
  evidence : Array[@contracts.EvidenceRef],
  recorded_at : Int64,
  expected_at : Int64?,
  source_observed_at : Int64?,
  late_for_ref : @contracts.RecordRef?,
  correction_of_ref : @contracts.RecordRef?,
  conflicts_with : Array[@contracts.RecordRef],
) -> (OutcomeHistoryV1, OutcomeObservationV1) raise OrchestrationError {
  require_text(observation_id, "outcome_observation_id_v1")
  require_non_negative(recorded_at, "outcome_recorded_at_v1")
  if self.observations.any(value => value.observation_ref.id() == observation_id) {
    raise IdempotencyConflict(key=observation_id)
  }
  match self.observations.last() {
    Some(previous) if recorded_at < previous.recorded_at =>
      raise OrderingViolation(field="outcome_recorded_at_v1")
    _ => ()
  }
  let conflicts_with = copy_unique_refs_v1(
    conflicts_with, "outcome_conflicts_duplicate_v1",
  )
  validate_outcome_shape_v1(
    self, kind, payload, expected_at, source_observed_at, late_for_ref, correction_of_ref,
    conflicts_with, recorded_at,
  )
  let evidence = copy_evidence_v1(evidence)
  let sequence = checked_add_non_negative(
    self.observations.length().to_int64(),
    1L,
    "outcome_sequence_v1",
  )
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/OUTCOME-OBSERVATION-V1/1.0.0")
  writer.string("1.0.0")
  writer.string(observation_id)
  write_ref(writer, self.delivery_receipt_ref)
  writer.int64(sequence)
  write_optional_ref(writer, self.head_ref)
  writer.string(kind.wire())
  write_optional_envelope_v1(writer, payload)
  writer.optional_int64(expected_at)
  writer.optional_int64(source_observed_at)
  write_optional_ref(writer, late_for_ref)
  write_optional_ref(writer, correction_of_ref)
  write_refs_v1(writer, conflicts_with)
  write_evidence(writer, evidence)
  writer.int64(recorded_at)
  let observation_canonical = writer.finish()
  let observation_digest = @contracts.sha256_digest(observation_canonical)
  let observation : OutcomeObservationV1 = {
    observation_ref: self_ref(
      "orchestration-outcome-observation-v1", observation_id, observation_digest,
    ),
    delivery_receipt_ref: self.delivery_receipt_ref,
    sequence,
    previous_observation_ref: self.head_ref,
    kind,
    payload,
    expected_at,
    source_observed_at,
    late_for_ref,
    correction_of_ref,
    conflicts_with,
    evidence,
    recorded_at,
    canonical: observation_canonical,
    digest: observation_digest,
  }
  let observations : Array[OutcomeObservationV1] = []
  for value in self.observations {
    observations.push(value)
  }
  observations.push(observation)
  let canonical = outcome_history_bytes_v1(
    self.delivery_receipt_ref,
    observations,
  )
  let digest = @contracts.sha256_digest(canonical)
  let current : OutcomeHistoryV1 = {
    history_ref: self_ref(
      "orchestration-outcome-history-v1",
      self.delivery_receipt_ref.id(),
      digest,
    ),
    delivery_receipt_ref: self.delivery_receipt_ref,
    observations: ReadOnlyArray::from_array(observations),
    head_ref: Some(observation.observation_ref),
    canonical,
    digest,
  }
  (current, observation)
}

///|
pub fn OutcomeHistoryV1::append_observed(
  self : OutcomeHistoryV1,
  observation_id : String,
  payload : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  source_observed_at : Int64?,
  recorded_at : Int64,
) -> (OutcomeHistoryV1, OutcomeObservationV1) raise OrchestrationError {
  self.append_internal(
    observation_id,
    OutcomeObservedV1,
    Some(payload),
    evidence,
    recorded_at,
    None,
    source_observed_at,
    None,
    None,
    [],
  )
}

///|
pub fn OutcomeHistoryV1::append_missing(
  self : OutcomeHistoryV1,
  observation_id : String,
  expected_at : Int64,
  evidence : Array[@contracts.EvidenceRef],
  recorded_at : Int64,
) -> (OutcomeHistoryV1, OutcomeObservationV1) raise OrchestrationError {
  self.append_internal(
    observation_id,
    OutcomeMissingV1,
    None,
    evidence,
    recorded_at,
    Some(expected_at),
    None,
    None,
    None,
    [],
  )
}

///|
pub fn OutcomeHistoryV1::append_late(
  self : OutcomeHistoryV1,
  observation_id : String,
  payload : @contracts.WireEnvelope,
  late_for_ref : @contracts.RecordRef,
  expected_at : Int64,
  evidence : Array[@contracts.EvidenceRef],
  source_observed_at : Int64?,
  recorded_at : Int64,
) -> (OutcomeHistoryV1, OutcomeObservationV1) raise OrchestrationError {
  self.append_internal(
    observation_id,
    OutcomeLateV1,
    Some(payload),
    evidence,
    recorded_at,
    Some(expected_at),
    source_observed_at,
    Some(late_for_ref),
    None,
    [],
  )
}

///|
pub fn OutcomeHistoryV1::append_conflicting(
  self : OutcomeHistoryV1,
  observation_id : String,
  payload : @contracts.WireEnvelope,
  conflicts_with : Array[@contracts.RecordRef],
  evidence : Array[@contracts.EvidenceRef],
  source_observed_at : Int64?,
  recorded_at : Int64,
) -> (OutcomeHistoryV1, OutcomeObservationV1) raise OrchestrationError {
  self.append_internal(
    observation_id,
    OutcomeConflictingV1,
    Some(payload),
    evidence,
    recorded_at,
    None,
    source_observed_at,
    None,
    None,
    conflicts_with,
  )
}

///|
pub fn OutcomeHistoryV1::append_correction(
  self : OutcomeHistoryV1,
  observation_id : String,
  payload : @contracts.WireEnvelope,
  correction_of_ref : @contracts.RecordRef,
  evidence : Array[@contracts.EvidenceRef],
  source_observed_at : Int64?,
  recorded_at : Int64,
) -> (OutcomeHistoryV1, OutcomeObservationV1) raise OrchestrationError {
  self.append_internal(
    observation_id,
    OutcomeCorrectedV1,
    Some(payload),
    evidence,
    recorded_at,
    None,
    source_observed_at,
    None,
    Some(correction_of_ref),
    [],
  )
}

///|
pub fn OutcomeHistoryV1::record_ref(
  self : OutcomeHistoryV1,
) -> @contracts.RecordRef {
  self.history_ref
}

///|
pub fn OutcomeHistoryV1::delivery_receipt_ref(
  self : OutcomeHistoryV1,
) -> @contracts.RecordRef {
  self.delivery_receipt_ref
}

///|
pub fn OutcomeHistoryV1::observations(
  self : OutcomeHistoryV1,
) -> ReadOnlyArray[OutcomeObservationV1] {
  self.observations
}

///|
pub fn OutcomeHistoryV1::head_ref(
  self : OutcomeHistoryV1,
) -> @contracts.RecordRef? {
  self.head_ref
}

///|
pub fn OutcomeHistoryV1::canonical_bytes(self : OutcomeHistoryV1) -> Bytes {
  self.canonical
}

///|
pub fn OutcomeHistoryV1::digest(
  self : OutcomeHistoryV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn OutcomeObservationV1::record_ref(
  self : OutcomeObservationV1,
) -> @contracts.RecordRef {
  self.observation_ref
}

///|
pub fn OutcomeObservationV1::kind(
  self : OutcomeObservationV1,
) -> OutcomeObservationKindV1 {
  self.kind
}

///|
pub fn OutcomeObservationV1::delivery_receipt_ref(
  self : OutcomeObservationV1,
) -> @contracts.RecordRef {
  self.delivery_receipt_ref
}

///|
pub fn OutcomeObservationV1::sequence(self : OutcomeObservationV1) -> Int64 {
  self.sequence
}

///|
pub fn OutcomeObservationV1::previous_observation_ref(
  self : OutcomeObservationV1,
) -> @contracts.RecordRef? {
  self.previous_observation_ref
}

///|
pub fn OutcomeObservationV1::payload(
  self : OutcomeObservationV1,
) -> @contracts.WireEnvelope? {
  self.payload
}

///|
pub fn OutcomeObservationV1::expected_at(self : OutcomeObservationV1) -> Int64? {
  self.expected_at
}

///|
pub fn OutcomeObservationV1::source_observed_at(
  self : OutcomeObservationV1,
) -> Int64? {
  self.source_observed_at
}

///|
pub fn OutcomeObservationV1::correction_of_ref(
  self : OutcomeObservationV1,
) -> @contracts.RecordRef? {
  self.correction_of_ref
}

///|
pub fn OutcomeObservationV1::late_for_ref(
  self : OutcomeObservationV1,
) -> @contracts.RecordRef? {
  self.late_for_ref
}

///|
pub fn OutcomeObservationV1::conflicts_with(
  self : OutcomeObservationV1,
) -> ReadOnlyArray[@contracts.RecordRef] {
  self.conflicts_with
}

///|
pub fn OutcomeObservationV1::evidence(
  self : OutcomeObservationV1,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn OutcomeObservationV1::recorded_at(self : OutcomeObservationV1) -> Int64 {
  self.recorded_at
}

///|
pub fn OutcomeObservationV1::canonical_bytes(
  self : OutcomeObservationV1,
) -> Bytes {
  self.canonical
}

///|
pub fn OutcomeObservationV1::digest(
  self : OutcomeObservationV1,
) -> @contracts.ContentDigest {
  self.digest
}
