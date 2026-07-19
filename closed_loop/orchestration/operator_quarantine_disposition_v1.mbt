///|
let quarantine_disposition_event_kind_v1 = "effect.recovery.quarantine-disposition.v1"

///|
let quarantine_disposition_record_magic_v1 = b"FLOW7/QUARANTINE-DISPOSITION-RECORD-V1/1.0.0"

///|
pub(all) enum QuarantineDispositionKindV1 {
  QuarantineReleaseToReconciliationV1
  QuarantineRetainV1
  QuarantineEscalateToManualV1
  QuarantineManuallyResolvedV1
} derive(Eq, Debug)

///|
fn QuarantineDispositionKindV1::wire(
  self : QuarantineDispositionKindV1,
) -> String {
  match self {
    QuarantineReleaseToReconciliationV1 => "release-to-reconciliation"
    QuarantineRetainV1 => "retain"
    QuarantineEscalateToManualV1 => "escalate-to-manual"
    QuarantineManuallyResolvedV1 => "manually-resolved"
  }
}

///|
fn quarantine_disposition_kind_from_wire_v1(
  value : String,
) -> QuarantineDispositionKindV1 raise OrchestrationError {
  match value {
    "release-to-reconciliation" => QuarantineReleaseToReconciliationV1
    "retain" => QuarantineRetainV1
    "escalate-to-manual" => QuarantineEscalateToManualV1
    "manually-resolved" => QuarantineManuallyResolvedV1
    _ => raise MalformedInput(field="quarantine_disposition_kind_v1")
  }
}

///|
pub struct QuarantineDispositionRecordV1 {
  record_ref : @contracts.RecordRef
  disposition_id : String
  workflow : @contracts.RecordRef
  callback_ref : @contracts.RecordRef
  callback_digest : @contracts.ContentDigest
  callback_bytes : Bytes
  intent_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  disposition : QuarantineDispositionKindV1
  authority_ref : @contracts.RecordRef
  review_ref : @contracts.RecordRef
  reason : String
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  decided_at : Int64
  prior_disposition_ref : @contracts.RecordRef?
  prior_disposition_digest : @contracts.ContentDigest?
  prior_disposition_bytes : Bytes?
  expected_work_revision : Int64
  expected_work_head_digest : @contracts.ContentDigest
  expected_work_replay_digest : @contracts.ContentDigest
  governance_workflow : @contracts.RecordRef
  governance_revision : Int64
  governance_head_digest : @contracts.ContentDigest?
  governance_replay_digest : @contracts.ContentDigest
  evidence_head : RecoveryEvidenceHeadV3
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn build_quarantine_disposition_record_v1(
  disposition_id : String,
  governed : CurrentGovernedRecoveryProjectionV3,
  evidence_head : RecoveryEvidenceHeadV3,
  entry : RecoveryCallbackProjectionEntryV3,
  disposition : QuarantineDispositionKindV1,
  authority_ref : @contracts.RecordRef,
  review_ref : @contracts.RecordRef,
  reason : String,
  evidence : Array[@contracts.EvidenceRef],
  decided_at : Int64,
  prior : QuarantineDispositionRecordV1?,
) -> QuarantineDispositionRecordV1 raise OrchestrationError {
  require_text(disposition_id, "quarantine_disposition_id_v1")
  require_text(reason, "quarantine_disposition_reason_v1")
  if evidence.is_empty() ||
    decided_at < 0L ||
    !entry.is_quarantined() ||
    evidence_head.bound_workflow != governed.work_replay.workflow() {
    raise MalformedInput(field="quarantine_disposition_binding_v1")
  }
  let callback = entry.record()
  if callback.work_workflow() != governed.work_replay.workflow() ||
    callback.evidence_workflow() != evidence_head.evidence_workflow ||
    !governed
    .v3_owned_intent_refs()
    .any(value => value == callback.intent_ref()) {
    raise ReplayBindingViolation(field="quarantine_disposition_source_v1")
  }
  match (disposition, prior) {
    (QuarantineManuallyResolvedV1, Some(value)) =>
      if value.disposition != QuarantineEscalateToManualV1 {
        raise RecoveryViolation(field="quarantine_manual_resolution_order_v1")
      }
    (QuarantineManuallyResolvedV1, None) =>
      raise RecoveryViolation(field="quarantine_manual_resolution_order_v1")
    (_, Some(value)) =>
      if value.callback_ref != callback.record_ref() {
        raise ReplayBindingViolation(field="quarantine_prior_disposition_v1")
      }
    (_, None) => ()
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(quarantine_disposition_record_magic_v1)
  writer.string("1.0.0")
  writer.string(disposition_id)
  write_ref(writer, governed.work_replay.workflow())
  write_ref(writer, callback.record_ref())
  writer.string(callback.digest().text())
  writer.bytes(callback.canonical_bytes())
  write_ref(writer, callback.intent_ref())
  guard governed.current_claim(callback.intent_ref()) is Some(claim) else {
    raise ReplayBindingViolation(field="quarantine_disposition_claim_v1")
  }
  write_ref(writer, claim.governed_subject)
  writer.string(disposition.wire())
  write_ref(writer, authority_ref)
  write_ref(writer, review_ref)
  writer.string(reason)
  write_evidence(writer, evidence)
  writer.int64(decided_at)
  match prior {
    Some(value) => {
      writer.byte(1)
      write_ref(writer, value.record_ref)
      writer.string(value.digest.text())
      writer.bytes(value.canonical)
    }
    None => writer.byte(0)
  }
  writer.int64(governed.current.work_revision)
  writer.string(governed.current.work_head_digest.text())
  writer.string(governed.current.work_replay_digest.text())
  write_ref(writer, governed.governance_replay.workflow())
  writer.int64(governed.current.governance_revision)
  writer.optional_digest(governed.current.governance_head_digest)
  writer.string(governed.current.governance_replay_digest.text())
  writer.bytes(evidence_head.canonical)
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  {
    record_ref: self_ref_v3(
      "orchestration-quarantine-disposition-v1", disposition_id, digest,
    ),
    disposition_id,
    workflow: governed.work_replay.workflow(),
    callback_ref: callback.record_ref(),
    callback_digest: callback.digest(),
    callback_bytes: callback.canonical_bytes(),
    intent_ref: callback.intent_ref(),
    governed_subject: claim.governed_subject,
    disposition,
    authority_ref,
    review_ref,
    reason,
    evidence: ReadOnlyArray::from_array(evidence),
    decided_at,
    prior_disposition_ref: prior.map(value => value.record_ref),
    prior_disposition_digest: prior.map(value => value.digest),
    prior_disposition_bytes: prior.map(value => value.canonical),
    expected_work_revision: governed.current.work_revision,
    expected_work_head_digest: governed.current.work_head_digest,
    expected_work_replay_digest: governed.current.work_replay_digest,
    governance_workflow: governed.governance_replay.workflow(),
    governance_revision: governed.current.governance_revision,
    governance_head_digest: governed.current.governance_head_digest,
    governance_replay_digest: governed.current.governance_replay_digest,
    evidence_head,
    canonical,
    digest,
  }
}

///|
fn decode_quarantine_disposition_record_v1(
  bytes : Bytes,
) -> QuarantineDispositionRecordV1 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != quarantine_disposition_record_magic_v1 {
    raise MalformedInput(field="quarantine_disposition_magic_v1")
  }
  let version = reader.read_string()
  if version != "1.0.0" {
    raise UnsupportedVersion(field="quarantine_disposition_v1", version~)
  }
  let disposition_id = reader.read_string()
  let workflow = reader.read_ref()
  let callback_ref = reader.read_ref()
  let callback_digest = reader.read_digest()
  let callback_bytes = reader.read_bytes()
  let intent_ref = reader.read_ref()
  let governed_subject = reader.read_ref()
  let disposition = quarantine_disposition_kind_from_wire_v1(
    reader.read_string(),
  )
  let authority_ref = reader.read_ref()
  let review_ref = reader.read_ref()
  let reason = reader.read_string()
  let evidence = reader.read_evidence()
  let decided_at = reader.read_int64()
  let (prior_ref, prior_digest, prior_bytes) = match reader.read_byte() {
    0 => (None, None, None)
    1 =>
      (
        Some(reader.read_ref()),
        Some(reader.read_digest()),
        Some(reader.read_bytes()),
      )
    _ => raise MalformedInput(field="quarantine_disposition_prior_v1")
  }
  let expected_work_revision = reader.read_int64()
  let expected_work_head_digest = reader.read_digest()
  let expected_work_replay_digest = reader.read_digest()
  let governance_workflow = reader.read_ref()
  let governance_revision = reader.read_int64()
  let governance_head_digest = reader.read_optional_digest()
  let governance_replay_digest = reader.read_digest()
  let evidence_head = decode_recovery_evidence_head_v3(reader.read_bytes())
  reader.require_end()
  require_text(disposition_id, "quarantine_disposition_id_v1")
  require_text(reason, "quarantine_disposition_reason_v1")
  let canonical = bytes.copy()
  let digest = @contracts.sha256_digest(canonical)
  let record = {
    record_ref: self_ref_v3(
      "orchestration-quarantine-disposition-v1", disposition_id, digest,
    ),
    disposition_id,
    workflow,
    callback_ref,
    callback_digest,
    callback_bytes,
    intent_ref,
    governed_subject,
    disposition,
    authority_ref,
    review_ref,
    reason,
    evidence: ReadOnlyArray::from_array(evidence),
    decided_at,
    prior_disposition_ref: prior_ref,
    prior_disposition_digest: prior_digest,
    prior_disposition_bytes: prior_bytes,
    expected_work_revision,
    expected_work_head_digest,
    expected_work_replay_digest,
    governance_workflow,
    governance_revision,
    governance_head_digest,
    governance_replay_digest,
    evidence_head,
    canonical,
    digest,
  }
  if callback_ref.digest() != callback_digest ||
    @contracts.sha256_digest(callback_bytes) != callback_digest ||
    evidence.is_empty() ||
    decided_at < 0L ||
    expected_work_revision < 0L ||
    governance_revision < 0L ||
    evidence_head.bound_workflow != workflow ||
    build_quarantine_disposition_record_v1_from_decoded(record) != bytes {
    raise ReplayBindingViolation(field="quarantine_disposition_bytes_v1")
  }
  record
}

///|
fn build_quarantine_disposition_record_v1_from_decoded(
  record : QuarantineDispositionRecordV1,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(quarantine_disposition_record_magic_v1)
  writer.string("1.0.0")
  writer.string(record.disposition_id)
  write_ref(writer, record.workflow)
  write_ref(writer, record.callback_ref)
  writer.string(record.callback_digest.text())
  writer.bytes(record.callback_bytes)
  write_ref(writer, record.intent_ref)
  write_ref(writer, record.governed_subject)
  writer.string(record.disposition.wire())
  write_ref(writer, record.authority_ref)
  write_ref(writer, record.review_ref)
  writer.string(record.reason)
  write_evidence(writer, record.evidence)
  writer.int64(record.decided_at)
  match
    (
      record.prior_disposition_ref,
      record.prior_disposition_digest,
      record.prior_disposition_bytes,
    ) {
    (Some(reference), Some(digest), Some(prior_bytes)) => {
      writer.byte(1)
      write_ref(writer, reference)
      writer.string(digest.text())
      writer.bytes(prior_bytes)
    }
    (None, None, None) => writer.byte(0)
    _ => raise ReplayBindingViolation(field="quarantine_disposition_prior_v1")
  }
  writer.int64(record.expected_work_revision)
  writer.string(record.expected_work_head_digest.text())
  writer.string(record.expected_work_replay_digest.text())
  write_ref(writer, record.governance_workflow)
  writer.int64(record.governance_revision)
  writer.optional_digest(record.governance_head_digest)
  writer.string(record.governance_replay_digest.text())
  writer.bytes(record.evidence_head.canonical)
  writer.finish()
}

///|
fn bytes_have_quarantine_disposition_magic_v1(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    value => value == quarantine_disposition_record_magic_v1
  }
}

///|
fn require_quarantine_disposition_event_v1(
  record : QuarantineDispositionRecordV1,
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let event_key = "quarantine-disposition-event:\{record.digest.text()}"
  let command_key = "quarantine-disposition-command:\{record.digest.text()}"
  let envelope = event.payload()
  if event.workflow() != record.workflow ||
    event.event_ref() != record.record_ref ||
    event.record_version().text() != orchestration_record_version ||
    event.schema_version().text() != orchestration_schema_version ||
    event.sequence() != event.revision() ||
    event.revision() != record.expected_work_revision + 1L ||
    event.previous_event_digest() != Some(record.expected_work_head_digest) ||
    event.idempotency_key() != event_key ||
    envelope.envelope_id() != record.record_ref.id() ||
    envelope.contract_id() != orchestration_contract_id ||
    envelope.contract_version().text() != orchestration_record_version ||
    envelope.producer_id() != orchestration_producer_id ||
    envelope.producer_version().text() != orchestration_record_version ||
    envelope.envelope_kind() != quarantine_disposition_event_kind_v1 ||
    envelope.schema() !=
    orchestration_schema(quarantine_disposition_event_kind_v1) ||
    envelope.subject() != record.record_ref ||
    envelope.payload() != record.canonical ||
    envelope.run_ref() != Some(record.workflow) ||
    envelope.correlation_ref() != Some(record.workflow.id()) ||
    envelope.causation_ref() != Some(record.authority_ref.id()) ||
    envelope.idempotency_ref() != Some(event_key) ||
    envelope.previous_digest() != Some(record.expected_work_head_digest) ||
    !same_evidence(event.evidence(), record.evidence) ||
    !same_evidence(envelope.evidence(), record.evidence) ||
    !envelope.artifacts().is_empty() ||
    !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(field="quarantine_disposition_transport_v1")
  }
  let prefix = verified_prefix_v3(
    replay,
    record.expected_work_revision,
    "quarantine_disposition_work_prefix_v1",
  )
  if prefix.head().last_event_digest() != Some(record.expected_work_head_digest) ||
    prefix.replay_digest() != record.expected_work_replay_digest {
    raise ReplayBindingViolation(field="quarantine_disposition_work_head_v1")
  }
  let batches = replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().length() == 1 &&
      batch.event_refs()[0] == event.event_ref() &&
      batch.intent_refs().is_empty()
    })
  if batches.length() != 1 ||
    batches[0].expected_revision() != record.expected_work_revision ||
    batches[0].command_idempotency_key() != command_key ||
    batches[0].guards().length() != 2 {
    raise ReplayBindingViolation(field="quarantine_disposition_transaction_v1")
  }
  let governance_guard = batches[0].guards()[0]
  let evidence_guard = batches[0].guards()[1]
  if governance_guard.workflow() != record.governance_workflow ||
    governance_guard.expected_revision() != record.governance_revision ||
    governance_guard.expected_head_digest() != record.governance_head_digest ||
    governance_guard.expected_replay_digest() != record.governance_replay_digest ||
    evidence_guard.workflow() != record.evidence_head.evidence_workflow ||
    evidence_guard.expected_revision() != record.evidence_head.revision ||
    evidence_guard.expected_head_digest() != record.evidence_head.head_digest ||
    evidence_guard.expected_replay_digest() !=
    record.evidence_head.replay_digest {
    raise ReplayBindingViolation(field="quarantine_disposition_guards_v1")
  }
}

///|
fn quarantine_disposition_event_consumption_v1(
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Int raise OrchestrationError {
  let record = decode_quarantine_disposition_record_v1(
    event.payload().payload(),
  )
  require_quarantine_disposition_event_v1(record, event, replay)
  1
}

///|
pub struct CurrentQuarantineDispositionProjectionV1 {
  workflow : @contracts.RecordRef
  work_replay_digest : @contracts.ContentDigest
  evidence_replay_digest : @contracts.ContentDigest
  entries : ReadOnlyArray[QuarantineDispositionRecordV1]
  current : ReadOnlyArray[QuarantineDispositionRecordV1]
  state_digest : @contracts.ContentDigest
}

///|
pub fn fold_quarantine_dispositions_v1(
  governed : CurrentGovernedRecoveryProjectionV3,
  evidence : CurrentRecoveryEvidenceProjectionV3,
) -> CurrentQuarantineDispositionProjectionV1 raise OrchestrationError {
  if evidence.bound_workflow() != governed.work_replay.workflow() ||
    evidence.bound_work_replay_digest() != governed.work_replay.replay_digest() {
    raise ReplayBindingViolation(field="quarantine_projection_heads_v1")
  }
  let entries : Array[QuarantineDispositionRecordV1] = []
  let current : Array[QuarantineDispositionRecordV1] = []
  for event in governed.work_replay.events() {
    if event.payload().envelope_kind() == quarantine_disposition_event_kind_v1 {
      let record = decode_quarantine_disposition_record_v1(
        event.payload().payload(),
      )
      require_quarantine_disposition_event_v1(
        record,
        event,
        governed.work_replay,
      )
      let evidence_prefix = verified_prefix_v3(
        evidence.replay,
        record.evidence_head.revision,
        "quarantine_disposition_evidence_prefix_v1",
      )
      if evidence_prefix.head().last_event_digest() !=
        record.evidence_head.head_digest ||
        evidence_prefix.replay_digest() != record.evidence_head.replay_digest {
        raise ReplayBindingViolation(
          field="quarantine_disposition_evidence_head_v1",
        )
      }
      let work_prefix = verified_prefix_v3(
        governed.work_replay,
        record.expected_work_revision,
        "quarantine_disposition_source_work_prefix_v1",
      )
      let source_projection = fold_recovery_evidence_stream_v3(
        evidence.binding,
        evidence_prefix,
        work_prefix,
      )
      if source_projection.state_digest() != record.evidence_head.state_digest {
        raise ReplayBindingViolation(
          field="quarantine_disposition_evidence_state_v1",
        )
      }
      guard first(source_projection.quarantined_entries(), value => {
          value.record().record_ref() == record.callback_ref &&
          value.record().digest() == record.callback_digest &&
          value.record().canonical_bytes() == record.callback_bytes &&
          value.record().intent_ref() == record.intent_ref
        })
        is Some(_) else {
        raise ReplayBindingViolation(field="quarantine_disposition_callback_v1")
      }
      let prior = current
        .filter(value => value.callback_ref == record.callback_ref)
        .last()
      match prior {
        Some(value) =>
          if record.prior_disposition_ref != Some(value.record_ref) ||
            record.prior_disposition_digest != Some(value.digest) ||
            record.prior_disposition_bytes != Some(value.canonical) {
            raise ReplayBindingViolation(
              field="quarantine_disposition_lineage_v1",
            )
          }
        None =>
          if record.prior_disposition_ref is Some(_) ||
            record.prior_disposition_digest is Some(_) ||
            record.prior_disposition_bytes is Some(_) {
            raise ReplayBindingViolation(
              field="quarantine_disposition_lineage_v1",
            )
          }
      }
      if record.disposition == QuarantineManuallyResolvedV1 &&
        prior.map(value => value.disposition) !=
        Some(QuarantineEscalateToManualV1) {
        raise RecoveryViolation(field="quarantine_manual_resolution_order_v1")
      }
      let retained = current.filter(value => {
        value.callback_ref != record.callback_ref
      })
      current.clear()
      for value in retained {
        current.push(value)
      }
      current.push(record)
      entries.push(record)
    } else if bytes_have_quarantine_disposition_magic_v1(
        event.payload().payload(),
      ) {
      raise ReplayBindingViolation(field="quarantine_disposition_wrapper_v1")
    }
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/CURRENT-QUARANTINE-DISPOSITION-V1/1.0.0")
  writer.string("1.0.0")
  write_ref(writer, governed.work_replay.workflow())
  writer.string(governed.work_replay.replay_digest().text())
  writer.string(evidence.replay_digest().text())
  writer.count(entries.length())
  for value in entries {
    writer.bytes(value.canonical)
  }
  writer.count(current.length())
  for value in current {
    writer.bytes(value.canonical)
  }
  {
    workflow: governed.work_replay.workflow(),
    work_replay_digest: governed.work_replay.replay_digest(),
    evidence_replay_digest: evidence.replay_digest(),
    entries: ReadOnlyArray::from_array(entries),
    current: ReadOnlyArray::from_array(current),
    state_digest: @contracts.sha256_digest(writer.finish()),
  }
}

///|
pub fn CurrentQuarantineDispositionProjectionV1::entries(
  self : CurrentQuarantineDispositionProjectionV1,
) -> ReadOnlyArray[QuarantineDispositionRecordV1] {
  self.entries
}

///|
pub fn CurrentQuarantineDispositionProjectionV1::current_for(
  self : CurrentQuarantineDispositionProjectionV1,
  callback_ref : @contracts.RecordRef,
) -> QuarantineDispositionRecordV1? {
  self.current.filter(value => value.callback_ref == callback_ref).last()
}

///|
pub fn CurrentQuarantineDispositionProjectionV1::current_entries(
  self : CurrentQuarantineDispositionProjectionV1,
) -> ReadOnlyArray[QuarantineDispositionRecordV1] {
  self.current
}

///|
pub fn CurrentQuarantineDispositionProjectionV1::released_to_reconciliation(
  self : CurrentQuarantineDispositionProjectionV1,
) -> ReadOnlyArray[QuarantineDispositionRecordV1] {
  ReadOnlyArray::from_array(
    self.current.filter(value => {
      value.disposition == QuarantineReleaseToReconciliationV1
    }),
  )
}

///|
pub fn CurrentQuarantineDispositionProjectionV1::escalated_to_manual(
  self : CurrentQuarantineDispositionProjectionV1,
) -> ReadOnlyArray[QuarantineDispositionRecordV1] {
  ReadOnlyArray::from_array(
    self.current.filter(value => {
      value.disposition == QuarantineEscalateToManualV1
    }),
  )
}

///|
pub fn CurrentQuarantineDispositionProjectionV1::state_digest(
  self : CurrentQuarantineDispositionProjectionV1,
) -> @contracts.ContentDigest {
  self.state_digest
}

///|
pub struct QuarantineDispositionCandidateV1 {
  record : QuarantineDispositionRecordV1
  guarded_request : @storage.GuardedCommitRequest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn prepare_quarantine_disposition_v1(
  governed : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
  disposition_id : String,
  callback_ref : @contracts.RecordRef,
  disposition : QuarantineDispositionKindV1,
  authority_ref : @contracts.RecordRef,
  review_ref : @contracts.RecordRef,
  reason : String,
  evidence : Array[@contracts.EvidenceRef],
  decided_at : Int64,
) -> QuarantineDispositionCandidateV1 raise OrchestrationError {
  if governed.current.work.work_terminal is Some(_) ||
    evidence_projection.bound_workflow() != governed.work_replay.workflow() ||
    evidence_projection.bound_work_replay_digest() !=
    governed.work_replay.replay_digest() {
    raise RecoveryViolation(field="quarantine_disposition_current_v1")
  }
  guard first(evidence_projection.quarantined_entries(), value => {
      value.record().record_ref() == callback_ref
    })
    is Some(entry) else {
    raise RecoveryViolation(field="quarantine_disposition_not_quarantined_v1")
  }
  let projection = fold_quarantine_dispositions_v1(
    governed, evidence_projection,
  )
  let prior = projection.current_for(callback_ref)
  let evidence_head = evidence_projection.recovery_evidence_head_v3()
  let record = build_quarantine_disposition_record_v1(
    disposition_id, governed, evidence_head, entry, disposition, authority_ref, review_ref,
    reason, evidence, decided_at, prior,
  )
  let event_key = "quarantine-disposition-event:\{record.digest.text()}"
  let command_key = "quarantine-disposition-command:\{record.digest.text()}"
  let event = prepare_phase1b_work_event_v22(
    record.workflow,
    governed.current.work_sequence + 1L,
    governed.current.work_revision + 1L,
    governed.current.work_head_digest,
    record.record_ref.id(),
    quarantine_disposition_event_kind_v1,
    record.record_ref,
    record.canonical,
    record.governed_subject,
    [
      for value in record.evidence => value
    ],
    record.authority_ref,
    event_key,
  )
  let request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    record.workflow,
    governed.current.work_revision,
    command_key,
    [event],
    [],
  ) catch {
    _ => raise MalformedInput(field="quarantine_disposition_commit_request_v1")
  }
  let guarded = @storage.GuardedCommitRequest::new(request, [
    @storage.WorkflowHeadGuard::new(
      record.governance_workflow,
      record.governance_revision,
      record.governance_head_digest,
      record.governance_replay_digest,
    ),
    @storage.WorkflowHeadGuard::new(
      evidence_head.evidence_workflow,
      evidence_head.revision,
      evidence_head.head_digest,
      evidence_head.replay_digest,
    ),
  ]) catch {
    _ => raise MalformedInput(field="quarantine_disposition_guarded_request_v1")
  }
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/QUARANTINE-DISPOSITION-CANDIDATE-V1/1.0.0")
  writer.string("1.0.0")
  writer.bytes(record.canonical)
  writer.bytes(guarded.canonical_bytes())
  let canonical = writer.finish()
  {
    record,
    guarded_request: guarded,
    canonical,
    digest: @contracts.sha256_digest(canonical),
  }
}

///|
pub(all) enum QuarantineDispositionCommitResultV1 {
  QuarantineDispositionFreshV1
  QuarantineDispositionAlreadyCommittedV1
  QuarantineDispositionRaceLostV1
  QuarantineDispositionGuardStaleV1
} derive(Eq, Debug)

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] commit_quarantine_disposition_v1(
  store : S,
  candidate : QuarantineDispositionCandidateV1,
) -> QuarantineDispositionCommitResultV1 raise {
  require_phase2_recovery_evidence_guard_profile_v3(
    store,
    candidate.guarded_request,
  )
  try {
    match store.classified_guarded_commit(candidate.guarded_request) {
      @storage.FreshlyApplied(_) => QuarantineDispositionFreshV1
      @storage.AlreadyCommitted(_) => QuarantineDispositionAlreadyCommittedV1
      @storage.GuardRejected(_) => QuarantineDispositionGuardStaleV1
    }
  } catch {
    @storage.OptimisticRevisionConflict(..) => QuarantineDispositionRaceLostV1
    error => raise error
  }
}

///|
pub fn QuarantineDispositionRecordV1::record_ref(
  self : QuarantineDispositionRecordV1,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn QuarantineDispositionRecordV1::callback_ref(
  self : QuarantineDispositionRecordV1,
) -> @contracts.RecordRef {
  self.callback_ref
}

///|
pub fn QuarantineDispositionRecordV1::disposition(
  self : QuarantineDispositionRecordV1,
) -> QuarantineDispositionKindV1 {
  self.disposition
}

///|
pub fn QuarantineDispositionRecordV1::requires_reconciliation(
  self : QuarantineDispositionRecordV1,
) -> Bool {
  self.disposition == QuarantineReleaseToReconciliationV1
}

///|
pub fn QuarantineDispositionRecordV1::requires_manual_intervention(
  self : QuarantineDispositionRecordV1,
) -> Bool {
  self.disposition == QuarantineEscalateToManualV1
}

///|
pub fn QuarantineDispositionRecordV1::is_resolved(
  self : QuarantineDispositionRecordV1,
) -> Bool {
  self.disposition == QuarantineManuallyResolvedV1
}

///|
pub fn QuarantineDispositionRecordV1::authority_ref(
  self : QuarantineDispositionRecordV1,
) -> @contracts.RecordRef {
  self.authority_ref
}

///|
pub fn QuarantineDispositionRecordV1::review_ref(
  self : QuarantineDispositionRecordV1,
) -> @contracts.RecordRef {
  self.review_ref
}

///|
pub fn QuarantineDispositionRecordV1::reason(
  self : QuarantineDispositionRecordV1,
) -> String {
  self.reason
}

///|
pub fn QuarantineDispositionRecordV1::evidence(
  self : QuarantineDispositionRecordV1,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn QuarantineDispositionRecordV1::decided_at(
  self : QuarantineDispositionRecordV1,
) -> Int64 {
  self.decided_at
}

///|
pub fn QuarantineDispositionRecordV1::canonical_bytes(
  self : QuarantineDispositionRecordV1,
) -> Bytes {
  self.canonical
}

///|
pub fn QuarantineDispositionRecordV1::digest(
  self : QuarantineDispositionRecordV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn QuarantineDispositionCandidateV1::record(
  self : QuarantineDispositionCandidateV1,
) -> QuarantineDispositionRecordV1 {
  self.record
}

///|
pub fn QuarantineDispositionCandidateV1::canonical_bytes(
  self : QuarantineDispositionCandidateV1,
) -> Bytes {
  self.canonical
}

///|
pub fn QuarantineDispositionCandidateV1::digest(
  self : QuarantineDispositionCandidateV1,
) -> @contracts.ContentDigest {
  self.digest
}
