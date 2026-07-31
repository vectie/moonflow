///|
priv struct MembershipWireV1 {
  membership_id : String
  principal : Json
  roles : Array[String]
  status : String
  added_by : Json
  updated_at : String
} derive(ToJson, FromJson)

///|
priv struct AssignmentWireV1 {
  assignment_id : String
  assignee : Json
  operation : Json
  subject_digest : String
  state : String
  due_at : String?
  submitted_artifact_ref : String?
  submitted_artifact_digest : String?
  approval_review_id : String?
  updated_at : String
} derive(ToJson, FromJson)

///|
priv struct AssignmentClaimWireV1 {
  lease_id : String
  assignment_id : String
  holder : Json
  acquired_at : String
  expires_at : String
  previous_lease_id : String?
  reclaimed_expired : Bool
  mutation_id : String
} derive(ToJson, FromJson)

///|
priv struct AnchoredCommentWireV1 {
  comment_id : String
  author : Json
  subject_digest : String
  anchor_ref : String
  body_ref : String
  body_digest : String
  mentions : Array[Json]
  created_at : String
} derive(ToJson, FromJson)

///|
priv struct ReviewInboxItemWireV1 {
  review_id : String
  subject_digest : String
  submitted_by : Json
  assigned_reviewer : Json
  requirement_id : String
  state : String
  decision_evidence_ref : String?
  decision_evidence_digest : String?
  updated_at : String
} derive(ToJson, FromJson)

///|
priv struct CollaborationMutationEventWireV1 {
  mutation_id : String
  event_kind : String
  actor : Json
  expected_head : String
  payload_digest : String
  resulting_head : String
  recorded_at : String
} derive(ToJson, FromJson)

///|
priv struct CollaborationSnapshotPayloadWireV1 {
  workspace_ref : Json
  memberships : Array[MembershipWireV1]
  assignments : Array[AssignmentWireV1]
  claims : Array[AssignmentClaimWireV1]
  comments : Array[AnchoredCommentWireV1]
  reviews : Array[ReviewInboxItemWireV1]
  events : Array[CollaborationMutationEventWireV1]
  head_digest : String
} derive(ToJson, FromJson)

///|
priv struct CollaborationSnapshotWireV1 {
  contract_id : String
  payload : Json
  content_digest : String
} derive(ToJson, FromJson)

///|
fn membership_wire_v1(value : MembershipV1) -> MembershipWireV1 {
  {
    membership_id: value.membership_id,
    principal: @capability.encode_principal_ref_v1(value.principal),
    roles: value.roles.map(role => role.id()).iter().to_array(),
    status: value.status.id(),
    added_by: @capability.encode_principal_ref_v1(value.added_by),
    updated_at: value.updated_at,
  }
}

///|
fn assignment_wire_v1(value : AssignmentV1) -> AssignmentWireV1 {
  {
    assignment_id: value.assignment_id,
    assignee: @capability.encode_principal_ref_v1(value.assignee),
    operation: @capability.encode_operation_ref_v1(value.operation),
    subject_digest: value.subject_digest.text(),
    state: value.state.id(),
    due_at: value.due_at,
    submitted_artifact_ref: value.submitted_artifact.map(item =>
      item.evidence_ref()
    ),
    submitted_artifact_digest: value.submitted_artifact.map(item =>
      item.evidence_digest()
    ),
    approval_review_id: value.approval_review_id,
    updated_at: value.updated_at,
  }
}

///|
fn assignment_claim_wire_v1(value : AssignmentClaimV1) -> AssignmentClaimWireV1 {
  {
    lease_id: value.lease_id,
    assignment_id: value.assignment_id,
    holder: @capability.encode_principal_ref_v1(value.holder),
    acquired_at: value.acquired_at,
    expires_at: value.expires_at,
    previous_lease_id: value.previous_lease_id,
    reclaimed_expired: value.reclaimed_expired,
    mutation_id: value.mutation_id,
  }
}

///|
fn anchored_comment_wire_v1(value : AnchoredCommentV1) -> AnchoredCommentWireV1 {
  {
    comment_id: value.comment_id,
    author: @capability.encode_principal_ref_v1(value.author),
    subject_digest: value.subject_digest.text(),
    anchor_ref: value.anchor_ref,
    body_ref: value.body.evidence_ref(),
    body_digest: value.body.evidence_digest(),
    mentions: value.mentions.map(mentioned =>
      @capability.encode_principal_ref_v1(mentioned)
    ).iter().to_array(),
    created_at: value.created_at,
  }
}

///|
fn review_inbox_item_wire_v1(value : ReviewInboxItemV1) -> ReviewInboxItemWireV1 {
  {
    review_id: value.review_id,
    subject_digest: value.subject_digest.text(),
    submitted_by: @capability.encode_principal_ref_v1(value.submitted_by),
    assigned_reviewer: @capability.encode_principal_ref_v1(
      value.assigned_reviewer,
    ),
    requirement_id: value.requirement_id,
    state: value.state.id(),
    decision_evidence_ref: value.decision_evidence.map(item =>
      item.evidence_ref()
    ),
    decision_evidence_digest: value.decision_evidence.map(item =>
      item.evidence_digest()
    ),
    updated_at: value.updated_at,
  }
}

///|
fn collaboration_event_wire_v1(
  value : CollaborationMutationEventV1,
) -> CollaborationMutationEventWireV1 {
  {
    mutation_id: value.mutation_id,
    event_kind: value.event_kind,
    actor: @capability.encode_principal_ref_v1(value.actor),
    expected_head: value.expected_head.text(),
    payload_digest: value.payload_digest.text(),
    resulting_head: value.resulting_head.text(),
    recorded_at: value.recorded_at,
  }
}

///|
fn collaboration_snapshot_payload_v1(
  projection : CollaborationProjectionV1,
) -> CollaborationSnapshotPayloadWireV1 {
  {
    workspace_ref: @capability.encode_workspace_ref_v1(projection.workspace),
    memberships: projection.memberships.map(value =>
      membership_wire_v1(value)
    ).iter().to_array(),
    assignments: projection.assignments.map(value =>
      assignment_wire_v1(value)
    ).iter().to_array(),
    claims: projection.claims.map(value =>
      assignment_claim_wire_v1(value)
    ).iter().to_array(),
    comments: projection.comments.map(value =>
      anchored_comment_wire_v1(value)
    ).iter().to_array(),
    reviews: projection.reviews.map(value =>
      review_inbox_item_wire_v1(value)
    ).iter().to_array(),
    events: projection.events.map(value =>
      collaboration_event_wire_v1(value)
    ).iter().to_array(),
    head_digest: projection.head_digest.text(),
  }
}

///|
pub fn encode_collaboration_snapshot_v1(
  projection : CollaborationProjectionV1,
) -> Json {
  let payload = collaboration_snapshot_payload_v1(projection).to_json()
  CollaborationSnapshotWireV1::{
    contract_id: "moonflow.collaboration-snapshot.v1",
    payload,
    content_digest: collaboration_digest_v1(payload.stringify()).text(),
  }.to_json()
}

///|
fn decode_snapshot_principal_v1(
  value : Json,
  field : String,
) -> @capability.PrincipalRefV1 raise CollaborationError {
  @capability.decode_principal_ref_v1(value) catch {
    _ => raise SnapshotDecode("invalid principal in \{field}")
  }
}

///|
fn decode_snapshot_digest_v1(
  value : String,
  field : String,
) -> @capability.DigestRefV1 raise CollaborationError {
  @capability.digest_ref_v1(value) catch {
    _ => raise SnapshotDecode("invalid digest in \{field}")
  }
}

///|
fn decode_optional_evidence_v1(
  reference : String?,
  digest : String?,
  field : String,
) -> @capability.ContentAddressedEvidenceRefV1? raise CollaborationError {
  if (reference is Some(_)) != (digest is Some(_)) {
    raise SnapshotDecode("\{field} reference and digest must appear together")
  }
  match (reference, digest) {
    (Some(ref_value), Some(digest_value)) =>
      Some(@capability.content_addressed_evidence_ref(
        ref_value,
        digest_value,
      ) catch {
        _ => raise SnapshotDecode("invalid content-addressed evidence in \{field}")
      })
    _ => None
  }
}

///|
fn decode_membership_wire_v1(
  wire : MembershipWireV1,
) -> MembershipV1 raise CollaborationError {
  let roles = wire.roles.map(value => membership_role_v1_from_id(value))
  let principal = decode_snapshot_principal_v1(wire.principal, "membership")
  if !@capability.identifier_component_is_canonical(wire.membership_id) ||
    !roles_are_canonical_v1(roles) ||
    !@capability.wire_timestamp_is_canonical(wire.updated_at) ||
    (roles.contains(Reviewer) &&
    principal.kind() != @capability.PrincipalKindV1::Human) {
    raise SnapshotDecode("invalid membership snapshot record")
  }
  {
    membership_id: wire.membership_id,
    principal,
    roles: ReadOnlyArray::from_array(roles),
    status: membership_status_v1_from_id(wire.status),
    added_by: decode_snapshot_principal_v1(wire.added_by, "membership.added_by"),
    updated_at: wire.updated_at,
  }
}

///|
fn decode_assignment_wire_v1(
  wire : AssignmentWireV1,
) -> AssignmentV1 raise CollaborationError {
  let state = assignment_state_v1_from_id(wire.state)
  let submitted_artifact = decode_optional_evidence_v1(
    wire.submitted_artifact_ref,
    wire.submitted_artifact_digest,
    "assignment.submitted_artifact",
  )
  if !@capability.identifier_component_is_canonical(wire.assignment_id) ||
    !@capability.wire_timestamp_is_canonical(wire.updated_at) ||
    (wire.due_at is Some(value) &&
    !@capability.wire_timestamp_is_canonical(value)) ||
    ((state == Submitted || state == Completed) && submitted_artifact is None) ||
    (state == Completed && wire.approval_review_id is None) ||
    (state != Completed && wire.approval_review_id is Some(_)) {
    raise SnapshotDecode("invalid assignment snapshot record")
  }
  {
    assignment_id: wire.assignment_id,
    assignee: decode_snapshot_principal_v1(wire.assignee, "assignment.assignee"),
    operation: @capability.decode_operation_ref_v1(wire.operation) catch {
      _ => raise SnapshotDecode("invalid assignment operation")
    },
    subject_digest: decode_snapshot_digest_v1(
      wire.subject_digest,
      "assignment.subject",
    ),
    state,
    due_at: wire.due_at,
    submitted_artifact,
    approval_review_id: wire.approval_review_id,
    updated_at: wire.updated_at,
  }
}

///|
fn decode_assignment_claim_wire_v1(
  wire : AssignmentClaimWireV1,
) -> AssignmentClaimV1 raise CollaborationError {
  if !@capability.identifier_component_is_canonical(wire.lease_id) ||
    !@capability.identifier_component_is_canonical(wire.assignment_id) ||
    !@capability.identifier_component_is_canonical(wire.mutation_id) ||
    !@capability.wire_timestamp_is_canonical(wire.acquired_at) ||
    !@capability.wire_timestamp_is_canonical(wire.expires_at) ||
    wire.acquired_at >= wire.expires_at ||
    wire.reclaimed_expired != (wire.previous_lease_id is Some(_)) {
    raise SnapshotDecode("invalid assignment claim snapshot record")
  }
  {
    lease_id: wire.lease_id,
    assignment_id: wire.assignment_id,
    holder: decode_snapshot_principal_v1(wire.holder, "claim.holder"),
    acquired_at: wire.acquired_at,
    expires_at: wire.expires_at,
    previous_lease_id: wire.previous_lease_id,
    reclaimed_expired: wire.reclaimed_expired,
    mutation_id: wire.mutation_id,
  }
}

///|
fn decode_comment_wire_v1(
  wire : AnchoredCommentWireV1,
) -> AnchoredCommentV1 raise CollaborationError {
  if !@capability.identifier_component_is_canonical(wire.comment_id) ||
    !@capability.evidence_artifact_ref_is_canonical(wire.anchor_ref) ||
    !@capability.wire_timestamp_is_canonical(wire.created_at) {
    raise SnapshotDecode("invalid anchored comment snapshot record")
  }
  {
    comment_id: wire.comment_id,
    author: decode_snapshot_principal_v1(wire.author, "comment.author"),
    subject_digest: decode_snapshot_digest_v1(
      wire.subject_digest,
      "comment.subject",
    ),
    anchor_ref: wire.anchor_ref,
    body: @capability.content_addressed_evidence_ref(
      wire.body_ref,
      wire.body_digest,
    ) catch {
      _ => raise SnapshotDecode("invalid anchored comment body")
    },
    mentions: ReadOnlyArray::from_array(wire.mentions.map(value =>
      decode_snapshot_principal_v1(value, "comment.mention")
    )),
    created_at: wire.created_at,
  }
}

///|
fn decode_review_wire_v1(
  wire : ReviewInboxItemWireV1,
) -> ReviewInboxItemV1 raise CollaborationError {
  let state = review_state_v1_from_id(wire.state)
  let decision_evidence = decode_optional_evidence_v1(
    wire.decision_evidence_ref,
    wire.decision_evidence_digest,
    "review.decision_evidence",
  )
  let submitted_by = decode_snapshot_principal_v1(
    wire.submitted_by,
    "review.submitter",
  )
  let assigned_reviewer = decode_snapshot_principal_v1(
    wire.assigned_reviewer,
    "review.reviewer",
  )
  if !@capability.identifier_component_is_canonical(wire.review_id) ||
    !@capability.identifier_component_is_canonical(wire.requirement_id) ||
    !@capability.wire_timestamp_is_canonical(wire.updated_at) ||
    submitted_by == assigned_reviewer ||
    assigned_reviewer.kind() != @capability.PrincipalKindV1::Human ||
    ((state == Approved || state == ChangesRequested) && decision_evidence is None) ||
    ((state == Requested || state == InReview || state == Withdrawn) &&
    decision_evidence is Some(_)) {
    raise SnapshotDecode("invalid review inbox snapshot record")
  }
  {
    review_id: wire.review_id,
    subject_digest: decode_snapshot_digest_v1(
      wire.subject_digest,
      "review.subject",
    ),
    submitted_by,
    assigned_reviewer,
    requirement_id: wire.requirement_id,
    state,
    decision_evidence,
    updated_at: wire.updated_at,
  }
}

///|
fn decode_collaboration_event_wire_v1(
  wire : CollaborationMutationEventWireV1,
) -> CollaborationMutationEventV1 raise CollaborationError {
  if !@capability.identifier_component_is_canonical(wire.mutation_id) ||
    !@capability.identifier_component_is_canonical(wire.event_kind) ||
    !@capability.wire_timestamp_is_canonical(wire.recorded_at) {
    raise SnapshotDecode("invalid collaboration mutation event")
  }
  {
    mutation_id: wire.mutation_id,
    event_kind: wire.event_kind,
    actor: decode_snapshot_principal_v1(wire.actor, "event.actor"),
    expected_head: decode_snapshot_digest_v1(wire.expected_head, "event.expected_head"),
    payload_digest: decode_snapshot_digest_v1(
      wire.payload_digest,
      "event.payload_digest",
    ),
    resulting_head: decode_snapshot_digest_v1(
      wire.resulting_head,
      "event.resulting_head",
    ),
    recorded_at: wire.recorded_at,
  }
}

///|
fn require_unique_collaboration_ids_v1(
  memberships : Array[MembershipV1],
  assignments : Array[AssignmentV1],
  claims : Array[AssignmentClaimV1],
  comments : Array[AnchoredCommentV1],
  reviews : Array[ReviewInboxItemV1],
) -> Unit raise CollaborationError {
  let membership_ids : Array[String] = []
  let principals : Array[String] = []
  for value in memberships {
    if membership_ids.contains(value.membership_id) ||
      principals.contains(value.principal.canonical_text()) {
      raise SnapshotDecode("duplicate membership identity")
    }
    membership_ids.push(value.membership_id)
    principals.push(value.principal.canonical_text())
  }
  let assignment_ids : Array[String] = []
  for value in assignments {
    if assignment_ids.contains(value.assignment_id) {
      raise SnapshotDecode("duplicate assignment identity")
    }
    assignment_ids.push(value.assignment_id)
  }
  let lease_ids : Array[String] = []
  for value in claims {
    if lease_ids.contains(value.lease_id) {
      raise SnapshotDecode("duplicate assignment lease identity")
    }
    lease_ids.push(value.lease_id)
  }
  let comment_ids : Array[String] = []
  for value in comments {
    if comment_ids.contains(value.comment_id) {
      raise SnapshotDecode("duplicate comment identity")
    }
    comment_ids.push(value.comment_id)
  }
  let review_ids : Array[String] = []
  for value in reviews {
    if review_ids.contains(value.review_id) {
      raise SnapshotDecode("duplicate review identity")
    }
    review_ids.push(value.review_id)
  }
}

///|
/// Restores a collaboration projection after verifying its content digest,
/// event head chain, identities, active owner, and separation-of-duty records.
pub fn decode_collaboration_snapshot_v1(
  value : Json,
) -> CollaborationProjectionV1 raise CollaborationError {
  let wire : CollaborationSnapshotWireV1 = @json.from_json(value) catch {
    _ => raise SnapshotDecode("collaboration snapshot is not valid JSON")
  }
  if wire.contract_id != "moonflow.collaboration-snapshot.v1" ||
    collaboration_digest_v1(wire.payload.stringify()).text() != wire.content_digest {
    raise SnapshotDecode("collaboration snapshot content digest mismatch")
  }
  let payload : CollaborationSnapshotPayloadWireV1 = @json.from_json(
    wire.payload,
  ) catch {
    _ => raise SnapshotDecode("collaboration snapshot payload is invalid")
  }
  let workspace = @capability.decode_workspace_ref_v1(payload.workspace_ref) catch {
    _ => raise SnapshotDecode("collaboration workspace reference is invalid")
  }
  let memberships = payload.memberships.map(value =>
    decode_membership_wire_v1(value)
  )
  let assignments = payload.assignments.map(value =>
    decode_assignment_wire_v1(value)
  )
  let claims = payload.claims.map(value => decode_assignment_claim_wire_v1(value))
  let comments = payload.comments.map(value => decode_comment_wire_v1(value))
  let reviews = payload.reviews.map(value => decode_review_wire_v1(value))
  let events = payload.events.map(value =>
    decode_collaboration_event_wire_v1(value)
  )
  require_unique_collaboration_ids_v1(
    memberships,
    assignments,
    claims,
    comments,
    reviews,
  )
  if !memberships.any(value => membership_has_role_v1(value, Owner)) ||
    events.is_empty() {
    raise SnapshotDecode("collaboration snapshot requires an active owner and event log")
  }
  for assignment in assignments {
    if !memberships.any(value =>
      value.principal == assignment.assignee && value.status == Active
    ) {
      raise SnapshotDecode("assignment refers to an inactive or missing assignee")
    }
    if assignment.approval_review_id is Some(review_id) &&
      !reviews.any(review =>
        review.review_id == review_id &&
        review.state == Approved &&
        assignment.submitted_artifact is Some(accepted_artifact) &&
        review.subject_digest.text() == accepted_artifact.evidence_digest() &&
        review.assigned_reviewer != assignment.assignee
      ) {
      raise SnapshotDecode("completed assignment lacks an independent approval")
    }
  }
  for index, claim in claims {
    if !assignments.any(value =>
      value.assignment_id == claim.assignment_id && value.assignee == claim.holder
    ) ||
      !memberships.any(value =>
        value.principal == claim.holder && value.status == Active
      ) ||
      (claim.previous_lease_id is Some(previous_id) &&
      (index == 0 || !claims[:index].any(value =>
        value.lease_id == previous_id && value.expires_at <= claim.acquired_at
      ))) {
      raise SnapshotDecode("assignment claim history is invalid")
    }
  }
  for comment in comments {
    let mention_ids : Array[String] = []
    for mentioned in comment.mentions {
      let identity = mentioned.canonical_text()
      if mention_ids.contains(identity) ||
        !memberships.any(value =>
          value.principal == mentioned && value.status == Active
        ) {
        raise SnapshotDecode("comment mention is not a unique active member")
      }
      mention_ids.push(identity)
    }
  }
  for review in reviews {
    if !memberships.any(value =>
      value.principal == review.assigned_reviewer &&
      membership_has_role_v1(value, Reviewer)
    ) {
      raise SnapshotDecode("review refers to an inactive or missing reviewer")
    }
  }
  let mut expected = collaboration_digest_v1(
    "\{workspace.canonical_text()}|collaboration-genesis",
  )
  let mutation_ids : Array[String] = []
  for index, event in events {
    if mutation_ids.contains(event.mutation_id) ||
      event.expected_head != expected ||
      event.resulting_head != collaboration_resulting_head_v1(
        expected,
        event.payload_digest,
      ) ||
      (index == 0 && event.event_kind != "collaboration-started") {
      raise SnapshotDecode("collaboration event chain does not replay")
    }
    mutation_ids.push(event.mutation_id)
    expected = event.resulting_head
  }
  if expected.text() != payload.head_digest {
    raise SnapshotDecode("collaboration terminal head does not match event replay")
  }
  {
    workspace,
    memberships: ReadOnlyArray::from_array(memberships),
    assignments: ReadOnlyArray::from_array(assignments),
    claims: ReadOnlyArray::from_array(claims),
    comments: ReadOnlyArray::from_array(comments),
    reviews: ReadOnlyArray::from_array(reviews),
    events: ReadOnlyArray::from_array(events),
    head_digest: expected,
  }
}
