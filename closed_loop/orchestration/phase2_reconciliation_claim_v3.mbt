///|
let reconciliation_claim_event_kind_v3 = "effect.reconciliation.claimed.v3"

///|
let reconciliation_query_started_event_kind_v3 = "effect.reconciliation.query-started.v3"

///|
let reconciliation_claim_magic_v3 = b"FLOW7/RECONCILIATION-CLAIM-V3/3.0.0"

///|
let reconciliation_query_started_magic_v3 = b"FLOW7/RECONCILIATION-QUERY-STARTED-V3/3.0.0"

///|
pub struct ReconciliationClaimRecordV3 {
  reconciliation_claim_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  dispatch_claim_ref : @contracts.RecordRef
  dispatch_claim_digest : @contracts.ContentDigest
  invocation_start_ref : @contracts.RecordRef
  invocation_start_digest : @contracts.ContentDigest
  external_idempotency_key : String
  capability_ref : @contracts.RecordRef
  capability_kind : String
  activation_ref : @contracts.RecordRef
  activation_digest : @contracts.ContentDigest
  provider_profile_digest : @contracts.ContentDigest
  policy_binding_ref : @contracts.RecordRef
  policy_binding_digest : @contracts.ContentDigest
  claim_event_id : String
  query_started_event_id : String
  command_idempotency_key : String
  owner : @contracts.RecordRef
  lease_receipt_ref : @contracts.RecordRef
  lease_receipt_digest : @contracts.ContentDigest
  lease_claimed_ref : @contracts.RecordRef
  lease_claimed_digest : @contracts.ContentDigest
  lease_epoch : Int64
  fencing_token : Int64
  reconciliation_ordinal : Int64
  claimed_at : Int64
  expires_at : Int64
  expected_work_revision : Int64
  expected_work_head_digest : @contracts.ContentDigest
  expected_work_replay_digest : @contracts.ContentDigest
  governance_workflow : @contracts.RecordRef
  expected_governance_revision : Int64
  expected_governance_head_digest : @contracts.ContentDigest?
  expected_governance_replay_digest : @contracts.ContentDigest
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn reconciliation_claim_signing_bytes_v3(
  claim_id : String,
  workflow : @contracts.RecordRef,
  intent_ref : @contracts.RecordRef,
  governed_subject : @contracts.RecordRef,
  dispatch_claim_ref : @contracts.RecordRef,
  dispatch_claim_digest : @contracts.ContentDigest,
  invocation_start_ref : @contracts.RecordRef,
  invocation_start_digest : @contracts.ContentDigest,
  external_idempotency_key : String,
  capability_ref : @contracts.RecordRef,
  capability_kind : String,
  activation_ref : @contracts.RecordRef,
  activation_digest : @contracts.ContentDigest,
  provider_profile_digest : @contracts.ContentDigest,
  policy_binding_ref : @contracts.RecordRef,
  policy_binding_digest : @contracts.ContentDigest,
  claim_event_id : String,
  query_started_event_id : String,
  command_idempotency_key : String,
  owner : @contracts.RecordRef,
  lease_receipt_ref : @contracts.RecordRef,
  lease_receipt_digest : @contracts.ContentDigest,
  lease_claimed_ref : @contracts.RecordRef,
  lease_claimed_digest : @contracts.ContentDigest,
  lease_epoch : Int64,
  fencing_token : Int64,
  reconciliation_ordinal : Int64,
  claimed_at : Int64,
  expires_at : Int64,
  expected_work_revision : Int64,
  expected_work_head_digest : @contracts.ContentDigest,
  expected_work_replay_digest : @contracts.ContentDigest,
  governance_workflow : @contracts.RecordRef,
  expected_governance_revision : Int64,
  expected_governance_head_digest : @contracts.ContentDigest?,
  expected_governance_replay_digest : @contracts.ContentDigest,
  evidence : ArrayView[@contracts.EvidenceRef],
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(reconciliation_claim_magic_v3)
  writer.string("3.0.0")
  writer.string(claim_id)
  write_ref(writer, workflow)
  write_ref(writer, intent_ref)
  write_ref(writer, governed_subject)
  write_ref(writer, dispatch_claim_ref)
  writer.string(dispatch_claim_digest.text())
  write_ref(writer, invocation_start_ref)
  writer.string(invocation_start_digest.text())
  writer.string(external_idempotency_key)
  write_ref(writer, capability_ref)
  writer.string(capability_kind)
  write_ref(writer, activation_ref)
  writer.string(activation_digest.text())
  writer.string(provider_profile_digest.text())
  write_ref(writer, policy_binding_ref)
  writer.string(policy_binding_digest.text())
  writer.string(claim_event_id)
  writer.string(query_started_event_id)
  writer.string(command_idempotency_key)
  write_ref(writer, owner)
  write_ref(writer, lease_receipt_ref)
  writer.string(lease_receipt_digest.text())
  write_ref(writer, lease_claimed_ref)
  writer.string(lease_claimed_digest.text())
  writer.int64(lease_epoch)
  writer.int64(fencing_token)
  writer.int64(reconciliation_ordinal)
  writer.int64(claimed_at)
  writer.int64(expires_at)
  writer.int64(expected_work_revision)
  writer.string(expected_work_head_digest.text())
  writer.string(expected_work_replay_digest.text())
  write_ref(writer, governance_workflow)
  writer.int64(expected_governance_revision)
  writer.optional_digest(expected_governance_head_digest)
  writer.string(expected_governance_replay_digest.text())
  write_evidence(writer, evidence)
  writer.finish()
}

///|
fn decode_reconciliation_claim_record_v3(
  bytes : Bytes,
) -> ReconciliationClaimRecordV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != reconciliation_claim_magic_v3 {
    raise MalformedInput(field="reconciliation_claim_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="reconciliation_claim_v3", version~)
  }
  let claim_id = reader.read_string()
  let workflow = reader.read_ref()
  let intent_ref = reader.read_ref()
  let governed_subject = reader.read_ref()
  let dispatch_claim_ref = reader.read_ref()
  let dispatch_claim_digest = reader.read_digest()
  let invocation_start_ref = reader.read_ref()
  let invocation_start_digest = reader.read_digest()
  let external_idempotency_key = reader.read_string()
  let capability_ref = reader.read_ref()
  let capability_kind = reader.read_string()
  let activation_ref = reader.read_ref()
  let activation_digest = reader.read_digest()
  let provider_profile_digest = reader.read_digest()
  let policy_binding_ref = reader.read_ref()
  let policy_binding_digest = reader.read_digest()
  let claim_event_id = reader.read_string()
  let query_started_event_id = reader.read_string()
  let command_idempotency_key = reader.read_string()
  let owner = reader.read_ref()
  let lease_receipt_ref = reader.read_ref()
  let lease_receipt_digest = reader.read_digest()
  let lease_claimed_ref = reader.read_ref()
  let lease_claimed_digest = reader.read_digest()
  let lease_epoch = reader.read_int64()
  let fencing_token = reader.read_int64()
  let reconciliation_ordinal = reader.read_int64()
  let claimed_at = reader.read_int64()
  let expires_at = reader.read_int64()
  let expected_work_revision = reader.read_int64()
  let expected_work_head_digest = reader.read_digest()
  let expected_work_replay_digest = reader.read_digest()
  let governance_workflow = reader.read_ref()
  let expected_governance_revision = reader.read_int64()
  let expected_governance_head_digest = reader.read_optional_digest()
  let expected_governance_replay_digest = reader.read_digest()
  let evidence = reader.read_evidence()
  reader.require_end()
  if lease_epoch < 0L ||
    fencing_token < 0L ||
    reconciliation_ordinal <= 0L ||
    claimed_at < 0L ||
    expires_at <= claimed_at ||
    expected_work_revision < 0L ||
    expected_governance_revision < 0L {
    raise MalformedInput(field="reconciliation_claim_v3_bounds")
  }
  let canonical = reconciliation_claim_signing_bytes_v3(
    claim_id, workflow, intent_ref, governed_subject, dispatch_claim_ref, dispatch_claim_digest,
    invocation_start_ref, invocation_start_digest, external_idempotency_key, capability_ref,
    capability_kind, activation_ref, activation_digest, provider_profile_digest,
    policy_binding_ref, policy_binding_digest, claim_event_id, query_started_event_id,
    command_idempotency_key, owner, lease_receipt_ref, lease_receipt_digest, lease_claimed_ref,
    lease_claimed_digest, lease_epoch, fencing_token, reconciliation_ordinal, claimed_at,
    expires_at, expected_work_revision, expected_work_head_digest, expected_work_replay_digest,
    governance_workflow, expected_governance_revision, expected_governance_head_digest,
    expected_governance_replay_digest, evidence,
  )
  if canonical != bytes {
    raise DigestMismatch(field="reconciliation_claim_v3_noncanonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    reconciliation_claim_ref: self_ref_v3(
      "orchestration-reconciliation-claim-v3", claim_id, digest,
    ),
    workflow,
    intent_ref,
    governed_subject,
    dispatch_claim_ref,
    dispatch_claim_digest,
    invocation_start_ref,
    invocation_start_digest,
    external_idempotency_key,
    capability_ref,
    capability_kind,
    activation_ref,
    activation_digest,
    provider_profile_digest,
    policy_binding_ref,
    policy_binding_digest,
    claim_event_id,
    query_started_event_id,
    command_idempotency_key,
    owner,
    lease_receipt_ref,
    lease_receipt_digest,
    lease_claimed_ref,
    lease_claimed_digest,
    lease_epoch,
    fencing_token,
    reconciliation_ordinal,
    claimed_at,
    expires_at,
    expected_work_revision,
    expected_work_head_digest,
    expected_work_replay_digest,
    governance_workflow,
    expected_governance_revision,
    expected_governance_head_digest,
    expected_governance_replay_digest,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical,
    digest,
  }
}

///|
pub struct ReconciliationQueryStartedV3 {
  query_start_ref : @contracts.RecordRef
  workflow : @contracts.RecordRef
  intent_ref : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  reconciliation_claim_ref : @contracts.RecordRef
  reconciliation_claim_digest : @contracts.ContentDigest
  dispatch_claim_ref : @contracts.RecordRef
  dispatch_claim_digest : @contracts.ContentDigest
  event_id : String
  claim_event_id : String
  command_idempotency_key : String
  owner : @contracts.RecordRef
  lease_epoch : Int64
  fencing_token : Int64
  reconciliation_ordinal : Int64
  started_at : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn reconciliation_query_started_signing_bytes_v3(
  start_id : String,
  claim : ReconciliationClaimRecordV3,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(reconciliation_query_started_magic_v3)
  writer.string("3.0.0")
  writer.string(start_id)
  write_ref(writer, claim.workflow)
  write_ref(writer, claim.intent_ref)
  write_ref(writer, claim.governed_subject)
  write_ref(writer, claim.reconciliation_claim_ref)
  writer.string(claim.digest.text())
  write_ref(writer, claim.dispatch_claim_ref)
  writer.string(claim.dispatch_claim_digest.text())
  writer.string(claim.query_started_event_id)
  writer.string(claim.claim_event_id)
  writer.string(claim.command_idempotency_key)
  write_ref(writer, claim.owner)
  writer.int64(claim.lease_epoch)
  writer.int64(claim.fencing_token)
  writer.int64(claim.reconciliation_ordinal)
  writer.int64(claim.claimed_at)
  write_evidence(writer, claim.evidence)
  writer.finish()
}

///|
fn make_reconciliation_query_started_v3(
  claim : ReconciliationClaimRecordV3,
) -> ReconciliationQueryStartedV3 raise OrchestrationError {
  let start_id = "\{claim.reconciliation_claim_ref.id()}:query-start"
  let canonical = reconciliation_query_started_signing_bytes_v3(start_id, claim)
  let digest = @contracts.sha256_digest(canonical)
  {
    query_start_ref: self_ref_v3(
      "orchestration-reconciliation-query-start-v3", start_id, digest,
    ),
    workflow: claim.workflow,
    intent_ref: claim.intent_ref,
    governed_subject: claim.governed_subject,
    reconciliation_claim_ref: claim.reconciliation_claim_ref,
    reconciliation_claim_digest: claim.digest,
    dispatch_claim_ref: claim.dispatch_claim_ref,
    dispatch_claim_digest: claim.dispatch_claim_digest,
    event_id: claim.query_started_event_id,
    claim_event_id: claim.claim_event_id,
    command_idempotency_key: claim.command_idempotency_key,
    owner: claim.owner,
    lease_epoch: claim.lease_epoch,
    fencing_token: claim.fencing_token,
    reconciliation_ordinal: claim.reconciliation_ordinal,
    started_at: claim.claimed_at,
    evidence: claim.evidence,
    canonical,
    digest,
  }
}

///|
fn decode_reconciliation_query_started_v3(
  bytes : Bytes,
) -> ReconciliationQueryStartedV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != reconciliation_query_started_magic_v3 {
    raise MalformedInput(field="reconciliation_query_started_v3_magic")
  }
  let version = reader.read_string()
  if version != "3.0.0" {
    raise UnsupportedVersion(field="reconciliation_query_started_v3", version~)
  }
  let start_id = reader.read_string()
  let workflow = reader.read_ref()
  let intent_ref = reader.read_ref()
  let governed_subject = reader.read_ref()
  let reconciliation_claim_ref = reader.read_ref()
  let reconciliation_claim_digest = reader.read_digest()
  let dispatch_claim_ref = reader.read_ref()
  let dispatch_claim_digest = reader.read_digest()
  let event_id = reader.read_string()
  let claim_event_id = reader.read_string()
  let command_idempotency_key = reader.read_string()
  let owner = reader.read_ref()
  let lease_epoch = reader.read_int64()
  let fencing_token = reader.read_int64()
  let reconciliation_ordinal = reader.read_int64()
  let started_at = reader.read_int64()
  let evidence = reader.read_evidence()
  reader.require_end()
  let writer = OrchestrationWriter::new()
  writer.bytes(reconciliation_query_started_magic_v3)
  writer.string("3.0.0")
  writer.string(start_id)
  write_ref(writer, workflow)
  write_ref(writer, intent_ref)
  write_ref(writer, governed_subject)
  write_ref(writer, reconciliation_claim_ref)
  writer.string(reconciliation_claim_digest.text())
  write_ref(writer, dispatch_claim_ref)
  writer.string(dispatch_claim_digest.text())
  writer.string(event_id)
  writer.string(claim_event_id)
  writer.string(command_idempotency_key)
  write_ref(writer, owner)
  writer.int64(lease_epoch)
  writer.int64(fencing_token)
  writer.int64(reconciliation_ordinal)
  writer.int64(started_at)
  write_evidence(writer, evidence)
  let canonical = writer.finish()
  if canonical != bytes ||
    start_id != "\{reconciliation_claim_ref.id()}:query-start" {
    raise DigestMismatch(field="reconciliation_query_started_v3_noncanonical")
  }
  let digest = @contracts.sha256_digest(canonical)
  {
    query_start_ref: self_ref_v3(
      "orchestration-reconciliation-query-start-v3", start_id, digest,
    ),
    workflow,
    intent_ref,
    governed_subject,
    reconciliation_claim_ref,
    reconciliation_claim_digest,
    dispatch_claim_ref,
    dispatch_claim_digest,
    event_id,
    claim_event_id,
    command_idempotency_key,
    owner,
    lease_epoch,
    fencing_token,
    reconciliation_ordinal,
    started_at,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical,
    digest,
  }
}

///|
fn reconciliation_claim_event_v3(
  current : CurrentGovernedClosedLoopProjectionV2,
  claim : ReconciliationClaimRecordV3,
) -> @storage.WorkflowEvent raise OrchestrationError {
  let evidence = [ for value in claim.evidence => value ]
  let envelope = @contracts.WireEnvelope::new(
    dispatch_claim_transport_contract_id_v3,
    orchestration_record_version,
    claim.claim_event_id,
    reconciliation_claim_event_kind_v3,
    claim.governed_subject,
    phase1b_effect_schema_v22(reconciliation_claim_event_kind_v3),
    claim.canonical,
    dispatch_claim_transport_producer_id_v3,
    orchestration_record_version,
    [],
    evidence,
    run_ref=claim.workflow,
    correlation_ref=claim.workflow.id(),
    causation_ref=claim.dispatch_claim_ref.id(),
    idempotency_ref=claim.reconciliation_claim_ref.id(),
    previous_digest=current.work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="reconciliation_claim_envelope_v3")
  }
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    claim.workflow,
    claim.claim_event_id,
    current.work_sequence + 1L,
    current.work_revision + 1L,
    claim.reconciliation_claim_ref.id(),
    envelope,
    evidence,
    previous_event_digest=current.work_head_digest,
  ) catch {
    _ => raise MalformedInput(field="reconciliation_claim_event_v3")
  }
}

///|
fn reconciliation_query_started_event_v3(
  claim : ReconciliationClaimRecordV3,
  claim_event : @storage.WorkflowEvent,
) -> @storage.WorkflowEvent raise OrchestrationError {
  let started = make_reconciliation_query_started_v3(claim)
  let evidence = [ for value in started.evidence => value ]
  let envelope = @contracts.WireEnvelope::new(
    dispatch_claim_transport_contract_id_v3,
    orchestration_record_version,
    started.event_id,
    reconciliation_query_started_event_kind_v3,
    started.governed_subject,
    phase1b_effect_schema_v22(reconciliation_query_started_event_kind_v3),
    started.canonical,
    dispatch_claim_transport_producer_id_v3,
    orchestration_record_version,
    [],
    evidence,
    run_ref=started.workflow,
    correlation_ref=started.workflow.id(),
    causation_ref=started.reconciliation_claim_ref.id(),
    idempotency_ref=started.query_start_ref.id(),
    previous_digest=claim_event.event_ref().digest(),
  ) catch {
    _ => raise MalformedInput(field="reconciliation_query_started_envelope_v3")
  }
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    started.workflow,
    started.event_id,
    claim_event.sequence() + 1L,
    claim_event.revision() + 1L,
    started.query_start_ref.id(),
    envelope,
    evidence,
    previous_event_digest=claim_event.event_ref().digest(),
  ) catch {
    _ => raise MalformedInput(field="reconciliation_query_started_event_v3")
  }
}

///|
fn bytes_have_reconciliation_claim_magic_v3(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    magic => magic == reconciliation_claim_magic_v3
  }
}

///|
fn bytes_have_reconciliation_query_started_magic_v3(bytes : Bytes) -> Bool {
  try OrchestrationReader::new(bytes).read_bytes() catch {
    _ => false
  } noraise {
    magic => magic == reconciliation_query_started_magic_v3
  }
}

///|
fn require_reconciliation_claim_transaction_v3(
  claim : ReconciliationClaimRecordV3,
  claim_event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  if try_require_callback_reconciliation_claim_transaction_v3(
      claim, claim_event, replay,
    ) {
    return
  }
  let batches = replay
    .committed_batches()
    .filter(batch => {
      batch.event_refs().any(value => value == claim_event.event_ref())
    })
  if batches.length() != 1 ||
    batches[0].expected_revision() != claim.expected_work_revision ||
    batches[0].command_idempotency_key() != claim.command_idempotency_key ||
    batches[0].event_refs().length() != 2 ||
    batches[0].event_refs()[0] != claim_event.event_ref() ||
    !batches[0].intent_refs().is_empty() ||
    batches[0].guards().length() != 1 {
    raise ReplayBindingViolation(field="reconciliation_claim_v3_transaction")
  }
  guard replay
    .events()
    .search_by(event => event.event_ref() == batches[0].event_refs()[1])
    is Some(start_index) else {
    raise ReplayBindingViolation(field="reconciliation_claim_v3_query_start")
  }
  let started = decode_reconciliation_query_started_v3(
    replay.events()[start_index].payload().payload(),
  )
  if started.reconciliation_claim_ref != claim.reconciliation_claim_ref ||
    started.reconciliation_claim_digest != claim.digest ||
    started.event_id != claim.query_started_event_id {
    raise ReplayBindingViolation(field="reconciliation_claim_v3_query_start")
  }
  let head_guard = batches[0].guards()[0]
  if head_guard.workflow() != claim.governance_workflow ||
    head_guard.expected_revision() != claim.expected_governance_revision ||
    head_guard.expected_head_digest() != claim.expected_governance_head_digest ||
    head_guard.expected_replay_digest() !=
    claim.expected_governance_replay_digest {
    raise ReplayBindingViolation(field="reconciliation_claim_v3_guard")
  }
}

///|
fn require_reconciliation_claim_event_binding_v3(
  claim : ReconciliationClaimRecordV3,
  event : @storage.WorkflowEvent,
) -> Unit raise OrchestrationError {
  let envelope = event.payload()
  if event.record_version().text() != orchestration_record_version ||
    event.schema_version().text() != orchestration_schema_version ||
    event.workflow() != claim.workflow ||
    event.event_ref().id() != claim.claim_event_id ||
    event.sequence() != event.revision() ||
    event.revision() != claim.expected_work_revision + 1L ||
    event.previous_event_digest() != Some(claim.expected_work_head_digest) ||
    event.idempotency_key() != claim.reconciliation_claim_ref.id() ||
    envelope.envelope_id() != event.event_ref().id() ||
    envelope.contract_id() != dispatch_claim_transport_contract_id_v3 ||
    envelope.contract_version().text() != orchestration_record_version ||
    envelope.producer_id() != dispatch_claim_transport_producer_id_v3 ||
    envelope.producer_version().text() != orchestration_record_version ||
    envelope.envelope_kind() != reconciliation_claim_event_kind_v3 ||
    envelope.subject() != claim.governed_subject ||
    envelope.run_ref() != Some(claim.workflow) ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() is Some(_) ||
    envelope.correlation_ref() != Some(claim.workflow.id()) ||
    envelope.causation_ref() != Some(claim.dispatch_claim_ref.id()) ||
    envelope.idempotency_ref() != Some(claim.reconciliation_claim_ref.id()) ||
    envelope.previous_digest() != Some(claim.expected_work_head_digest) ||
    envelope.schema() !=
    phase1b_effect_schema_v22(reconciliation_claim_event_kind_v3) ||
    envelope.payload() != claim.canonical ||
    !same_evidence(event.evidence(), claim.evidence) ||
    !same_evidence(envelope.evidence(), claim.evidence) ||
    !envelope.artifacts().is_empty() ||
    !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(field="reconciliation_claim_v3_transport")
  }
}

///|
fn require_reconciliation_query_started_binding_v3(
  started : ReconciliationQueryStartedV3,
  event : @storage.WorkflowEvent,
  claim : ReconciliationClaimRecordV3,
) -> Unit raise OrchestrationError {
  let envelope = event.payload()
  if started.reconciliation_claim_ref != claim.reconciliation_claim_ref ||
    started.reconciliation_claim_digest != claim.digest ||
    started.dispatch_claim_ref != claim.dispatch_claim_ref ||
    started.dispatch_claim_digest != claim.dispatch_claim_digest ||
    started.intent_ref != claim.intent_ref ||
    started.owner != claim.owner ||
    started.lease_epoch != claim.lease_epoch ||
    started.fencing_token != claim.fencing_token ||
    started.reconciliation_ordinal != claim.reconciliation_ordinal ||
    started.started_at != claim.claimed_at ||
    event.workflow() != claim.workflow ||
    event.event_ref().id() != claim.query_started_event_id ||
    event.sequence() != event.revision() ||
    event.revision() != claim.expected_work_revision + 2L ||
    event.previous_event_digest() is None ||
    event.idempotency_key() != started.query_start_ref.id() ||
    envelope.envelope_id() != event.event_ref().id() ||
    envelope.contract_id() != dispatch_claim_transport_contract_id_v3 ||
    envelope.contract_version().text() != orchestration_record_version ||
    envelope.producer_id() != dispatch_claim_transport_producer_id_v3 ||
    envelope.producer_version().text() != orchestration_record_version ||
    envelope.envelope_kind() != reconciliation_query_started_event_kind_v3 ||
    envelope.subject() != claim.governed_subject ||
    envelope.run_ref() != Some(claim.workflow) ||
    envelope.stage_ref() is Some(_) ||
    envelope.attempt_ref() is Some(_) ||
    envelope.correlation_ref() != Some(claim.workflow.id()) ||
    envelope.causation_ref() != Some(claim.reconciliation_claim_ref.id()) ||
    envelope.idempotency_ref() != Some(started.query_start_ref.id()) ||
    envelope.previous_digest() != event.previous_event_digest() ||
    envelope.schema() !=
    phase1b_effect_schema_v22(reconciliation_query_started_event_kind_v3) ||
    envelope.payload() != started.canonical ||
    !same_evidence(event.evidence(), claim.evidence) ||
    !same_evidence(envelope.evidence(), claim.evidence) ||
    !envelope.artifacts().is_empty() ||
    !envelope.extensions().is_empty() {
    raise ReplayBindingViolation(
      field="reconciliation_query_started_v3_transport",
    )
  }
}

///|
fn require_reconciliation_claim_prefix_v3(
  empty : @effects.EffectsProjection,
  claim : ReconciliationClaimRecordV3,
  work_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  if try_require_callback_reconciliation_claim_prefix_v3(
      empty, claim, work_replay, governance_replay,
    ) {
    return
  }
  let work_prefix = verified_prefix_v3(
    work_replay,
    claim.expected_work_revision,
    "reconciliation_claim_v3_work_prefix",
  )
  let governance_prefix = verified_prefix_v3(
    governance_replay,
    claim.expected_governance_revision,
    "reconciliation_claim_v3_governance_prefix",
  )
  if work_prefix.head().last_event_digest() !=
    Some(claim.expected_work_head_digest) ||
    work_prefix.replay_digest() != claim.expected_work_replay_digest ||
    governance_prefix.workflow() != claim.governance_workflow ||
    governance_prefix.head().last_event_digest() !=
    claim.expected_governance_head_digest ||
    governance_prefix.replay_digest() != claim.expected_governance_replay_digest {
    raise ReplayBindingViolation(field="reconciliation_claim_v3_prefix")
  }
  let prefix = fold_governed_recovery_v3(empty, work_prefix, governance_prefix)
  guard prefix.current_claim(claim.intent_ref) is Some(dispatch_claim) else {
    raise ReplayBindingViolation(field="reconciliation_claim_v3_dispatch")
  }
  guard first(prefix.invocation_starts, started => {
      started.start_ref == claim.invocation_start_ref
    })
    is Some(started) else {
    raise ReplayBindingViolation(field="reconciliation_claim_v3_invocation")
  }
  guard prefix.recovery_policy_for_v3(claim.intent_ref) is Some(policy_binding) else {
    raise ReplayBindingViolation(field="reconciliation_claim_v3_policy")
  }
  if dispatch_claim.claim_ref != claim.dispatch_claim_ref ||
    dispatch_claim.digest != claim.dispatch_claim_digest ||
    started.digest != claim.invocation_start_digest ||
    dispatch_claim.external_idempotency_key != claim.external_idempotency_key ||
    dispatch_claim.capability_ref != claim.capability_ref ||
    dispatch_claim.capability_kind != claim.capability_kind ||
    dispatch_claim.activation_ref != claim.activation_ref ||
    dispatch_claim.activation_digest != claim.activation_digest ||
    dispatch_claim.provider_profile_digest != claim.provider_profile_digest ||
    policy_binding.binding_ref != claim.policy_binding_ref ||
    policy_binding.digest != claim.policy_binding_digest {
    raise ReplayBindingViolation(field="reconciliation_claim_v3_source")
  }
  guard prefix.current.work.orchestration.committed_lease_authority_receipt()
    is Some(lease) else {
    raise ReplayBindingViolation(field="reconciliation_claim_v3_lease")
  }
  lease.validate_current(prefix.current.work.orchestration, claim.claimed_at)
  if lease.receipt_ref() != claim.lease_receipt_ref ||
    lease.digest() != claim.lease_receipt_digest ||
    lease.lease_claimed_ref() != claim.lease_claimed_ref ||
    lease.lease_claimed_digest() != claim.lease_claimed_digest ||
    lease.owner() != claim.owner ||
    lease.epoch() != claim.lease_epoch ||
    lease.fencing_token() != claim.fencing_token ||
    claim.expires_at > lease.expires_at() {
    raise ReplayBindingViolation(field="reconciliation_claim_v3_lease")
  }
  prefix.require_reconciliation_claim_transition_v3(
    claim, dispatch_claim, policy_binding,
  )
}

///|
fn CurrentGovernedRecoveryProjectionV3::require_reconciliation_claim_transition_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  proposed : ReconciliationClaimRecordV3,
  dispatch_claim : DispatchClaimRecordV3,
  policy_binding : RecoveryPolicyBoundV3,
) -> Unit raise OrchestrationError {
  if self.current.work.work_terminal is Some(_) {
    raise RecoveryViolation(field="reconciliation_claim_v3_terminal")
  }
  let policy = policy_binding.policy
  if proposed.claimed_at > int64_max - policy.claim_ttl ||
    proposed.expires_at != proposed.claimed_at + policy.claim_ttl ||
    proposed.reconciliation_ordinal > policy.maximum_reconciliation_attempts {
    raise RecoveryViolation(field="reconciliation_claim_v3_policy_bounds")
  }
  match self.current_reconciliation_claim_v3(proposed.intent_ref) {
    None => {
      if proposed.reconciliation_ordinal != 1L {
        raise RecoveryViolation(field="reconciliation_claim_v3_ordinal")
      }
      match self.state_for(proposed.intent_ref) {
        @effects.RecoveryUnknownRequiresReconciliationV3 => ()
        @effects.RecoveryDispatchAttemptedV3 =>
          if proposed.claimed_at < dispatch_claim.expires_at {
            raise RecoveryViolation(
              field="reconciliation_claim_v3_dispatch_live",
            )
          }
        _ => raise RecoveryViolation(field="reconciliation_claim_v3_state")
      }
    }
    Some(prior) => {
      if prior.reconciliation_ordinal >= policy.maximum_reconciliation_attempts {
        raise RecoveryViolation(field="reconciliation_claim_v3_takeover")
      }
      if proposed.reconciliation_ordinal != prior.reconciliation_ordinal + 1L ||
        proposed.claimed_at < prior.expires_at ||
        proposed.lease_epoch <= prior.lease_epoch ||
        proposed.fencing_token <= prior.fencing_token {
        raise RecoveryViolation(field="reconciliation_claim_v3_takeover")
      }
      match self.current_reconciliation_result_v3(proposed.intent_ref) {
        None => ()
        Some(result) if result.outcome == ReconciliationUnknownV3 => {
          guard self.current_recovery_due_at_v3(proposed.intent_ref)
            is Some(due_at) else {
            raise RecoveryViolation(field="reconciliation_claim_v3_backoff")
          }
          if proposed.claimed_at < due_at {
            raise RecoveryViolation(field="reconciliation_claim_v3_backoff")
          }
        }
        Some(_) =>
          raise RecoveryViolation(field="reconciliation_claim_v3_takeover")
      }
    }
  }
}

///|
priv struct ReconciliationClaimCandidateV3 {
  claim : ReconciliationClaimRecordV3
  started : ReconciliationQueryStartedV3
  request : @storage.CommitRequest
  guarded : @storage.GuardedCommitRequest
  empty_effects : @effects.EffectsProjection
  governance_replay : @storage.ReplayResult
}

///|
fn CurrentGovernedRecoveryProjectionV3::prepare_reconciliation_claim_v3(
  self : CurrentGovernedRecoveryProjectionV3,
  intent_ref : @contracts.RecordRef,
  claim_id : String,
  claim_event_id : String,
  query_started_event_id : String,
  command_idempotency_key : String,
  claimed_at : Int64,
) -> ReconciliationClaimCandidateV3 raise OrchestrationError {
  require_text(claim_id, "reconciliation_claim_v3_id")
  require_text(claim_event_id, "reconciliation_claim_v3_event")
  require_text(query_started_event_id, "reconciliation_query_started_v3_event")
  require_text(command_idempotency_key, "reconciliation_claim_v3_command")
  if claim_event_id == query_started_event_id || claimed_at < 0L {
    raise MalformedInput(field="reconciliation_claim_v3_identity")
  }
  guard self.current_claim(intent_ref) is Some(dispatch_claim) else {
    raise RecoveryViolation(field="reconciliation_claim_v3_dispatch")
  }
  guard first(self.invocation_starts, started => {
      started.claim_ref == dispatch_claim.claim_ref
    })
    is Some(invocation) else {
    raise RecoveryViolation(field="reconciliation_claim_v3_invocation")
  }
  guard self.recovery_policy_for_v3(intent_ref) is Some(policy_binding) else {
    raise RecoveryViolation(field="reconciliation_claim_v3_policy")
  }
  guard self.current.work.orchestration.committed_lease_authority_receipt()
    is Some(lease) else {
    raise RecoveryViolation(field="reconciliation_claim_v3_lease")
  }
  lease.validate_current(self.current.work.orchestration, claimed_at)
  let ordinal = match self.current_reconciliation_claim_v3(intent_ref) {
    None => 1L
    Some(prior) => prior.reconciliation_ordinal + 1L
  }
  let ttl = policy_binding.policy.claim_ttl
  if claimed_at > int64_max - ttl {
    raise ArithmeticOverflow(field="reconciliation_claim_v3_expiry")
  }
  let expires_at = claimed_at + ttl
  let canonical = reconciliation_claim_signing_bytes_v3(
    claim_id,
    dispatch_claim.workflow,
    dispatch_claim.intent_ref,
    dispatch_claim.governed_subject,
    dispatch_claim.claim_ref,
    dispatch_claim.digest,
    invocation.start_ref,
    invocation.digest,
    dispatch_claim.external_idempotency_key,
    dispatch_claim.capability_ref,
    dispatch_claim.capability_kind,
    dispatch_claim.activation_ref,
    dispatch_claim.activation_digest,
    dispatch_claim.provider_profile_digest,
    policy_binding.binding_ref,
    policy_binding.digest,
    claim_event_id,
    query_started_event_id,
    command_idempotency_key,
    lease.owner(),
    lease.receipt_ref(),
    lease.digest(),
    lease.lease_claimed_ref(),
    lease.lease_claimed_digest(),
    lease.epoch(),
    lease.fencing_token(),
    ordinal,
    claimed_at,
    expires_at,
    self.current.work_revision,
    self.current.work_head_digest,
    self.current.work_replay_digest,
    self.governance_replay.workflow(),
    self.current.governance_revision,
    self.current.governance_head_digest,
    self.current.governance_replay_digest,
    dispatch_claim.evidence,
  )
  let digest = @contracts.sha256_digest(canonical)
  let claim : ReconciliationClaimRecordV3 = {
    reconciliation_claim_ref: self_ref_v3(
      "orchestration-reconciliation-claim-v3", claim_id, digest,
    ),
    workflow: dispatch_claim.workflow,
    intent_ref: dispatch_claim.intent_ref,
    governed_subject: dispatch_claim.governed_subject,
    dispatch_claim_ref: dispatch_claim.claim_ref,
    dispatch_claim_digest: dispatch_claim.digest,
    invocation_start_ref: invocation.start_ref,
    invocation_start_digest: invocation.digest,
    external_idempotency_key: dispatch_claim.external_idempotency_key,
    capability_ref: dispatch_claim.capability_ref,
    capability_kind: dispatch_claim.capability_kind,
    activation_ref: dispatch_claim.activation_ref,
    activation_digest: dispatch_claim.activation_digest,
    provider_profile_digest: dispatch_claim.provider_profile_digest,
    policy_binding_ref: policy_binding.binding_ref,
    policy_binding_digest: policy_binding.digest,
    claim_event_id,
    query_started_event_id,
    command_idempotency_key,
    owner: lease.owner(),
    lease_receipt_ref: lease.receipt_ref(),
    lease_receipt_digest: lease.digest(),
    lease_claimed_ref: lease.lease_claimed_ref(),
    lease_claimed_digest: lease.lease_claimed_digest(),
    lease_epoch: lease.epoch(),
    fencing_token: lease.fencing_token(),
    reconciliation_ordinal: ordinal,
    claimed_at,
    expires_at,
    expected_work_revision: self.current.work_revision,
    expected_work_head_digest: self.current.work_head_digest,
    expected_work_replay_digest: self.current.work_replay_digest,
    governance_workflow: self.governance_replay.workflow(),
    expected_governance_revision: self.current.governance_revision,
    expected_governance_head_digest: self.current.governance_head_digest,
    expected_governance_replay_digest: self.current.governance_replay_digest,
    evidence: dispatch_claim.evidence,
    canonical,
    digest,
  }
  self.require_reconciliation_claim_transition_v3(
    claim, dispatch_claim, policy_binding,
  )
  let claim_event = reconciliation_claim_event_v3(self.current, claim)
  let query_event = reconciliation_query_started_event_v3(claim, claim_event)
  let started = make_reconciliation_query_started_v3(claim)
  let request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    claim.workflow,
    claim.expected_work_revision,
    claim.command_idempotency_key,
    [claim_event, query_event],
    [],
  ) catch {
    _ => raise MalformedInput(field="reconciliation_claim_commit_request_v3")
  }
  let guarded = @storage.GuardedCommitRequest::new(request, [
    @storage.WorkflowHeadGuard::new(
      claim.governance_workflow,
      claim.expected_governance_revision,
      claim.expected_governance_head_digest,
      claim.expected_governance_replay_digest,
    ),
  ]) catch {
    _ => raise MalformedInput(field="reconciliation_claim_guarded_request_v3")
  }
  {
    claim,
    started,
    request,
    guarded,
    empty_effects: self.empty_effects,
    governance_replay: self.governance_replay,
  }
}

///|
priv enum ReconciliationClaimCommitOutcomeV3 {
  ReconciliationClaimFreshV3
  ReconciliationClaimAlreadyCommittedV3
  ReconciliationClaimRaceLostV3
  ReconciliationClaimStaleGovernanceV3
}

///|
fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] commit_reconciliation_claim_v3(
  store : S,
  candidate : ReconciliationClaimCandidateV3,
) -> ReconciliationClaimCommitOutcomeV3 raise {
  require_phase2_governance_guard_profile_v3(store, candidate.guarded)
  try {
    match store.classified_guarded_commit(candidate.guarded) {
      @storage.FreshlyApplied(_) => ReconciliationClaimFreshV3
      @storage.AlreadyCommitted(_) => ReconciliationClaimAlreadyCommittedV3
      @storage.GuardRejected(_) => ReconciliationClaimStaleGovernanceV3
    }
  } catch {
    @storage.OptimisticRevisionConflict(..) => ReconciliationClaimRaceLostV3
    error => raise error
  }
}

///|
pub fn ReconciliationClaimRecordV3::record_ref(
  self : ReconciliationClaimRecordV3,
) -> @contracts.RecordRef {
  self.reconciliation_claim_ref
}

///|
pub fn ReconciliationClaimRecordV3::intent_ref(
  self : ReconciliationClaimRecordV3,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn ReconciliationClaimRecordV3::ordinal(
  self : ReconciliationClaimRecordV3,
) -> Int64 {
  self.reconciliation_ordinal
}

///|
pub fn ReconciliationClaimRecordV3::owner(
  self : ReconciliationClaimRecordV3,
) -> @contracts.RecordRef {
  self.owner
}

///|
pub fn ReconciliationClaimRecordV3::claimed_at(
  self : ReconciliationClaimRecordV3,
) -> Int64 {
  self.claimed_at
}

///|
pub fn ReconciliationClaimRecordV3::fencing_token(
  self : ReconciliationClaimRecordV3,
) -> Int64 {
  self.fencing_token
}

///|
pub fn ReconciliationClaimRecordV3::expires_at(
  self : ReconciliationClaimRecordV3,
) -> Int64 {
  self.expires_at
}

///|
pub fn ReconciliationClaimRecordV3::canonical_bytes(
  self : ReconciliationClaimRecordV3,
) -> Bytes {
  self.canonical
}

///|
pub fn ReconciliationClaimRecordV3::digest(
  self : ReconciliationClaimRecordV3,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn ReconciliationQueryStartedV3::record_ref(
  self : ReconciliationQueryStartedV3,
) -> @contracts.RecordRef {
  self.query_start_ref
}

///|
pub fn ReconciliationQueryStartedV3::intent_ref(
  self : ReconciliationQueryStartedV3,
) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn ReconciliationQueryStartedV3::reconciliation_claim_ref(
  self : ReconciliationQueryStartedV3,
) -> @contracts.RecordRef {
  self.reconciliation_claim_ref
}
