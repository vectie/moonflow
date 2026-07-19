///|
/// Immutable request for one opaque external effect. This value performs no
/// action and does not become eligible until authoritative replay proves its
/// causal event and request-only outbox record were committed together.
pub struct EffectIntent {
  record_version : @contracts.Version
  schema_version : @contracts.Version
  intent_ref : @contracts.RecordRef
  attempt_ref : @contracts.RecordRef
  attempt_digest : @contracts.ContentDigest
  workflow : @contracts.RecordRef
  governed_subject : @contracts.RecordRef
  governance : GovernanceBinding
  effect_request : @contracts.WireEnvelope
  effect_request_bytes : Bytes
  evidence : ReadOnlyArray[@contracts.EvidenceRef]
  evidence_digest : @contracts.ContentDigest
  external_idempotency_key : String
  capability_ref : @contracts.RecordRef
  capability_kind : String
  fencing : FencingBinding?
  created_at : Int64
  causation_ref : @contracts.RecordRef
  previous_digest : @contracts.ContentDigest
  canonical : Bytes
}

///|
pub fn EffectIntent::new(
  intent_id : String,
  intent_version : String,
  attempt : AttemptRegistration,
  governance : GovernanceBinding,
  effect_request : @contracts.WireEnvelope,
  evidence : Array[@contracts.EvidenceRef],
  external_idempotency_key : String,
  capability_ref : @contracts.RecordRef,
  capability_kind : String,
  created_at : Int64,
  causation_ref : @contracts.RecordRef,
  previous_digest : @contracts.ContentDigest,
  fencing_required : Bool,
  fencing? : FencingBinding,
) -> EffectIntent raise EffectsError {
  require_version(intent_version, "effect_intent_version")
  require_text(intent_id, "effect_intent_id")
  require_text(external_idempotency_key, "external_idempotency_key")
  require_text(capability_kind, "capability_kind")
  if attempt.workflow() != governance.workflow() {
    raise IdentityMismatch(field="intent_workflow")
  }
  if attempt.governance().binding_digest() != governance.binding_digest() {
    raise GovernanceViolation(field="attempt_governance_binding")
  }
  if effect_request.subject() != governance.governed_subject() {
    raise IdentityMismatch(field="effect_subject")
  }
  if causation_ref != attempt.attempt_ref() {
    raise IdentityMismatch(field="intent_causation")
  }
  if fencing_required && fencing is None {
    raise FencingViolation(field="required_fencing_binding")
  }
  governance.require_active(created_at)
  let evidence_snapshot = evidence.copy()
  let evidence_digest = ordered_evidence_digest(b"MF6AINE1", evidence_snapshot)
  let effect_request_bytes = @contracts.encode_wire_envelope(effect_request)
  let writer = EffectsWriter::new()
  writer.bytes(b"MF6AINT1")
  writer.string(effects_record_version)
  writer.string(effects_schema_version)
  writer.string(intent_id)
  write_ref(writer, attempt.attempt_ref())
  writer.string(attempt.binding_digest().text())
  write_ref(writer, attempt.workflow())
  write_ref(writer, governance.governed_subject())
  writer.bytes(governance.canonical_bytes())
  writer.bytes(effect_request_bytes)
  write_evidence(writer, evidence_snapshot)
  writer.string(evidence_digest.text())
  writer.string(external_idempotency_key)
  write_ref(writer, capability_ref)
  writer.string(capability_kind)
  match fencing {
    None => writer.byte(0)
    Some(value) => {
      writer.byte(1)
      writer.bytes(value.canonical_bytes())
    }
  }
  writer.int64(created_at)
  write_ref(writer, causation_ref)
  writer.string(previous_digest.text())
  let canonical = writer.finish()
  {
    record_version: effects_version(),
    schema_version: effects_version(),
    intent_ref: self_ref(
      "effect-intent",
      intent_id,
      @contracts.sha256_digest(canonical),
    ),
    attempt_ref: attempt.attempt_ref(),
    attempt_digest: attempt.binding_digest(),
    workflow: attempt.workflow(),
    governed_subject: governance.governed_subject(),
    governance,
    effect_request,
    effect_request_bytes,
    evidence: ReadOnlyArray::from_array(evidence_snapshot),
    evidence_digest,
    external_idempotency_key,
    capability_ref,
    capability_kind,
    fencing,
    created_at,
    causation_ref,
    previous_digest,
    canonical,
  }
}

///|
pub fn EffectIntent::intent_ref(self : EffectIntent) -> @contracts.RecordRef {
  self.intent_ref
}

///|
pub fn EffectIntent::attempt_ref(self : EffectIntent) -> @contracts.RecordRef {
  self.attempt_ref
}

///|
pub fn EffectIntent::workflow(self : EffectIntent) -> @contracts.RecordRef {
  self.workflow
}

///|
pub fn EffectIntent::governance(self : EffectIntent) -> GovernanceBinding {
  self.governance
}

///|
pub fn EffectIntent::effect_request(
  self : EffectIntent,
) -> @contracts.WireEnvelope {
  self.effect_request
}

///|
pub fn EffectIntent::evidence(
  self : EffectIntent,
) -> ReadOnlyArray[@contracts.EvidenceRef] {
  self.evidence
}

///|
pub fn EffectIntent::external_idempotency_key(self : EffectIntent) -> String {
  self.external_idempotency_key
}

///|
/// Inert provenance used by the governed aggregate preparation boundary.
pub fn EffectIntent::previous_digest(
  self : EffectIntent,
) -> @contracts.ContentDigest {
  self.previous_digest
}

///|
pub fn EffectIntent::capability_ref(
  self : EffectIntent,
) -> @contracts.RecordRef {
  self.capability_ref
}

///|
pub fn EffectIntent::capability_kind(self : EffectIntent) -> String {
  self.capability_kind
}

///|
pub fn EffectIntent::fencing(self : EffectIntent) -> FencingBinding? {
  self.fencing
}

///|
pub fn EffectIntent::canonical_bytes(self : EffectIntent) -> Bytes {
  self.canonical
}

///|
pub fn EffectIntent::binding_digest(
  self : EffectIntent,
) -> @contracts.ContentDigest {
  self.intent_ref.digest()
}

///|
pub impl Eq for EffectIntent with fn equal(left, right) {
  left.intent_ref == right.intent_ref && left.canonical == right.canonical
}

///|
pub struct PreparedEffectCommit {
  record_version : @contracts.Version
  effect_intent : EffectIntent
  event : @storage.WorkflowEvent
  outbox_intent : @storage.OutboxIntent
  commit_request : @storage.CommitRequest
}

///|
pub fn PreparedEffectCommit::effect_intent(
  self : PreparedEffectCommit,
) -> EffectIntent {
  self.effect_intent
}

///|
pub fn PreparedEffectCommit::event(
  self : PreparedEffectCommit,
) -> @storage.WorkflowEvent {
  self.event
}

///|
pub fn PreparedEffectCommit::outbox_intent(
  self : PreparedEffectCommit,
) -> @storage.OutboxIntent {
  self.outbox_intent
}

///|
pub fn PreparedEffectCommit::commit_request(
  self : PreparedEffectCommit,
) -> @storage.CommitRequest {
  self.commit_request
}

///|
/// Prepare the mandatory one-event/one-request-only-outbox atomic batch.
fn prepare_effect_commit(
  projection : EffectsProjection,
  event_id : String,
  outbox_intent_id : String,
  command_idempotency_key : String,
  intent : EffectIntent,
) -> PreparedEffectCommit raise {
  projection.require_intent(intent)
  if projection.last_event_digest() != Some(intent.previous_digest) {
    raise DigestMismatch(field="intent_previous_digest")
  }
  let payload = event_envelope(
    event_id,
    "effect.intent.requested.v1",
    projection.workflow(),
    intent.governed_subject,
    intent.canonical_bytes(),
    copy_readonly(intent.evidence()),
    intent.attempt_ref(),
    intent.attempt_ref().id(),
    intent.external_idempotency_key(),
    intent.previous_digest,
  )
  let event = @storage.WorkflowEvent::new(
    effects_record_version,
    effects_schema_version,
    projection.workflow(),
    event_id,
    projection.sequence() + 1L,
    projection.revision() + 1L,
    "effect-event/\{intent.external_idempotency_key()}",
    payload,
    copy_readonly(intent.evidence()),
    previous_event_digest=projection.last_event_digest().unwrap(),
  )
  let outbox = @storage.OutboxIntent::new(
    effects_record_version,
    effects_schema_version,
    outbox_intent_id,
    projection.workflow(),
    event.event_ref(),
    intent.external_idempotency_key(),
    intent.effect_request(),
    copy_readonly(intent.evidence()),
  )
  let request = @storage.CommitRequest::new(
    effects_record_version,
    effects_schema_version,
    projection.workflow(),
    projection.revision(),
    command_idempotency_key,
    [event],
    [outbox],
  )
  {
    record_version: effects_version(),
    effect_intent: intent,
    event,
    outbox_intent: outbox,
    commit_request: request,
  }
}
