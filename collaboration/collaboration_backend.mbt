///|
priv enum CollaborationMutationGuardV1 {
  MutationProceed(@capability.DigestRefV1)
  MutationReplay(CollaborationMutationReceiptV1)
  MutationHeadConflict(CollaborationConflictReceiptV1)
  MutationInvalid(String)
}

///|
fn collaboration_digest_v1(value : String) -> @capability.DigestRefV1 {
  @capability.sha256_digest_ref_v1(@utf8.encode(value))
}

///|
fn collaboration_payload_digest_v1(
  mutation_id : String,
  event_kind : String,
  actor : @capability.PrincipalRefV1,
  expected_head : @capability.DigestRefV1,
  detail : String,
  recorded_at : String,
) -> @capability.DigestRefV1 {
  collaboration_digest_v1(
    "\{mutation_id}|\{event_kind}|\{actor.canonical_text()}|\{expected_head.text()}|\{detail}|\{recorded_at}",
  )
}

///|
fn collaboration_resulting_head_v1(
  expected_head : @capability.DigestRefV1,
  payload_digest : @capability.DigestRefV1,
) -> @capability.DigestRefV1 {
  collaboration_digest_v1("\{expected_head.text()}|\{payload_digest.text()}")
}

///|
fn collaboration_receipt_v1(
  event : CollaborationMutationEventV1,
  idempotent : Bool,
) -> CollaborationMutationReceiptV1 {
  {
    mutation_id: event.mutation_id,
    event_kind: event.event_kind,
    head_digest: event.resulting_head,
    payload_digest: event.payload_digest,
    idempotent,
    recorded_at: event.recorded_at,
  }
}

///|
fn collaboration_event_v1(
  mutation_id : String,
  event_kind : String,
  actor : @capability.PrincipalRefV1,
  expected_head : @capability.DigestRefV1,
  payload_digest : @capability.DigestRefV1,
  recorded_at : String,
) -> CollaborationMutationEventV1 {
  {
    mutation_id,
    event_kind,
    actor,
    expected_head,
    payload_digest,
    resulting_head: collaboration_resulting_head_v1(
      expected_head, payload_digest,
    ),
    recorded_at,
  }
}

///|
fn guard_collaboration_mutation_v1(
  projection : CollaborationProjectionV1,
  mutation_id : String,
  event_kind : String,
  actor : @capability.PrincipalRefV1,
  expected_head : @capability.DigestRefV1,
  detail : String,
  recorded_at : String,
) -> CollaborationMutationGuardV1 {
  if !@capability.identifier_component_is_canonical(mutation_id) ||
    !@capability.identifier_component_is_canonical(event_kind) ||
    !@capability.wire_timestamp_is_canonical(recorded_at) {
    return MutationInvalid(
      "mutation identity, kind, and timestamp must be canonical",
    )
  }
  let payload_digest = collaboration_payload_digest_v1(
    mutation_id, event_kind, actor, expected_head, detail, recorded_at,
  )
  for existing in projection.events {
    if existing.mutation_id == mutation_id {
      if existing.payload_digest == payload_digest {
        return MutationReplay(collaboration_receipt_v1(existing, true))
      }
      return MutationHeadConflict({
        mutation_id,
        expected_head,
        actual_head: projection.head_digest,
        reason: "mutation identity was reused with different content",
        recorded_at,
      })
    }
  }
  if projection.events.last() is Some(last_event) &&
    recorded_at < last_event.recorded_at {
    return MutationInvalid(
      "collaboration mutation cannot backdate the durable timeline",
    )
  }
  if expected_head != projection.head_digest {
    return MutationHeadConflict({
      mutation_id,
      expected_head,
      actual_head: projection.head_digest,
      reason: "expected head does not match current collaboration head",
      recorded_at,
    })
  }
  MutationProceed(payload_digest)
}

///|
fn roles_are_canonical_v1(roles : Array[MembershipRoleV1]) -> Bool {
  if roles.is_empty() {
    return false
  }
  let ids : Array[String] = []
  for role in roles {
    let id = role.id()
    if ids.contains(id) {
      return false
    }
    ids.push(id)
  }
  true
}

///|
fn find_membership_v1(
  projection : CollaborationProjectionV1,
  principal : @capability.PrincipalRefV1,
) -> MembershipV1? {
  for membership in projection.memberships {
    if membership.principal == principal {
      return Some(membership)
    }
  }
  None
}

///|
fn membership_has_role_v1(
  membership : MembershipV1,
  role : MembershipRoleV1,
) -> Bool {
  membership.status == Active && membership.roles.contains(role)
}

///|
fn actor_has_role_v1(
  projection : CollaborationProjectionV1,
  actor : @capability.PrincipalRefV1,
  role : MembershipRoleV1,
) -> Bool {
  match find_membership_v1(projection, actor) {
    Some(membership) => membership_has_role_v1(membership, role)
    None => false
  }
}

///|
fn actor_is_active_v1(
  projection : CollaborationProjectionV1,
  actor : @capability.PrincipalRefV1,
) -> Bool {
  match find_membership_v1(projection, actor) {
    Some(membership) => membership.status == Active
    None => false
  }
}

///|
fn actor_can_contribute_v1(
  projection : CollaborationProjectionV1,
  actor : @capability.PrincipalRefV1,
) -> Bool {
  actor_has_role_v1(projection, actor, Owner) ||
  actor_has_role_v1(projection, actor, Contributor)
}

///|
fn append_collaboration_event_v1(
  projection : CollaborationProjectionV1,
  event : CollaborationMutationEventV1,
  memberships : Array[MembershipV1],
  assignments : Array[AssignmentV1],
  comments : Array[AnchoredCommentV1],
  reviews : Array[ReviewInboxItemV1],
) -> CollaborationProjectionV1 {
  let events = projection.events.iter().to_array()
  events.push(event)
  {
    workspace: projection.workspace,
    memberships: ReadOnlyArray::from_array(memberships),
    assignments: ReadOnlyArray::from_array(assignments),
    claims: projection.claims,
    comments: ReadOnlyArray::from_array(comments),
    reviews: ReadOnlyArray::from_array(reviews),
    events: ReadOnlyArray::from_array(events),
    head_digest: event.resulting_head,
  }
}

///|
fn unchanged_memberships_v1(
  projection : CollaborationProjectionV1,
) -> Array[MembershipV1] {
  projection.memberships.iter().to_array()
}

///|
fn unchanged_assignments_v1(
  projection : CollaborationProjectionV1,
) -> Array[AssignmentV1] {
  projection.assignments.iter().to_array()
}

///|
fn unchanged_comments_v1(
  projection : CollaborationProjectionV1,
) -> Array[AnchoredCommentV1] {
  projection.comments.iter().to_array()
}

///|
fn unchanged_reviews_v1(
  projection : CollaborationProjectionV1,
) -> Array[ReviewInboxItemV1] {
  projection.reviews.iter().to_array()
}

///|
pub fn start_collaboration_v1(
  workspace : @capability.WorkspaceRefV1,
  owner_membership_id : String,
  owner : @capability.PrincipalRefV1,
  mutation_id : String,
  recorded_at : String,
) -> CollaborationProjectionV1 raise CollaborationError {
  if !@capability.identifier_component_is_canonical(owner_membership_id) ||
    !@capability.identifier_component_is_canonical(mutation_id) ||
    owner.kind() != @capability.PrincipalKindV1::Human ||
    !@capability.wire_timestamp_is_canonical(recorded_at) {
    raise InvalidCollaboration(
      "collaboration genesis requires a named human owner",
    )
  }
  let empty_head = collaboration_digest_v1(
    "\{workspace.canonical_text()}|collaboration-genesis",
  )
  let detail = "\{owner_membership_id}|\{owner.canonical_text()}|owner"
  let payload_digest = collaboration_payload_digest_v1(
    mutation_id, "collaboration-started", owner, empty_head, detail, recorded_at,
  )
  let event = collaboration_event_v1(
    mutation_id, "collaboration-started", owner, empty_head, payload_digest, recorded_at,
  )
  {
    workspace,
    memberships: ReadOnlyArray::from_array([
      {
        membership_id: owner_membership_id,
        principal: owner,
        roles: ReadOnlyArray::from_array([Owner]),
        status: Active,
        added_by: owner,
        updated_at: recorded_at,
      },
    ]),
    assignments: ReadOnlyArray::from_array([]),
    claims: ReadOnlyArray::from_array([]),
    comments: ReadOnlyArray::from_array([]),
    reviews: ReadOnlyArray::from_array([]),
    events: ReadOnlyArray::from_array([event]),
    head_digest: event.resulting_head,
  }
}

///|
pub fn add_membership_v1(
  projection : CollaborationProjectionV1,
  membership_id : String,
  principal : @capability.PrincipalRefV1,
  roles : Array[MembershipRoleV1],
  actor : @capability.PrincipalRefV1,
  mutation_id : String,
  expected_head : @capability.DigestRefV1,
  recorded_at : String,
) -> CollaborationMutationResultV1 {
  let role_ids = roles.map(role => role.id()).join(",")
  let detail = "\{membership_id}|\{principal.canonical_text()}|\{role_ids}"
  match
    guard_collaboration_mutation_v1(
      projection, mutation_id, "membership-added", actor, expected_head, detail,
      recorded_at,
    ) {
    MutationReplay(receipt) => return CollaborationIdempotent(receipt)
    MutationHeadConflict(receipt) => return CollaborationConflict(receipt)
    MutationInvalid(reason) => return CollaborationDenied(reason)
    MutationProceed(payload_digest) => {
      if !actor_has_role_v1(projection, actor, Owner) {
        return CollaborationDenied("only an active owner may add a member")
      }
      if !@capability.identifier_component_is_canonical(membership_id) ||
        !roles_are_canonical_v1(roles) {
        return CollaborationDenied("membership id and roles must be canonical")
      }
      if roles.contains(Reviewer) &&
        principal.kind() != @capability.PrincipalKindV1::Human {
        return CollaborationDenied(
          "reviewer membership is restricted to humans",
        )
      }
      if find_membership_v1(projection, principal) is Some(_) ||
        projection.memberships.any(value => value.membership_id == membership_id) {
        return CollaborationDenied("membership or principal already exists")
      }
      let memberships = unchanged_memberships_v1(projection)
      memberships.push({
        membership_id,
        principal,
        roles: ReadOnlyArray::from_array(roles),
        status: Active,
        added_by: actor,
        updated_at: recorded_at,
      })
      let event = collaboration_event_v1(
        mutation_id, "membership-added", actor, expected_head, payload_digest, recorded_at,
      )
      let updated = append_collaboration_event_v1(
        projection,
        event,
        memberships,
        unchanged_assignments_v1(projection),
        unchanged_comments_v1(projection),
        unchanged_reviews_v1(projection),
      )
      CollaborationApplied(updated, collaboration_receipt_v1(event, false))
    }
  }
}

///|
pub fn set_membership_status_v1(
  projection : CollaborationProjectionV1,
  principal : @capability.PrincipalRefV1,
  status : MembershipStatusV1,
  actor : @capability.PrincipalRefV1,
  mutation_id : String,
  expected_head : @capability.DigestRefV1,
  recorded_at : String,
) -> CollaborationMutationResultV1 {
  let detail = "\{principal.canonical_text()}|\{status.id()}"
  match
    guard_collaboration_mutation_v1(
      projection, mutation_id, "membership-status-set", actor, expected_head, detail,
      recorded_at,
    ) {
    MutationReplay(receipt) => return CollaborationIdempotent(receipt)
    MutationHeadConflict(receipt) => return CollaborationConflict(receipt)
    MutationInvalid(reason) => return CollaborationDenied(reason)
    MutationProceed(payload_digest) => {
      if !actor_has_role_v1(projection, actor, Owner) {
        return CollaborationDenied("only an active owner may change membership")
      }
      guard find_membership_v1(projection, principal) is Some(target) else {
        return CollaborationDenied("membership does not exist")
      }
      if target.status == status {
        return CollaborationDenied(
          "membership already has the requested status",
        )
      }
      if target.roles.contains(Owner) && status != Active {
        let active_owner_count = projection.memberships.fold(init=0, fn(
          count,
          item,
        ) {
          if membership_has_role_v1(item, Owner) {
            count + 1
          } else {
            count
          }
        })
        if active_owner_count <= 1 {
          return CollaborationDenied("the last active owner cannot be disabled")
        }
      }
      let memberships = projection.memberships
        .map(item => {
          if item.principal == principal {
            MembershipV1::{ ..item, status, updated_at: recorded_at }
          } else {
            item
          }
        })
        .iter()
        .to_array()
      let event = collaboration_event_v1(
        mutation_id, "membership-status-set", actor, expected_head, payload_digest,
        recorded_at,
      )
      let updated = append_collaboration_event_v1(
        projection,
        event,
        memberships,
        unchanged_assignments_v1(projection),
        unchanged_comments_v1(projection),
        unchanged_reviews_v1(projection),
      )
      CollaborationApplied(updated, collaboration_receipt_v1(event, false))
    }
  }
}

///|
fn find_assignment_v1(
  projection : CollaborationProjectionV1,
  assignment_id : String,
) -> AssignmentV1? {
  for assignment in projection.assignments {
    if assignment.assignment_id == assignment_id {
      return Some(assignment)
    }
  }
  None
}

///|
fn find_review_v1(
  projection : CollaborationProjectionV1,
  review_id : String,
) -> ReviewInboxItemV1? {
  for review in projection.reviews {
    if review.review_id == review_id {
      return Some(review)
    }
  }
  None
}

///|
pub fn latest_assignment_claim_v1(
  projection : CollaborationProjectionV1,
  assignment_id : String,
) -> AssignmentClaimV1? {
  let mut result : AssignmentClaimV1? = None
  for claim in projection.claims {
    if claim.assignment_id == assignment_id {
      result = Some(claim)
    }
  }
  result
}

///|
pub fn active_assignment_claim_v1(
  projection : CollaborationProjectionV1,
  assignment_id : String,
  at : String,
) -> AssignmentClaimV1? {
  match latest_assignment_claim_v1(projection, assignment_id) {
    Some(claim) if @capability.wire_timestamp_is_canonical(at) &&
      claim.acquired_at <= at &&
      at < claim.expires_at => Some(claim)
    _ => None
  }
}

///|
/// Acquires an optional bounded lease, or records a reclaim only after the
/// previous lease expired. The immutable claim itself is the expiry/reclaim
/// receipt and is retained across restart.
pub fn claim_assignment_v1(
  projection : CollaborationProjectionV1,
  assignment_id : String,
  lease_id : String,
  holder : @capability.PrincipalRefV1,
  expires_at : String,
  mutation_id : String,
  expected_head : @capability.DigestRefV1,
  recorded_at : String,
) -> CollaborationMutationResultV1 {
  let detail = "\{assignment_id}|\{lease_id}|\{holder.canonical_text()}|\{expires_at}"
  match
    guard_collaboration_mutation_v1(
      projection, mutation_id, "assignment-claimed", holder, expected_head, detail,
      recorded_at,
    ) {
    MutationReplay(receipt) => return CollaborationIdempotent(receipt)
    MutationHeadConflict(receipt) => return CollaborationConflict(receipt)
    MutationInvalid(reason) => return CollaborationDenied(reason)
    MutationProceed(payload_digest) => {
      guard find_assignment_v1(projection, assignment_id) is Some(assignment) else {
        return CollaborationDenied("assignment does not exist")
      }
      if assignment.state == Completed ||
        assignment.state == Cancelled ||
        holder != assignment.assignee ||
        !actor_is_active_v1(projection, holder) {
        return CollaborationDenied(
          "only the active assignee may claim open work",
        )
      }
      if !@capability.identifier_component_is_canonical(lease_id) ||
        projection.claims.any(value => value.lease_id == lease_id) ||
        !@capability.wire_timestamp_is_canonical(expires_at) ||
        expires_at <= recorded_at ||
        (assignment.due_at is Some(due_at) && expires_at > due_at) {
        return CollaborationDenied(
          "assignment lease id or bounded expiry is invalid",
        )
      }
      let previous = latest_assignment_claim_v1(projection, assignment_id)
      if previous is Some(current) && recorded_at < current.expires_at {
        return CollaborationDenied("assignment already has an unexpired lease")
      }
      let claim = AssignmentClaimV1::{
        lease_id,
        assignment_id,
        holder,
        acquired_at: recorded_at,
        expires_at,
        previous_lease_id: previous.map(value => value.lease_id),
        reclaimed_expired: previous is Some(_),
        mutation_id,
      }
      let event = collaboration_event_v1(
        mutation_id, "assignment-claimed", holder, expected_head, payload_digest,
        recorded_at,
      )
      let claims = projection.claims.iter().to_array()
      claims.push(claim)
      let events = projection.events.iter().to_array()
      events.push(event)
      let updated = CollaborationProjectionV1::{
        workspace: projection.workspace,
        memberships: projection.memberships,
        assignments: projection.assignments,
        claims: ReadOnlyArray::from_array(claims),
        comments: projection.comments,
        reviews: projection.reviews,
        events: ReadOnlyArray::from_array(events),
        head_digest: event.resulting_head,
      }
      CollaborationApplied(updated, collaboration_receipt_v1(event, false))
    }
  }
}

///|
pub fn create_assignment_v1(
  projection : CollaborationProjectionV1,
  assignment_id : String,
  assignee : @capability.PrincipalRefV1,
  operation : @capability.OperationRef,
  subject_digest : @capability.DigestRefV1,
  actor : @capability.PrincipalRefV1,
  mutation_id : String,
  expected_head : @capability.DigestRefV1,
  recorded_at : String,
  due_at? : String,
) -> CollaborationMutationResultV1 {
  let due = due_at.unwrap_or("-")
  let detail = "\{assignment_id}|\{assignee.canonical_text()}|\{operation.format()}|\{subject_digest.text()}|\{due}"
  match
    guard_collaboration_mutation_v1(
      projection, mutation_id, "assignment-created", actor, expected_head, detail,
      recorded_at,
    ) {
    MutationReplay(receipt) => return CollaborationIdempotent(receipt)
    MutationHeadConflict(receipt) => return CollaborationConflict(receipt)
    MutationInvalid(reason) => return CollaborationDenied(reason)
    MutationProceed(payload_digest) => {
      if !actor_can_contribute_v1(projection, actor) {
        return CollaborationDenied(
          "only an active contributor may create an assignment",
        )
      }
      if !@capability.identifier_component_is_canonical(assignment_id) ||
        find_assignment_v1(projection, assignment_id) is Some(_) {
        return CollaborationDenied("assignment id is invalid or already exists")
      }
      guard find_membership_v1(projection, assignee)
        is Some(assignee_membership) &&
        assignee_membership.status == Active else {
        return CollaborationDenied(
          "assignee must be an active workspace member",
        )
      }
      if due_at is Some(value) &&
        (
          !@capability.wire_timestamp_is_canonical(value) ||
          value <= recorded_at
        ) {
        return CollaborationDenied("assignment due_at must follow creation")
      }
      let assignments = unchanged_assignments_v1(projection)
      assignments.push({
        assignment_id,
        assignee,
        operation,
        subject_digest,
        state: Assigned,
        due_at,
        submitted_artifact: None,
        approval_review_id: None,
        updated_at: recorded_at,
      })
      let event = collaboration_event_v1(
        mutation_id, "assignment-created", actor, expected_head, payload_digest,
        recorded_at,
      )
      let updated = append_collaboration_event_v1(
        projection,
        event,
        unchanged_memberships_v1(projection),
        assignments,
        unchanged_comments_v1(projection),
        unchanged_reviews_v1(projection),
      )
      CollaborationApplied(updated, collaboration_receipt_v1(event, false))
    }
  }
}

///|
fn assignment_transition_allowed_v1(
  from_state : AssignmentStateV1,
  to_state : AssignmentStateV1,
) -> Bool {
  match (from_state, to_state) {
    (Assigned, InProgress | Cancelled) => true
    (InProgress, Submitted | Cancelled) => true
    (Submitted, InProgress | Completed | Cancelled) => true
    _ => false
  }
}

///|
pub fn transition_assignment_v1(
  projection : CollaborationProjectionV1,
  assignment_id : String,
  to_state : AssignmentStateV1,
  actor : @capability.PrincipalRefV1,
  mutation_id : String,
  expected_head : @capability.DigestRefV1,
  recorded_at : String,
  submitted_artifact? : @capability.ContentAddressedEvidenceRefV1,
  approval_review_id? : String,
) -> CollaborationMutationResultV1 {
  let artifact_digest = submitted_artifact
    .map(value => value.evidence_digest())
    .unwrap_or("-")
  let review_ref = approval_review_id.unwrap_or("-")
  let detail = "\{assignment_id}|\{to_state.id()}|\{artifact_digest}|\{review_ref}"
  match
    guard_collaboration_mutation_v1(
      projection, mutation_id, "assignment-transitioned", actor, expected_head, detail,
      recorded_at,
    ) {
    MutationReplay(receipt) => return CollaborationIdempotent(receipt)
    MutationHeadConflict(receipt) => return CollaborationConflict(receipt)
    MutationInvalid(reason) => return CollaborationDenied(reason)
    MutationProceed(payload_digest) => {
      guard find_assignment_v1(projection, assignment_id) is Some(assignment) else {
        return CollaborationDenied("assignment does not exist")
      }
      if !assignment_transition_allowed_v1(assignment.state, to_state) {
        return CollaborationDenied(
          "invalid assignment transition: \{assignment.state.id()} -> \{to_state.id()}",
        )
      }
      if recorded_at < assignment.updated_at {
        return CollaborationDenied(
          "assignment transition predates current state",
        )
      }
      if latest_assignment_claim_v1(projection, assignment_id) is Some(claim) {
        if recorded_at >= claim.expires_at {
          return CollaborationDenied(
            "assignment lease is stale; acquire a new lease first",
          )
        }
        if actor != claim.holder {
          return CollaborationDenied(
            "assignment is leased to another principal",
          )
        }
      }
      let mut next_artifact = assignment.submitted_artifact
      let mut next_review = assignment.approval_review_id
      match to_state {
        InProgress => {
          if actor != assignment.assignee ||
            !actor_is_active_v1(projection, actor) {
            return CollaborationDenied(
              "only the active assignee may start or resume work",
            )
          }
          if submitted_artifact is Some(_) || approval_review_id is Some(_) {
            return CollaborationDenied(
              "in-progress transition cannot attach acceptance data",
            )
          }
          next_artifact = None
          next_review = None
        }
        Submitted => {
          if actor != assignment.assignee ||
            !actor_is_active_v1(projection, actor) {
            return CollaborationDenied(
              "only the active assignee may submit work",
            )
          }
          guard submitted_artifact is Some(artifact) else {
            return CollaborationDenied(
              "submitted work requires a content-addressed artifact",
            )
          }
          if approval_review_id is Some(_) {
            return CollaborationDenied(
              "submission cannot claim an approval review",
            )
          }
          next_artifact = Some(artifact)
          next_review = None
        }
        Completed => {
          if submitted_artifact is Some(_) {
            return CollaborationDenied(
              "completion reuses the immutable submitted artifact",
            )
          }
          guard approval_review_id is Some(review_id) &&
            find_review_v1(projection, review_id) is Some(review) else {
            return CollaborationDenied("completion requires an existing review")
          }
          guard assignment.submitted_artifact is Some(accepted_artifact) else {
            return CollaborationDenied(
              "completed assignment has no submitted artifact",
            )
          }
          if review.state != Approved ||
            review.subject_digest.text() != accepted_artifact.evidence_digest() ||
            review.assigned_reviewer != actor ||
            actor == assignment.assignee ||
            !review.separation_of_duty_ok() {
            return CollaborationDenied(
              "completion requires the independent assigned human review approval",
            )
          }
          next_review = Some(review_id)
        }
        Cancelled => {
          if actor != assignment.assignee &&
            !actor_has_role_v1(projection, actor, Owner) {
            return CollaborationDenied(
              "only the assignee or an owner may cancel work",
            )
          }
          if submitted_artifact is Some(_) || approval_review_id is Some(_) {
            return CollaborationDenied(
              "cancellation cannot attach acceptance data",
            )
          }
        }
        Assigned =>
          return CollaborationDenied(
            "assignment cannot transition back to assigned",
          )
      }
      let assignments = projection.assignments
        .map(item => {
          if item.assignment_id == assignment_id {
            AssignmentV1::{
              ..item,
              state: to_state,
              submitted_artifact: next_artifact,
              approval_review_id: next_review,
              updated_at: recorded_at,
            }
          } else {
            item
          }
        })
        .iter()
        .to_array()
      let event = collaboration_event_v1(
        mutation_id, "assignment-transitioned", actor, expected_head, payload_digest,
        recorded_at,
      )
      let updated = append_collaboration_event_v1(
        projection,
        event,
        unchanged_memberships_v1(projection),
        assignments,
        unchanged_comments_v1(projection),
        unchanged_reviews_v1(projection),
      )
      CollaborationApplied(updated, collaboration_receipt_v1(event, false))
    }
  }
}

///|
/// Adds discussion evidence anchored to immutable subject bytes. This API has
/// no acceptance field: a comment can never be mistaken for a review receipt.
pub fn add_anchored_comment_v1(
  projection : CollaborationProjectionV1,
  comment_id : String,
  subject_digest : @capability.DigestRefV1,
  anchor_ref : String,
  body : @capability.ContentAddressedEvidenceRefV1,
  actor : @capability.PrincipalRefV1,
  mutation_id : String,
  expected_head : @capability.DigestRefV1,
  recorded_at : String,
  mentions? : Array[@capability.PrincipalRefV1] = [],
) -> CollaborationMutationResultV1 {
  let mention_text = mentions.map(value => value.canonical_text()).join(",")
  let detail = "\{comment_id}|\{subject_digest.text()}|\{anchor_ref}|\{body.evidence_ref()}|\{body.evidence_digest()}|\{mention_text}"
  match
    guard_collaboration_mutation_v1(
      projection, mutation_id, "comment-anchored", actor, expected_head, detail,
      recorded_at,
    ) {
    MutationReplay(receipt) => return CollaborationIdempotent(receipt)
    MutationHeadConflict(receipt) => return CollaborationConflict(receipt)
    MutationInvalid(reason) => return CollaborationDenied(reason)
    MutationProceed(payload_digest) => {
      guard find_membership_v1(projection, actor) is Some(actor_membership) &&
        actor_membership.status == Active else {
        return CollaborationDenied("only an active member may comment")
      }
      if !@capability.identifier_component_is_canonical(comment_id) ||
        !@capability.evidence_artifact_ref_is_canonical(anchor_ref) ||
        projection.comments.any(value => value.comment_id == comment_id) {
        return CollaborationDenied("comment identity or anchor is invalid")
      }
      let seen_mentions : Array[String] = []
      for mentioned in mentions {
        let key = mentioned.canonical_text()
        if seen_mentions.contains(key) ||
          !actor_is_active_v1(projection, mentioned) {
          return CollaborationDenied(
            "comment mentions must be unique active workspace principals",
          )
        }
        seen_mentions.push(key)
      }
      let comments = unchanged_comments_v1(projection)
      comments.push({
        comment_id,
        author: actor,
        subject_digest,
        anchor_ref,
        body,
        mentions: ReadOnlyArray::from_array(mentions),
        created_at: recorded_at,
      })
      let event = collaboration_event_v1(
        mutation_id, "comment-anchored", actor, expected_head, payload_digest, recorded_at,
      )
      let updated = append_collaboration_event_v1(
        projection,
        event,
        unchanged_memberships_v1(projection),
        unchanged_assignments_v1(projection),
        comments,
        unchanged_reviews_v1(projection),
      )
      CollaborationApplied(updated, collaboration_receipt_v1(event, false))
    }
  }
}

///|
pub fn request_review_v1(
  projection : CollaborationProjectionV1,
  review_id : String,
  subject_digest : @capability.DigestRefV1,
  assigned_reviewer : @capability.PrincipalRefV1,
  requirement_id : String,
  actor : @capability.PrincipalRefV1,
  mutation_id : String,
  expected_head : @capability.DigestRefV1,
  recorded_at : String,
) -> CollaborationMutationResultV1 {
  let detail = "\{review_id}|\{subject_digest.text()}|\{assigned_reviewer.canonical_text()}|\{requirement_id}"
  match
    guard_collaboration_mutation_v1(
      projection, mutation_id, "review-requested", actor, expected_head, detail,
      recorded_at,
    ) {
    MutationReplay(receipt) => return CollaborationIdempotent(receipt)
    MutationHeadConflict(receipt) => return CollaborationConflict(receipt)
    MutationInvalid(reason) => return CollaborationDenied(reason)
    MutationProceed(payload_digest) => {
      if !actor_can_contribute_v1(projection, actor) {
        return CollaborationDenied(
          "only an active contributor may request review",
        )
      }
      if !@capability.identifier_component_is_canonical(review_id) ||
        !@capability.identifier_component_is_canonical(requirement_id) ||
        find_review_v1(projection, review_id) is Some(_) {
        return CollaborationDenied(
          "review identity is invalid or already exists",
        )
      }
      guard find_membership_v1(projection, assigned_reviewer)
        is Some(reviewer_membership) &&
        membership_has_role_v1(reviewer_membership, Reviewer) &&
        assigned_reviewer.kind() == @capability.PrincipalKindV1::Human else {
        return CollaborationDenied(
          "assigned reviewer must be an active human reviewer",
        )
      }
      if actor == assigned_reviewer {
        return CollaborationDenied(
          "submitter and reviewer must be different principals",
        )
      }
      let reviews = unchanged_reviews_v1(projection)
      reviews.push({
        review_id,
        subject_digest,
        submitted_by: actor,
        assigned_reviewer,
        requirement_id,
        state: Requested,
        decision_evidence: None,
        updated_at: recorded_at,
      })
      let event = collaboration_event_v1(
        mutation_id, "review-requested", actor, expected_head, payload_digest, recorded_at,
      )
      let updated = append_collaboration_event_v1(
        projection,
        event,
        unchanged_memberships_v1(projection),
        unchanged_assignments_v1(projection),
        unchanged_comments_v1(projection),
        reviews,
      )
      CollaborationApplied(updated, collaboration_receipt_v1(event, false))
    }
  }
}

///|
pub fn begin_review_v1(
  projection : CollaborationProjectionV1,
  review_id : String,
  actor : @capability.PrincipalRefV1,
  mutation_id : String,
  expected_head : @capability.DigestRefV1,
  recorded_at : String,
) -> CollaborationMutationResultV1 {
  match
    guard_collaboration_mutation_v1(
      projection, mutation_id, "review-started", actor, expected_head, review_id,
      recorded_at,
    ) {
    MutationReplay(receipt) => return CollaborationIdempotent(receipt)
    MutationHeadConflict(receipt) => return CollaborationConflict(receipt)
    MutationInvalid(reason) => return CollaborationDenied(reason)
    MutationProceed(payload_digest) => {
      guard find_review_v1(projection, review_id) is Some(review) else {
        return CollaborationDenied("review does not exist")
      }
      if review.state != Requested ||
        actor != review.assigned_reviewer ||
        !actor_is_active_v1(projection, actor) {
        return CollaborationDenied(
          "only the active assigned reviewer may begin review",
        )
      }
      let reviews = projection.reviews
        .map(item => {
          if item.review_id == review_id {
            ReviewInboxItemV1::{
              ..item,
              state: InReview,
              updated_at: recorded_at,
            }
          } else {
            item
          }
        })
        .iter()
        .to_array()
      let event = collaboration_event_v1(
        mutation_id, "review-started", actor, expected_head, payload_digest, recorded_at,
      )
      let updated = append_collaboration_event_v1(
        projection,
        event,
        unchanged_memberships_v1(projection),
        unchanged_assignments_v1(projection),
        unchanged_comments_v1(projection),
        reviews,
      )
      CollaborationApplied(updated, collaboration_receipt_v1(event, false))
    }
  }
}

///|
/// A decision is a distinct reviewed mutation with immutable evidence. Anchored
/// comments cannot invoke this path and therefore cannot approve work.
pub fn decide_review_v1(
  projection : CollaborationProjectionV1,
  review_id : String,
  decision : ReviewStateV1,
  evidence : @capability.ContentAddressedEvidenceRefV1,
  actor : @capability.PrincipalRefV1,
  mutation_id : String,
  expected_head : @capability.DigestRefV1,
  recorded_at : String,
) -> CollaborationMutationResultV1 {
  let detail = "\{review_id}|\{decision.id()}|\{evidence.evidence_ref()}|\{evidence.evidence_digest()}"
  match
    guard_collaboration_mutation_v1(
      projection, mutation_id, "review-decided", actor, expected_head, detail, recorded_at,
    ) {
    MutationReplay(receipt) => return CollaborationIdempotent(receipt)
    MutationHeadConflict(receipt) => return CollaborationConflict(receipt)
    MutationInvalid(reason) => return CollaborationDenied(reason)
    MutationProceed(payload_digest) => {
      if decision != Approved && decision != ChangesRequested {
        return CollaborationDenied(
          "review decision must approve or request changes",
        )
      }
      guard find_review_v1(projection, review_id) is Some(review) else {
        return CollaborationDenied("review does not exist")
      }
      if (review.state != Requested && review.state != InReview) ||
        actor != review.assigned_reviewer ||
        actor == review.submitted_by ||
        actor.kind() != @capability.PrincipalKindV1::Human ||
        !actor_has_role_v1(projection, actor, Reviewer) {
        return CollaborationDenied(
          "review decision requires the independent active assigned human reviewer",
        )
      }
      let reviews = projection.reviews
        .map(item => {
          if item.review_id == review_id {
            ReviewInboxItemV1::{
              ..item,
              state: decision,
              decision_evidence: Some(evidence),
              updated_at: recorded_at,
            }
          } else {
            item
          }
        })
        .iter()
        .to_array()
      let event = collaboration_event_v1(
        mutation_id, "review-decided", actor, expected_head, payload_digest, recorded_at,
      )
      let updated = append_collaboration_event_v1(
        projection,
        event,
        unchanged_memberships_v1(projection),
        unchanged_assignments_v1(projection),
        unchanged_comments_v1(projection),
        reviews,
      )
      CollaborationApplied(updated, collaboration_receipt_v1(event, false))
    }
  }
}

///|
pub fn withdraw_review_v1(
  projection : CollaborationProjectionV1,
  review_id : String,
  actor : @capability.PrincipalRefV1,
  mutation_id : String,
  expected_head : @capability.DigestRefV1,
  recorded_at : String,
) -> CollaborationMutationResultV1 {
  match
    guard_collaboration_mutation_v1(
      projection, mutation_id, "review-withdrawn", actor, expected_head, review_id,
      recorded_at,
    ) {
    MutationReplay(receipt) => return CollaborationIdempotent(receipt)
    MutationHeadConflict(receipt) => return CollaborationConflict(receipt)
    MutationInvalid(reason) => return CollaborationDenied(reason)
    MutationProceed(payload_digest) => {
      guard find_review_v1(projection, review_id) is Some(review) else {
        return CollaborationDenied("review does not exist")
      }
      if (review.state != Requested && review.state != InReview) ||
        actor != review.submitted_by ||
        !actor_is_active_v1(projection, actor) {
        return CollaborationDenied(
          "only the active submitter may withdraw an open review",
        )
      }
      let reviews = projection.reviews
        .map(item => {
          if item.review_id == review_id {
            ReviewInboxItemV1::{
              ..item,
              state: Withdrawn,
              updated_at: recorded_at,
            }
          } else {
            item
          }
        })
        .iter()
        .to_array()
      let event = collaboration_event_v1(
        mutation_id, "review-withdrawn", actor, expected_head, payload_digest, recorded_at,
      )
      let updated = append_collaboration_event_v1(
        projection,
        event,
        unchanged_memberships_v1(projection),
        unchanged_assignments_v1(projection),
        unchanged_comments_v1(projection),
        reviews,
      )
      CollaborationApplied(updated, collaboration_receipt_v1(event, false))
    }
  }
}
