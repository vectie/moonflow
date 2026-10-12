///|
/// A read-only observation of one exact run revision and event head.
/// It is not a live-status guarantee or an execution/retry permission.
pub(all) struct OwnerSummaryV1 {
  contract_id : String
  run_id : String
  book_id : String
  declaration_revision : String
  source_digest : String
  last_sequence : Int
  last_event_id : String?
  recorded_at : String?
  outcome : String
  outcome_label : String
  next_action : String
  next_actor_id : String?
  next_role : String?
  actions : Array[OwnerActionV1]
  evidence : Array[OwnerEvidenceV1]
  acceptance_boundary : String
} derive(Debug, Eq, ToJson)

///|
pub(all) struct OwnerActionV1 {
  work_item_id : String
  product_id : String
  status : String
  action : String
  next_actor_id : String?
  next_role : String?
  reasons : Array[String]
  depends_on : Array[String]
} derive(Debug, Eq, ToJson)

///|
pub(all) struct OwnerEvidenceV1 {
  work_item_id : String
  attempt_id : String
  result_id : String
  output_digest : String
  artifacts : Array[String]
  review_id : String
  review_artifact : String
  reviewer_id : String
} derive(Debug, Eq, ToJson)

///|
fn owner_action_v1(
  projection : RunProjection,
  item : RuntimeItem,
) -> OwnerActionV1? {
  if item.status == Accepted {
    return None
  }
  let reasons : Array[String] = []
  if !item.blocker.trim().is_empty() {
    reasons.push(item.blocker)
  }
  if !item.error_kind.trim().is_empty() && !reasons.contains(item.error_kind) {
    reasons.push(item.error_kind)
  }
  let dependencies : Array[String] = []
  for id in item.depends_on {
    match projection.find_item(id) {
      Some(dependency) if dependency.status == Accepted => ()
      dependency => {
        dependencies.push(id)
        let dependency_state = match dependency {
          Some(value) => value.status.id()
          None => "dependency not recorded"
        }
        reasons.push("Waiting for " + id + ": " + dependency_state)
      }
    }
  }
  let (action, role) : (String, String?) = if item.attempt_status == "unknown" {
    ("Reconcile the unknown outcome before any retry", Some("run operator"))
  } else {
    match item.status {
      Review =>
        ("Review the output against the acceptance criteria", Some("reviewer"))
      Failed =>
        (
          "Inspect the failure and determine a governed recovery",
          Some("run operator"),
        )
      Blocked => ("Resolve the recorded blocker", None)
      Waiting => ("Resolve the wait or obtain the missing evidence", None)
      Ready =>
        (
          "Continue through the existing execution controls",
          Some("run operator"),
        )
      Active =>
        (
          "Wait for the current attempt and reconcile its result",
          Some("execution adapter"),
        )
      Proposed =>
        if dependencies.is_empty() {
          (
            "Check readiness through the existing controls",
            Some("run operator"),
          )
        } else {
          ("Resolve the unmet dependencies", None)
        }
      Cancelled =>
        (
          "Inspect the cancellation before deciding on new work",
          Some("run operator"),
        )
      Superseded =>
        (
          "Open the replacement revision before continuing",
          Some("run operator"),
        )
      Accepted => ("No next action recorded", None)
    }
  }
  if reasons.is_empty() {
    reasons.push(
      match item.status {
        Review =>
          "Internal review is required; execution success is not acceptance"
        Ready =>
          "Dependencies are accepted; execution remains subject to existing authority checks"
        Active =>
          "No completed, reviewed result has been recorded for the current attempt"
        Failed =>
          "Failure recorded without a reason; retry eligibility has not been established"
        Blocked => "Blocked without a recorded reason"
        Waiting => "Waiting without a recorded reason"
        Proposed => "Readiness has not been recorded"
        Cancelled => "This work was cancelled"
        Superseded => "This work was superseded"
        Accepted => "Internal work acceptance recorded"
      },
    )
  }
  Some({
    work_item_id: item.work_item_id,
    product_id: item.product_id,
    status: if item.attempt_status == "unknown" {
      "unknown"
    } else {
      item.status.id()
    },
    action,
    // Runtime events do not carry a next-person assignment. A product,
    // approval authority or previous reviewer must not become an assignee.
    next_actor_id: None,
    next_role: role,
    reasons,
    depends_on: dependencies,
  })
}

///|
/// Project the current event-derived facts without changing the run.
/// Attention states precede review, waits, execution and terminal history.
/// Registration order is retained within each group; dependency reasons retain
/// the graph's declared order. Arrays are copied so the result is a snapshot.
///
/// ```mbt check
/// test {
///   let summary = @moonflow.owner_summary_v1(
///     @moonflow.empty_projection("new-run"),
///   )
///   assert_eq(summary.contract_id, "moonflow.owner-summary.v1")
///   assert_true(summary.next_actor_id is None)
/// }
/// ```
pub fn owner_summary_v1(projection : RunProjection) -> OwnerSummaryV1 {
  let actions : Array[OwnerActionV1] = []
  let candidates = projection.items.filter_map(item => {
    owner_action_v1(projection, item)
  })
  for
    status in [
      "unknown", "failed", "blocked", "review", "waiting", "ready", "active", "proposed",
      "cancelled", "superseded",
    ] {
    for candidate in candidates {
      if candidate.status == status {
        actions.push(candidate)
      }
    }
  }
  let head = projection.applied_events.last()
  let outcome_label = match projection.outcome {
    "accepted" => "Internal work accepted for this revision"
    "review" => "Output awaits internal review"
    "failed" => "Work failed; recovery needs a decision"
    "blocked" => "Work is blocked"
    "active" => "Work is running"
    "ready" => "Work is ready for governed execution"
    "waiting" => "Work is waiting"
    "proposed" => "Readiness has not been established"
    _ => "Outcome is unknown"
  }
  {
    contract_id: "moonflow.owner-summary.v1",
    run_id: projection.run_id,
    book_id: projection.book_id,
    declaration_revision: projection.declaration_revision,
    source_digest: projection.source_digest,
    last_sequence: projection.last_sequence,
    last_event_id: head.map(event => event.event_id),
    recorded_at: head.map(event => event.recorded_at),
    outcome: projection.outcome,
    outcome_label,
    next_action: match actions.get(0) {
      Some(action) => action.action
      None if projection.outcome == "accepted" =>
        "No further internal work action is recorded for this revision"
      None => "Inspect the run evidence; no next action is recorded"
    },
    next_actor_id: None,
    next_role: match actions.get(0) {
      Some(action) => action.next_role
      None => None
    },
    actions,
    evidence: projection.items.map(item => {
      work_item_id: item.work_item_id,
      attempt_id: item.active_attempt_id,
      result_id: item.result_id,
      output_digest: item.output_digest,
      artifacts: item.artifacts.copy(),
      review_id: item.acceptance_review_id,
      review_artifact: item.acceptance_review_artifact,
      reviewer_id: item.acceptance_reviewer_id,
    }),
    acceptance_boundary: "Internal work acceptance does not establish customer approval, delivery acceptance or payment",
  }
}

///|
/// Exact snapshot comparison rejects earlier sequences, changed revisions,
/// changed evidence and summaries copied from a different run.
pub fn owner_summary_is_current_v1(
  summary : OwnerSummaryV1,
  projection : RunProjection,
) -> Bool {
  summary == owner_summary_v1(projection)
}

///|
/// The compact CLI form uses the same labels and ordering as the host payload.
pub fn owner_summary_text_v1(summary : OwnerSummaryV1) -> String {
  let lines = [summary.outcome_label, "Next: " + summary.next_action]
  for action in summary.actions {
    lines.push(action.work_item_id + ": " + action.action)
    lines.push(
      "  Next role: " +
      action.next_role.unwrap_or("unknown") +
      "; owner: " +
      action.next_actor_id.unwrap_or("unknown"),
    )
    for reason in action.reasons {
      lines.push("  - " + reason)
    }
  }
  lines.push(
    "Revision " +
    summary.declaration_revision +
    " | run " +
    summary.run_id +
    " | sequence " +
    summary.last_sequence.to_string(),
  )
  lines.push(
    "Event " +
    summary.last_event_id.unwrap_or("unknown") +
    " | recorded " +
    summary.recorded_at.unwrap_or("unknown"),
  )
  lines.push("Source " + summary.source_digest)
  for evidence in summary.evidence {
    lines.push(
      evidence.work_item_id +
      " | attempt " +
      evidence.attempt_id +
      " | result " +
      evidence.result_id +
      " | output " +
      evidence.output_digest,
    )
    for artifact in evidence.artifacts {
      lines.push("  Artifact: " + artifact)
    }
    if !evidence.review_artifact.is_empty() {
      lines.push(
        "  Review: " +
        evidence.review_artifact +
        " | reviewer " +
        evidence.reviewer_id,
      )
    }
  }
  lines.push(summary.acceptance_boundary)
  lines.join("\n")
}
