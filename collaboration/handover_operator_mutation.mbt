///|
priv struct HandoverOperatorMutationWireV1 {
  contract_id : String
  handover_id : String
  action : String
  transition_id : String
  actor : Json
  expected_head : String?
  target_state : String?
  authority : Json?
  quarantine : Json?
  bundle : Json?
  envelope : Json?
  recorded_at : String
} derive(FromJson)

///|
pub(all) enum HandoverOperatorMutationResultV1 {
  HandoverOperatorApplied(HandoverProjectionV1, HandoverTransitionReceiptV1)
  HandoverOperatorIdempotent(HandoverProjectionV1, HandoverTransitionReceiptV1)
  HandoverOperatorConflict(HandoverConflictReceiptV1)
  HandoverOperatorDenied(String)
} derive(Debug)

///|
pub fn apply_handover_operator_mutation_v1(
  current : HandoverProjectionV1?,
  value : Json,
) -> HandoverOperatorMutationResultV1 raise CollaborationError {
  let wire : HandoverOperatorMutationWireV1 = @json.from_json(value) catch {
    _ => raise SnapshotDecode("invalid handover operator mutation")
  }
  if wire.contract_id != "moonflow.handover-operator-mutation.v1" ||
    !@capability.identifier_component_is_canonical(wire.handover_id) {
    raise SnapshotDecode("unsupported handover operator mutation")
  }
  let actor = @capability.decode_principal_ref_v1(wire.actor) catch {
    _ => raise SnapshotDecode("handover mutation actor is invalid")
  }
  if wire.action == "start" {
    guard wire.bundle is Some(bundle_json) &&
      wire.envelope is Some(envelope_json) &&
      wire.expected_head is None &&
      wire.target_state is None else {
      raise SnapshotDecode("start handover mutation is incomplete")
    }
    let bundle = @capability.decode_handover_bundle_v1(bundle_json) catch {
      _ => raise SnapshotDecode("handover start bundle is invalid")
    }
    let envelope = @capability.decode_handover_control_envelope_v1(
      envelope_json, bundle,
    ) catch {
      _ => raise SnapshotDecode("handover start envelope is invalid")
    }
    if envelope.handover_id() != wire.handover_id {
      return HandoverOperatorDenied(
        "mutation handover id does not match envelope",
      )
    }
    let desired = start_handover_v1(
      bundle,
      envelope,
      wire.transition_id,
      actor,
      wire.recorded_at,
    )
    let event = desired.transitions[0]
    let receipt : HandoverTransitionReceiptV1 = {
      transition_id: event.transition_id,
      handover_id: wire.handover_id,
      state: event.to_state,
      head_digest: event.resulting_head,
      payload_digest: event.payload_digest,
      idempotent: false,
      recorded_at: event.recorded_at,
    }
    match current {
      None => HandoverOperatorApplied(desired, receipt)
      Some(existing) =>
        if existing.transitions.any(item => item == event) {
          HandoverOperatorIdempotent(existing, HandoverTransitionReceiptV1::{
            ..receipt,
            idempotent: true,
          })
        } else {
          HandoverOperatorDenied(
            "handover already exists with a different genesis",
          )
        }
    }
  } else if wire.action == "transition" {
    guard current is Some(projection) &&
      wire.expected_head is Some(head_text) &&
      wire.target_state is Some(state_text) else {
      raise SnapshotDecode(
        "handover transition requires current state, head, and target",
      )
    }
    if projection.envelope.handover_id() != wire.handover_id {
      return HandoverOperatorDenied(
        "mutation handover id does not match snapshot",
      )
    }
    let expected_head = @capability.digest_ref_v1(head_text) catch {
      _ => raise SnapshotDecode("handover expected head is invalid")
    }
    let authority = decode_optional_authority_v1(wire.authority)
    let quarantine = decode_optional_quarantine_v1(wire.quarantine)
    match
      advance_handover_v1(
        projection,
        wire.transition_id,
        handover_state_v1_from_id(state_text),
        actor,
        expected_head,
        wire.recorded_at,
        authority?,
        quarantine?,
      ) {
      Applied(next, receipt) => HandoverOperatorApplied(next, receipt)
      Idempotent(receipt) => HandoverOperatorIdempotent(projection, receipt)
      Conflict(receipt) => HandoverOperatorConflict(receipt)
      Denied(reason) => HandoverOperatorDenied(reason)
    }
  } else {
    HandoverOperatorDenied("unsupported handover operator action")
  }
}

///|
pub fn encode_handover_operator_receipt_v1(
  receipt : HandoverTransitionReceiptV1,
) -> Json {
  {
    "contract_id": "moonflow.handover-operator-receipt.v1",
    "transition_id": receipt.transition_id,
    "handover_id": receipt.handover_id,
    "state": receipt.state.id(),
    "head_digest": receipt.head_digest.text(),
    "payload_digest": receipt.payload_digest.text(),
    "idempotent": receipt.idempotent,
    "recorded_at": receipt.recorded_at,
  }
}

///|
pub fn encode_handover_conflict_v1(receipt : HandoverConflictReceiptV1) -> Json {
  {
    "contract_id": "moonflow.handover-conflict.v1",
    "transition_id": receipt.transition_id,
    "handover_id": receipt.handover_id,
    "expected_head": receipt.expected_head.text(),
    "actual_head": receipt.actual_head.text(),
    "reason": receipt.reason,
    "recorded_at": receipt.recorded_at,
  }
}
