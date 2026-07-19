///|
let committed_cancellation_governance_receipt_kind_v22 = "orchestration-committed-cancellation-governance-receipt-v2"

///|
let cancellation_governance_event_kinds_v22 : ReadOnlyArray[String] = [
  "EvidenceAttached", "AuthorityRequested", "AuthorityGranted", "ReviewRequested",
  "ReviewDecisionRecorded", "ReviewReceiptBound",
]

///|
/// Opaque joint current view of one root-bound work stream and its distinct,
/// root-selected governance stream. There is deliberately no public
/// constructor or decoder.
pub struct CurrentGovernedClosedLoopProjectionV2 {
  work : ClosedLoopProjectionV2
  root_binding : CommittedCancellationGovernanceBindingReceiptV2
  governance_policy : @governance.GovernancePolicy
  governance : @governance.GovernanceProjection
  governance_events : ReadOnlyArray[@storage.WorkflowEvent]
  work_sequence : Int64
  work_revision : Int64
  work_head_digest : @contracts.ContentDigest
  work_effects_state_digest : @contracts.ContentDigest
  work_orchestration_state_digest : @contracts.ContentDigest
  work_replay_digest : @contracts.ContentDigest
  governance_sequence : Int64
  governance_revision : Int64
  governance_head_digest : @contracts.ContentDigest?
  governance_state_digest : @contracts.ContentDigest
  governance_replay_digest : @contracts.ContentDigest
  phase2_recovery_active : Bool
  phase2_recovery_activations : ReadOnlyArray[RecoveryProtocolActivatedV3]
  mut cancellation_authoritative : Bool
}

///|
fn phase2_recovery_activations_v22(
  replay : @storage.ReplayResult,
) -> ReadOnlyArray[RecoveryProtocolActivatedV3] raise OrchestrationError {
  let values : Array[RecoveryProtocolActivatedV3] = []
  for event in replay.events() {
    if event.payload().envelope_kind() == recovery_activation_event_kind_v3 {
      values.push(
        decode_recovery_protocol_activated_v3(event.payload().payload()),
      )
    }
  }
  ReadOnlyArray::from_array(values)
}

///|
fn fold_governed_base_v22(
  empty_effects : @effects.EffectsProjection,
  work_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
) -> CurrentGovernedClosedLoopProjectionV2 raise OrchestrationError {
  let root_binding = fold_initial_work_receipt_v22(empty_effects, work_replay)
  let work = fold_closed_loop_v2(empty_effects, work_replay)
  require_root_binding_matches_aggregate_v22(root_binding, work)
  let governance_stream = root_binding.cancellation_governance.governance_stream_ref
  if governance_stream == root_binding.workflow {
    raise ReplayBindingViolation(field="cancellation_governance_stream_binding")
  }
  if governance_replay.workflow() != governance_stream ||
    governance_replay.head().workflow() != governance_stream {
    raise ReplayBindingViolation(field="cancellation_governance_stream_binding")
  }
  let bound_policy_ref = root_binding.cancellation_governance.governance_policy_ref
  let bound_policy_bytes = root_binding.cancellation_governance.governance_policy_bytes
  let governance_policy = @governance.GovernancePolicy::decode(
    bound_policy_ref, bound_policy_bytes,
  ) catch {
    _ => raise PolicyMismatch(field="root_cancellation_governance_binding")
  }
  if governance_policy.policy_ref() != bound_policy_ref ||
    governance_policy.digest() !=
    root_binding.cancellation_governance.governance_policy_digest ||
    governance_policy.canonical_bytes() != bound_policy_bytes {
    raise PolicyMismatch(field="root_cancellation_governance_binding")
  }
  let governance = @governance.fold_replay(governance_policy, governance_replay) catch {
    _ =>
      raise ReplayBindingViolation(
        field="cancellation_governance_event_membership",
      )
  }
  let governance_head = governance_replay.head()
  if governance.workflow() != governance_stream ||
    governance.sequence() != governance_head.sequence() ||
    governance.revision() != governance_head.revision() ||
    governance.last_event_digest() != governance_head.last_event_digest() {
    raise ReplayBindingViolation(field="cancellation_governance_stream_binding")
  }
  guard work.prefix_event is Some(work_head) else {
    raise ReplayBindingViolation(field="cancellation_head_binding")
  }
  {
    work,
    root_binding,
    governance_policy,
    governance,
    governance_events: ReadOnlyArray::from_array(
      [
        for event in governance_replay.events() => event
      ],
    ),
    work_sequence: work_head.sequence(),
    work_revision: work_head.revision(),
    work_head_digest: work_head.event_ref().digest(),
    work_effects_state_digest: work.effects.state_digest(),
    work_orchestration_state_digest: work.orchestration.state_digest(),
    work_replay_digest: work_replay.replay_digest(),
    governance_sequence: governance_head.sequence(),
    governance_revision: governance_head.revision(),
    governance_head_digest: governance_head.last_event_digest(),
    governance_state_digest: governance.state_digest(),
    governance_replay_digest: governance_replay.replay_digest(),
    phase2_recovery_active: work_replay
    .events()
    .any(event => {
      event.payload().envelope_kind() == recovery_activation_event_kind_v3
    }),
    phase2_recovery_activations: phase2_recovery_activations_v22(work_replay),
    cancellation_authoritative: false,
  }
}

///|
/// Capability ownership is monotonic after activation and independent of the
/// intent's current V2 state. Catalog failures are never converted to absence.
fn CurrentGovernedClosedLoopProjectionV2::v3_owns_intent_v22(
  self : CurrentGovernedClosedLoopProjectionV2,
  intent_ref : @contracts.RecordRef,
) -> Bool raise OrchestrationError {
  if !self.phase2_recovery_active {
    return false
  }
  let catalog = self.work.effects.strict_recovery_intent_catalog_v3() catch {
    _ => raise ReplayBindingViolation(field="v3_effect_identity_catalog")
  }
  guard first(catalog, identity => identity.intent_ref() == intent_ref)
    is Some(identity) else {
    raise ReplayBindingViolation(field="v3_effect_identity_catalog")
  }
  self.phase2_recovery_activations.any(activation => {
    activation.source_intent_ref == intent_ref ||
    (
      activation.capability_ref == identity.capability_ref() &&
      activation.capability_kind == identity.capability_kind()
    )
  })
}

///|
fn CurrentGovernedClosedLoopProjectionV2::require_legacy_intent_mutation_v22(
  self : CurrentGovernedClosedLoopProjectionV2,
  intent_ref : @contracts.RecordRef,
) -> Unit raise OrchestrationError {
  if self.v3_owns_intent_v22(intent_ref) {
    raise RecoveryViolation(field="legacy_effect_transition_retired_phase2")
  }
}

///|
/// Phase-2 activation closes legacy caller-selected reconciliation and retry
/// mutation paths for the entire stream. Historical V2 facts remain replayable
/// but cannot be extended into a Phase-2 retry proof.
fn CurrentGovernedClosedLoopProjectionV2::require_legacy_effect_protocol_v2(
  self : CurrentGovernedClosedLoopProjectionV2,
) -> Unit raise OrchestrationError {
  if self.phase2_recovery_active {
    raise RecoveryViolation(field="legacy_effect_protocol_retired_phase2")
  }
}

///|
/// Strictly fold separate storage-verified work and governance replays. Any
/// committed cancellation is first treated as an untrusted work-stream
/// candidate, then revalidated against its exact storage prefix and the exact
/// current six-event governance stream before this governed aggregate exists.
pub fn fold_governed_closed_loop_v2(
  empty_effects : @effects.EffectsProjection,
  work_replay : @storage.ReplayResult,
  governance_replay : @storage.ReplayResult,
) -> CurrentGovernedClosedLoopProjectionV2 raise OrchestrationError {
  require_no_event_after_work_terminal_v22(work_replay)
  let current = fold_governed_base_v22(
    empty_effects, work_replay, governance_replay,
  )
  let mut authoritative_cancellation : CancellationRequestV2? = None
  let mut cancellation_prefix_current : CurrentGovernedClosedLoopProjectionV2? = None
  match current.work.cancellation {
    None => ()
    Some(candidate) => {
      let proposal_prefix_replay = work_replay.verified_prefix(
        candidate.proposal.prefix_revision,
      ) catch {
        _ => raise ReplayBindingViolation(field="cancellation_head_binding")
      }
      let proposal_prefix_current = fold_governed_base_v22(
        empty_effects, proposal_prefix_replay, governance_replay,
      )
      if proposal_prefix_current.work.cancellation is Some(_) ||
        proposal_prefix_current.work.work_terminal is Some(_) {
        raise ReplayBindingViolation(field="cancellation_head_binding")
      }
      let decoded = if candidate.authorization_work_revision ==
        candidate.proposal.prefix_revision {
        decode_cancellation_request_v22(
          candidate.request_ref,
          candidate.canonical,
          proposal_prefix_current,
        )
      } else {
        let authorization_prefix_replay = work_replay.verified_prefix(
          candidate.authorization_work_revision,
        ) catch {
          _ =>
            raise ReplayBindingViolation(
              field="cancellation_claim_first_prefix",
            )
        }
        if authorization_prefix_replay.head().sequence() !=
          candidate.authorization_work_sequence ||
          authorization_prefix_replay.head().last_event_digest() !=
          Some(candidate.authorization_work_head_digest) ||
          authorization_prefix_replay.replay_digest() !=
          candidate.authorization_work_replay_digest ||
          candidate.authorization_governance_stream !=
          governance_replay.workflow() ||
          candidate.authorization_governance_sequence !=
          current.governance_sequence ||
          candidate.authorization_governance_revision !=
          current.governance_revision ||
          candidate.authorization_governance_head_digest !=
          current.governance_head_digest.unwrap() ||
          candidate.authorization_governance_replay_digest !=
          current.governance_replay_digest {
          raise ReplayBindingViolation(field="cancellation_claim_first_prefix")
        }
        let authorization_prefix_current = fold_governed_base_v22(
          empty_effects, authorization_prefix_replay, governance_replay,
        )
        decode_historical_cancellation_request_v3(
          candidate.request_ref,
          candidate.canonical,
          authorization_prefix_current,
          proposal_prefix_current,
        )
      }
      if decoded.request_ref != candidate.request_ref ||
        decoded.canonical != candidate.canonical ||
        decoded.proposal.record_ref() != candidate.proposal.record_ref() ||
        decoded.proposal.canonical_bytes() !=
        candidate.proposal.canonical_bytes() {
        raise ReplayBindingViolation(
          field="cancellation_committed_governance_receipt_required",
        )
      }
      authoritative_cancellation = Some(decoded)
      cancellation_prefix_current = Some(proposal_prefix_current)
    }
  }
  match current.work.work_terminal {
    None => ()
    Some(terminal) =>
      if terminal.outcome == CancelledBeforeEffectIntentV2 {
        guard authoritative_cancellation is Some(request) &&
          cancellation_prefix_current is Some(prefix) else {
          raise CancellationPrecedenceViolation(
            field="work_terminal_outcome_conflict",
          )
        }
        require_authoritative_safe_work_terminal_v22(terminal, request, prefix)
      } else {
        let terminal_prefix_replay = work_replay.verified_prefix(
          terminal.prefix_revision,
        ) catch {
          _ => raise ReplayBindingViolation(field="work_terminal_head_binding")
        }
        let terminal_prefix_current = fold_governed_base_v22(
          empty_effects, terminal_prefix_replay, governance_replay,
        )
        if terminal_prefix_current.work.work_terminal is Some(_) {
          raise ReplayBindingViolation(field="work_terminal_head_binding")
        }
        require_authoritative_effect_work_terminal_v22(
          terminal, terminal_prefix_current,
        )
      }
  }
  current.cancellation_authoritative = true
  current
}

///|
fn require_proposal_current_v22(
  proposal : CancellationProposalV2,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> Unit raise OrchestrationError {
  require_root_binding_matches_aggregate_v22(current.root_binding, current.work)
  let registration = current.root_binding.registration
  let admission = registration.schedule().admission()
  let (expected_attempt_ref, expected_intent_ref) = cancellation_source_lineage_v22(
    current.work.effects,
  )
  let expected_attempt_digest = expected_attempt_ref.map(value => value.digest())
  let expected_intent_digest = expected_intent_ref.map(value => value.digest())
  if proposal.source_attempt_ref != expected_attempt_ref ||
    proposal.source_attempt_digest != expected_attempt_digest ||
    proposal.source_intent_ref != expected_intent_ref ||
    proposal.source_intent_digest != expected_intent_digest {
    raise ReplayBindingViolation(field="cancellation_source_lineage")
  }
  if proposal.workflow != current.root_binding.workflow ||
    proposal.root_registration_ref != registration.record_ref() ||
    proposal.root_registration_bytes != registration.canonical_bytes() ||
    proposal.root_schedule_ref != registration.schedule_ref() ||
    proposal.root_requested_work_ref != admission.planned().requested_work_ref() ||
    proposal.root_requested_work_digest !=
    admission.planned().requested_work_digest() ||
    proposal.root_attempt_ref != admission.attempt().attempt_ref() ||
    proposal.root_attempt_digest != admission.attempt().attempt_digest() ||
    proposal.root_intent_ref != admission.intent_ref() ||
    proposal.root_intent_digest != admission.intent_digest() ||
    proposal.governed_subject != admission.governance().governed_subject() ||
    proposal.prefix_event_ref.digest() != current.work_head_digest ||
    proposal.prefix_event_ref != current.work.prefix_event.unwrap().event_ref() ||
    proposal.prefix_sequence != current.work_sequence ||
    proposal.prefix_revision != current.work_revision ||
    proposal.prefix_replay_digest != current.work_replay_digest {
    raise ReplayBindingViolation(field="cancellation_head_binding")
  }
  let decoded = decode_cancellation_proposal_v22_strict(
    proposal.proposal_ref,
    proposal.canonical,
  )
  if decoded.canonical != proposal.canonical ||
    decoded.governance_subject != proposal.governance_subject {
    raise ReplayBindingViolation(field="cancellation_proposal_self_address")
  }
}

///|
fn require_exact_cancellation_governance_events_v22(
  events : ArrayView[@storage.WorkflowEvent],
) -> Unit raise OrchestrationError {
  if events.length() != cancellation_governance_event_kinds_v22.length() {
    raise ReplayBindingViolation(
      field="cancellation_governance_event_membership",
    )
  }
  for index, event in events {
    if event.payload().envelope_kind() !=
      cancellation_governance_event_kinds_v22[index] ||
      event.sequence() != index.to_int64() + 1L ||
      event.revision() != index.to_int64() + 1L {
      raise ReplayBindingViolation(
        field="cancellation_governance_event_membership",
      )
    }
  }
}

///|
fn write_phase1b_record_v22(
  writer : OrchestrationWriter,
  record_ref : @contracts.RecordRef,
  bytes : Bytes,
) -> Unit raise OrchestrationError {
  write_ref(writer, record_ref)
  writer.string(record_ref.digest().text())
  writer.bytes(bytes)
}

///|
fn committed_cancellation_governance_receipt_signing_bytes_v22(
  receipt_id : String,
  current : CurrentGovernedClosedLoopProjectionV2,
  proposal : CancellationProposalV2,
  attachment : @governance.EvidenceAttachment,
  authority_request : @governance.AuthorityRequest,
  authority_grant : @governance.AuthorityDecision,
  review_request : @governance.ReviewRequest,
  review_decision : @governance.ReviewDecision,
  review_receipt : @governance.ReviewReceipt,
  observed_at : Int64,
  effective_valid_until_inclusive : Int64,
  deadline_exclusive : Int64,
) -> Bytes raise OrchestrationError {
  let writer = OrchestrationWriter::new()
  writer.bytes(b"FLOW7/COMMITTED-CANCELLATION-GOVERNANCE-RECEIPT-V2/2.2.0")
  writer.string(orchestration_record_version_v22)
  writer.string(receipt_id)
  write_ref(writer, current.root_binding.workflow)
  write_ref(
    writer,
    current.root_binding.cancellation_governance.governance_stream_ref,
  )
  write_phase1b_record_v22(
    writer,
    current.root_binding.cancellation_governance.governance_policy_ref,
    current.root_binding.cancellation_governance.governance_policy_bytes,
  )
  write_phase1b_record_v22(
    writer,
    current.root_binding.record_ref,
    current.root_binding.canonical,
  )
  write_phase1b_record_v22(writer, proposal.proposal_ref, proposal.canonical)
  write_ref(writer, proposal.governed_subject)
  writer.bytes(@contracts.encode_wire_envelope(proposal.governance_subject))
  write_evidence(writer, proposal.evidence)
  write_phase1b_record_v22(
    writer,
    attachment.attachment_ref(),
    attachment.canonical_bytes(),
  )
  write_evidence(writer, attachment.evidence())
  write_phase1b_record_v22(
    writer,
    authority_request.request_ref(),
    authority_request.canonical_bytes(),
  )
  write_phase1b_record_v22(
    writer,
    authority_grant.decision_ref(),
    authority_grant.canonical_bytes(),
  )
  write_phase1b_record_v22(
    writer,
    review_request.request_ref(),
    review_request.canonical_bytes(),
  )
  write_phase1b_record_v22(
    writer,
    review_decision.decision_ref(),
    review_decision.canonical_bytes(),
  )
  write_phase1b_record_v22(
    writer,
    review_receipt.receipt_ref(),
    review_receipt.canonical_bytes(),
  )
  write_ref(writer, authority_grant.authority_ref())
  write_ref(writer, review_decision.reviewer_ref())
  writer.int64(proposal.observed_at)
  writer.int64(authority_request.requested_at())
  writer.int64(authority_grant.decided_at())
  writer.int64(review_request.requested_at())
  writer.int64(review_decision.decided_at())
  writer.int64(review_receipt.bound_at())
  writer.optional_int64(authority_request.expires_at())
  writer.int64(current.root_binding.valid_until_inclusive())
  writer.int64(observed_at)
  writer.int64(effective_valid_until_inclusive)
  writer.int64(deadline_exclusive)
  writer.count(current.governance_events.length())
  for event in current.governance_events {
    write_phase1b_record_v22(writer, event.event_ref(), event.canonical_bytes())
    writer.string(event.payload().envelope_kind())
    writer.int64(event.sequence())
    writer.int64(event.revision())
  }
  writer.int64(current.governance_sequence)
  writer.int64(current.governance_revision)
  writer.string(current.governance_head_digest.unwrap().text())
  writer.string(current.governance_state_digest.text())
  writer.string(current.governance_replay_digest.text())
  writer.int64(current.work_sequence)
  writer.int64(current.work_revision)
  writer.string(current.work_head_digest.text())
  writer.string(current.work_effects_state_digest.text())
  writer.string(current.work_orchestration_state_digest.text())
  writer.string(current.work_replay_digest.text())
  writer.finish()
}

///|
/// Opaque, replay-only proof of the exact approved six-event cancellation
/// governance chain at one exact pair of work/governance heads.
pub struct CommittedCancellationGovernanceReceiptV2 {
  record_ref : @contracts.RecordRef
  proposal : CancellationProposalV2
  root_binding_ref : @contracts.RecordRef
  root_binding_bytes : Bytes
  governance_stream_ref : @contracts.RecordRef
  governance_policy_ref : @contracts.RecordRef
  governance_policy_bytes : Bytes
  authority_ref : @contracts.RecordRef
  reviewer_ref : @contracts.RecordRef
  authority_requested_at : Int64
  authority_decided_at : Int64
  review_requested_at : Int64
  review_decided_at : Int64
  review_bound_at : Int64
  request_deadline_exclusive : Int64?
  observed_at : Int64
  effective_valid_until_inclusive : Int64
  deadline_exclusive : Int64
  governance_sequence : Int64
  governance_revision : Int64
  governance_head_digest : @contracts.ContentDigest
  governance_state_digest : @contracts.ContentDigest
  governance_replay_digest : @contracts.ContentDigest
  work_sequence : Int64
  work_revision : Int64
  work_head_digest : @contracts.ContentDigest
  work_effects_state_digest : @contracts.ContentDigest
  work_orchestration_state_digest : @contracts.ContentDigest
  work_replay_digest : @contracts.ContentDigest
  canonical : Bytes
  digest : @contracts.ContentDigest
}

///|
fn CurrentGovernedClosedLoopProjectionV2::mint_committed_cancellation_governance_receipt_v22(
  self : CurrentGovernedClosedLoopProjectionV2,
  proposal : CancellationProposalV2,
) -> CommittedCancellationGovernanceReceiptV2 raise OrchestrationError {
  require_exact_cancellation_governance_events_v22(self.governance_events)
  if self.governance.authority_status() != @governance.AuthorityGrantedStatus ||
    self.governance.review_status() !=
    @governance.ReviewReceiptBoundStatus(@governance.Approved) {
    raise ReplayBindingViolation(
      field="cancellation_governance_event_membership",
    )
  }
  guard self.governance.evidence_attachment_record() is Some(attachment) &&
    self.governance.authority_request_record() is Some(authority_request) &&
    self.governance.authority_decision_record() is Some(authority_grant) &&
    self.governance.review_request_record() is Some(review_request) &&
    self.governance.review_decision_record() is Some(review_decision) &&
    self.governance.receipt() is Some(review_receipt) &&
    self.governance_head_digest is Some(governance_head_digest) else {
    raise ReplayBindingViolation(
      field="cancellation_governance_event_membership",
    )
  }
  if authority_grant.outcome() != @governance.Granted ||
    review_decision.outcome() != @governance.Approved ||
    !review_receipt.is_terminal_approved() ||
    authority_request.workflow() != self.root_binding.governance_stream_ref() ||
    attachment.workflow() != self.root_binding.governance_stream_ref() ||
    authority_request.authority_subject() != proposal.governance_subject ||
    review_request.subject() != proposal.governance_subject ||
    attachment.purpose() != proposal.proposal_ref ||
    !same_evidence(attachment.evidence(), proposal.evidence) ||
    review_receipt.authority_ref() != authority_grant.authority_ref() ||
    review_receipt.reviewer_ref() != review_decision.reviewer_ref() {
    raise ReplayBindingViolation(
      field="cancellation_governance_event_membership",
    )
  }
  let (observed_at, effective_valid_until_inclusive, deadline_exclusive) = cancellation_authorization_times_v22(
    proposal.observed_at,
    authority_request.requested_at(),
    authority_grant.decided_at(),
    review_request.requested_at(),
    review_decision.decided_at(),
    review_receipt.bound_at(),
    self.root_binding.valid_until_inclusive(),
    authority_request.expires_at(),
  )
  let receipt_id = "\{proposal.proposal_ref.id()}:committed-governance"
  let canonical = committed_cancellation_governance_receipt_signing_bytes_v22(
    receipt_id, self, proposal, attachment, authority_request, authority_grant, review_request,
    review_decision, review_receipt, observed_at, effective_valid_until_inclusive,
    deadline_exclusive,
  )
  let digest = @contracts.sha256_digest(canonical)
  {
    record_ref: self_ref_v22(
      committed_cancellation_governance_receipt_kind_v22, receipt_id, digest,
    ),
    proposal,
    root_binding_ref: self.root_binding.record_ref,
    root_binding_bytes: self.root_binding.canonical,
    governance_stream_ref: self.root_binding.governance_stream_ref(),
    governance_policy_ref: self.root_binding.governance_policy_ref(),
    governance_policy_bytes: self.root_binding.cancellation_governance.governance_policy_bytes,
    authority_ref: authority_grant.authority_ref(),
    reviewer_ref: review_decision.reviewer_ref(),
    authority_requested_at: authority_request.requested_at(),
    authority_decided_at: authority_grant.decided_at(),
    review_requested_at: review_request.requested_at(),
    review_decided_at: review_decision.decided_at(),
    review_bound_at: review_receipt.bound_at(),
    request_deadline_exclusive: authority_request.expires_at(),
    observed_at,
    effective_valid_until_inclusive,
    deadline_exclusive,
    governance_sequence: self.governance_sequence,
    governance_revision: self.governance_revision,
    governance_head_digest,
    governance_state_digest: self.governance_state_digest,
    governance_replay_digest: self.governance_replay_digest,
    work_sequence: self.work_sequence,
    work_revision: self.work_revision,
    work_head_digest: self.work_head_digest,
    work_effects_state_digest: self.work_effects_state_digest,
    work_orchestration_state_digest: self.work_orchestration_state_digest,
    work_replay_digest: self.work_replay_digest,
    canonical,
    digest,
  }
}

///|
pub fn CurrentGovernedClosedLoopProjectionV2::committed_cancellation_governance_receipt(
  self : CurrentGovernedClosedLoopProjectionV2,
  proposal : CancellationProposalV2,
) -> CommittedCancellationGovernanceReceiptV2 raise OrchestrationError {
  require_proposal_current_v22(proposal, self)
  self.mint_committed_cancellation_governance_receipt_v22(proposal)
}

///|
fn read_phase1b_record_v22(
  reader : OrchestrationReader,
) -> (@contracts.RecordRef, Bytes) raise OrchestrationError {
  let record_ref = reader.read_ref()
  let digest = reader.read_digest()
  let bytes = reader.read_bytes()
  // Governance records use their own strict canonical codecs: their public
  // transport bytes wrap signing bytes plus the signing digest, so the hash of
  // the transport bytes is not necessarily the RecordRef digest. Bind the
  // explicit digest here; proposal/current replay reconstruction below checks
  // every embedded byte and the full receipt canonical form exactly.
  if record_ref.digest() != digest {
    raise ReplayBindingViolation(
      field="cancellation_governance_receipt_self_address",
    )
  }
  (record_ref, bytes)
}

///|
fn decode_committed_cancellation_governance_receipt_at_v22(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
  current : CurrentGovernedClosedLoopProjectionV2,
  historical_proposal_current : CurrentGovernedClosedLoopProjectionV2?,
) -> CommittedCancellationGovernanceReceiptV2 raise OrchestrationError {
  let reader = OrchestrationReader::new(bytes)
  if reader.read_bytes() !=
    b"FLOW7/COMMITTED-CANCELLATION-GOVERNANCE-RECEIPT-V2/2.2.0" {
    raise MalformedInput(field="cancellation_governance_receipt_tag")
  }
  let version = reader.read_string()
  if version != orchestration_record_version_v22 {
    raise UnsupportedVersion(field="cancellation_governance_receipt", version~)
  }
  ignore(reader.read_string())
  ignore(reader.read_ref())
  ignore(reader.read_ref())
  ignore(read_phase1b_record_v22(reader))
  ignore(read_phase1b_record_v22(reader))
  let (proposal_ref, proposal_bytes) = read_phase1b_record_v22(reader)
  let proposal = decode_cancellation_proposal_v22_strict(
    proposal_ref, proposal_bytes,
  )
  ignore(reader.read_ref())
  ignore(
    @contracts.decode_wire_envelope(reader.read_bytes()) catch {
      _ => raise MalformedInput(field="cancellation_governance_subject")
    },
  )
  ignore(reader.read_evidence())
  ignore(read_phase1b_record_v22(reader))
  ignore(reader.read_evidence())
  for _ in 0..<5 {
    ignore(read_phase1b_record_v22(reader))
  }
  ignore(reader.read_ref())
  ignore(reader.read_ref())
  for _ in 0..<6 {
    ignore(reader.read_int64())
  }
  ignore(reader.read_optional_int64())
  for _ in 0..<4 {
    ignore(reader.read_int64())
  }
  let event_count = reader.read_count()
  if event_count != 6 {
    raise ReplayBindingViolation(
      field="cancellation_governance_event_membership",
    )
  }
  for _ in 0..<event_count {
    ignore(read_phase1b_record_v22(reader))
    ignore(reader.read_string())
    ignore(reader.read_int64())
    ignore(reader.read_int64())
  }
  for _ in 0..<2 {
    ignore(reader.read_int64())
  }
  for _ in 0..<3 {
    ignore(reader.read_digest())
  }
  for _ in 0..<2 {
    ignore(reader.read_int64())
  }
  for _ in 0..<4 {
    ignore(reader.read_digest())
  }
  reader.require_end()
  let decoded = try {
    match historical_proposal_current {
      None => current.committed_cancellation_governance_receipt(proposal)
      Some(proposal_current) => {
        require_proposal_current_v22(proposal, proposal_current)
        current.mint_committed_cancellation_governance_receipt_v22(proposal)
      }
    }
  } catch {
    _ =>
      raise ReplayBindingViolation(
        field="cancellation_governance_receipt_not_current",
      )
  }
  if decoded.record_ref != expected_ref ||
    decoded.canonical != bytes ||
    expected_ref.kind() != committed_cancellation_governance_receipt_kind_v22 ||
    expected_ref.version().text() != orchestration_record_version_v22 {
    raise ReplayBindingViolation(
      field="cancellation_governance_receipt_self_address",
    )
  }
  decoded
}

///|
fn decode_committed_cancellation_governance_receipt_v22(
  expected_ref : @contracts.RecordRef,
  bytes : Bytes,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> CommittedCancellationGovernanceReceiptV2 raise OrchestrationError {
  decode_committed_cancellation_governance_receipt_at_v22(
    expected_ref,
    bytes,
    current,
    None,
  )
}

///|
pub fn CommittedCancellationGovernanceReceiptV2::validate_current(
  self : CommittedCancellationGovernanceReceiptV2,
  current : CurrentGovernedClosedLoopProjectionV2,
) -> Unit raise OrchestrationError {
  let replayed = current.committed_cancellation_governance_receipt(
    self.proposal,
  ) catch {
    _ =>
      raise ReplayBindingViolation(
        field="cancellation_governance_receipt_not_current",
      )
  }
  if replayed.record_ref != self.record_ref ||
    replayed.canonical != self.canonical ||
    replayed.governance_head_digest != self.governance_head_digest ||
    replayed.governance_replay_digest != self.governance_replay_digest ||
    replayed.work_head_digest != self.work_head_digest ||
    replayed.work_replay_digest != self.work_replay_digest {
    raise ReplayBindingViolation(
      field="cancellation_governance_receipt_not_current",
    )
  }
}

///|
pub fn CommittedCancellationGovernanceReceiptV2::record_ref(
  self : CommittedCancellationGovernanceReceiptV2,
) -> @contracts.RecordRef {
  self.record_ref
}

///|
pub fn CommittedCancellationGovernanceReceiptV2::digest(
  self : CommittedCancellationGovernanceReceiptV2,
) -> @contracts.ContentDigest {
  self.digest
}

///|
pub fn CommittedCancellationGovernanceReceiptV2::canonical_bytes(
  self : CommittedCancellationGovernanceReceiptV2,
) -> Bytes {
  self.canonical
}

///|
pub fn CommittedCancellationGovernanceReceiptV2::observed_at(
  self : CommittedCancellationGovernanceReceiptV2,
) -> Int64 {
  self.observed_at
}

///|
pub fn CommittedCancellationGovernanceReceiptV2::effective_valid_until_inclusive(
  self : CommittedCancellationGovernanceReceiptV2,
) -> Int64 {
  self.effective_valid_until_inclusive
}

///|
pub fn CommittedCancellationGovernanceReceiptV2::deadline_exclusive(
  self : CommittedCancellationGovernanceReceiptV2,
) -> Int64 {
  self.deadline_exclusive
}
