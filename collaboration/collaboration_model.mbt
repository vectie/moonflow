///|
pub(all) enum MembershipRoleV1 {
  Owner
  Contributor
  Reviewer
  Viewer
} derive(Debug, Eq)

///|
pub fn MembershipRoleV1::id(self : MembershipRoleV1) -> String {
  match self {
    Owner => "owner"
    Contributor => "contributor"
    Reviewer => "reviewer"
    Viewer => "viewer"
  }
}

///|
fn membership_role_v1_from_id(
  value : String,
) -> MembershipRoleV1 raise CollaborationError {
  match value {
    "owner" => Owner
    "contributor" => Contributor
    "reviewer" => Reviewer
    "viewer" => Viewer
    _ => raise SnapshotDecode("unsupported membership role: \{value}")
  }
}

///|
pub(all) enum MembershipStatusV1 {
  Active
  Suspended
  Removed
} derive(Debug, Eq)

///|
pub fn MembershipStatusV1::id(self : MembershipStatusV1) -> String {
  match self {
    Active => "active"
    Suspended => "suspended"
    Removed => "removed"
  }
}

///|
fn membership_status_v1_from_id(
  value : String,
) -> MembershipStatusV1 raise CollaborationError {
  match value {
    "active" => Active
    "suspended" => Suspended
    "removed" => Removed
    _ => raise SnapshotDecode("unsupported membership status: \{value}")
  }
}

///|
pub struct MembershipV1 {
  membership_id : String
  principal : @capability.PrincipalRefV1
  roles : ReadOnlyArray[MembershipRoleV1]
  status : MembershipStatusV1
  added_by : @capability.PrincipalRefV1
  updated_at : String
} derive(Debug, Eq)

///|
pub fn MembershipV1::membership_id(self : MembershipV1) -> String {
  self.membership_id
}

///|
pub fn MembershipV1::principal(
  self : MembershipV1,
) -> @capability.PrincipalRefV1 {
  self.principal
}

///|
pub fn MembershipV1::roles(
  self : MembershipV1,
) -> ReadOnlyArray[MembershipRoleV1] {
  self.roles
}

///|
pub fn MembershipV1::status(self : MembershipV1) -> MembershipStatusV1 {
  self.status
}

///|
pub(all) enum AssignmentStateV1 {
  Assigned
  InProgress
  Submitted
  Completed
  Cancelled
} derive(Debug, Eq)

///|
pub fn AssignmentStateV1::id(self : AssignmentStateV1) -> String {
  match self {
    Assigned => "assigned"
    InProgress => "in-progress"
    Submitted => "submitted"
    Completed => "completed"
    Cancelled => "cancelled"
  }
}

///|
fn assignment_state_v1_from_id(
  value : String,
) -> AssignmentStateV1 raise CollaborationError {
  match value {
    "assigned" => Assigned
    "in-progress" => InProgress
    "submitted" => Submitted
    "completed" => Completed
    "cancelled" => Cancelled
    _ => raise SnapshotDecode("unsupported assignment state: \{value}")
  }
}

///|
pub struct AssignmentV1 {
  assignment_id : String
  assignee : @capability.PrincipalRefV1
  operation : @capability.OperationRef
  subject_digest : @capability.DigestRefV1
  state : AssignmentStateV1
  due_at : String?
  submitted_artifact : @capability.ContentAddressedEvidenceRefV1?
  approval_review_id : String?
  updated_at : String
} derive(Debug, Eq)

///|
/// Immutable receipt for acquiring or reclaiming a bounded assignment lease.
/// Expiry is evaluated against `expires_at`; a reclaim names the expired lease.
pub struct AssignmentClaimV1 {
  lease_id : String
  assignment_id : String
  holder : @capability.PrincipalRefV1
  acquired_at : String
  expires_at : String
  previous_lease_id : String?
  reclaimed_expired : Bool
  mutation_id : String
} derive(Debug, Eq)

///|
pub fn AssignmentClaimV1::lease_id(self : AssignmentClaimV1) -> String {
  self.lease_id
}

///|
pub fn AssignmentClaimV1::assignment_id(self : AssignmentClaimV1) -> String {
  self.assignment_id
}

///|
pub fn AssignmentClaimV1::holder(
  self : AssignmentClaimV1,
) -> @capability.PrincipalRefV1 {
  self.holder
}

///|
pub fn AssignmentClaimV1::expires_at(self : AssignmentClaimV1) -> String {
  self.expires_at
}

///|
pub fn AssignmentClaimV1::reclaimed_expired(self : AssignmentClaimV1) -> Bool {
  self.reclaimed_expired
}

///|
pub fn AssignmentV1::assignment_id(self : AssignmentV1) -> String {
  self.assignment_id
}

///|
pub fn AssignmentV1::assignee(
  self : AssignmentV1,
) -> @capability.PrincipalRefV1 {
  self.assignee
}

///|
pub fn AssignmentV1::operation(self : AssignmentV1) -> @capability.OperationRef {
  self.operation
}

///|
pub fn AssignmentV1::state(self : AssignmentV1) -> AssignmentStateV1 {
  self.state
}

///|
pub fn AssignmentV1::subject_digest(
  self : AssignmentV1,
) -> @capability.DigestRefV1 {
  self.subject_digest
}

///|
pub struct AnchoredCommentV1 {
  comment_id : String
  author : @capability.PrincipalRefV1
  subject_digest : @capability.DigestRefV1
  anchor_ref : String
  body : @capability.ContentAddressedEvidenceRefV1
  mentions : ReadOnlyArray[@capability.PrincipalRefV1]
  created_at : String
} derive(Debug, Eq)

///|
pub fn AnchoredCommentV1::comment_id(self : AnchoredCommentV1) -> String {
  self.comment_id
}

///|
pub fn AnchoredCommentV1::author(
  self : AnchoredCommentV1,
) -> @capability.PrincipalRefV1 {
  self.author
}

///|
pub fn AnchoredCommentV1::subject_digest(
  self : AnchoredCommentV1,
) -> @capability.DigestRefV1 {
  self.subject_digest
}

///|
pub fn AnchoredCommentV1::anchor_ref(self : AnchoredCommentV1) -> String {
  self.anchor_ref
}

///|
pub fn AnchoredCommentV1::body(
  self : AnchoredCommentV1,
) -> @capability.ContentAddressedEvidenceRefV1 {
  self.body
}

///|
pub fn AnchoredCommentV1::mentions(
  self : AnchoredCommentV1,
) -> ReadOnlyArray[@capability.PrincipalRefV1] {
  self.mentions
}

///|
pub(all) enum ReviewStateV1 {
  Requested
  InReview
  Approved
  ChangesRequested
  Withdrawn
} derive(Debug, Eq)

///|
pub fn ReviewStateV1::id(self : ReviewStateV1) -> String {
  match self {
    Requested => "requested"
    InReview => "in-review"
    Approved => "approved"
    ChangesRequested => "changes-requested"
    Withdrawn => "withdrawn"
  }
}

///|
fn review_state_v1_from_id(
  value : String,
) -> ReviewStateV1 raise CollaborationError {
  match value {
    "requested" => Requested
    "in-review" => InReview
    "approved" => Approved
    "changes-requested" => ChangesRequested
    "withdrawn" => Withdrawn
    _ => raise SnapshotDecode("unsupported review state: \{value}")
  }
}

///|
pub struct ReviewInboxItemV1 {
  review_id : String
  subject_digest : @capability.DigestRefV1
  submitted_by : @capability.PrincipalRefV1
  assigned_reviewer : @capability.PrincipalRefV1
  requirement_id : String
  state : ReviewStateV1
  decision_evidence : @capability.ContentAddressedEvidenceRefV1?
  updated_at : String
} derive(Debug, Eq)

///|
pub fn ReviewInboxItemV1::review_id(self : ReviewInboxItemV1) -> String {
  self.review_id
}

///|
pub fn ReviewInboxItemV1::subject_digest(
  self : ReviewInboxItemV1,
) -> @capability.DigestRefV1 {
  self.subject_digest
}

///|
pub fn ReviewInboxItemV1::assigned_reviewer(
  self : ReviewInboxItemV1,
) -> @capability.PrincipalRefV1 {
  self.assigned_reviewer
}

///|
pub fn ReviewInboxItemV1::state(self : ReviewInboxItemV1) -> ReviewStateV1 {
  self.state
}

///|
pub fn ReviewInboxItemV1::separation_of_duty_ok(
  self : ReviewInboxItemV1,
) -> Bool {
  self.submitted_by != self.assigned_reviewer &&
  self.assigned_reviewer.kind() == @capability.PrincipalKindV1::Human
}

///|
pub struct CollaborationMutationEventV1 {
  mutation_id : String
  event_kind : String
  actor : @capability.PrincipalRefV1
  expected_head : @capability.DigestRefV1
  payload_digest : @capability.DigestRefV1
  resulting_head : @capability.DigestRefV1
  recorded_at : String
} derive(Debug, Eq)

///|
pub struct CollaborationMutationReceiptV1 {
  mutation_id : String
  event_kind : String
  head_digest : @capability.DigestRefV1
  payload_digest : @capability.DigestRefV1
  idempotent : Bool
  recorded_at : String
} derive(Debug, Eq)

///|
pub fn CollaborationMutationReceiptV1::head_digest(
  self : CollaborationMutationReceiptV1,
) -> @capability.DigestRefV1 {
  self.head_digest
}

///|
pub fn CollaborationMutationReceiptV1::idempotent(
  self : CollaborationMutationReceiptV1,
) -> Bool {
  self.idempotent
}

///|
pub struct CollaborationConflictReceiptV1 {
  mutation_id : String
  expected_head : @capability.DigestRefV1
  actual_head : @capability.DigestRefV1
  reason : String
  recorded_at : String
} derive(Debug, Eq)

///|
pub fn CollaborationConflictReceiptV1::expected_head(
  self : CollaborationConflictReceiptV1,
) -> @capability.DigestRefV1 {
  self.expected_head
}

///|
pub fn CollaborationConflictReceiptV1::actual_head(
  self : CollaborationConflictReceiptV1,
) -> @capability.DigestRefV1 {
  self.actual_head
}

///|
pub(all) enum CollaborationMutationResultV1 {
  CollaborationApplied(
    CollaborationProjectionV1,
    CollaborationMutationReceiptV1
  )
  CollaborationIdempotent(CollaborationMutationReceiptV1)
  CollaborationConflict(CollaborationConflictReceiptV1)
  CollaborationDenied(String)
} derive(Debug)

///|
pub struct CollaborationProjectionV1 {
  workspace : @capability.WorkspaceRefV1
  memberships : ReadOnlyArray[MembershipV1]
  assignments : ReadOnlyArray[AssignmentV1]
  claims : ReadOnlyArray[AssignmentClaimV1]
  comments : ReadOnlyArray[AnchoredCommentV1]
  reviews : ReadOnlyArray[ReviewInboxItemV1]
  events : ReadOnlyArray[CollaborationMutationEventV1]
  head_digest : @capability.DigestRefV1
} derive(Debug, Eq)

///|
pub fn CollaborationProjectionV1::workspace(
  self : CollaborationProjectionV1,
) -> @capability.WorkspaceRefV1 {
  self.workspace
}

///|
pub fn CollaborationProjectionV1::memberships(
  self : CollaborationProjectionV1,
) -> ReadOnlyArray[MembershipV1] {
  self.memberships
}

///|
pub fn CollaborationProjectionV1::assignments(
  self : CollaborationProjectionV1,
) -> ReadOnlyArray[AssignmentV1] {
  self.assignments
}

///|
pub fn CollaborationProjectionV1::assignment_claims(
  self : CollaborationProjectionV1,
) -> ReadOnlyArray[AssignmentClaimV1] {
  self.claims
}

///|
pub fn CollaborationProjectionV1::comments(
  self : CollaborationProjectionV1,
) -> ReadOnlyArray[AnchoredCommentV1] {
  self.comments
}

///|
pub fn CollaborationProjectionV1::review_inbox(
  self : CollaborationProjectionV1,
) -> ReadOnlyArray[ReviewInboxItemV1] {
  self.reviews
}

///|
pub fn CollaborationProjectionV1::head_digest(
  self : CollaborationProjectionV1,
) -> @capability.DigestRefV1 {
  self.head_digest
}
