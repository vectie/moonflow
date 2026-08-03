///|
priv struct HandoverTransitionWireV1 {
  transition_id : String
  from_state : String
  to_state : String
  actor : Json
  expected_head : String
  payload_digest : String
  resulting_head : String
  authority : Json?
  quarantine : Json?
  recorded_at : String
} derive(ToJson, FromJson)

///|
priv struct HandoverSnapshotWireV1 {
  contract_id : String
  bundle : Json
  envelope : Json
  state : String
  head_digest : String
  transitions : Array[HandoverTransitionWireV1]
} derive(ToJson, FromJson)

///|
fn handover_transition_wire_v1(
  transition : HandoverTransitionV1,
) -> HandoverTransitionWireV1 {
  {
    transition_id: transition.transition_id,
    from_state: transition.from_state.id(),
    to_state: transition.to_state.id(),
    actor: @capability.encode_principal_ref_v1(transition.actor),
    expected_head: transition.expected_head.text(),
    payload_digest: transition.payload_digest.text(),
    resulting_head: transition.resulting_head.text(),
    authority: transition.authority.map(value => {
      @capability.encode_authority_decision_ref_v1(value)
    }),
    quarantine: transition.quarantine.map(value => {
      @capability.encode_quarantine_metadata_v1(value)
    }),
    recorded_at: transition.recorded_at,
  }
}

///|
pub fn encode_handover_snapshot_v1(projection : HandoverProjectionV1) -> Json {
  HandoverSnapshotWireV1::{
    contract_id: "moonflow.handover-snapshot.v1",
    bundle: @capability.encode_handover_bundle_v1(projection.bundle),
    envelope: @capability.encode_handover_control_envelope_v1(
      projection.envelope,
    ),
    state: projection.state.id(),
    head_digest: projection.head_digest.text(),
    transitions: projection.transitions
    .iter()
    .to_array()
    .map(transition => handover_transition_wire_v1(transition)),
  }.to_json()
}

///|
fn decode_optional_authority_v1(
  value : Json?,
) -> @capability.AuthorityDecisionRefV1? raise CollaborationError {
  match value {
    Some(encoded) =>
      Some(
        @capability.decode_authority_decision_ref_v1(encoded) catch {
          _ => raise SnapshotDecode("invalid authority decision reference")
        },
      )
    None => None
  }
}

///|
fn decode_optional_quarantine_v1(
  value : Json?,
) -> @capability.QuarantineMetadataV1? raise CollaborationError {
  match value {
    Some(encoded) =>
      Some(
        @capability.decode_quarantine_metadata_v1(encoded) catch {
          _ => raise SnapshotDecode("invalid quarantine metadata")
        },
      )
    None => None
  }
}

///|
fn transition_matches_wire_v1(
  transition : HandoverTransitionV1,
  wire : HandoverTransitionWireV1,
) -> Bool {
  transition.transition_id == wire.transition_id &&
  transition.from_state.id() == wire.from_state &&
  transition.to_state.id() == wire.to_state &&
  transition.actor ==
  (@capability.decode_principal_ref_v1(wire.actor) catch { _ => return false }) &&
  transition.expected_head.text() == wire.expected_head &&
  transition.payload_digest.text() == wire.payload_digest &&
  transition.resulting_head.text() == wire.resulting_head &&
  transition.recorded_at == wire.recorded_at
}

///|
/// Restores a durable handover only by replaying its immutable transition log.
/// Tampered heads, payloads, authorities, and terminal projections are rejected.
pub fn decode_handover_snapshot_v1(
  value : Json,
) -> HandoverProjectionV1 raise CollaborationError {
  let wire : HandoverSnapshotWireV1 = @json.from_json(value) catch {
    _ => raise SnapshotDecode("handover snapshot is not valid JSON")
  }
  if wire.contract_id != "moonflow.handover-snapshot.v1" ||
    wire.transitions.is_empty() {
    raise SnapshotDecode("unsupported or empty handover snapshot")
  }
  let bundle = @capability.decode_handover_bundle_v1(wire.bundle) catch {
    _ => raise SnapshotDecode("handover bundle failed content verification")
  }
  let envelope = @capability.decode_handover_control_envelope_v1(
    wire.envelope,
    bundle,
  ) catch {
    _ => raise SnapshotDecode("handover control envelope failed verification")
  }
  let genesis_wire = wire.transitions[0]
  if genesis_wire.from_state != "draft" ||
    genesis_wire.to_state != "draft" ||
    genesis_wire.authority is Some(_) ||
    genesis_wire.quarantine is Some(_) {
    raise SnapshotDecode("handover snapshot has an invalid genesis transition")
  }
  let genesis_actor = @capability.decode_principal_ref_v1(genesis_wire.actor) catch {
    _ => raise SnapshotDecode("handover genesis actor is invalid")
  }
  let mut projection = start_handover_v1(
    bundle,
    envelope,
    genesis_wire.transition_id,
    genesis_actor,
    genesis_wire.recorded_at,
  ) catch {
    _ => raise SnapshotDecode("handover genesis cannot be replayed")
  }
  if !transition_matches_wire_v1(projection.transitions[0], genesis_wire) {
    raise SnapshotDecode("handover genesis digest does not replay")
  }
  for index = 1; index < wire.transitions.length(); index = index + 1 {
    let item = wire.transitions[index]
    let actor = @capability.decode_principal_ref_v1(item.actor) catch {
      _ => raise SnapshotDecode("handover transition actor is invalid")
    }
    let expected_head = @capability.digest_ref_v1(item.expected_head) catch {
      _ => raise SnapshotDecode("handover expected head is invalid")
    }
    let to_state = handover_state_v1_from_id(item.to_state)
    let authority = decode_optional_authority_v1(item.authority)
    let quarantine = decode_optional_quarantine_v1(item.quarantine)
    match
      advance_handover_v1(
        projection,
        item.transition_id,
        to_state,
        actor,
        expected_head,
        item.recorded_at,
        authority?,
        quarantine?,
      ) {
      Applied(next, _) => projection = next
      Idempotent(_) =>
        raise SnapshotDecode("handover replay unexpectedly became idempotent")
      Conflict(_) =>
        raise SnapshotDecode("handover replay contains a head conflict")
      Denied(reason) =>
        raise SnapshotDecode("handover replay denied: \{reason}")
    }
    if item.from_state != projection.transitions.last().unwrap().from_state.id() ||
      !transition_matches_wire_v1(projection.transitions.last().unwrap(), item) {
      raise SnapshotDecode("handover transition digest does not replay")
    }
  }
  if projection.state.id() != wire.state ||
    projection.head_digest.text() != wire.head_digest {
    raise SnapshotDecode(
      "handover snapshot terminal projection does not match replay",
    )
  }
  projection
}
