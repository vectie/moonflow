///|
let operator_mutation_handoff_contract_id_v1 = "moonflow.operator-mutation-handoff.v1"

///|
let operator_mutation_handoff_contract_version_v1 = "1.0.0"

///|
pub(all) enum OperatorMutationCompanionV1 {
  OperatorRecoveryRetryCompanionV1(
    RecoverySettlementSourceV3,
    OperatorAuthorityProofV1
  )
  OperatorManualHoldCompanionV1(
    @contracts.RecordRef,
    ManualInterventionAuthorityV3,
    String,
    ReadOnlyArray[@contracts.EvidenceRef]
  )
  OperatorManualResumeCompanionV1(
    @contracts.RecordRef,
    ManualInterventionAuthorityV3,
    String,
    ReadOnlyArray[@contracts.EvidenceRef]
  )
  OperatorQuarantineCompanionV1(QuarantineDispositionKindV1, String)
}

///|
pub struct OperatorAuthorityProofV1 {
  authority_ref : @contracts.RecordRef
  authority_bytes : Bytes
  scope : String
  issued_at : Int64
  expires_at : Int64?
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  json : Json
  canonical_json : String
  digest : @contracts.ContentDigest
}

///|
pub struct OperatorMutationHandoffV1 {
  command : PackHandoffEnvelopeV1
  companion : OperatorMutationCompanionV1
  json : Json
  canonical_json : String
  digest : @contracts.ContentDigest
}

///|
fn operator_handoff_json_array_v1(
  fields : Map[String, Json],
  key : String,
) -> Array[Json] raise OrchestrationError {
  guard fields.get(key) is Some(Array(values)) else {
    raise MalformedInput(field=key)
  }
  values
}

///|
fn operator_handoff_optional_int64_v1(
  fields : Map[String, Json],
  key : String,
) -> Int64? raise OrchestrationError {
  match fields.get(key) {
    Some(Null) => None
    Some(String(value)) =>
      Some(
        @string.parse_int64(value) catch {
          _ => raise MalformedInput(field=key)
        },
      )
    _ => raise MalformedInput(field=key)
  }
}

///|
fn operator_handoff_evidence_json_v1(
  values : ReadOnlyArray[@contracts.EvidenceRef],
) -> Json {
  Json::array([ for value in values => handoff_evidence_json_v1(value) ])
}

///|
fn operator_handoff_evidence_from_json_v1(
  fields : Map[String, Json],
) -> Array[@contracts.EvidenceRef] raise OrchestrationError {
  [
    for value in operator_handoff_json_array_v1(fields, "evidence") => {
      handoff_decode_evidence_v1(value)
    }
  ]
}

///|
fn recovery_settlement_kind_from_wire_for_handoff_v1(
  value : String,
) -> RecoverySettlementKindV3 raise OrchestrationError {
  match value {
    "known_success_v3" => RecoverySettlementKnownSuccessV3
    "known_failure_v3" => RecoverySettlementKnownFailureV3
    "reconciled_success_v3" => RecoverySettlementReconciledSuccessV3
    "reconciled_failure_v3" => RecoverySettlementReconciledFailureV3
    "confirmed_not_applied_v3" => RecoverySettlementConfirmedNotAppliedV3
    _ => raise MalformedInput(field="recovery_settlement_source_kind_v1")
  }
}

///|
fn decode_recovery_settlement_source_handoff_v1(
  bytes : Bytes,
) -> RecoverySettlementSourceV3 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() != recovery_settlement_source_magic_v3 ||
    reader.read_string() != "3.0.0" {
    raise MalformedInput(field="recovery_settlement_source_handoff_v1")
  }
  let source_id = reader.read_string()
  let workflow = reader.read_ref()
  let governed_subject = reader.read_ref()
  let intent_ref = reader.read_ref()
  let dispatch_claim_ref = reader.read_ref()
  let dispatch_claim_digest = reader.read_digest()
  let origin_ref = reader.read_ref()
  let origin_digest = reader.read_digest()
  let origin_bytes = reader.read_bytes()
  let kind = recovery_settlement_kind_from_wire_for_handoff_v1(
    reader.read_string(),
  )
  let settled_at = reader.read_int64()
  let recovery_state_digest = reader.read_digest()
  let work_revision = reader.read_int64()
  let work_head_digest = reader.read_digest()
  let work_replay_digest = reader.read_digest()
  let governance_workflow = reader.read_ref()
  let governance_revision = reader.read_int64()
  let governance_head_digest = reader.read_optional_digest()
  let governance_replay_digest = reader.read_digest()
  let recovery_evidence_head = match reader.read_byte() {
    0 => None
    1 => Some(decode_recovery_evidence_head_v3(reader.read_bytes()))
    _ =>
      raise MalformedInput(field="recovery_settlement_source_evidence_head_v1")
  }
  let evidence = reader.read_evidence()
  reader.require_end()
  if settled_at < 0L ||
    work_revision < 0L ||
    governance_revision < 0L ||
    origin_ref.digest() != origin_digest ||
    @contracts.sha256_digest(origin_bytes) != origin_digest {
    raise ReplayBindingViolation(field="recovery_settlement_source_handoff_v1")
  }
  let digest = @contracts.sha256_digest(bytes)
  {
    source_ref: self_ref_v3(
      "orchestration-recovery-settlement-source-v3", source_id, digest,
    ),
    workflow,
    governed_subject,
    intent_ref,
    dispatch_claim_ref,
    dispatch_claim_digest,
    origin_ref,
    origin_digest,
    origin_bytes,
    kind,
    settled_at,
    recovery_evidence_head,
    recovery_state_digest,
    work_revision,
    work_head_digest,
    work_replay_digest,
    governance_workflow,
    governance_revision,
    governance_head_digest,
    governance_replay_digest,
    evidence: ReadOnlyArray::from_array(evidence),
    canonical: bytes,
    digest,
  }
}

///|
fn decode_operator_authority_proof_v1(
  value : Json,
  requested_at : Int64,
) -> OperatorAuthorityProofV1 raise OrchestrationError {
  let fields = handoff_json_object_v1(value, "authority_proof", [
    "authority_ref", "authority_digest", "authority_hex", "scope", "issued_at", "expires_at",
    "evidence",
  ])
  guard fields.get("authority_ref") is Some(reference_json) else {
    raise MalformedInput(field="authority_proof.authority_ref")
  }
  let authority_ref = handoff_decode_record_ref_v1(
    reference_json, "authority_proof.authority_ref",
  )
  let authority_digest = @contracts.ContentDigest::parse(
    handoff_json_string_v1(fields, "authority_digest"),
  ) catch {
    _ => raise MalformedInput(field="authority_proof.authority_digest")
  }
  let authority_bytes = handoff_bytes_from_hex_v1(
    handoff_json_string_v1(fields, "authority_hex"),
  )
  let issued_at = @string.parse_int64(
    handoff_json_string_v1(fields, "issued_at"),
  ) catch {
    _ => raise MalformedInput(field="authority_proof.issued_at")
  }
  let expires_at = operator_handoff_optional_int64_v1(fields, "expires_at")
  let evidence = operator_handoff_evidence_from_json_v1(fields)
  if authority_bytes.is_empty() ||
    authority_ref.digest() != authority_digest ||
    @contracts.sha256_digest(authority_bytes) != authority_digest ||
    issued_at < 0L ||
    issued_at > requested_at ||
    evidence.is_empty() {
    raise ReplayBindingViolation(field="operator_authority_proof_v1")
  }
  match expires_at {
    Some(value) if value <= issued_at || requested_at >= value =>
      raise ReplayBindingViolation(field="operator_authority_proof_expiry_v1")
    _ => ()
  }
  let canonical_json = value.stringify()
  {
    authority_ref,
    authority_bytes,
    scope: handoff_json_string_v1(fields, "scope"),
    issued_at,
    expires_at,
    evidence: ReadOnlyArray::from_array(evidence),
    json: value,
    canonical_json,
    digest: @contracts.sha256_digest(@utf8.encode(canonical_json)),
  }
}

///|
fn decode_operator_retry_companion_v1(
  fields : Map[String, Json],
  request : OperatorCommandRequestV1,
) -> OperatorMutationCompanionV1 raise OrchestrationError {
  guard fields.get("source_ref") is Some(source_ref_json) &&
    fields.get("authority_proof") is Some(authority_json) else {
    raise MalformedInput(field="operator_retry_companion_v1")
  }
  let source_ref = handoff_decode_record_ref_v1(
    source_ref_json, "companion.source_ref",
  )
  let source_digest = @contracts.ContentDigest::parse(
    handoff_json_string_v1(fields, "source_digest"),
  ) catch {
    _ => raise MalformedInput(field="companion.source_digest")
  }
  let source = decode_recovery_settlement_source_handoff_v1(
    handoff_bytes_from_hex_v1(handoff_json_string_v1(fields, "source_hex")),
  )
  let proof = decode_operator_authority_proof_v1(
    authority_json,
    request.requested_at(),
  )
  if request.kind() != OperatorRecoveryRetryV1 ||
    request.authority_ref() != Some(proof.authority_ref) ||
    proof.scope != "operator.recovery-retry.v1" ||
    source.record_ref() != source_ref ||
    source.digest() != source_digest ||
    source.governed_subject != request.subject_ref() ||
    !same_evidence(request.evidence(), proof.evidence) ||
    !same_evidence(request.evidence(), source.evidence) {
    raise ReplayBindingViolation(field="operator_retry_companion_v1")
  }
  OperatorRecoveryRetryCompanionV1(source, proof)
}

///|
fn decode_operator_manual_companion_v1(
  fields : Map[String, Json],
  request : OperatorCommandRequestV1,
) -> OperatorMutationCompanionV1 raise OrchestrationError {
  guard fields.get("intent_ref") is Some(intent_json) else {
    raise MalformedInput(field="companion.intent_ref")
  }
  let intent_ref = handoff_decode_record_ref_v1(
    intent_json, "companion.intent_ref",
  )
  let authority_digest = @contracts.ContentDigest::parse(
    handoff_json_string_v1(fields, "authority_digest"),
  ) catch {
    _ => raise MalformedInput(field="companion.authority_digest")
  }
  let authority = decode_manual_intervention_authority_v3(
    handoff_bytes_from_hex_v1(handoff_json_string_v1(fields, "authority_hex")),
  )
  let reason = handoff_json_string_v1(fields, "reason")
  let evidence = operator_handoff_evidence_from_json_v1(fields)
  let selector = handoff_json_string_v1(fields, "selector")
  if request.kind() != OperatorManualInterventionResolutionV1 ||
    request.subject_ref() != intent_ref ||
    request.authority_ref() != Some(authority.authority_ref()) ||
    authority.digest() != authority_digest ||
    !same_evidence(request.evidence(), evidence) {
    raise ReplayBindingViolation(field="operator_manual_companion_v1")
  }
  match (selector, authority.scope()) {
    ("hold", ManualInterventionHoldAuthorityV3) =>
      OperatorManualHoldCompanionV1(
        intent_ref,
        authority,
        reason,
        ReadOnlyArray::from_array(evidence),
      )
    ("resume", ManualInterventionResumeAuthorityV3) =>
      OperatorManualResumeCompanionV1(
        intent_ref,
        authority,
        reason,
        ReadOnlyArray::from_array(evidence),
      )
    _ => raise ReplayBindingViolation(field="operator_manual_selector_v1")
  }
}

///|
fn decode_operator_quarantine_companion_v1(
  fields : Map[String, Json],
  request : OperatorCommandRequestV1,
) -> OperatorMutationCompanionV1 raise OrchestrationError {
  if request.kind() != OperatorQuarantineResolutionV1 {
    raise ReplayBindingViolation(field="operator_quarantine_companion_v1")
  }
  OperatorQuarantineCompanionV1(
    quarantine_disposition_kind_from_wire_v1(
      handoff_json_string_v1(fields, "disposition"),
    ),
    handoff_json_string_v1(fields, "reason"),
  )
}

///|
pub fn decode_operator_mutation_handoff_v1(
  value : Json,
) -> OperatorMutationHandoffV1 raise OrchestrationError {
  let fields = handoff_json_object_v1(value, "operator_mutation_handoff", [
    "contract_id", "contract_version", "command", "companion",
  ])
  let version = handoff_json_string_v1(fields, "contract_version")
  if handoff_json_string_v1(fields, "contract_id") !=
    operator_mutation_handoff_contract_id_v1 ||
    version != operator_mutation_handoff_contract_version_v1 {
    raise UnsupportedVersion(field="operator_mutation_handoff_v1", version~)
  }
  guard fields.get("command") is Some(command_json) &&
    fields.get("companion") is Some(companion_json) else {
    raise MalformedInput(field="operator_mutation_handoff_shape_v1")
  }
  let command = decode_pack_handoff_envelope_v1(command_json)
  let request = command.operator_command()
  let kind_fields = handoff_json_object_v1(
    companion_json,
    "operator_mutation_companion",
    match request.kind() {
      OperatorRecoveryRetryV1 =>
        ["kind", "source_ref", "source_digest", "source_hex", "authority_proof"]
      OperatorManualInterventionResolutionV1 =>
        [
          "kind", "intent_ref", "authority_digest", "authority_hex", "selector",
          "reason", "evidence",
        ]
      OperatorQuarantineResolutionV1 => ["kind", "disposition", "reason"]
      _ => raise MalformedInput(field="operator_mutation_command_kind_v1")
    },
  )
  let companion_kind = handoff_json_string_v1(kind_fields, "kind")
  let companion = match companion_kind {
    "recovery-retry-v1" =>
      decode_operator_retry_companion_v1(kind_fields, request)
    "manual-intervention-v1" =>
      decode_operator_manual_companion_v1(kind_fields, request)
    "quarantine-disposition-v1" =>
      decode_operator_quarantine_companion_v1(kind_fields, request)
    _ => raise MalformedInput(field="operator_mutation_companion_kind_v1")
  }
  let canonical_json = value.stringify()
  {
    command,
    companion,
    json: value,
    canonical_json,
    digest: @contracts.sha256_digest(@utf8.encode(canonical_json)),
  }
}

///|
pub fn decode_operator_mutation_handoff_json_v1(
  input : Bytes,
) -> OperatorMutationHandoffV1 raise OrchestrationError {
  let text = @utf8.decode(input) catch {
    _ => raise MalformedInput(field="operator_mutation_handoff_utf8_v1")
  }
  decode_operator_mutation_handoff_v1(
    @json.parse(text) catch {
      _ => raise MalformedInput(field="operator_mutation_handoff_json_v1")
    },
  )
}

///|
fn pack_operator_mutation_receipt_v1(
  mutation : OperatorMutationHandoffV1,
  receipt : OperatorCommandReceiptV1,
) -> PackHostReceiptV1 {
  make_pack_host_receipt_v1(
    "operator-command",
    operator_disposition_wire_v1(receipt.disposition()),
    receipt.record_persisted(),
    receipt.durable_receipt_ref(),
    [],
    mutation.digest,
  )
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] execute_pack_operator_mutation_v1(
  store : S,
  surface : MoonFlowOperatorSurfaceV1,
  current : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
  mutation : OperatorMutationHandoffV1,
) -> PackHostReceiptV1 raise {
  let request = mutation.command.operator_command()
  let routed = route_operator_command_v1(surface, request)
  match routed.disposition() {
    OperatorPreparedForExistingCommitV1(_) => ()
    disposition =>
      return make_pack_host_receipt_v1(
        "operator-command",
        operator_disposition_wire_v1(disposition),
        false,
        None,
        [],
        mutation.digest,
      )
  }
  let receipt = match mutation.companion {
    OperatorRecoveryRetryCompanionV1(source, _) =>
      execute_operator_recovery_retry_v1(
        store, surface, current, evidence_projection, request, source,
      )
    OperatorManualHoldCompanionV1(intent_ref, authority, reason, _) =>
      execute_operator_manual_hold_v1(
        store, surface, current, evidence_projection, request, intent_ref, authority,
        reason,
      )
    OperatorManualResumeCompanionV1(intent_ref, authority, reason, _) =>
      execute_operator_manual_resume_v1(
        store, surface, current, evidence_projection, request, intent_ref, authority,
        reason,
      )
    OperatorQuarantineCompanionV1(disposition, reason) =>
      execute_operator_quarantine_disposition_v1(
        store, surface, current, evidence_projection, request, disposition, reason,
      )
  }
  pack_operator_mutation_receipt_v1(mutation, receipt)
}

///|
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] execute_pack_operator_mutation_json_v1(
  store : S,
  surface : MoonFlowOperatorSurfaceV1,
  current : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
  input : Bytes,
) -> PackHostReceiptV1 raise {
  execute_pack_operator_mutation_v1(
    store,
    surface,
    current,
    evidence_projection,
    decode_operator_mutation_handoff_json_v1(input),
  )
}

///|
fn require_operator_mutation_committed_time_v1(
  run_id : String,
  current : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
  time : TimeEvidenceProjectionV3,
  request : OperatorCommandRequestV1,
) -> Unit raise OrchestrationError {
  let committed_now = phase3_committed_now_v3(time)
  if request.run_id() != run_id ||
    request.requested_at() != committed_now ||
    request.head_scope() != OperatorWorkHeadV1 ||
    request.expected_head_digest !=
    current.work_replay.head().last_event_digest() ||
    request.expected_replay_digest != current.work_replay.replay_digest() ||
    request.expected_state_digest != current.state_digest() ||
    evidence_projection.bound_workflow() != current.work_replay.workflow() ||
    evidence_projection.bound_work_replay_digest() !=
    current.work_replay.replay_digest() {
    raise ReplayBindingViolation(field="operator_mutation_committed_time_v1")
  }
}

///|
/// Native hosts use this replay-only mutation entrypoint after folding their
/// work, governance, recovery-evidence, and committed-time roots. It is the
/// same prepare/commit path as the operator surface wrappers, but obtains
/// freshness from the durable time projection rather than a materialized UI
/// projection. No provider is invoked.
pub fn[S : @storage.ClassifiedRegistryBoundGuardedStoragePort] execute_pack_operator_mutation_at_committed_time_v1(
  store : S,
  run_id : String,
  current : CurrentGovernedRecoveryProjectionV3,
  evidence_projection : CurrentRecoveryEvidenceProjectionV3,
  time : TimeEvidenceProjectionV3,
  mutation : OperatorMutationHandoffV1,
) -> PackHostReceiptV1 raise {
  let request = mutation.command.operator_command()
  require_operator_mutation_committed_time_v1(
    run_id, current, evidence_projection, time, request,
  )
  let receipt = match mutation.companion {
    OperatorRecoveryRetryCompanionV1(source, _) => {
      guard request.authority_ref is Some(_) else {
        raise ReplayBindingViolation(field="operator_retry_authority_v1")
      }
      if request.kind != OperatorRecoveryRetryV1 ||
        request.subject_ref != source.governed_subject ||
        request.payload.subject() != source.governed_subject ||
        !same_evidence(request.evidence, source.evidence) {
        raise ReplayBindingViolation(field="operator_retry_request_v1")
      }
      guard request.payload.idempotency_ref() is Some(external_key) else {
        raise MalformedInput(field="operator_retry_external_idempotency_v1")
      }
      let command_id = request.command_ref.id()
      let candidate = prepare_recovery_retry_candidate_v3(
        current,
        source,
        request.payload,
        "\{command_id}:retry-intent",
        "\{command_id}:retry-schedule",
        "\{command_id}:retry-intent-event",
        "\{command_id}:retry-schedule-event",
        "\{command_id}:retry-outbox",
        "operator-recovery-retry:\{request.digest.text()}",
        external_key,
        request.requested_at,
      )
      operator_retry_commit_receipt_v1(
        request,
        candidate.schedule().record_ref(),
        commit_recovery_retry_v3(store, candidate),
      )
    }
    OperatorManualHoldCompanionV1(intent_ref, authority, reason, _) => {
      if request.kind != OperatorManualInterventionResolutionV1 ||
        request.subject_ref != intent_ref ||
        request.authority_ref != Some(authority.authority_ref()) ||
        authority.scope() != ManualInterventionHoldAuthorityV3 {
        raise ReplayBindingViolation(field="operator_manual_hold_request_v1")
      }
      let candidate = prepare_manual_intervention_hold_v3(
        current,
        evidence_projection,
        "\{request.command_ref.id()}:hold",
        intent_ref,
        authority,
        reason,
        [
          for value in request.evidence => value
        ],
        request.requested_at,
      )
      operator_manual_commit_receipt_v1(
        request,
        candidate.record().record_ref(),
        commit_manual_intervention_v3(store, candidate),
      )
    }
    OperatorManualResumeCompanionV1(intent_ref, authority, reason, _) => {
      if request.kind != OperatorManualInterventionResolutionV1 ||
        request.subject_ref != intent_ref ||
        request.authority_ref != Some(authority.authority_ref()) ||
        authority.scope() != ManualInterventionResumeAuthorityV3 {
        raise ReplayBindingViolation(field="operator_manual_resume_request_v1")
      }
      let candidate = prepare_manual_intervention_resume_v3(
        current,
        evidence_projection,
        "\{request.command_ref.id()}:resume",
        intent_ref,
        authority,
        reason,
        [
          for value in request.evidence => value
        ],
        request.requested_at,
      )
      operator_manual_commit_receipt_v1(
        request,
        candidate.record().record_ref(),
        commit_manual_intervention_v3(store, candidate),
      )
    }
    OperatorQuarantineCompanionV1(disposition, reason) => {
      guard request.authority_ref is Some(authority_ref) &&
        request.review_ref is Some(review_ref) else {
        raise ReplayBindingViolation(field="operator_quarantine_authority_v1")
      }
      if request.kind != OperatorQuarantineResolutionV1 ||
        !evidence_projection
        .quarantined_entries()
        .any(value => value.record().record_ref() == request.subject_ref) {
        raise ReplayBindingViolation(field="operator_quarantine_subject_v1")
      }
      let candidate = prepare_quarantine_disposition_v1(
        current,
        evidence_projection,
        "\{request.command_ref.id()}:quarantine",
        request.subject_ref,
        disposition,
        authority_ref,
        review_ref,
        reason,
        [
          for value in request.evidence => value
        ],
        request.requested_at,
      )
      operator_quarantine_commit_receipt_v1(
        request,
        candidate.record().record_ref(),
        commit_quarantine_disposition_v1(store, candidate),
      )
    }
  }
  pack_operator_mutation_receipt_v1(mutation, receipt)
}

///|
pub fn OperatorMutationHandoffV1::to_json(
  self : OperatorMutationHandoffV1,
) -> Json {
  self.json
}

///|
pub fn OperatorMutationHandoffV1::digest(
  self : OperatorMutationHandoffV1,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn OperatorMutationHandoffV1::companion(
  self : OperatorMutationHandoffV1,
) -> OperatorMutationCompanionV1 {
  self.companion
}
