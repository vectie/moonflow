///|
let work_terminal_record_kind_v22 = "orchestration-work-terminal-v2"

///|
pub struct ReplayedCancellationRequestV2 {
  request_ref : @contracts.RecordRef
  proposal : CancellationProposalV2
  authorization_ref : @contracts.RecordRef
  authorization_bytes : Bytes
  authorization_observed_at : Int64
  authorization_work_sequence : Int64
  authorization_work_revision : Int64
  authorization_work_head_digest : @contracts.ContentDigest
  authorization_work_replay_digest : @contracts.ContentDigest
  authorization_governance_stream : @contracts.RecordRef
  authorization_governance_sequence : Int64
  authorization_governance_revision : Int64
  authorization_governance_head_digest : @contracts.ContentDigest
  authorization_governance_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
/// Opaque future-compatible terminal record. Phase 1B.2 constructs and
/// decodes only `CancelledBeforeEffectIntentV2`.
pub struct WorkTerminalRecordV2 {
  terminal_ref : @contracts.RecordRef
  outcome : WorkTerminalOutcomeV2
  lineage_digest : @contracts.ContentDigest
  root_registration_ref : @contracts.RecordRef
  root_attempt_ref : @contracts.RecordRef
  root_attempt_digest : @contracts.ContentDigest
  root_intent_ref : @contracts.RecordRef
  root_intent_digest : @contracts.ContentDigest
  source_attempt_ref : @contracts.RecordRef?
  source_intent_ref : @contracts.RecordRef?
  source_proof_ref : @contracts.RecordRef
  source_proof_digest : @contracts.ContentDigest
  source_proof_bytes : Bytes
  source_event_ref : @contracts.RecordRef
  source_event_digest : @contracts.ContentDigest
  source_event_bytes : Bytes
  cancellation_request_ref : @contracts.RecordRef?
  cancellation_request_digest : @contracts.ContentDigest?
  cancellation_request_bytes : Bytes?
  retry_policy_ref : @contracts.RecordRef?
  retry_policy_digest : @contracts.ContentDigest?
  retry_policy_bytes : Bytes?
  attempt_count : Int64?
  retry_count : Int64?
  workflow : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  effects_prefix_state_digest : @contracts.ContentDigest
  effects_prefix_replay_digest : @contracts.ContentDigest
  orchestration_prefix_state_digest : @contracts.ContentDigest
  orchestration_prefix_replay_digest : @contracts.ContentDigest
  prefix_event_ref : @contracts.RecordRef
  prefix_sequence : Int64
  prefix_revision : Int64
  prefix_replay_digest : @contracts.ContentDigest
  terminal_logical_instant : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation : @contracts.RecordRef
  event_idempotency_key : String
  command_idempotency_key : String
  previous_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn require_phase1b_self_address_v22(
  expected_ref : @contracts.RecordRef,
  expected_kind : String,
  bytes : Bytes,
  field : String,
) -> @contracts.ContentDigest raise OrchestrationError {
  if expected_ref.kind() != expected_kind ||
    expected_ref.version().text() != orchestration_record_version_v22 {
    raise ReplayBindingViolation(field~)
  }
  let digest = @contracts.sha256_digest(bytes)
  if expected_ref.digest() != digest {
    raise ReplayBindingViolation(field~)
  }
  digest
}

///|
priv struct ReplayedCancellationAuthorizationBindingV22 {
  observed_at : Int64
  work_sequence : Int64
  work_revision : Int64
  work_head_digest : @contracts.ContentDigest
  work_replay_digest : @contracts.ContentDigest
  governance_stream : @contracts.RecordRef
  governance_sequence : Int64
  governance_revision : Int64
  governance_head_digest : @contracts.ContentDigest
  governance_replay_digest : @contracts.ContentDigest
}

///|
fn decode_committed_cancellation_authorization_v22(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
  proposal : CancellationProposalV2,
) -> ReplayedCancellationAuthorizationBindingV22 raise OrchestrationError {
  ignore(
    require_phase1b_self_address_v22(
      expected_ref, cancellation_authorization_record_kind_v22, bytes, "cancellation_authorization_proposal_binding",
    ),
  )
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/CANCELLATION-AUTHORIZATION-V2/2.2.0" {
    raise MalformedInput(field="cancellation_authorization_tag")
  }
  let version = reader.read_string()
  if version != orchestration_record_version_v22 {
    raise UnsupportedVersion(field="cancellation_authorization", version~)
  }
  if reader.read_string() != expected_ref.id() {
    raise IdentityMismatch(field="cancellation_authorization_id")
  }
  let (proposal_ref, proposal_bytes) = read_phase1b_record_v22(reader)
  if proposal_ref != proposal.proposal_ref ||
    proposal_bytes != proposal.canonical {
    raise ReplayBindingViolation(
      field="cancellation_authorization_proposal_binding",
    )
  }
  let (receipt_ref, receipt_bytes) = read_phase1b_record_v22(reader)
  ignore(
    require_phase1b_self_address_v22(
      receipt_ref, committed_cancellation_governance_receipt_kind_v22, receipt_bytes,
      "cancellation_governance_receipt_self_address",
    ),
  )
  let workflow = reader.read_ref()
  let governed_subject = reader.read_ref()
  let governance_stream = reader.read_ref()
  let work_sequence = reader.read_int64()
  let work_revision = reader.read_int64()
  let work_head_digest = reader.read_digest()
  let work_replay_digest = reader.read_digest()
  let governance_sequence = reader.read_int64()
  let governance_revision = reader.read_int64()
  let governance_head_digest = reader.read_digest()
  let governance_replay_digest = reader.read_digest()
  let observed_at = reader.read_int64()
  let valid_until_inclusive = reader.read_int64()
  let deadline_exclusive = reader.read_int64()
  reader.require_end()
  if workflow != proposal.workflow ||
    governed_subject != proposal.governed_subject ||
    observed_at < proposal.observed_at ||
    observed_at >= deadline_exclusive ||
    valid_until_inclusive + 1L != deadline_exclusive {
    raise ReplayBindingViolation(
      field="cancellation_authorization_proposal_binding",
    )
  }
  {
    observed_at,
    work_sequence,
    work_revision,
    work_head_digest,
    work_replay_digest,
    governance_stream,
    governance_sequence,
    governance_revision,
    governance_head_digest,
    governance_replay_digest,
  }
}

///|
fn decode_committed_cancellation_request_v22(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
) -> ReplayedCancellationRequestV2 raise OrchestrationError {
  let digest = require_phase1b_self_address_v22(
    expected_ref, cancellation_request_record_kind_v22, bytes, "cancellation_request_composite_binding",
  )
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/CANCELLATION-REQUEST-V2/2.2.0" {
    raise MalformedInput(field="cancellation_request_tag")
  }
  let version = reader.read_string()
  if version != orchestration_record_version_v22 {
    raise UnsupportedVersion(field="cancellation_request", version~)
  }
  if reader.read_string() != expected_ref.id() {
    raise IdentityMismatch(field="cancellation_request_id")
  }
  let (proposal_ref, proposal_bytes) = read_phase1b_record_v22(reader)
  let proposal = decode_cancellation_proposal_v22_strict(
    proposal_ref, proposal_bytes,
  )
  let (authorization_ref, authorization_bytes) = read_phase1b_record_v22(reader)
  reader.require_end()
  let authorization = decode_committed_cancellation_authorization_v22(
    authorization_ref, authorization_bytes, proposal,
  )
  {
    request_ref: expected_ref,
    proposal,
    authorization_ref,
    authorization_bytes,
    authorization_observed_at: authorization.observed_at,
    authorization_work_sequence: authorization.work_sequence,
    authorization_work_revision: authorization.work_revision,
    authorization_work_head_digest: authorization.work_head_digest,
    authorization_work_replay_digest: authorization.work_replay_digest,
    authorization_governance_stream: authorization.governance_stream,
    authorization_governance_sequence: authorization.governance_sequence,
    authorization_governance_revision: authorization.governance_revision,
    authorization_governance_head_digest: authorization.governance_head_digest,
    authorization_governance_replay_digest: authorization.governance_replay_digest,
    canonical: bytes,
    digest,
  }
}

///|
priv struct WorkTerminalDraftV22 {
  terminal_id : String
  outcome : WorkTerminalOutcomeV2
  lineage_digest : @contracts.ContentDigest
  root_registration_ref : @contracts.RecordRef
  root_attempt_ref : @contracts.RecordRef
  root_attempt_digest : @contracts.ContentDigest
  root_intent_ref : @contracts.RecordRef
  root_intent_digest : @contracts.ContentDigest
  source_attempt_ref : @contracts.RecordRef?
  source_intent_ref : @contracts.RecordRef?
  source_proof_ref : @contracts.RecordRef
  source_proof_bytes : Bytes
  source_event_ref : @contracts.RecordRef
  source_event_bytes : Bytes
  cancellation_request_ref : @contracts.RecordRef?
  cancellation_request_bytes : Bytes?
  retry_policy_ref : @contracts.RecordRef?
  retry_policy_bytes : Bytes?
  attempt_count : Int64?
  retry_count : Int64?
  workflow : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  effects_prefix_state_digest : @contracts.ContentDigest
  effects_prefix_replay_digest : @contracts.ContentDigest
  orchestration_prefix_state_digest : @contracts.ContentDigest
  orchestration_prefix_replay_digest : @contracts.ContentDigest
  prefix_event_ref : @contracts.RecordRef
  prefix_sequence : Int64
  prefix_revision : Int64
  prefix_replay_digest : @contracts.ContentDigest
  terminal_logical_instant : Int64
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  causation : @contracts.RecordRef
  event_idempotency_key : String
  command_idempotency_key : String
  previous_digest : @contracts.ContentDigest
}

///|
fn work_terminal_lineage_digest_v22(
  workflow : @contracts.RecordRef,
  root_attempt_ref : @contracts.RecordRef,
  root_intent_ref : @contracts.RecordRef,
  source_attempt_ref : @contracts.RecordRef?,
  source_intent_ref : @contracts.RecordRef?,
) -> @contracts.ContentDigest raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  write_ref(writer, workflow)
  write_ref(writer, root_attempt_ref)
  write_ref(writer, root_intent_ref)
  write_optional_ref(writer, source_attempt_ref)
  write_optional_ref(writer, source_intent_ref)
  @contracts.sha256_digest(writer.finish())
}

///|
fn retry_terminal_composite_proof_v22(
  source : @effects.CommittedEffectTerminalSourceV2,
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
) -> (@contracts.RecordRef, Bytes, @contracts.ContentDigest) raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.string("FLOW7/WORK-TERMINAL-RETRY-PROOF-V2/2.2.0")
  write_ref(writer, source.receipt_ref())
  writer.bytes(source.canonical_bytes())
  write_ref(writer, receipt.receipt_ref())
  writer.bytes(receipt.canonical_bytes())
  let canonical = writer.finish()
  let digest = @contracts.sha256_digest(canonical)
  (
    self_ref_v22(
      "work-terminal-retry-proof-v2",
      "\{source.source_record_ref().id()}:\{receipt.receipt_ref().id()}",
      digest,
    ),
    canonical,
    digest,
  )
}

///|
fn validate_work_terminal_option_shape_v22(
  draft : WorkTerminalDraftV22,
) -> Unit raise OrchestrationError {
  let cancellation_present = draft.cancellation_request_ref is Some(_) &&
    draft.cancellation_request_bytes is Some(_)
  let cancellation_absent = draft.cancellation_request_ref is None &&
    draft.cancellation_request_bytes is None
  let policy_present = draft.retry_policy_ref is Some(_) &&
    draft.retry_policy_bytes is Some(_) &&
    draft.attempt_count is Some(_) &&
    draft.retry_count is Some(_)
  let policy_absent = draft.retry_policy_ref is None &&
    draft.retry_policy_bytes is None &&
    draft.attempt_count is None &&
    draft.retry_count is None
  let valid = match draft.outcome {
    SucceededV2 => cancellation_absent && policy_absent
    FailedNonRetryableV2 | FailedRetryExhaustedV2 =>
      cancellation_absent && policy_present
    FailedCancellationStoppedRetryV2 => cancellation_present && policy_present
    CancelledBeforeEffectIntentV2 | CancelledAfterReconciledNotAppliedV2 =>
      cancellation_present && policy_absent
  }
  if !valid {
    raise ReplayBindingViolation(field="work_terminal_option_shape")
  }
  if draft.prefix_sequence < 0L ||
    draft.prefix_revision < 0L ||
    draft.terminal_logical_instant < 0L {
    raise MalformedInput(field="work_terminal_v22_counter")
  }
  match (draft.attempt_count, draft.retry_count) {
    (Some(attempt_count), Some(retry_count)) =>
      if attempt_count < 1L || retry_count < 0L {
        raise MalformedInput(field="work_terminal_v22_counter")
      }
    (None, None) => ()
    _ => raise ReplayBindingViolation(field="work_terminal_option_shape")
  }
}

///|
fn work_terminal_signing_bytes_v22(
  draft : WorkTerminalDraftV22,
) -> Bytes raise OrchestrationError {
  validate_work_terminal_option_shape_v22(draft)
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/WORK-TERMINAL-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(draft.terminal_id)
  writer.string(draft.outcome.wire())
  writer.string(draft.lineage_digest.text())
  write_ref(writer, draft.root_registration_ref)
  write_ref(writer, draft.root_attempt_ref)
  writer.string(draft.root_attempt_digest.text())
  write_ref(writer, draft.root_intent_ref)
  writer.string(draft.root_intent_digest.text())
  write_optional_ref(writer, draft.source_attempt_ref)
  write_optional_ref(writer, draft.source_intent_ref)
  write_phase1b_record_v22(
    writer,
    draft.source_proof_ref,
    draft.source_proof_bytes,
  )
  write_phase1b_record_v22(
    writer,
    draft.source_event_ref,
    draft.source_event_bytes,
  )
  match (draft.cancellation_request_ref, draft.cancellation_request_bytes) {
    (None, None) => writer.int64(0L)
    (Some(record_ref), Some(bytes)) => {
      writer.int64(1L)
      write_phase1b_record_v22(writer, record_ref, bytes)
    }
    _ => raise ReplayBindingViolation(field="work_terminal_option_shape")
  }
  match (draft.retry_policy_ref, draft.retry_policy_bytes) {
    (None, None) => writer.int64(0L)
    (Some(record_ref), Some(bytes)) => {
      writer.int64(1L)
      write_phase1b_record_v22(writer, record_ref, bytes)
    }
    _ => raise ReplayBindingViolation(field="work_terminal_option_shape")
  }
  writer.optional_int64(draft.attempt_count)
  writer.optional_int64(draft.retry_count)
  write_ref(writer, draft.workflow)
  write_ref(writer, draft.governed_subject)
  writer.string(draft.effects_prefix_state_digest.text())
  writer.string(draft.effects_prefix_replay_digest.text())
  writer.string(draft.orchestration_prefix_state_digest.text())
  writer.string(draft.orchestration_prefix_replay_digest.text())
  write_ref(writer, draft.prefix_event_ref)
  writer.int64(draft.prefix_sequence)
  writer.int64(draft.prefix_revision)
  writer.string(draft.prefix_replay_digest.text())
  writer.int64(draft.terminal_logical_instant)
  write_evidence(writer, draft.evidence)
  write_ref(writer, draft.causation)
  writer.string(draft.event_idempotency_key)
  writer.string(draft.command_idempotency_key)
  writer.string(draft.previous_digest.text())
  writer.finish()
}

///|
fn seal_work_terminal_v22(
  draft : WorkTerminalDraftV22,
) -> WorkTerminalRecordV2 raise OrchestrationError {
  let canonical = work_terminal_signing_bytes_v22(draft)
  let digest = @contracts.sha256_digest(canonical)
  {
    terminal_ref: self_ref_v22(
      work_terminal_record_kind_v22,
      draft.terminal_id,
      digest,
    ),
    outcome: draft.outcome,
    lineage_digest: draft.lineage_digest,
    root_registration_ref: draft.root_registration_ref,
    root_attempt_ref: draft.root_attempt_ref,
    root_attempt_digest: draft.root_attempt_digest,
    root_intent_ref: draft.root_intent_ref,
    root_intent_digest: draft.root_intent_digest,
    source_attempt_ref: draft.source_attempt_ref,
    source_intent_ref: draft.source_intent_ref,
    source_proof_ref: draft.source_proof_ref,
    source_proof_digest: draft.source_proof_ref.digest(),
    source_proof_bytes: draft.source_proof_bytes,
    source_event_ref: draft.source_event_ref,
    source_event_digest: draft.source_event_ref.digest(),
    source_event_bytes: draft.source_event_bytes,
    cancellation_request_ref: draft.cancellation_request_ref,
    cancellation_request_digest: draft.cancellation_request_ref.map(value => {
      value.digest()
    }),
    cancellation_request_bytes: draft.cancellation_request_bytes,
    retry_policy_ref: draft.retry_policy_ref,
    retry_policy_digest: draft.retry_policy_ref.map(value => value.digest()),
    retry_policy_bytes: draft.retry_policy_bytes,
    attempt_count: draft.attempt_count,
    retry_count: draft.retry_count,
    workflow: draft.workflow,
    governed_subject: draft.governed_subject,
    effects_prefix_state_digest: draft.effects_prefix_state_digest,
    effects_prefix_replay_digest: draft.effects_prefix_replay_digest,
    orchestration_prefix_state_digest: draft.orchestration_prefix_state_digest,
    orchestration_prefix_replay_digest: draft.orchestration_prefix_replay_digest,
    prefix_event_ref: draft.prefix_event_ref,
    prefix_sequence: draft.prefix_sequence,
    prefix_revision: draft.prefix_revision,
    prefix_replay_digest: draft.prefix_replay_digest,
    terminal_logical_instant: draft.terminal_logical_instant,
    evidence: draft.evidence,
    causation: draft.causation,
    event_idempotency_key: draft.event_idempotency_key,
    command_idempotency_key: draft.command_idempotency_key,
    previous_digest: draft.previous_digest,
    canonical,
    digest,
  }
}

///|
fn require_cancelled_before_effect_codec_binding_v22(
  draft : WorkTerminalDraftV22,
) -> Unit raise OrchestrationError {
  if draft.outcome != CancelledBeforeEffectIntentV2 {
    return
  }
  let request = decode_committed_cancellation_request_v22(
    draft.source_proof_ref,
    draft.source_proof_bytes,
  ) catch {
    _ => raise ReplayBindingViolation(field="work_record_byte_binding")
  }
  if draft.source_event_ref.id() != request.request_ref.id() ||
    draft.terminal_id != "\{request.request_ref.id()}:safe-terminal" ||
    draft.cancellation_request_ref != Some(request.request_ref) ||
    draft.cancellation_request_bytes != Some(request.canonical) ||
    draft.workflow != request.proposal.workflow ||
    draft.governed_subject != request.proposal.governed_subject ||
    draft.root_registration_ref != request.proposal.root_registration_ref ||
    draft.root_attempt_ref != request.proposal.root_attempt_ref ||
    draft.root_attempt_digest != request.proposal.root_attempt_digest ||
    draft.root_intent_ref != request.proposal.root_intent_ref ||
    draft.root_intent_digest != request.proposal.root_intent_digest ||
    draft.source_attempt_ref != request.proposal.source_attempt_ref ||
    draft.source_intent_ref != request.proposal.source_intent_ref ||
    draft.prefix_event_ref != request.proposal.prefix_event_ref ||
    draft.prefix_sequence != request.proposal.prefix_sequence ||
    draft.prefix_revision != request.proposal.prefix_revision ||
    draft.prefix_replay_digest != request.proposal.prefix_replay_digest ||
    draft.effects_prefix_replay_digest != request.proposal.prefix_replay_digest ||
    draft.orchestration_prefix_replay_digest !=
    request.proposal.prefix_replay_digest ||
    draft.terminal_logical_instant != request.authorization_observed_at ||
    !same_evidence(draft.evidence, request.proposal.evidence) ||
    draft.causation != request.request_ref ||
    draft.event_idempotency_key !=
    "\{request.proposal.event_idempotency_key}:safe-terminal" ||
    draft.command_idempotency_key != request.proposal.command_idempotency_key ||
    draft.previous_digest != draft.source_event_ref.digest() {
    raise ReplayBindingViolation(field="work_record_byte_binding")
  }
}

///|
fn new_cancelled_before_effect_intent_terminal_v22(
  request : CancellationRequestV2,
  cancellation_event : @storage.WorkflowEvent,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> WorkTerminalRecordV2 raise OrchestrationError {
  let terminal_id = "\{request.request_ref.id()}:safe-terminal"
  let event_idempotency_key = "\{request.proposal.event_idempotency_key}:safe-terminal"
  let observed_at = request.authorization.observed_at
  seal_work_terminal_v22({
    terminal_id,
    outcome: CancelledBeforeEffectIntentV2,
    lineage_digest: work_terminal_lineage_digest_v22(
      request.proposal.workflow,
      request.proposal.root_attempt_ref,
      request.proposal.root_intent_ref,
      request.proposal.source_attempt_ref,
      request.proposal.source_intent_ref,
    ),
    root_registration_ref: request.proposal.root_registration_ref,
    root_attempt_ref: request.proposal.root_attempt_ref,
    root_attempt_digest: request.proposal.root_attempt_digest,
    root_intent_ref: request.proposal.root_intent_ref,
    root_intent_digest: request.proposal.root_intent_digest,
    source_attempt_ref: request.proposal.source_attempt_ref,
    source_intent_ref: request.proposal.source_intent_ref,
    source_proof_ref: request.request_ref,
    source_proof_bytes: request.canonical,
    source_event_ref: cancellation_event.event_ref(),
    source_event_bytes: cancellation_event.canonical_bytes(),
    cancellation_request_ref: Some(request.request_ref),
    cancellation_request_bytes: Some(request.canonical),
    retry_policy_ref: None,
    retry_policy_bytes: None,
    attempt_count: None,
    retry_count: None,
    workflow: request.proposal.workflow,
    governed_subject: request.proposal.governed_subject,
    effects_prefix_state_digest: current.work_effects_state_digest,
    effects_prefix_replay_digest: current.work_replay_digest,
    orchestration_prefix_state_digest: current.work_orchestration_state_digest,
    orchestration_prefix_replay_digest: current.work_replay_digest,
    prefix_event_ref: request.proposal.prefix_event_ref,
    prefix_sequence: request.proposal.prefix_sequence,
    prefix_revision: request.proposal.prefix_revision,
    prefix_replay_digest: request.proposal.prefix_replay_digest,
    terminal_logical_instant: observed_at,
    evidence: request.proposal.evidence,
    causation: request.request_ref,
    event_idempotency_key,
    command_idempotency_key: request.proposal.command_idempotency_key,
    previous_digest: cancellation_event.event_ref().digest(),
  })
}

///|
fn decode_work_terminal_record_v22(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
) -> WorkTerminalRecordV2 raise OrchestrationError {
  let digest = require_phase1b_self_address_v22(
    expected_ref, work_terminal_record_kind_v22, bytes, "work_record_byte_binding",
  )
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != b"FLOW7/WORK-TERMINAL-V2/2.2.0" {
    raise MalformedInput(field="work_terminal_v22_tag")
  }
  let version = reader.read_string()
  if version != orchestration_record_version_v22 {
    raise UnsupportedVersion(field="work_terminal_v22", version~)
  }
  if reader.read_string() != expected_ref.id() {
    raise IdentityMismatch(field="work_terminal_v22_id")
  }
  let outcome = decode_terminal_outcome_v22(reader.read_string())
  let lineage_digest = reader.read_digest()
  let root_registration_ref = reader.read_ref()
  let root_attempt_ref = reader.read_ref()
  let root_attempt_digest = reader.read_digest()
  let root_intent_ref = reader.read_ref()
  let root_intent_digest = reader.read_digest()
  let source_attempt_ref = reader.read_optional_ref()
  let source_intent_ref = reader.read_optional_ref()
  let (source_proof_ref, source_proof_bytes) = read_phase1b_record_v22(reader)
  let source_proof_digest = source_proof_ref.digest()
  let (source_event_ref, source_event_bytes) = read_phase1b_record_v22(reader)
  let source_event_digest = source_event_ref.digest()
  let (
    cancellation_request_ref,
    cancellation_request_digest,
    cancellation_request_bytes,
  ) = match reader.read_int64() {
    0L => (None, None, None)
    1L => {
      let (record_ref, record_bytes) = read_phase1b_record_v22(reader)
      (Some(record_ref), Some(record_ref.digest()), Some(record_bytes))
    }
    _ => raise MalformedInput(field="work_terminal_v22_cancellation_option")
  }
  let (retry_policy_ref, retry_policy_digest, retry_policy_bytes) = match
    reader.read_int64() {
    0L => (None, None, None)
    1L => {
      let (record_ref, record_bytes) = read_phase1b_record_v22(reader)
      (Some(record_ref), Some(record_ref.digest()), Some(record_bytes))
    }
    _ => raise MalformedInput(field="work_terminal_v22_retry_policy_option")
  }
  let attempt_count = reader.read_optional_int64()
  let retry_count = reader.read_optional_int64()
  let workflow = reader.read_ref()
  let governed_subject = reader.read_ref()
  let effects_prefix_state_digest = reader.read_digest()
  let effects_prefix_replay_digest = reader.read_digest()
  let orchestration_prefix_state_digest = reader.read_digest()
  let orchestration_prefix_replay_digest = reader.read_digest()
  let prefix_event_ref = reader.read_ref()
  let prefix_sequence = reader.read_int64()
  let prefix_revision = reader.read_int64()
  let prefix_replay_digest = reader.read_digest()
  let terminal_logical_instant = reader.read_int64()
  let evidence = reader.read_evidence()
  let causation = reader.read_ref()
  let event_idempotency_key = reader.read_string()
  let command_idempotency_key = reader.read_string()
  let previous_digest = reader.read_digest()
  reader.require_end()
  let draft : WorkTerminalDraftV22 = {
    terminal_id: expected_ref.id(),
    outcome,
    lineage_digest,
    root_registration_ref,
    root_attempt_ref,
    root_attempt_digest,
    root_intent_ref,
    root_intent_digest,
    source_attempt_ref,
    source_intent_ref,
    source_proof_ref,
    source_proof_bytes,
    source_event_ref,
    source_event_bytes,
    cancellation_request_ref,
    cancellation_request_bytes,
    retry_policy_ref,
    retry_policy_bytes,
    attempt_count,
    retry_count,
    workflow,
    governed_subject,
    effects_prefix_state_digest,
    effects_prefix_replay_digest,
    orchestration_prefix_state_digest,
    orchestration_prefix_replay_digest,
    prefix_event_ref,
    prefix_sequence,
    prefix_revision,
    prefix_replay_digest,
    terminal_logical_instant,
    evidence: ReadOnlyArray::from_array(evidence.copy()),
    causation,
    event_idempotency_key,
    command_idempotency_key,
    previous_digest,
  }
  let expected_lineage_digest = work_terminal_lineage_digest_v22(
    workflow, root_attempt_ref, root_intent_ref, source_attempt_ref, source_intent_ref,
  )
  if lineage_digest != expected_lineage_digest ||
    work_terminal_signing_bytes_v22(draft) != bytes {
    raise ReplayBindingViolation(field="work_record_byte_binding")
  }
  require_cancelled_before_effect_codec_binding_v22(draft)
  let decoded = seal_work_terminal_v22(draft)
  if decoded.terminal_ref != expected_ref || decoded.digest != digest {
    raise ReplayBindingViolation(field="work_record_byte_binding")
  }
  decoded
}

///|
fn prepare_phase1b_work_event_v22(
  workflow : @contracts.RecordRef,
  sequence : Int64,
  revision : Int64,
  previous_digest : @contracts.ContentDigest,
  event_id : String,
  event_kind : String,
  subject : @contracts.RecordRef,
  payload_bytes : Bytes,
  governed_subject : @contracts.RecordRef,
  evidence : Array[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  event_idempotency_key : String,
) -> @storage.WorkflowEvent raise OrchestrationError {
  let payload = @contracts.WireEnvelope::new(
    orchestration_contract_id,
    orchestration_record_version,
    event_id,
    event_kind,
    subject,
    orchestration_schema(event_kind),
    payload_bytes,
    orchestration_producer_id,
    orchestration_record_version,
    [],
    evidence,
    run_ref=workflow,
    correlation_ref=workflow.id(),
    causation_ref=causation.id(),
    idempotency_ref=event_idempotency_key,
    previous_digest~,
  ) catch {
    _ => raise MalformedInput(field="phase1b_work_event_payload")
  }
  // The governed subject is bound by the signed cancellation record. The
  // transport subject remains the exact self-addressed durable record.
  ignore(governed_subject)
  @storage.WorkflowEvent::new(
    orchestration_record_version,
    orchestration_schema_version,
    workflow,
    event_id,
    sequence,
    revision,
    event_idempotency_key,
    payload,
    evidence,
    previous_event_digest=previous_digest,
  ) catch {
    _ => raise MalformedInput(field="phase1b_work_event")
  }
}

///|
pub struct PreparedCancellationV2 {
  request : CancellationRequestV2
  terminal_outcome : WorkTerminalOutcomeV2?
  commit_request : @storage.CommitRequest
}

///|
pub fn PreparedCancellationV2::request(
  self : PreparedCancellationV2,
) -> CancellationRequestV2 {
  self.request
}

///|
pub fn PreparedCancellationV2::terminal_outcome(
  self : PreparedCancellationV2,
) -> WorkTerminalOutcomeV2? {
  self.terminal_outcome
}

///|
fn PreparedCancellationV2::commit_request(
  self : PreparedCancellationV2,
) -> @storage.CommitRequest {
  self.commit_request
}

///|
pub struct PreparedWorkTerminalV2 {
  outcome : WorkTerminalOutcomeV2
  commit_request : @storage.CommitRequest
}

///|
pub fn PreparedWorkTerminalV2::outcome(
  self : PreparedWorkTerminalV2,
) -> WorkTerminalOutcomeV2 {
  self.outcome
}

///|
fn PreparedWorkTerminalV2::commit_request(
  self : PreparedWorkTerminalV2,
) -> @storage.CommitRequest {
  self.commit_request
}

///|
fn effect_terminal_evidence_v22(
  source : @effects.CommittedEffectTerminalSourceV2,
  cancellation : ReplayedCancellationRequestV2?,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  let values : Array[@contracts.EvidenceRef] = [
    for value in source.source_evidence() => value
  ]
  match cancellation {
    None => ()
    Some(request) =>
      for value in request.proposal.evidence {
        values.push(value)
      }
  }
  ReadOnlyArray::from_array(values)
}

///|
fn effect_terminal_logical_instant_v22(
  source : @effects.CommittedEffectTerminalSourceV2,
  cancellation : ReplayedCancellationRequestV2?,
) -> Int64 {
  match cancellation {
    None => source.source_observed_at()
    Some(request) =>
      if request.authorization_observed_at > source.source_observed_at() {
        request.authorization_observed_at
      } else {
        source.source_observed_at()
      }
  }
}

///|
fn effect_terminal_failure_cause_v22(
  source : @effects.CommittedEffectTerminalSourceV2,
) -> String raise OrchestrationError {
  match source.state() {
    @effects.KnownFailure | @effects.ReconciledFailureState => "terminal_failed"
    @effects.ReconciledNotAppliedRetryEligible => "reconciled_not_applied"
    _ =>
      raise CancellationPrecedenceViolation(
        field="work_terminal_outcome_conflict",
      )
  }
}

///|
fn require_work_terminal_counter_bounds_v22(
  policy : RetryPolicyV2,
  attempt_count : Int64,
  retry_count : Int64,
) -> Unit raise OrchestrationError {
  if attempt_count < 1L ||
    retry_count < 0L ||
    attempt_count > policy.maximum_attempt_count() ||
    retry_count > policy.maximum_retry_count() {
    raise RetryBoundViolation(field="work_terminal_failure_counter")
  }
}

///|
fn classify_failure_policy_v22(
  policy : RetryPolicyV2,
  cause : String,
  attempt_count : Int64,
  retry_count : Int64,
  cancellation_pending : Bool,
) -> WorkTerminalOutcomeV2 raise OrchestrationError {
  require_work_terminal_counter_bounds_v22(policy, attempt_count, retry_count)
  if !policy.retryable_failure_classes.any(value => value == cause) {
    FailedNonRetryableV2
  } else if attempt_count == policy.maximum_attempt_count() ||
    retry_count == policy.maximum_retry_count() {
    FailedRetryExhaustedV2
  } else if cancellation_pending {
    FailedCancellationStoppedRetryV2
  } else {
    raise CancellationPrecedenceViolation(
      field="work_terminal_retry_still_open",
    )
  }
}

///|
fn classify_effect_failure_terminal_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
  source : @effects.CommittedEffectTerminalSourceV2,
) -> WorkTerminalOutcomeV2 raise OrchestrationError {
  if current.work.cancellation is Some(_) &&
    source.state() == @effects.ReconciledNotAppliedRetryEligible {
    raise CancellationPrecedenceViolation(
      field="work_terminal_outcome_conflict",
    )
  }
  let binding = current.root_binding.retry_policy
  let policy = RetryPolicyV2::decode(
    binding.retry_policy_ref.id(),
    binding.retry_policy_bytes,
  )
  if policy.policy_ref() != binding.retry_policy_ref ||
    policy.digest() != binding.retry_policy_digest ||
    policy.canonical_bytes() != binding.retry_policy_bytes {
    raise PolicyMismatch(field="root_retry_policy_binding")
  }
  let cause = effect_terminal_failure_cause_v22(source)
  let outcome = classify_failure_policy_v22(
    policy,
    cause,
    source.attempt_count(),
    source.retry_count(),
    current.work.cancellation is Some(_),
  )
  if outcome == FailedRetryExhaustedV2 {
    raise CancellationPrecedenceViolation(
      field="work_terminal_retry_receipt_required",
    )
  }
  if source.state() == @effects.ReconciledNotAppliedRetryEligible {
    raise CancellationPrecedenceViolation(
      field="work_terminal_retry_receipt_required",
    )
  }
  outcome
}

///|
fn prepare_effect_work_terminal_v22(
  current : CurrentGovernedClosedLoopProjectionV2,
  source : @effects.CommittedEffectTerminalSourceV2,
  outcome : WorkTerminalOutcomeV2,
  cancellation : ReplayedCancellationRequestV2?,
  retry_receipt? : @effects.CommittedRetryEligibilityReceiptV2? = None,
) -> PreparedWorkTerminalV2 raise OrchestrationError {
  if current.work.work_terminal is Some(_) {
    raise CancellationPrecedenceViolation(
      field="work_terminal_already_committed",
    )
  }
  if !current.cancellation_authoritative {
    raise ReplayBindingViolation(
      field="cancellation_committed_governance_receipt_required",
    )
  }
  source.validate_current(current.work.effects) catch {
    _ => raise ReplayBindingViolation(field="work_terminal_source")
  }
  match retry_receipt {
    None => ()
    Some(receipt) => {
      receipt.validate_current(current.work.effects) catch {
        _ => raise ReplayBindingViolation(field="work_terminal_source")
      }
      if receipt.source_intent_ref() != source.source_intent_ref() ||
        receipt.source_attempt_ref() != source.source_attempt_ref() ||
        receipt.source_record_ref() != source.source_record_ref() ||
        receipt.source_event_ref() != source.source_event_ref() ||
        receipt.source_event_digest() != source.source_event_ref().digest() ||
        receipt.attempt_count() != source.attempt_count() ||
        receipt.retry_count() != source.retry_count() {
        raise ReplayBindingViolation(field="work_terminal_source")
      }
    }
  }
  if source.workflow() != current.root_binding.workflow {
    raise ReplayBindingViolation(field="work_terminal_source")
  }
  let (latest_attempt_ref, latest_intent_ref) = cancellation_source_lineage_v22(
    current.work.effects,
  )
  if latest_attempt_ref != Some(source.source_attempt_ref()) ||
    latest_intent_ref != Some(source.source_intent_ref()) {
    raise ReplayBindingViolation(field="work_terminal_source_lineage")
  }
  guard current.work.prefix_event is Some(prefix_event) else {
    raise ReplayBindingViolation(field="work_terminal_head_binding")
  }
  let registration = current.root_binding.registration
  let admission = registration.schedule().admission()
  let terminal_id = "\{source.source_record_ref().id()}:\{outcome.wire()}"
  let (source_proof_ref, source_proof_bytes, source_proof_digest) = match
    retry_receipt {
    Some(receipt) => retry_terminal_composite_proof_v22(source, receipt)
    None => (source.receipt_ref(), source.canonical_bytes(), source.digest())
  }
  let event_idempotency_key = "work-terminal-event:\{source_proof_digest.text()}:\{outcome.wire()}"
  let command_idempotency_key = "work-terminal-command:\{source_proof_digest.text()}:\{outcome.wire()}"
  let evidence = effect_terminal_evidence_v22(source, cancellation)
  let failure_outcome = outcome == FailedNonRetryableV2 ||
    outcome == FailedRetryExhaustedV2 ||
    outcome == FailedCancellationStoppedRetryV2
  let retry_policy_ref = if failure_outcome {
    Some(current.root_binding.retry_policy.retry_policy_ref)
  } else {
    None
  }
  let retry_policy_bytes = if failure_outcome {
    Some(current.root_binding.retry_policy.retry_policy_bytes)
  } else {
    None
  }
  let terminal = seal_work_terminal_v22({
    terminal_id,
    outcome,
    lineage_digest: work_terminal_lineage_digest_v22(
      current.root_binding.workflow,
      admission.attempt().attempt_ref(),
      admission.intent_ref(),
      Some(source.source_attempt_ref()),
      Some(source.source_intent_ref()),
    ),
    root_registration_ref: registration.record_ref(),
    root_attempt_ref: admission.attempt().attempt_ref(),
    root_attempt_digest: admission.attempt().attempt_digest(),
    root_intent_ref: admission.intent_ref(),
    root_intent_digest: admission.intent_digest(),
    source_attempt_ref: Some(source.source_attempt_ref()),
    source_intent_ref: Some(source.source_intent_ref()),
    source_proof_ref,
    source_proof_bytes,
    source_event_ref: source.source_event_ref(),
    source_event_bytes: source.source_event_bytes(),
    cancellation_request_ref: cancellation.map(value => value.request_ref),
    cancellation_request_bytes: cancellation.map(value => value.canonical),
    retry_policy_ref,
    retry_policy_bytes,
    attempt_count: if failure_outcome {
      Some(source.attempt_count())
    } else {
      None
    },
    retry_count: if failure_outcome {
      Some(source.retry_count())
    } else {
      None
    },
    workflow: current.root_binding.workflow,
    governed_subject: admission.governance().governed_subject(),
    effects_prefix_state_digest: current.work_effects_state_digest,
    effects_prefix_replay_digest: current.work_replay_digest,
    orchestration_prefix_state_digest: current.work_orchestration_state_digest,
    orchestration_prefix_replay_digest: current.work_replay_digest,
    prefix_event_ref: prefix_event.event_ref(),
    prefix_sequence: current.work_sequence,
    prefix_revision: current.work_revision,
    prefix_replay_digest: current.work_replay_digest,
    terminal_logical_instant: effect_terminal_logical_instant_v22(
      source, cancellation,
    ),
    evidence,
    causation: source.source_record_ref(),
    event_idempotency_key,
    command_idempotency_key,
    previous_digest: current.work_head_digest,
  })
  let terminal_event = prepare_phase1b_work_event_v22(
    current.root_binding.workflow,
    current.work_sequence + 1L,
    current.work_revision + 1L,
    current.work_head_digest,
    terminal.terminal_ref.id(),
    work_terminal_event_kind_v22,
    terminal.terminal_ref,
    terminal.canonical,
    terminal.governed_subject,
    [
      for value in terminal.evidence => value
    ],
    terminal.causation,
    terminal.event_idempotency_key,
  )
  let commit_request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    current.root_binding.workflow,
    current.work_revision,
    command_idempotency_key,
    [terminal_event],
    [],
  ) catch {
    _ => raise ReplayBindingViolation(field="work_batch_boundary_shape")
  }
  { outcome, commit_request }
}

///|
/// Prepare the deterministic success terminal from the exact current,
/// storage-verified effect source. No caller-selected outcome or identifier is
/// accepted.
fn prepare_succeeded_work_terminal_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  source : @effects.CommittedEffectTerminalSourceV2,
) -> PreparedWorkTerminalV2 raise OrchestrationError {
  match source.state() {
    @effects.KnownSuccess | @effects.ReconciledSuccessState =>
      prepare_effect_work_terminal_v22(current, source, SucceededV2, None)
    _ =>
      raise CancellationPrecedenceViolation(
        field="work_terminal_outcome_conflict",
      )
  }
}

///|
/// Prepare the deterministic cancellation winner after the latest effect was
/// conclusively reconciled as not applied.
fn prepare_cancelled_after_reconciled_not_applied_work_terminal_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  source : @effects.CommittedEffectTerminalSourceV2,
) -> PreparedWorkTerminalV2 raise OrchestrationError {
  if source.state() != @effects.ReconciledNotAppliedRetryEligible {
    raise CancellationPrecedenceViolation(
      field="work_terminal_outcome_conflict",
    )
  }
  let retry_receipt_option = current.work.effects.committed_retry_eligibility_receipt(
    source.source_intent_ref(),
  ) catch {
    _ => raise ReplayBindingViolation(field="work_terminal_source")
  }
  guard retry_receipt_option is Some(retry_receipt) else {
    raise ReplayBindingViolation(field="work_terminal_source")
  }
  retry_receipt.validate_current(current.work.effects) catch {
    _ => raise ReplayBindingViolation(field="work_terminal_source")
  }
  let policy_binding = current.root_binding.retry_policy
  let policy = RetryPolicyV2::decode(
    policy_binding.retry_policy_ref.id(),
    policy_binding.retry_policy_bytes,
  )
  require_work_terminal_counter_bounds_v22(
    policy,
    retry_receipt.attempt_count(),
    retry_receipt.retry_count(),
  )
  guard current.work.cancellation is Some(cancellation) else {
    raise CancellationPrecedenceViolation(
      field="work_terminal_cancellation_required",
    )
  }
  prepare_effect_work_terminal_v22(
    current,
    source,
    CancelledAfterReconciledNotAppliedV2,
    Some(cancellation),
  )
}

///|
/// Classify and prepare a terminal failure from the exact current root retry
/// policy, cause class, and lineage counters. Under-bound retryable failures
/// without cancellation remain open and cannot terminalize.
fn prepare_failed_work_terminal_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  source : @effects.CommittedEffectTerminalSourceV2,
) -> PreparedWorkTerminalV2 raise OrchestrationError {
  let outcome = classify_effect_failure_terminal_v22(current, source)
  let cancellation = if outcome == FailedCancellationStoppedRetryV2 {
    current.work.cancellation
  } else {
    None
  }
  prepare_effect_work_terminal_v22(current, source, outcome, cancellation)
}

///|
/// Classify a retry-proven failure as nonretryable or exhausted from the exact
/// current retry-eligibility receipt. An effect terminal source alone is
/// insufficient authority for the exhaustion branch.
fn prepare_retry_proven_failure_work_terminal_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
) -> PreparedWorkTerminalV2 raise OrchestrationError {
  receipt.validate_current(current.work.effects) catch {
    _ => raise ReplayBindingViolation(field="work_terminal_source")
  }
  let current_source = current.work.effects.committed_effect_terminal_source_v2(
    receipt.source_intent_ref(),
  ) catch {
    _ => raise ReplayBindingViolation(field="work_terminal_source")
  }
  guard current_source is Some(source) else {
    raise ReplayBindingViolation(field="work_terminal_source")
  }
  if current.work.cancellation is Some(_) &&
    receipt.cause_key() == "reconciled_not_applied" {
    raise CancellationPrecedenceViolation(
      field="work_terminal_outcome_conflict",
    )
  }
  let binding = current.root_binding.retry_policy
  let policy = RetryPolicyV2::decode(
    binding.retry_policy_ref.id(),
    binding.retry_policy_bytes,
  )
  if policy.policy_ref() != binding.retry_policy_ref ||
    policy.digest() != binding.retry_policy_digest ||
    policy.canonical_bytes() != binding.retry_policy_bytes {
    raise CancellationPrecedenceViolation(
      field="work_terminal_outcome_conflict",
    )
  }
  let outcome = classify_failure_policy_v22(
    policy,
    receipt.cause_key(),
    receipt.attempt_count(),
    receipt.retry_count(),
    false,
  )
  if outcome != FailedNonRetryableV2 && outcome != FailedRetryExhaustedV2 {
    raise CancellationPrecedenceViolation(
      field="work_terminal_outcome_conflict",
    )
  }
  prepare_effect_work_terminal_v22(
    current,
    source,
    outcome,
    None,
    retry_receipt=if outcome == FailedRetryExhaustedV2 ||
      source.state() == @effects.ReconciledNotAppliedRetryEligible {
      Some(receipt)
    } else {
      None
    },
  )
}

///|
/// Prepare exact-bound exhaustion from the current replay-minted retry proof.
fn prepare_retry_exhausted_work_terminal_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  receipt : @effects.CommittedRetryEligibilityReceiptV2,
) -> PreparedWorkTerminalV2 raise OrchestrationError {
  let prepared = prepare_retry_proven_failure_work_terminal_v2(current, receipt)
  if prepared.outcome() != FailedRetryExhaustedV2 {
    raise CancellationPrecedenceViolation(
      field="work_terminal_outcome_conflict",
    )
  }
  prepared
}

///|
fn prepare_cancellation_v2(
  current : CurrentGovernedClosedLoopProjectionV2,
  request : CancellationRequestV2,
) -> PreparedCancellationV2 raise OrchestrationError {
  if current.work.cancellation is Some(_) ||
    current.work.work_terminal is Some(_) {
    raise CancellationPrecedenceViolation(
      field="work_terminal_already_committed",
    )
  }
  let decoded = decode_cancellation_request_v22(
    request.request_ref,
    request.canonical,
    current,
  )
  if decoded.request_ref != request.request_ref ||
    decoded.digest != request.digest ||
    decoded.canonical != request.canonical {
    raise ReplayBindingViolation(field="cancellation_request_composite_binding")
  }
  require_proposal_current_v22(request.proposal, current)
  guard current.work.prefix_event is Some(prefix_event) else {
    raise ReplayBindingViolation(field="cancellation_head_binding")
  }
  let event = prepare_phase1b_work_event_v22(
    request.proposal.workflow,
    current.work_sequence + 1L,
    current.work_revision + 1L,
    current.work_head_digest,
    request.request_ref.id(),
    cancellation_requested_event_kind_v22,
    request.request_ref,
    request.canonical,
    request.proposal.governed_subject,
    [
      for value in request.proposal.evidence => value
    ],
    request.proposal.causation,
    request.proposal.event_idempotency_key,
  )
  let has_durable_effect = (!current.work.effects
  .committed_intent_refs()
  .is_empty() ||
  !current.work.effects.strict_matched_outbox_refs().is_empty()) catch {
    _ => raise ReplayBindingViolation(field="aggregate_effect_coverage")
  }
  // An active lease is already-started durable work. Cancellation revokes
  // new-work authority, but the exact release/expiry settlement must remain
  // possible; therefore it can never take the immediate safe-terminal path.
  let requires_inflight_settlement = has_durable_effect ||
    current.work.orchestration.has_active_lease()
  let events : Array[@storage.WorkflowEvent] = [event]
  let mut terminal_outcome : WorkTerminalOutcomeV2? = None
  if !requires_inflight_settlement {
    let terminal = new_cancelled_before_effect_intent_terminal_v22(
      request, event, current,
    )
    let terminal_event = prepare_phase1b_work_event_v22(
      request.proposal.workflow,
      current.work_sequence + 2L,
      current.work_revision + 2L,
      event.event_ref().digest(),
      terminal.terminal_ref.id(),
      work_terminal_event_kind_v22,
      terminal.terminal_ref,
      terminal.canonical,
      terminal.governed_subject,
      [
        for value in terminal.evidence => value
      ],
      terminal.causation,
      terminal.event_idempotency_key,
    )
    events.push(terminal_event)
    terminal_outcome = Some(CancelledBeforeEffectIntentV2)
  }
  let commit_request = @storage.CommitRequest::new(
    orchestration_record_version,
    orchestration_schema_version,
    request.proposal.workflow,
    prefix_event.revision(),
    request.proposal.command_idempotency_key,
    events,
    [],
  ) catch {
    _ => raise ReplayBindingViolation(field="work_batch_boundary_shape")
  }
  { request, terminal_outcome, commit_request }
}

///|
fn require_phase1b_event_transport_v22(
  event : @storage.WorkflowEvent,
  event_kind : String,
  subject : @contracts.RecordRef,
  evidence : ArrayView[@contracts.EvidenceRef],
  causation : @contracts.RecordRef,
  idempotency_key : String,
) -> Unit raise OrchestrationError {
  require_v2_transport_binding(event, event_kind, subject, evidence, causation)
  require_v2_payload_idempotency(event, idempotency_key)
}

///|
fn require_phase1b_cancellation_batch_v22(
  replay : @storage.ReplayResult,
  cancellation_event : @storage.WorkflowEvent,
  terminal_event : @storage.WorkflowEvent?,
  command_key : String,
  prefix_revision : Int64,
) -> Unit raise OrchestrationError {
  let matching = replay
    .committed_batches()
    .filter(batch => {
      let refs = batch.event_refs()
      let shape_ok = match terminal_event {
        None => refs.length() == 1 && refs[0] == cancellation_event.event_ref()
        Some(terminal) =>
          refs.length() == 2 &&
          refs[0] == cancellation_event.event_ref() &&
          refs[1] == terminal.event_ref()
      }
      shape_ok &&
      batch.intent_refs().is_empty() &&
      batch.expected_revision() == prefix_revision &&
      batch.command_idempotency_key() == command_key
    })
  if matching.length() != 1 {
    raise ReplayBindingViolation(field="work_batch_boundary_shape")
  }
}

///|
fn require_phase1b_terminal_batch_v22(
  replay : @storage.ReplayResult,
  terminal_event : @storage.WorkflowEvent,
  terminal : WorkTerminalRecordV2,
) -> Unit raise OrchestrationError {
  let matching = replay
    .committed_batches()
    .filter(batch => {
      let refs = batch.event_refs()
      refs.length() == 1 &&
      refs[0] == terminal_event.event_ref() &&
      batch.intent_refs().is_empty() &&
      batch.expected_revision() == terminal.prefix_revision &&
      batch.command_idempotency_key() == terminal.command_idempotency_key
    })
  if matching.length() != 1 {
    raise ReplayBindingViolation(field="work_batch_boundary_shape")
  }
}

///|
fn phase1b_event_allowed_after_pending_v22(
  event : @storage.WorkflowEvent,
  replay : @storage.ReplayResult,
) -> Bool raise OrchestrationError {
  let kind = event.payload().envelope_kind()
  kind == "effect.dispatch.observed.v1" ||
  kind == "effect.receipt.recorded.v1" ||
  kind == "effect.outcome.unknown.v1" ||
  kind == "effect.reconciliation.requested.v1" ||
  kind == "effect.reconciliation.resolved.v1" ||
  kind == lease_released_event_kind_v2 ||
  kind == lease_expired_event_kind_v2 ||
  (
    (
      kind == dispatch_observation_event_kind_v3 ||
      kind == recovery_policy_bound_event_kind_v3 ||
      kind == reconciliation_claim_event_kind_v3 ||
      kind == reconciliation_query_started_event_kind_v3 ||
      kind == reconciliation_result_event_kind_v3 ||
      kind == recovery_backoff_event_kind_v3 ||
      kind == recovery_automation_stopped_event_kind_v3 ||
      kind == manual_intervention_hold_event_kind_v3 ||
      kind == manual_intervention_resume_event_kind_v3
    ) &&
    recovery_event_consumption_v3(event, replay) == 1
  ) ||
  (
    kind == recovery_work_terminal_event_kind_v3 &&
    recovery_fact_allowed_after_pending_cancellation_v3(event, replay)
  )
}

///|
/// Finality is a structural stream invariant, so reject a suffix after a
/// terminal marker before any later domain decoder can reinterpret that suffix.
fn require_no_event_after_work_terminal_v22(
  replay : @storage.ReplayResult,
) -> Unit raise OrchestrationError {
  let mut terminal_seen = false
  for event in replay.events() {
    if terminal_seen {
      raise CancellationPrecedenceViolation(
        field="late_event_after_work_terminal",
      )
    }
    if event.payload().envelope_kind() == work_terminal_event_kind_v22 {
      terminal_seen = true
    }
  }
}

///|
fn fold_phase1b_cancellation_state_v22(
  replay : @storage.ReplayResult,
  effects : @effects.EffectsProjection,
) -> (ReplayedCancellationRequestV2?, WorkTerminalRecordV2?) raise OrchestrationError {
  let events = replay.events()
  let mut cancellation : ReplayedCancellationRequestV2? = None
  let mut cancellation_event : @storage.WorkflowEvent? = None
  let mut terminal : WorkTerminalRecordV2? = None
  let mut terminal_event : @storage.WorkflowEvent? = None
  for index, event in events {
    let kind = event.payload().envelope_kind()
    if terminal is Some(_) {
      raise CancellationPrecedenceViolation(
        field="late_event_after_work_terminal",
      )
    }
    if cancellation is Some(_) &&
      kind != work_terminal_event_kind_v22 &&
      !phase1b_event_allowed_after_pending_v22(event, replay) {
      raise CancellationPrecedenceViolation(
        field="cancellation_dispatch_blocked",
      )
    }
    match kind {
      "work.cancellation.requested.v2" => {
        if cancellation is Some(_) {
          raise CancellationPrecedenceViolation(
            field="work_terminal_already_committed",
          )
        }
        let decoded = decode_committed_cancellation_request_v22(
          event.payload().subject(),
          event.payload().payload(),
        )
        if decoded.proposal.workflow != replay.workflow() {
          raise ReplayBindingViolation(field="cancellation_head_binding")
        }
        let normal_current_head = decoded.proposal.prefix_sequence + 1L ==
          event.sequence() &&
          decoded.proposal.prefix_revision + 1L == event.revision() &&
          event.previous_event_digest() ==
          Some(decoded.proposal.prefix_event_ref.digest())
        if normal_current_head {
          if decoded.authorization_work_revision !=
            decoded.proposal.prefix_revision {
            raise ReplayBindingViolation(field="cancellation_head_binding")
          }
        } else {
          if decoded.authorization_work_revision <=
            decoded.proposal.prefix_revision {
            raise ReplayBindingViolation(
              field="cancellation_claim_first_prefix",
            )
          }
          guard decoded.proposal.source_intent_ref is Some(source_intent_ref) else {
            raise ReplayBindingViolation(field="cancellation_source_lineage")
          }
          require_claim_first_cancellation_suffix_v3(
            replay,
            decoded.authorization_work_sequence,
            decoded.authorization_work_revision,
            decoded.authorization_work_head_digest,
            decoded.authorization_work_replay_digest,
            source_intent_ref,
            Some(event),
          )
        }
        require_phase1b_event_transport_v22(
          event,
          cancellation_requested_event_kind_v22,
          decoded.request_ref,
          decoded.proposal.evidence,
          decoded.proposal.causation,
          decoded.proposal.event_idempotency_key,
        )
        cancellation = Some(decoded)
        cancellation_event = Some(event)
      }
      "work.terminal.v2" => {
        if terminal is Some(_) || index == 0 {
          raise ReplayBindingViolation(field="work_batch_boundary_shape")
        }
        let decoded = decode_work_terminal_record_v22(
          event.payload().subject(),
          event.payload().payload(),
        )
        let prefix_event = events[index - 1]
        require_phase1b_event_transport_v22(
          event,
          work_terminal_event_kind_v22,
          decoded.terminal_ref,
          decoded.evidence,
          decoded.causation,
          decoded.event_idempotency_key,
        )
        if decoded.outcome == CancelledBeforeEffectIntentV2 {
          guard cancellation_event is Some(request_event) &&
            cancellation is Some(request) else {
            raise CancellationPrecedenceViolation(
              field="work_terminal_outcome_conflict",
            )
          }
          if decoded.prefix_event_ref != request.proposal.prefix_event_ref ||
            decoded.prefix_sequence + 2L != event.sequence() ||
            decoded.prefix_revision + 2L != event.revision() ||
            prefix_event.event_ref() != request_event.event_ref() ||
            event.previous_event_digest() != Some(decoded.previous_digest) ||
            decoded.previous_digest != request_event.event_ref().digest() {
            raise ReplayBindingViolation(field="work_batch_boundary_shape")
          }
          if decoded.source_event_ref != request_event.event_ref() ||
            decoded.source_event_digest != request_event.event_ref().digest() ||
            decoded.source_event_bytes != request_event.canonical_bytes() {
            raise ReplayBindingViolation(field="work_terminal_source")
          }
        } else {
          if decoded.prefix_event_ref != prefix_event.event_ref() ||
            decoded.prefix_sequence + 1L != event.sequence() ||
            decoded.prefix_revision + 1L != event.revision() ||
            event.previous_event_digest() != Some(decoded.previous_digest) ||
            decoded.previous_digest != prefix_event.event_ref().digest() {
            raise ReplayBindingViolation(field="work_batch_boundary_shape")
          }
          require_phase1b_terminal_batch_v22(replay, event, decoded)
        }
        terminal = Some(decoded)
        terminal_event = Some(event)
      }
      _ => ()
    }
  }
  match (cancellation, cancellation_event) {
    (Some(request), Some(request_event)) => {
      let committed_intents = effects.committed_intent_refs() catch {
        _ => raise ReplayBindingViolation(field="aggregate_effect_coverage")
      }
      let matched_outbox = effects.strict_matched_outbox_refs() catch {
        _ => raise ReplayBindingViolation(field="aggregate_outbox_coverage")
      }
      let durable = !committed_intents.is_empty() || !matched_outbox.is_empty()
      let cancellation_prefix = replay.verified_prefix(
        request.proposal.prefix_revision,
      ) catch {
        _ => raise ReplayBindingViolation(field="cancellation_head_binding")
      }
      let prefix_orchestration = fold_root_bound_orchestration_auto_v22(
        cancellation_prefix,
      )
      let requires_inflight_settlement = durable ||
        prefix_orchestration.has_active_lease()
      if requires_inflight_settlement &&
        terminal.map(value => value.outcome) ==
        Some(CancelledBeforeEffectIntentV2) {
        raise CancellationPrecedenceViolation(
          field="cancellation_safe_effect_lineage_not_empty",
        )
      }
      if !requires_inflight_settlement &&
        terminal.map(value => value.outcome) !=
        Some(CancelledBeforeEffectIntentV2) {
        raise ReplayBindingViolation(field="work_batch_boundary_shape")
      }
      require_phase1b_cancellation_batch_v22(
        replay,
        request_event,
        if terminal.map(value => value.outcome) ==
          Some(CancelledBeforeEffectIntentV2) {
          terminal_event
        } else {
          None
        },
        request.proposal.command_idempotency_key,
        if request.authorization_work_revision ==
          request.proposal.prefix_revision {
          request.proposal.prefix_revision
        } else {
          request_event.revision() - 1L
        },
      )
    }
    (None, None) =>
      match terminal {
        None => ()
        Some(value) =>
          if value.outcome != SucceededV2 &&
            value.outcome != FailedNonRetryableV2 &&
            value.outcome != FailedRetryExhaustedV2 {
            raise CancellationPrecedenceViolation(
              field="work_terminal_outcome_conflict",
            )
          }
      }
    _ => raise ReplayBindingViolation(field="work_batch_boundary_shape")
  }
  (cancellation, terminal)
}

///|
fn require_authoritative_safe_work_terminal_v22(
  terminal : WorkTerminalRecordV2,
  request : CancellationRequestV2,
  prefix : CurrentGovernedClosedLoopProjectionV2,
) -> Unit raise OrchestrationError {
  let committed_intents = prefix.work.effects.committed_intent_refs() catch {
    _ => raise ReplayBindingViolation(field="aggregate_effect_coverage")
  }
  let matched_outbox = prefix.work.effects.strict_matched_outbox_refs() catch {
    _ => raise ReplayBindingViolation(field="aggregate_outbox_coverage")
  }
  if !committed_intents.is_empty() ||
    !matched_outbox.is_empty() ||
    terminal.outcome != CancelledBeforeEffectIntentV2 ||
    terminal.source_proof_ref != request.request_ref ||
    terminal.source_proof_digest != request.digest ||
    terminal.source_proof_bytes != request.canonical ||
    terminal.cancellation_request_ref != Some(request.request_ref) ||
    terminal.cancellation_request_digest != Some(request.digest) ||
    terminal.cancellation_request_bytes != Some(request.canonical) ||
    terminal.retry_policy_ref is Some(_) ||
    terminal.retry_policy_digest is Some(_) ||
    terminal.retry_policy_bytes is Some(_) ||
    terminal.attempt_count is Some(_) ||
    terminal.retry_count is Some(_) ||
    terminal.workflow != request.proposal.workflow ||
    terminal.governed_subject != request.proposal.governed_subject ||
    terminal.root_registration_ref != request.proposal.root_registration_ref ||
    terminal.root_attempt_ref != request.proposal.root_attempt_ref ||
    terminal.root_attempt_digest != request.proposal.root_attempt_digest ||
    terminal.root_intent_ref != request.proposal.root_intent_ref ||
    terminal.root_intent_digest != request.proposal.root_intent_digest ||
    terminal.source_attempt_ref != request.proposal.source_attempt_ref ||
    terminal.source_intent_ref != request.proposal.source_intent_ref ||
    terminal.effects_prefix_state_digest != prefix.work_effects_state_digest ||
    terminal.effects_prefix_replay_digest != prefix.work_replay_digest ||
    terminal.orchestration_prefix_state_digest !=
    prefix.work_orchestration_state_digest ||
    terminal.orchestration_prefix_replay_digest != prefix.work_replay_digest ||
    terminal.prefix_event_ref != request.proposal.prefix_event_ref ||
    terminal.prefix_sequence != prefix.work_sequence ||
    terminal.prefix_revision != prefix.work_revision ||
    terminal.prefix_replay_digest != prefix.work_replay_digest ||
    terminal.terminal_logical_instant != request.authorization.observed_at ||
    terminal.command_idempotency_key != request.proposal.command_idempotency_key {
    raise ReplayBindingViolation(field="work_terminal_source")
  }
}

///|
fn require_authoritative_effect_work_terminal_v22(
  terminal : WorkTerminalRecordV2,
  prefix : CurrentGovernedClosedLoopProjectionV2,
) -> Unit raise OrchestrationError {
  guard terminal.source_intent_ref is Some(source_intent_ref) &&
    terminal.source_attempt_ref is Some(source_attempt_ref) else {
    raise ReplayBindingViolation(field="work_terminal_source")
  }
  let current_source = prefix.work.effects.committed_effect_terminal_source_v2(
    source_intent_ref,
  ) catch {
    _ => raise ReplayBindingViolation(field="work_terminal_source")
  }
  guard current_source is Some(source) else {
    raise ReplayBindingViolation(field="work_terminal_source")
  }
  source.validate_current(prefix.work.effects) catch {
    _ => raise ReplayBindingViolation(field="work_terminal_source")
  }
  let retry_receipt = if terminal.outcome == FailedRetryExhaustedV2 ||
    (
      terminal.outcome == FailedNonRetryableV2 &&
      source.state() == @effects.ReconciledNotAppliedRetryEligible
    ) {
    let candidate = prefix.work.effects.committed_retry_eligibility_receipt(
      source_intent_ref,
    ) catch {
      _ => raise ReplayBindingViolation(field="work_terminal_source")
    }
    guard candidate is Some(receipt) else {
      raise ReplayBindingViolation(field="work_terminal_source")
    }
    receipt.validate_current(prefix.work.effects) catch {
      _ => raise ReplayBindingViolation(field="work_terminal_source")
    }
    Some(receipt)
  } else {
    None
  }
  let cancellation = match terminal.outcome {
    SucceededV2 => {
      if source.state() != @effects.KnownSuccess &&
        source.state() != @effects.ReconciledSuccessState {
        raise CancellationPrecedenceViolation(
          field="work_terminal_outcome_conflict",
        )
      }
      None
    }
    CancelledAfterReconciledNotAppliedV2 => {
      if source.state() != @effects.ReconciledNotAppliedRetryEligible {
        raise CancellationPrecedenceViolation(
          field="work_terminal_outcome_conflict",
        )
      }
      let retry_receipt_option = prefix.work.effects.committed_retry_eligibility_receipt(
        source.source_intent_ref(),
      ) catch {
        _ => raise ReplayBindingViolation(field="work_terminal_source")
      }
      guard retry_receipt_option is Some(retry_receipt) else {
        raise ReplayBindingViolation(field="work_terminal_source")
      }
      retry_receipt.validate_current(prefix.work.effects) catch {
        _ => raise ReplayBindingViolation(field="work_terminal_source")
      }
      let policy_binding = prefix.root_binding.retry_policy
      let policy = RetryPolicyV2::decode(
        policy_binding.retry_policy_ref.id(),
        policy_binding.retry_policy_bytes,
      )
      require_work_terminal_counter_bounds_v22(
        policy,
        retry_receipt.attempt_count(),
        retry_receipt.retry_count(),
      )
      guard prefix.work.cancellation is Some(request) else {
        raise CancellationPrecedenceViolation(
          field="work_terminal_cancellation_required",
        )
      }
      Some(request)
    }
    FailedNonRetryableV2 | FailedCancellationStoppedRetryV2 => {
      if prefix.work.cancellation is Some(_) &&
        source.state() == @effects.ReconciledNotAppliedRetryEligible {
        raise CancellationPrecedenceViolation(
          field="work_terminal_outcome_conflict",
        )
      }
      let expected = match retry_receipt {
        Some(receipt) => {
          let binding = prefix.root_binding.retry_policy
          let policy = RetryPolicyV2::decode(
            binding.retry_policy_ref.id(),
            binding.retry_policy_bytes,
          )
          classify_failure_policy_v22(
            policy,
            receipt.cause_key(),
            receipt.attempt_count(),
            receipt.retry_count(),
            prefix.work.cancellation is Some(_),
          )
        }
        None => classify_effect_failure_terminal_v22(prefix, source)
      }
      if terminal.outcome != expected {
        raise CancellationPrecedenceViolation(
          field="work_terminal_outcome_conflict",
        )
      }
      if expected == FailedCancellationStoppedRetryV2 {
        prefix.work.cancellation
      } else {
        None
      }
    }
    FailedRetryExhaustedV2 => {
      guard retry_receipt is Some(receipt) else {
        raise ReplayBindingViolation(field="work_terminal_source")
      }
      if prefix.work.cancellation is Some(_) &&
        receipt.cause_key() == "reconciled_not_applied" {
        raise CancellationPrecedenceViolation(
          field="work_terminal_outcome_conflict",
        )
      }
      let binding = prefix.root_binding.retry_policy
      let policy = RetryPolicyV2::decode(
        binding.retry_policy_ref.id(),
        binding.retry_policy_bytes,
      )
      if classify_failure_policy_v22(
          policy,
          receipt.cause_key(),
          receipt.attempt_count(),
          receipt.retry_count(),
          prefix.work.cancellation is Some(_),
        ) !=
        FailedRetryExhaustedV2 {
        raise CancellationPrecedenceViolation(
          field="work_terminal_outcome_conflict",
        )
      }
      None
    }
    _ =>
      raise CancellationPrecedenceViolation(
        field="work_terminal_outcome_conflict",
      )
  }
  let (latest_attempt_ref, latest_intent_ref) = cancellation_source_lineage_v22(
    prefix.work.effects,
  )
  let registration = prefix.root_binding.registration
  let admission = registration.schedule().admission()
  let (
    expected_source_proof_ref,
    expected_source_proof_bytes,
    expected_source_proof_digest,
  ) = match retry_receipt {
    Some(receipt) => retry_terminal_composite_proof_v22(source, receipt)
    None => (source.receipt_ref(), source.canonical_bytes(), source.digest())
  }
  let expected_terminal_id = "\{source.source_record_ref().id()}:\{terminal.outcome.wire()}"
  let expected_event_key = "work-terminal-event:\{expected_source_proof_digest.text()}:\{terminal.outcome.wire()}"
  let expected_command_key = "work-terminal-command:\{expected_source_proof_digest.text()}:\{terminal.outcome.wire()}"
  let expected_evidence = effect_terminal_evidence_v22(source, cancellation)
  let failure_outcome = terminal.outcome == FailedNonRetryableV2 ||
    terminal.outcome == FailedRetryExhaustedV2 ||
    terminal.outcome == FailedCancellationStoppedRetryV2
  let expected_policy_ref = if failure_outcome {
    Some(prefix.root_binding.retry_policy.retry_policy_ref)
  } else {
    None
  }
  let expected_policy_digest = if failure_outcome {
    Some(prefix.root_binding.retry_policy.retry_policy_digest)
  } else {
    None
  }
  let expected_policy_bytes = if failure_outcome {
    Some(prefix.root_binding.retry_policy.retry_policy_bytes)
  } else {
    None
  }
  guard prefix.work.prefix_event is Some(prefix_event) else {
    raise ReplayBindingViolation(field="work_terminal_head_binding")
  }
  if latest_attempt_ref != Some(source_attempt_ref) ||
    latest_intent_ref != Some(source_intent_ref) ||
    source_attempt_ref != source.source_attempt_ref() ||
    source_intent_ref != source.source_intent_ref() ||
    terminal.terminal_ref.id() != expected_terminal_id ||
    terminal.source_proof_ref != expected_source_proof_ref ||
    terminal.source_proof_digest != expected_source_proof_digest ||
    terminal.source_proof_bytes != expected_source_proof_bytes ||
    terminal.source_event_ref != source.source_event_ref() ||
    terminal.source_event_digest != source.source_event_ref().digest() ||
    terminal.source_event_bytes != source.source_event_bytes() ||
    terminal.cancellation_request_ref !=
    cancellation.map(value => value.request_ref) ||
    terminal.cancellation_request_digest !=
    cancellation.map(value => value.digest) ||
    terminal.cancellation_request_bytes !=
    cancellation.map(value => value.canonical) ||
    terminal.retry_policy_ref != expected_policy_ref ||
    terminal.retry_policy_digest != expected_policy_digest ||
    terminal.retry_policy_bytes != expected_policy_bytes ||
    terminal.attempt_count !=
    (if failure_outcome { Some(source.attempt_count()) } else { None }) ||
    terminal.retry_count !=
    (if failure_outcome { Some(source.retry_count()) } else { None }) ||
    terminal.workflow != prefix.root_binding.workflow ||
    terminal.governed_subject != admission.governance().governed_subject() ||
    terminal.root_registration_ref != registration.record_ref() ||
    terminal.root_attempt_ref != admission.attempt().attempt_ref() ||
    terminal.root_attempt_digest != admission.attempt().attempt_digest() ||
    terminal.root_intent_ref != admission.intent_ref() ||
    terminal.root_intent_digest != admission.intent_digest() ||
    terminal.effects_prefix_state_digest != prefix.work_effects_state_digest ||
    terminal.effects_prefix_replay_digest != prefix.work_replay_digest ||
    terminal.orchestration_prefix_state_digest !=
    prefix.work_orchestration_state_digest ||
    terminal.orchestration_prefix_replay_digest != prefix.work_replay_digest ||
    terminal.prefix_event_ref != prefix_event.event_ref() ||
    terminal.prefix_sequence != prefix.work_sequence ||
    terminal.prefix_revision != prefix.work_revision ||
    terminal.prefix_replay_digest != prefix.work_replay_digest ||
    terminal.terminal_logical_instant !=
    effect_terminal_logical_instant_v22(source, cancellation) ||
    !same_evidence(terminal.evidence, expected_evidence) ||
    terminal.causation != source.source_record_ref() ||
    terminal.event_idempotency_key != expected_event_key ||
    terminal.command_idempotency_key != expected_command_key ||
    terminal.previous_digest != prefix.work_head_digest {
    raise ReplayBindingViolation(field="work_terminal_source")
  }
}

///|
let committed_work_terminal_receipt_kind_v22 = "orchestration-committed-work-terminal-receipt-v2"

///|
fn committed_work_terminal_receipt_signing_bytes_v22(
  receipt_id : String,
  terminal : WorkTerminalRecordV2,
  terminal_event : @storage.WorkflowEvent,
  boundary : @storage.CommittedBatchBoundary,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/COMMITTED-WORK-TERMINAL-RECEIPT-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(receipt_id)
  write_phase1b_record_v22(writer, terminal.terminal_ref, terminal.canonical)
  writer.string(terminal.outcome.wire())
  write_ref(writer, terminal_event.event_ref())
  writer.int64(boundary.expected_revision())
  writer.string(boundary.command_idempotency_key())
  writer.string(boundary.batch_digest().text())
  writer.count(boundary.event_refs().length())
  for event_ref in boundary.event_refs() {
    write_ref(writer, event_ref)
  }
  writer.count(boundary.intent_refs().length())
  for intent_ref in boundary.intent_refs() {
    write_ref(writer, intent_ref)
  }
  writer.int64(current.work_sequence)
  writer.int64(current.work_revision)
  writer.string(current.work_head_digest.text())
  writer.string(current.work_effects_state_digest.text())
  writer.string(current.work_orchestration_state_digest.text())
  writer.string(current.work_replay_digest.text())
  writer.finish()
}

///|
/// Opaque replay-only proof of exactly one committed aggregate terminal.
pub struct CommittedWorkTerminalReceiptV2 {
  receipt_ref : @contracts.RecordRef
  terminal_ref : @contracts.RecordRef
  outcome : WorkTerminalOutcomeV2
  terminal_event_ref : @contracts.RecordRef
  batch_digest : @contracts.ContentDigest
  work_revision : Int64
  work_head_digest : @contracts.ContentDigest
  work_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
pub fn CurrentGovernedClosedLoopProjectionV2::committed_work_terminal_receipt(
  self : CurrentGovernedClosedLoopProjectionV2,
) -> CommittedWorkTerminalReceiptV2? raise OrchestrationError {
  if !self.cancellation_authoritative {
    raise ReplayBindingViolation(
      field="cancellation_committed_governance_receipt_required",
    )
  }
  match (self.work.work_terminal, self.work.terminal_batch_boundary) {
    (None, None) => None
    (Some(terminal), Some(boundary)) => {
      guard self.work.prefix_event is Some(terminal_event) else {
        raise RecoveryViolation(field="work_terminal_receipt_not_current")
      }
      let refs = boundary.event_refs()
      let boundary_shape_ok = if terminal.outcome ==
        CancelledBeforeEffectIntentV2 {
        refs.length() == 2 &&
        refs[0] == terminal.source_event_ref &&
        refs[1] == terminal_event.event_ref()
      } else {
        refs.length() == 1 && refs[0] == terminal_event.event_ref()
      }
      if terminal_event.payload().envelope_kind() !=
        work_terminal_event_kind_v22 ||
        terminal_event.payload().subject() != terminal.terminal_ref ||
        terminal_event.payload().payload() != terminal.canonical ||
        !boundary_shape_ok ||
        !boundary.intent_refs().is_empty() ||
        boundary.expected_revision() != terminal.prefix_revision ||
        boundary.command_idempotency_key() != terminal.command_idempotency_key {
        raise ReplayBindingViolation(field="work_batch_boundary_shape")
      }
      let receipt_id = "\{terminal.terminal_ref.id()}:committed"
      let canonical = committed_work_terminal_receipt_signing_bytes_v22(
        receipt_id, terminal, terminal_event, boundary, self,
      )
      let digest = @contracts.sha256_digest(canonical)
      Some({
        receipt_ref: self_ref_v22(
          committed_work_terminal_receipt_kind_v22, receipt_id, digest,
        ),
        terminal_ref: terminal.terminal_ref,
        outcome: terminal.outcome,
        terminal_event_ref: terminal_event.event_ref(),
        batch_digest: boundary.batch_digest(),
        work_revision: self.work_revision,
        work_head_digest: self.work_head_digest,
        work_replay_digest: self.work_replay_digest,
        canonical,
        digest,
      })
    }
    _ => raise RecoveryViolation(field="work_terminal_receipt_not_current")
  }
}

///|
pub fn CommittedWorkTerminalReceiptV2::validate_current(
  self : CommittedWorkTerminalReceiptV2,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> Unit raise OrchestrationError {
  guard current.committed_work_terminal_receipt() is Some(replayed) else {
    raise RecoveryViolation(field="work_terminal_receipt_not_current")
  }
  if replayed.receipt_ref != self.receipt_ref ||
    replayed.canonical != self.canonical ||
    replayed.work_revision != self.work_revision ||
    replayed.work_head_digest != self.work_head_digest ||
    replayed.work_replay_digest != self.work_replay_digest {
    raise RecoveryViolation(field="work_terminal_receipt_not_current")
  }
}

///|
pub fn CommittedWorkTerminalReceiptV2::record_ref(
  self : CommittedWorkTerminalReceiptV2,
) -> @contracts.RecordRef {
  self.receipt_ref
}

///|
pub fn CommittedWorkTerminalReceiptV2::outcome(
  self : CommittedWorkTerminalReceiptV2,
) -> WorkTerminalOutcomeV2 {
  self.outcome
}

///|
pub fn CommittedWorkTerminalReceiptV2::canonical_bytes(
  self : CommittedWorkTerminalReceiptV2,
) -> Bytes {
  self.canonical
}

///|
pub fn CommittedWorkTerminalReceiptV2::digest(
  self : CommittedWorkTerminalReceiptV2,
) -> @contracts.ContentDigest {
  self.digest
}
