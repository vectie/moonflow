///|
/// Recorded item state immediately before or after one applied event. Retained
/// artifacts and approvals are cumulative, not necessarily this event's evidence.
pub(all) struct RunHistoryStateV1 {
  declaration_id : String
  product_id : String
  operation : String
  status : String
  attempt_count : Int
  request_id : String
  attempt_id : String
  idempotency_key : String
  external_job_id : String
  attempt_status : String
  input_digest : String
  result_id : String
  output_digest : String
  error_kind : String
  compensable : Bool
  blocker : String
  review_id : String
  review_artifact : String
  reviewer_id : String
  retained_artifacts : Array[String]
  recorded_approvals : Array[String]
} derive(Debug, Eq, ToJson)

///|
/// `event` is the normalized known event contract, without fields inferred from
/// later state. Null item snapshots represent run-level events or pre-registration.
pub(all) struct RunHistoryEntryV1 {
  event : Json
  before : RunHistoryStateV1?
  after : RunHistoryStateV1?
  run_outcome_before : String
  run_outcome_after : String
} derive(Debug, Eq)

///|
pub(all) struct RunHistoryV1 {
  contract_id : String
  head : ResultsRunV1
  selected_work_item_id : String?
  input_event_count : Int
  canonical_event_count : Int
  duplicate_event_count : Int
  entries : Array[RunHistoryEntryV1]
} derive(Debug, Eq)

///|
pub impl ToJson for RunHistoryEntryV1 with fn to_json(self) -> Json {
  {
    "event": self.event,
    "before": self.before.map(s => s.to_json()).unwrap_or(Json::null()),
    "after": self.after.map(s => s.to_json()).unwrap_or(Json::null()),
    "run_outcome_before": self.run_outcome_before,
    "run_outcome_after": self.run_outcome_after,
  }
}

///|
pub impl ToJson for RunHistoryV1 with fn to_json(self) -> Json {
  {
    "contract_id": self.contract_id,
    "head": self.head.to_json(),
    "selected_work_item_id": self.selected_work_item_id
    .map(s => s.to_json())
    .unwrap_or(Json::null()),
    "input_event_count": self.input_event_count,
    "canonical_event_count": self.canonical_event_count,
    "duplicate_event_count": self.duplicate_event_count,
    "entries": self.entries.to_json(),
  }
}

///|
fn run_history_state(item : RuntimeItem) -> RunHistoryStateV1 {
  {
    declaration_id: item.declaration_id,
    product_id: item.product_id,
    operation: item.operation,
    status: item.status.id(),
    attempt_count: item.attempt_count,
    request_id: item.request_id,
    attempt_id: item.active_attempt_id,
    idempotency_key: item.idempotency_key,
    external_job_id: item.external_job_id,
    attempt_status: item.attempt_status,
    input_digest: item.input_digest,
    result_id: item.result_id,
    output_digest: item.output_digest,
    error_kind: item.error_kind,
    compensable: item.compensable,
    blocker: item.blocker,
    review_id: item.acceptance_review_id,
    review_artifact: item.acceptance_review_artifact,
    reviewer_id: item.acceptance_reviewer_id,
    retained_artifacts: item.artifacts.copy(),
    recorded_approvals: item.approvals.copy(),
  }
}

///|
/// Replay the entire stream once using the engine's ordinary apply contract.
/// Selection affects only returned rows, never validation or run outcomes.
/// Exact duplicate deliveries collapse; conflicting duplicates remain errors.
/// At most 4096 input events are accepted, including duplicate deliveries.
pub fn run_history_v1(
  run_id : String,
  events : Array[RuntimeEvent],
  work_item_id? : String,
) -> RunHistoryV1 raise {
  guard !run_id.trim().is_empty() else { fail("Select a nonblank run_id") }
  guard events.length() <= 4096 else {
    fail("Run history supports at most 4096 input events")
  }
  if work_item_id is Some(id) {
    guard !id.trim().is_empty() else { fail("Select a nonblank work_item_id") }
  }
  let projection = empty_projection(run_id)
  let entries : Array[RunHistoryEntryV1] = []
  for event in events {
    let before = projection.find_item(event.work_item_id).map(run_history_state)
    let run_outcome_before = projection.outcome
    let previous_sequence = projection.last_sequence
    projection.apply(event)
    if projection.last_sequence != previous_sequence &&
      (work_item_id is None || work_item_id == Some(event.work_item_id)) {
      entries.push({
        event: runtime_event_json(event),
        before,
        after: projection.find_item(event.work_item_id).map(run_history_state),
        run_outcome_before,
        run_outcome_after: projection.outcome,
      })
    }
  }
  if work_item_id is Some(id) {
    guard projection.find_item(id) is Some(_) else {
      fail("Work item is not recorded in this run: \{id}")
    }
  }
  let last = projection.applied_events.last()
  {
    contract_id: "moonflow.run-history.v1",
    head: {
      run_id,
      book_id: projection.book_id,
      declaration_revision: projection.declaration_revision,
      source_digest: projection.source_digest,
      last_sequence: projection.last_sequence,
      last_event_id: last.map(e => e.event_id).unwrap_or(""),
      recorded_at: last.map(e => e.recorded_at).unwrap_or(""),
      run_outcome: projection.outcome,
    },
    selected_work_item_id: work_item_id,
    input_event_count: events.length(),
    canonical_event_count: projection.applied_events.length(),
    duplicate_event_count: events.length() - projection.applied_events.length(),
    entries,
  }
}

///|
fn run_history_text_state(state : RunHistoryStateV1?) -> String {
  match state {
    None => "none"
    Some(s) => {
      let base = s.status + " (attempts=" + s.attempt_count.to_string() + ")"
      if s.attempt_id.is_empty() {
        base
      } else {
        base +
        " attempt=" +
        s.attempt_id.to_json().stringify() +
        " attempt_status=" +
        s.attempt_status.to_json().stringify()
      }
    }
  }
}

///|
/// Compact operator view. Quote arbitrary strings as JSON so embedded newlines
/// or control characters cannot masquerade as another timeline entry.
/// The JSON report retains complete event evidence and item snapshots.
pub fn run_history_text_v1(history : RunHistoryV1) -> String raise {
  let head = history.head
  let lines = [
    "Run " +
    head.run_id.to_json().stringify() +
    " | outcome=" +
    head.run_outcome.to_json().stringify() +
    " | event head=" +
    head.last_sequence.to_string() +
    " " +
    head.last_event_id.to_json().stringify(),
    "Book " +
    head.book_id.to_json().stringify() +
    " revision=" +
    head.declaration_revision.to_json().stringify() +
    " source=" +
    head.source_digest.to_json().stringify(),
    "Showing " +
    history.entries.length().to_string() +
    " of " +
    history.canonical_event_count.to_string() +
    " applied events; " +
    history.duplicate_event_count.to_string() +
    " duplicate deliveries omitted.",
    "Recorded internal state only; acceptance does not establish customer approval or payment.",
  ]
  if history.selected_work_item_id is Some(id) {
    lines.push("Selected work item " + id.to_json().stringify())
  }
  for entry in history.entries {
    let fields = wire_object(entry.event, "history event")
    let id = wire_string(fields, "event_id")
    let kind = wire_string(fields, "kind")
    let item_id = wire_string(fields, "work_item_id", allow_empty=true)
    let recorded_at = wire_string(fields, "recorded_at")
    lines.push(
      "#" +
      wire_int(fields, "sequence").to_string() +
      " " +
      recorded_at.to_json().stringify() +
      " " +
      kind.to_json().stringify() +
      " event=" +
      id.to_json().stringify() +
      " item=" +
      item_id.to_json().stringify(),
    )
    lines.push(
      "  item: " +
      run_history_text_state(entry.before) +
      " -> " +
      run_history_text_state(entry.after) +
      " | run: " +
      entry.run_outcome_before.to_json().stringify() +
      " -> " +
      entry.run_outcome_after.to_json().stringify(),
    )
    let evidence : Array[String] = []
    for
      key in [
        "request_id", "attempt_id", "result_id", "attempt_status", "input_digest",
        "output_digest", "artifact_id", "authority_id", "error_kind", "detail",
      ] {
      let value = wire_string(fields, key, allow_empty=true)
      if !value.is_empty() {
        evidence.push(key + "=" + value.to_json().stringify())
      }
    }
    let outputs = wire_strings(fields, "output_artifacts", required=false)
    if !outputs.is_empty() {
      evidence.push("output_artifacts=" + outputs.to_json().stringify())
    }
    if !evidence.is_empty() {
      lines.push("  event: " + evidence.join(" "))
    }
    if entry.after is Some(state) && !state.review_id.is_empty() {
      lines.push(
        "  recorded review: " +
        state.review_id.to_json().stringify() +
        " reviewer=" +
        state.reviewer_id.to_json().stringify() +
        " artifact=" +
        state.review_artifact.to_json().stringify(),
      )
    }
  }
  lines.join("\n")
}
