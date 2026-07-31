///|
/// One generic, typed mutation envelope for the MoonFlow operator surface.
/// Action-specific payloads are decoded below; callers cannot submit a whole
/// replacement projection or bypass the package's policy functions.
priv struct CollaborationOperatorMutationWireV1 {
  contract_id : String
  workspace_id : String
  action : String
  mutation_id : String
  actor : Json
  expected_head : String?
  recorded_at : String
  workspace_ref : Json?
  payload : Json
} derive(FromJson)

///|
priv struct StartPayloadV1 {
  owner_membership_id : String
} derive(FromJson)

///|
priv struct AddMemberPayloadV1 {
  membership_id : String
  principal : Json
  roles : Array[String]
} derive(FromJson)

///|
priv struct AssignPayloadV1 {
  assignment_id : String
  assignee : Json
  operation : Json
  subject_digest : String
  due_at : String?
} derive(FromJson)

///|
priv struct ClaimPayloadV1 {
  assignment_id : String
  lease_id : String
  expires_at : String
} derive(FromJson)

///|
priv struct CommentPayloadV1 {
  comment_id : String
  subject_digest : String
  anchor_ref : String
  body_ref : String
  body_digest : String
  mentions : Array[Json]
} derive(FromJson)

///|
priv struct ReviewPayloadV1 {
  review_id : String
  subject_digest : String
  assigned_reviewer : Json
  requirement_id : String
} derive(FromJson)

///|
priv struct ReviewDecisionPayloadV1 {
  review_id : String
  decision : String
  evidence_ref : String
  evidence_digest : String
} derive(FromJson)

///|
priv struct AssignmentTransitionPayloadV1 {
  assignment_id : String
  to_state : String
  submitted_artifact_ref : String?
  submitted_artifact_digest : String?
  approval_review_id : String?
} derive(FromJson)

///|
pub(all) enum CollaborationOperatorMutationResultV1 {
  OperatorApplied(CollaborationProjectionV1, CollaborationMutationReceiptV1)
  OperatorIdempotent(CollaborationProjectionV1, CollaborationMutationReceiptV1)
  OperatorConflict(CollaborationConflictReceiptV1)
  OperatorDenied(String)
} derive(Debug)

///|
fn[T : FromJson] operator_decode_v1(value : Json, label : String) -> T raise CollaborationError {
  @json.from_json(value) catch {
    _ => raise SnapshotDecode("invalid \{label}")
  }
}

///|
fn operator_principal_v1(value : Json, label : String) -> @capability.PrincipalRefV1 raise CollaborationError {
  @capability.decode_principal_ref_v1(value) catch {
    _ => raise SnapshotDecode("invalid principal in \{label}")
  }
}

///|
fn operator_digest_v1(value : String, label : String) -> @capability.DigestRefV1 raise CollaborationError {
  @capability.digest_ref_v1(value) catch {
    _ => raise SnapshotDecode("invalid digest in \{label}")
  }
}

///|
fn require_operator_head_v1(
  wire : CollaborationOperatorMutationWireV1,
) -> @capability.DigestRefV1 raise CollaborationError {
  match wire.expected_head {
    Some(value) => operator_digest_v1(value, "expected_head")
    None => raise SnapshotDecode("non-start collaboration mutation requires expected_head")
  }
}

///|
fn lift_operator_result_v1(
  current : CollaborationProjectionV1,
  result : CollaborationMutationResultV1,
) -> CollaborationOperatorMutationResultV1 {
  match result {
    CollaborationApplied(next, receipt) => OperatorApplied(next, receipt)
    CollaborationIdempotent(receipt) => OperatorIdempotent(current, receipt)
    CollaborationConflict(receipt) => OperatorConflict(receipt)
    CollaborationDenied(reason) => OperatorDenied(reason)
  }
}

///|
fn apply_existing_collaboration_mutation_v1(
  projection : CollaborationProjectionV1,
  wire : CollaborationOperatorMutationWireV1,
  actor : @capability.PrincipalRefV1,
) -> CollaborationOperatorMutationResultV1 raise CollaborationError {
  if projection.workspace.workspace_id() != wire.workspace_id {
    return OperatorDenied("mutation workspace does not match durable projection")
  }
  let expected_head = require_operator_head_v1(wire)
  let result = match wire.action {
    "add-member" => {
      let payload : AddMemberPayloadV1 = operator_decode_v1(
        wire.payload,
        "add-member payload",
      )
      add_membership_v1(
        projection,
        payload.membership_id,
        operator_principal_v1(payload.principal, "member"),
        payload.roles.map(role => membership_role_v1_from_id(role)),
        actor,
        wire.mutation_id,
        expected_head,
        wire.recorded_at,
      )
    }
    "assign" => {
      let payload : AssignPayloadV1 = operator_decode_v1(
        wire.payload,
        "assignment payload",
      )
      let operation = @capability.decode_operation_ref_v1(
        payload.operation,
      ) catch {
        _ => raise SnapshotDecode("invalid assignment operation")
      }
      create_assignment_v1(
        projection,
        payload.assignment_id,
        operator_principal_v1(payload.assignee, "assignee"),
        operation,
        operator_digest_v1(payload.subject_digest, "assignment subject"),
        actor,
        wire.mutation_id,
        expected_head,
        wire.recorded_at,
        due_at?=payload.due_at,
      )
    }
    "claim" => {
      let payload : ClaimPayloadV1 = operator_decode_v1(
        wire.payload,
        "claim payload",
      )
      claim_assignment_v1(
        projection,
        payload.assignment_id,
        payload.lease_id,
        actor,
        payload.expires_at,
        wire.mutation_id,
        expected_head,
        wire.recorded_at,
      )
    }
    "comment" => {
      let payload : CommentPayloadV1 = operator_decode_v1(
        wire.payload,
        "comment payload",
      )
      add_anchored_comment_v1(
        projection,
        payload.comment_id,
        operator_digest_v1(payload.subject_digest, "comment subject"),
        payload.anchor_ref,
        (@capability.content_addressed_evidence_ref(
          payload.body_ref,
          payload.body_digest,
        ) catch {
          _ => raise SnapshotDecode("invalid comment body evidence")
        }),
        actor,
        wire.mutation_id,
        expected_head,
        wire.recorded_at,
        mentions=payload.mentions.map(value =>
          operator_principal_v1(value, "comment mention")
        ),
      )
    }
    "review" => {
      let payload : ReviewPayloadV1 = operator_decode_v1(
        wire.payload,
        "review payload",
      )
      request_review_v1(
        projection,
        payload.review_id,
        operator_digest_v1(payload.subject_digest, "review subject"),
        operator_principal_v1(payload.assigned_reviewer, "assigned reviewer"),
        payload.requirement_id,
        actor,
        wire.mutation_id,
        expected_head,
        wire.recorded_at,
      )
    }
    "review-begin" => {
      guard wire.payload is { "review_id": String(review_id), .. } else {
        raise SnapshotDecode("invalid review-begin payload")
      }
      begin_review_v1(
        projection,
        review_id,
        actor,
        wire.mutation_id,
        expected_head,
        wire.recorded_at,
      )
    }
    "decision" => {
      let payload : ReviewDecisionPayloadV1 = operator_decode_v1(
        wire.payload,
        "review decision payload",
      )
      decide_review_v1(
        projection,
        payload.review_id,
        review_state_v1_from_id(payload.decision),
        (@capability.content_addressed_evidence_ref(
          payload.evidence_ref,
          payload.evidence_digest,
        ) catch {
          _ => raise SnapshotDecode("invalid review decision evidence")
        }),
        actor,
        wire.mutation_id,
        expected_head,
        wire.recorded_at,
      )
    }
    "assignment-transition" => {
      let payload : AssignmentTransitionPayloadV1 = operator_decode_v1(
        wire.payload,
        "assignment transition payload",
      )
      let submitted = decode_optional_evidence_v1(
        payload.submitted_artifact_ref,
        payload.submitted_artifact_digest,
        "submitted artifact",
      )
      transition_assignment_v1(
        projection,
        payload.assignment_id,
        assignment_state_v1_from_id(payload.to_state),
        actor,
        wire.mutation_id,
        expected_head,
        wire.recorded_at,
        submitted_artifact?=submitted,
        approval_review_id?=payload.approval_review_id,
      )
    }
    _ => return OperatorDenied("unsupported collaboration operator action")
  }
  lift_operator_result_v1(projection, result)
}

///|
/// Decode and apply one typed operator mutation. The current projection is
/// optional only for `start`; all other actions require a validated snapshot.
pub fn apply_collaboration_operator_mutation_v1(
  current : CollaborationProjectionV1?,
  value : Json,
) -> CollaborationOperatorMutationResultV1 raise CollaborationError {
  let wire : CollaborationOperatorMutationWireV1 = operator_decode_v1(
    value,
    "moonflow.collaboration-operator-mutation.v1",
  )
  if wire.contract_id != "moonflow.collaboration-operator-mutation.v1" ||
    !@capability.identifier_component_is_canonical(wire.workspace_id) {
    raise SnapshotDecode("unsupported collaboration operator mutation")
  }
  let actor = operator_principal_v1(wire.actor, "actor")
  if wire.action == "start" {
    guard wire.workspace_ref is Some(encoded_workspace) else {
      raise SnapshotDecode("start mutation requires workspace_ref")
    }
    let workspace = @capability.decode_workspace_ref_v1(
      encoded_workspace,
    ) catch {
      _ => raise SnapshotDecode("start mutation workspace_ref is invalid")
    }
    if workspace.workspace_id() != wire.workspace_id ||
      wire.expected_head is Some(_) {
      return OperatorDenied("start mutation workspace or expected_head is invalid")
    }
    let payload : StartPayloadV1 = operator_decode_v1(
      wire.payload,
      "start payload",
    )
    let desired = start_collaboration_v1(
      workspace,
      payload.owner_membership_id,
      actor,
      wire.mutation_id,
      wire.recorded_at,
    )
    match current {
      None => {
        let event = desired.events[0]
        OperatorApplied(desired, collaboration_receipt_v1(event, false))
      }
      Some(existing) => {
        let event = desired.events[0]
        if existing.workspace == workspace &&
          existing.events.any(item => item == event) {
          OperatorIdempotent(existing, collaboration_receipt_v1(event, true))
        } else {
          OperatorDenied("collaboration already exists with a different genesis")
        }
      }
    }
  } else {
    match current {
      Some(projection) =>
        apply_existing_collaboration_mutation_v1(projection, wire, actor)
      None => OperatorDenied("collaboration must be started before this action")
    }
  }
}

///|
pub fn encode_collaboration_operator_receipt_v1(
  receipt : CollaborationMutationReceiptV1,
) -> Json {
  {
    "contract_id": "moonflow.collaboration-operator-receipt.v1",
    "mutation_id": receipt.mutation_id,
    "event_kind": receipt.event_kind,
    "head_digest": receipt.head_digest.text(),
    "payload_digest": receipt.payload_digest.text(),
    "idempotent": receipt.idempotent,
    "recorded_at": receipt.recorded_at,
  }
}

///|
pub fn encode_collaboration_conflict_v1(
  receipt : CollaborationConflictReceiptV1,
) -> Json {
  {
    "contract_id": "moonflow.collaboration-conflict.v1",
    "mutation_id": receipt.mutation_id,
    "expected_head": receipt.expected_head.text(),
    "actual_head": receipt.actual_head.text(),
    "reason": receipt.reason,
    "recorded_at": receipt.recorded_at,
  }
}
