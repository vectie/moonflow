///|
pub(all) enum RuntimeStatus {
  Proposed
  Ready
  Active
  Waiting
  Blocked
  Review
  Accepted
  Failed
  Cancelled
  Superseded
} derive(Debug, Eq, Compare, Hash, ToJson)

///|
pub fn RuntimeStatus::id(self : RuntimeStatus) -> String {
  match self {
    Proposed => "proposed"
    Ready => "ready"
    Active => "active"
    Waiting => "waiting"
    Blocked => "blocked"
    Review => "review"
    Accepted => "accepted"
    Failed => "failed"
    Cancelled => "cancelled"
    Superseded => "superseded"
  }
}

///|
pub fn RuntimeStatus::is_terminal(self : RuntimeStatus) -> Bool {
  match self {
    Accepted | Failed | Cancelled | Superseded => true
    _ => false
  }
}

///|
pub(all) enum EventKind {
  RunCreated
  ItemRegistered
  ItemReady
  ItemStarted
  ItemWaiting
  ItemBlocked
  ItemReviewRequested
  ItemAccepted
  ItemFailed
  ItemCancelled
  ItemSuperseded
  ArtifactAttached
  ApprovalGranted
} derive(Debug, Eq, Compare, Hash, ToJson)

///|
pub fn EventKind::id(self : EventKind) -> String {
  match self {
    RunCreated => "run-created"
    ItemRegistered => "item-registered"
    ItemReady => "item-ready"
    ItemStarted => "item-started"
    ItemWaiting => "item-waiting"
    ItemBlocked => "item-blocked"
    ItemReviewRequested => "item-review-requested"
    ItemAccepted => "item-accepted"
    ItemFailed => "item-failed"
    ItemCancelled => "item-cancelled"
    ItemSuperseded => "item-superseded"
    ArtifactAttached => "artifact-attached"
    ApprovalGranted => "approval-granted"
  }
}

///|
pub(all) struct RuntimeEvent {
  sequence : Int
  event_id : String
  run_id : String
  work_item_id : String
  kind : EventKind
  product_id : String
  depends_on : Array[String]
  detail : String
  artifact_id : String
  authority_id : String
  recorded_at : String
} derive(Debug, Eq, ToJson)

///|
pub(all) struct RuntimeItem {
  work_item_id : String
  product_id : String
  depends_on : Array[String]
  mut status : RuntimeStatus
  mut attempt_count : Int
  mut blocker : String
  artifacts : Array[String]
  approvals : Array[String]
} derive(Debug, Eq, ToJson)

///|
pub(all) struct RunProjection {
  run_id : String
  mut last_sequence : Int
  items : Array[RuntimeItem]
  applied_event_ids : Array[String]
  applied_events : Array[RuntimeEvent]
  mut outcome : String
} derive(Debug, Eq, ToJson)

///|
pub(all) suberror FlowError {
  EmptyEventId
  EmptyRunId
  InvalidSequence(expected~ : Int, actual~ : Int)
  ConflictingDuplicateEvent(String)
  RunIdMismatch(expected~ : String, actual~ : String)
  MissingWorkItem(String)
  DuplicateWorkItem(String)
  InvalidTransition(item_id~ : String, from~ : String, event~ : String)
  DependencyNotAccepted(item_id~ : String, dependency_id~ : String)
  MissingArtifactId(String)
  MissingAuthorityId(String)
} derive(Debug, Eq, ToJson)
