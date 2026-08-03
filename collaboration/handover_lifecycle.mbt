///|
pub(all) enum HandoverStateV1 {
  Draft
  Sealed
  Offered
  Accepted
  Rejected
  Expired
  Imported
  Resumed
  Completed
} derive(Debug, Eq)

///|
pub fn HandoverStateV1::id(self : HandoverStateV1) -> String {
  match self {
    Draft => "draft"
    Sealed => "sealed"
    Offered => "offered"
    Accepted => "accepted"
    Rejected => "rejected"
    Expired => "expired"
    Imported => "imported"
    Resumed => "resumed"
    Completed => "completed"
  }
}

///|
fn handover_state_v1_from_id(
  value : String,
) -> HandoverStateV1 raise CollaborationError {
  match value {
    "draft" => Draft
    "sealed" => Sealed
    "offered" => Offered
    "accepted" => Accepted
    "rejected" => Rejected
    "expired" => Expired
    "imported" => Imported
    "resumed" => Resumed
    "completed" => Completed
    _ => raise InvalidLifecycle("unsupported handover state: \{value}")
  }
}

///|
pub(all) suberror CollaborationError {
  InvalidLifecycle(String)
  InvalidCollaboration(String)
  SnapshotDecode(String)
} derive(Debug, Eq)

///|
pub struct HandoverTransitionV1 {
  transition_id : String
  from_state : HandoverStateV1
  to_state : HandoverStateV1
  actor : @capability.PrincipalRefV1
  expected_head : @capability.DigestRefV1
  payload_digest : @capability.DigestRefV1
  resulting_head : @capability.DigestRefV1
  authority : @capability.AuthorityDecisionRefV1?
  quarantine : @capability.QuarantineMetadataV1?
  recorded_at : String
} derive(Debug, Eq)

///|
pub fn HandoverTransitionV1::transition_id(
  self : HandoverTransitionV1,
) -> String {
  self.transition_id
}

///|
pub fn HandoverTransitionV1::to_state(
  self : HandoverTransitionV1,
) -> HandoverStateV1 {
  self.to_state
}

///|
pub fn HandoverTransitionV1::payload_digest(
  self : HandoverTransitionV1,
) -> @capability.DigestRefV1 {
  self.payload_digest
}

///|
pub fn HandoverTransitionV1::resulting_head(
  self : HandoverTransitionV1,
) -> @capability.DigestRefV1 {
  self.resulting_head
}

///|
pub struct HandoverTransitionReceiptV1 {
  transition_id : String
  handover_id : String
  state : HandoverStateV1
  head_digest : @capability.DigestRefV1
  payload_digest : @capability.DigestRefV1
  idempotent : Bool
  recorded_at : String
} derive(Debug, Eq)

///|
pub fn HandoverTransitionReceiptV1::state(
  self : HandoverTransitionReceiptV1,
) -> HandoverStateV1 {
  self.state
}

///|
pub fn HandoverTransitionReceiptV1::head_digest(
  self : HandoverTransitionReceiptV1,
) -> @capability.DigestRefV1 {
  self.head_digest
}

///|
pub fn HandoverTransitionReceiptV1::idempotent(
  self : HandoverTransitionReceiptV1,
) -> Bool {
  self.idempotent
}

///|
pub struct HandoverConflictReceiptV1 {
  transition_id : String
  handover_id : String
  expected_head : @capability.DigestRefV1
  actual_head : @capability.DigestRefV1
  reason : String
  recorded_at : String
} derive(Debug, Eq)

///|
pub fn HandoverConflictReceiptV1::reason(
  self : HandoverConflictReceiptV1,
) -> String {
  self.reason
}

///|
pub(all) enum HandoverMutationResultV1 {
  Applied(HandoverProjectionV1, HandoverTransitionReceiptV1)
  Idempotent(HandoverTransitionReceiptV1)
  Conflict(HandoverConflictReceiptV1)
  Denied(String)
} derive(Debug)

///|
pub struct HandoverProjectionV1 {
  bundle : @capability.HandoverBundleV1
  envelope : @capability.HandoverControlEnvelopeV1
  state : HandoverStateV1
  head_digest : @capability.DigestRefV1
  transitions : ReadOnlyArray[HandoverTransitionV1]
} derive(Debug, Eq)

///|
pub fn HandoverProjectionV1::bundle(
  self : HandoverProjectionV1,
) -> @capability.HandoverBundleV1 {
  self.bundle
}

///|
pub fn HandoverProjectionV1::envelope(
  self : HandoverProjectionV1,
) -> @capability.HandoverControlEnvelopeV1 {
  self.envelope
}

///|
pub fn HandoverProjectionV1::state(
  self : HandoverProjectionV1,
) -> HandoverStateV1 {
  self.state
}

///|
pub fn HandoverProjectionV1::head_digest(
  self : HandoverProjectionV1,
) -> @capability.DigestRefV1 {
  self.head_digest
}

///|
pub fn HandoverProjectionV1::transitions(
  self : HandoverProjectionV1,
) -> ReadOnlyArray[HandoverTransitionV1] {
  self.transitions
}

///|
fn lifecycle_digest(seed : String) -> @capability.DigestRefV1 {
  @capability.sha256_digest_ref_v1(@utf8.encode(seed))
}

///|
fn transition_payload_digest_v1(
  transition_id : String,
  from_state : HandoverStateV1,
  to_state : HandoverStateV1,
  actor : @capability.PrincipalRefV1,
  expected_head : @capability.DigestRefV1,
  authority : @capability.AuthorityDecisionRefV1?,
  quarantine : @capability.QuarantineMetadataV1?,
  recorded_at : String,
) -> @capability.DigestRefV1 {
  let authority_digest = match authority {
    Some(value) => value.digest().text()
    None => "-"
  }
  let quarantine_text = match quarantine {
    Some(value) => @capability.encode_quarantine_metadata_v1(value).stringify()
    None => "-"
  }
  lifecycle_digest(
    "\{transition_id}|\{from_state.id()}|\{to_state.id()}|\{actor.canonical_text()}|\{expected_head.text()}|\{authority_digest}|\{quarantine_text}|\{recorded_at}",
  )
}

///|
fn resulting_head_v1(
  expected_head : @capability.DigestRefV1,
  payload_digest : @capability.DigestRefV1,
) -> @capability.DigestRefV1 {
  lifecycle_digest("\{expected_head.text()}|\{payload_digest.text()}")
}

///|
fn handover_transition_allowed(
  from_state : HandoverStateV1,
  to_state : HandoverStateV1,
) -> Bool {
  match (from_state, to_state) {
    (Draft, Sealed) => true
    (Sealed, Offered) => true
    (Offered, Accepted | Rejected | Expired) => true
    (Accepted, Imported) => true
    (Imported, Resumed) => true
    (Resumed, Completed) => true
    _ => false
  }
}

///|
fn expected_actor_v1(
  envelope : @capability.HandoverControlEnvelopeV1,
  from_state : HandoverStateV1,
  to_state : HandoverStateV1,
  actor : @capability.PrincipalRefV1,
) -> Bool {
  match (from_state, to_state) {
    (Draft, Sealed) | (Sealed, Offered) => actor == envelope.source_principal()
    (Offered, Expired) =>
      actor == envelope.source_principal() ||
      actor == envelope.recipient_principal()
    _ => actor == envelope.recipient_principal()
  }
}

///|
pub fn start_handover_v1(
  bundle : @capability.HandoverBundleV1,
  envelope : @capability.HandoverControlEnvelopeV1,
  transition_id : String,
  actor : @capability.PrincipalRefV1,
  recorded_at : String,
) -> HandoverProjectionV1 raise CollaborationError {
  if !@capability.identifier_component_is_canonical(transition_id) ||
    actor != envelope.source_principal() ||
    envelope.bundle_digest() != bundle.content_digest() ||
    !@capability.wire_timestamp_is_canonical(recorded_at) ||
    recorded_at >= envelope.expires_at() {
    raise InvalidLifecycle("invalid draft handover genesis")
  }
  let empty_head = lifecycle_digest(
    "\{envelope.envelope_digest().text()}|genesis",
  )
  let payload_digest = transition_payload_digest_v1(
    transition_id,
    Draft,
    Draft,
    actor,
    empty_head,
    None,
    None,
    recorded_at,
  )
  let resulting_head = resulting_head_v1(empty_head, payload_digest)
  let transition = HandoverTransitionV1::{
    transition_id,
    from_state: Draft,
    to_state: Draft,
    actor,
    expected_head: empty_head,
    payload_digest,
    resulting_head,
    authority: None,
    quarantine: None,
    recorded_at,
  }
  {
    bundle,
    envelope,
    state: Draft,
    head_digest: resulting_head,
    transitions: ReadOnlyArray::from_array([transition]),
  }
}

///|
fn transition_receipt_v1(
  projection : HandoverProjectionV1,
  transition : HandoverTransitionV1,
  idempotent : Bool,
) -> HandoverTransitionReceiptV1 {
  {
    transition_id: transition.transition_id,
    handover_id: projection.envelope.handover_id(),
    state: transition.to_state,
    head_digest: transition.resulting_head,
    payload_digest: transition.payload_digest,
    idempotent,
    recorded_at: transition.recorded_at,
  }
}

///|
pub fn advance_handover_v1(
  projection : HandoverProjectionV1,
  transition_id : String,
  to_state : HandoverStateV1,
  actor : @capability.PrincipalRefV1,
  expected_head : @capability.DigestRefV1,
  recorded_at : String,
  authority? : @capability.AuthorityDecisionRefV1,
  quarantine? : @capability.QuarantineMetadataV1,
) -> HandoverMutationResultV1 {
  if !@capability.identifier_component_is_canonical(transition_id) ||
    !@capability.wire_timestamp_is_canonical(recorded_at) {
    return Denied("transition identity and timestamp must be canonical")
  }
  for existing in projection.transitions {
    if existing.transition_id == transition_id {
      let replay_payload_digest = transition_payload_digest_v1(
        transition_id,
        existing.from_state,
        to_state,
        actor,
        expected_head,
        authority,
        quarantine,
        recorded_at,
      )
      if existing.to_state == to_state &&
        existing.actor == actor &&
        existing.expected_head == expected_head &&
        existing.authority == authority &&
        existing.quarantine == quarantine &&
        existing.recorded_at == recorded_at &&
        existing.payload_digest == replay_payload_digest {
        return Idempotent(transition_receipt_v1(projection, existing, true))
      }
      return Conflict({
        transition_id,
        handover_id: projection.envelope.handover_id(),
        expected_head,
        actual_head: projection.head_digest,
        reason: "transition identity was reused with different content",
        recorded_at,
      })
    }
  }
  if projection.transitions.last() is Some(last_transition) &&
    recorded_at < last_transition.recorded_at {
    return Denied("handover transition cannot backdate the durable timeline")
  }
  let payload_digest = transition_payload_digest_v1(
    transition_id,
    projection.state,
    to_state,
    actor,
    expected_head,
    authority,
    quarantine,
    recorded_at,
  )
  if expected_head != projection.head_digest {
    return Conflict({
      transition_id,
      handover_id: projection.envelope.handover_id(),
      expected_head,
      actual_head: projection.head_digest,
      reason: "expected head does not match current handover head",
      recorded_at,
    })
  }
  if !handover_transition_allowed(projection.state, to_state) {
    return Denied(
      "invalid handover transition: \{projection.state.id()} -> \{to_state.id()}",
    )
  }
  if !expected_actor_v1(projection.envelope, projection.state, to_state, actor) {
    return Denied("actor is not the principal permitted for this transition")
  }
  if to_state == Expired {
    if recorded_at < projection.envelope.expires_at() {
      return Denied("handover cannot expire before its declared expiry")
    }
  } else if recorded_at >= projection.envelope.expires_at() {
    return Denied("handover has expired")
  }
  if to_state == Imported {
    guard authority is Some(decision) else {
      return Denied("import requires a fresh receiver authority decision")
    }
    if !decision.is_fresh_for(
        projection.envelope.recipient_principal(),
        recorded_at,
      ) {
      return Denied("import authority is stale or bound to another principal")
    }
    if projection.bundle.requires_quarantine() {
      guard quarantine is Some(clearance) else {
        return Denied("import requires quarantine clearance")
      }
      if clearance.status() != @capability.QuarantineStatusV1::Cleared {
        return Denied("quarantine did not clear the imported content")
      }
    }
  } else if authority is Some(_) || quarantine is Some(_) {
    return Denied(
      "authority and quarantine evidence are accepted only at import",
    )
  }
  let resulting_head = resulting_head_v1(expected_head, payload_digest)
  let transition = HandoverTransitionV1::{
    transition_id,
    from_state: projection.state,
    to_state,
    actor,
    expected_head,
    payload_digest,
    resulting_head,
    authority,
    quarantine,
    recorded_at,
  }
  let transitions = projection.transitions.iter().to_array()
  transitions.push(transition)
  let updated = HandoverProjectionV1::{
    bundle: projection.bundle,
    envelope: projection.envelope,
    state: to_state,
    head_digest: resulting_head,
    transitions: ReadOnlyArray::from_array(transitions),
  }
  Applied(updated, transition_receipt_v1(updated, transition, false))
}
