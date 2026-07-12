///|
pub(all) struct CheckpointMigrationDecision {
  child_work_item_id : String
  source_work_item_id : String
  declaration_id : String
  decision : String
  reason : String
  evidence_refs : Array[String]
} derive(Debug, Eq, ToJson)

///|
pub(all) struct RunMigrationReceipt {
  contract_id : String
  migration_id : String
  parent_run_id : String
  child_run_id : String
  parent_revision : String
  child_revision : String
  parent_source_digest : String
  child_source_digest : String
  revision_proposal_ref : String
  decisions : Array[CheckpointMigrationDecision]
  reused_count : Int
  invalidated_count : Int
  new_count : Int
  recorded_at : String
} derive(Debug, Eq, ToJson)

///|
pub(all) struct RunRevisionResult {
  events : Array[RuntimeEvent]
  receipt : RunMigrationReceipt
} derive(Debug, Eq, ToJson)

///|
pub fn RunMigrationReceipt::quality_issues(
  self : RunMigrationReceipt,
) -> Array[String] {
  let issues : Array[String] = []
  if self.contract_id != "moonflow.run-migration.v1" {
    issues.push("unsupported run migration contract")
  }
  for
    pair in [
      ("migration_id", self.migration_id),
      ("parent_run_id", self.parent_run_id),
      ("child_run_id", self.child_run_id),
      ("parent_revision", self.parent_revision),
      ("child_revision", self.child_revision),
      ("parent_source_digest", self.parent_source_digest),
      ("child_source_digest", self.child_source_digest),
      ("revision_proposal_ref", self.revision_proposal_ref),
      ("recorded_at", self.recorded_at),
    ] {
    let (field, value) = pair
    if value.trim().is_empty() {
      issues.push("\{field} is required")
    }
  }
  if self.parent_run_id == self.child_run_id {
    issues.push("child run must not overwrite parent history")
  }
  if !artifact_ref_is_workspace_relative(self.revision_proposal_ref) {
    issues.push("revision proposal must be workspace-relative")
  }
  if self.decisions.is_empty() {
    issues.push("checkpoint decisions are required")
  }
  if self.reused_count + self.invalidated_count + self.new_count !=
    self.decisions.length() {
    issues.push("checkpoint counts do not match decisions")
  }
  issues
}

///|
fn parent_item_for_declaration(
  parent : RunProjection,
  declaration_id : String,
) -> RuntimeItem? {
  let mut found : RuntimeItem? = None
  for item in parent.items {
    if item.declaration_id == declaration_id {
      if found is Some(_) {
        return None
      }
      found = Some(item)
    }
  }
  found
}

///|
fn checkpoint_identity_issue(
  parent : RuntimeItem,
  child : RuntimeItem,
) -> String? {
  if parent.status != Accepted {
    return Some("source checkpoint is not accepted")
  }
  if parent.product_id != child.product_id {
    return Some("product owner changed")
  }
  if parent.requested_authority != child.requested_authority {
    return Some("requested authority changed")
  }
  if parent.acceptance_criteria != child.acceptance_criteria {
    return Some("acceptance criteria changed")
  }
  for
    pair in [
      ("result identity", parent.result_id),
      ("attempt identity", parent.active_attempt_id),
      ("output digest", parent.output_digest),
      ("acceptance review", parent.acceptance_review_id),
      ("review artifact", parent.acceptance_review_artifact),
      ("review authority", parent.acceptance_reviewer_id),
    ] {
    let (label, value) = pair
    if value.trim().is_empty() {
      return Some("source checkpoint lacks \{label}")
    }
  }
  None
}

///|
fn checkpoint_dependencies_accepted(
  child : RuntimeItem,
  projection : RunProjection,
) -> Bool {
  child.depends_on.all(dependency_id => {
    match projection.find_item(dependency_id) {
      Some(dependency) => dependency.status == Accepted
      None => false
    }
  })
}

///|
fn checkpoint_reuse_event(
  parent_projection : RunProjection,
  child_projection : RunProjection,
  parent : RuntimeItem,
  child : RuntimeItem,
  recorded_at : String,
) -> RuntimeEvent {
  {
    sequence: child_projection.last_sequence + 1,
    event_id: "event-\{child_projection.run_id}-reuse-\{child.work_item_id}-from-\{parent_projection.run_id}",
    run_id: child_projection.run_id,
    work_item_id: child.work_item_id,
    kind: CheckpointReused,
    product_id: child.product_id,
    declaration_id: child.declaration_id,
    book_id: child_projection.book_id,
    declaration_revision: child_projection.declaration_revision,
    source_digest: child_projection.source_digest,
    requested_authority: child.requested_authority,
    acceptance_criteria: child.acceptance_criteria.copy(),
    request_id: parent.request_id,
    result_id: parent.result_id,
    attempt_id: parent.active_attempt_id,
    idempotency_key: parent.idempotency_key,
    external_job_id: parent.external_job_id,
    attempt_status: "checkpoint-reused",
    input_digest: parent.input_digest,
    output_digest: parent.output_digest,
    output_artifacts: parent.artifacts.copy(),
    error_kind: "",
    compensable: false,
    depends_on: child.depends_on.copy(),
    detail: parent.acceptance_review_id,
    artifact_id: parent.acceptance_review_artifact,
    authority_id: parent.acceptance_reviewer_id,
    recorded_at,
  }
}

///|
pub fn revise_run(
  parent : RunProjection,
  child_graph : Json,
  migration_id : String,
  revision_proposal_ref : String,
  recorded_at : String,
) -> RunRevisionResult raise {
  if parent.run_id.trim().is_empty() ||
    parent.declaration_revision.trim().is_empty() {
    fail("parent projection must have durable run identity")
  }
  if migration_id.trim().is_empty() {
    fail("migration_id is required")
  }
  if !artifact_ref_is_workspace_relative(revision_proposal_ref) {
    fail("revision proposal must be workspace-relative")
  }
  let events = events_from_work_graph(child_graph)
  let child_run_id = events[0].run_id
  if child_run_id == parent.run_id {
    fail("revision must create a child run")
  }
  let child = replay(child_run_id, events)
  if child.declaration_revision == parent.declaration_revision {
    fail("revision must change declaration_revision")
  }
  for ;; {
    let mut progressed = false
    for child_item in child.items {
      if child_item.status == Accepted {
        continue
      }
      guard parent_item_for_declaration(parent, child_item.declaration_id)
        is Some(parent_item) else {
        continue
      }
      if checkpoint_identity_issue(parent_item, child_item) is None &&
        checkpoint_dependencies_accepted(child_item, child) {
        let event = checkpoint_reuse_event(
          parent, child, parent_item, child_item, recorded_at,
        )
        events.push(event)
        child.apply(event)
        progressed = true
      }
    }
    if !progressed {
      break
    }
  }
  let decisions : Array[CheckpointMigrationDecision] = []
  let mut reused_count = 0
  let mut invalidated_count = 0
  let mut new_count = 0
  for child_item in child.items {
    match parent_item_for_declaration(parent, child_item.declaration_id) {
      None => {
        new_count += 1
        decisions.push({
          child_work_item_id: child_item.work_item_id,
          source_work_item_id: "",
          declaration_id: child_item.declaration_id,
          decision: "new",
          reason: "no parent checkpoint has this declaration identity",
          evidence_refs: [],
        })
      }
      Some(parent_item) =>
        if child_item.status == Accepted &&
          child_item.attempt_status == "checkpoint-reused" {
          reused_count += 1
          decisions.push({
            child_work_item_id: child_item.work_item_id,
            source_work_item_id: parent_item.work_item_id,
            declaration_id: child_item.declaration_id,
            decision: "reused",
            reason: "owner, authority, criteria, evidence identity, and dependencies revalidated",
            evidence_refs: parent_item.artifacts.copy(),
          })
        } else {
          invalidated_count += 1
          decisions.push({
            child_work_item_id: child_item.work_item_id,
            source_work_item_id: parent_item.work_item_id,
            declaration_id: child_item.declaration_id,
            decision: "invalidated",
            reason: checkpoint_identity_issue(parent_item, child_item).unwrap_or(
              "a dependency checkpoint changed or was not reusable",
            ),
            evidence_refs: parent_item.artifacts.copy(),
          })
        }
    }
  }
  let receipt = RunMigrationReceipt::{
    contract_id: "moonflow.run-migration.v1",
    migration_id,
    parent_run_id: parent.run_id,
    child_run_id: child.run_id,
    parent_revision: parent.declaration_revision,
    child_revision: child.declaration_revision,
    parent_source_digest: parent.source_digest,
    child_source_digest: child.source_digest,
    revision_proposal_ref,
    decisions,
    reused_count,
    invalidated_count,
    new_count,
    recorded_at,
  }
  let issues = receipt.quality_issues()
  if !issues.is_empty() {
    fail("invalid run migration: \{issues.join("; ")}")
  }
  { events, receipt }
}
