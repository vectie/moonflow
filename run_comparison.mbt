///|
/// One stable declaration, paired across two runs. A missing side is explicit
/// null in JSON. Item snapshots retain exact recorded references and values.
pub(all) struct RunComparisonRowV1 {
  declaration_id : String
  change : String
  changed_fields : Array[String]
  before : Json?
  after : Json?
  retained_artifacts_added : Array[String]
  retained_artifacts_removed : Array[String]
} derive(Debug, Eq)

///|
pub impl ToJson for RunComparisonRowV1 with fn to_json(self) -> Json {
  {
    "declaration_id": self.declaration_id,
    "change": self.change,
    "changed_fields": self.changed_fields.to_json(),
    "before": self.before.unwrap_or(Json::null()),
    "after": self.after.unwrap_or(Json::null()),
    "retained_artifacts_added": self.retained_artifacts_added.to_json(),
    "retained_artifacts_removed": self.retained_artifacts_removed.to_json(),
  }
}

///|
/// Direction is caller-selected, not a verified ancestry or time ordering.
/// Heads are two independent observations of the same book, not one transaction.
pub(all) struct RunComparisonV1 {
  contract_id : String
  before_head : ResultsRunV1
  after_head : ResultsRunV1
  added_count : Int
  removed_count : Int
  changed_count : Int
  unchanged_count : Int
  rows : Array[RunComparisonRowV1]
} derive(Debug, Eq, ToJson)

///|
fn run_comparison_snapshot(item : RuntimeItem) -> Json raise {
  let state = wire_object(run_history_state(item).to_json(), "item state")
  state["work_item_id"] = item.work_item_id.to_json()
  state["requested_authority"] = item.requested_authority.to_json()
  state["acceptance_criteria"] = item.acceptance_criteria.to_json()
  state["input_contracts"] = item.input_contracts.to_json()
  state["output_contracts"] = item.output_contracts.to_json()
  state["required_claim"] = item.required_claim.to_json()
  state["input_artifacts"] = item.input_artifacts.to_json()
  state["timeout_ms"] = item.timeout_ms.to_json()
  state["depends_on"] = item.depends_on.to_json()
  Json::object(state)
}

///|
fn run_comparison_projection(
  run_id : String,
  events : Array[RuntimeEvent],
) -> RunProjection raise {
  guard !run_id.trim().is_empty() else { fail("Select a nonblank run_id") }
  guard events.length() <= 4096 else {
    fail("Run comparison supports at most 4096 input events per run")
  }
  let run = replay(run_id, events)
  guard !run.book_id.is_empty() else {
    fail("Run comparison requires recorded run source identity: " + run_id)
  }
  guard run.items.length() <= 256 else {
    fail("Run comparison supports at most 256 items per run")
  }
  let declarations : Array[String] = []
  for item in run.items {
    guard !declarations.contains(item.declaration_id) else {
      fail(
        "Ambiguous declaration_id in run " + run_id + ": " + item.declaration_id,
      )
    }
    declarations.push(item.declaration_id)
  }
  run
}

///|
fn run_comparison_row(
  declaration_id : String,
  before : RuntimeItem?,
  after : RuntimeItem?,
) -> RunComparisonRowV1 raise {
  let before_snapshot = before.map(run_comparison_snapshot)
  let after_snapshot = after.map(run_comparison_snapshot)
  let changed_fields : Array[String] = []
  if before_snapshot is Some(b) && after_snapshot is Some(a) {
    let old = wire_object(b, "before item")
    let current = wire_object(a, "after item")
    // Fixed order is part of the report contract. Run-head metadata is excluded
    // so a new revision alone does not make every item a changed result.
    for
      key in [
        "work_item_id", "product_id", "requested_authority", "acceptance_criteria",
        "operation", "input_contracts", "output_contracts", "required_claim", "input_artifacts",
        "timeout_ms", "depends_on", "status", "attempt_count", "request_id", "attempt_id",
        "idempotency_key", "external_job_id", "attempt_status", "input_digest", "result_id",
        "output_digest", "error_kind", "compensable", "blocker", "review_id", "review_artifact",
        "reviewer_id", "retained_artifacts", "recorded_approvals",
      ] {
      if old.get(key) != current.get(key) {
        changed_fields.push(key)
      }
    }
  }
  let old_artifacts = before.map(i => i.artifacts).unwrap_or([])
  let new_artifacts = after.map(i => i.artifacts).unwrap_or([])
  {
    declaration_id,
    change: if before is None {
      "added"
    } else if after is None {
      "removed"
    } else if changed_fields.is_empty() {
      "unchanged"
    } else {
      "changed"
    },
    changed_fields,
    before: before_snapshot,
    after: after_snapshot,
    retained_artifacts_added: new_artifacts.filter(a => {
      !old_artifacts.contains(a)
    }),
    retained_artifacts_removed: old_artifacts.filter(a => {
      !new_artifacts.contains(a)
    }),
  }
}

///|
/// Replay both full event streams and compare final recorded items by exact
/// declaration_id. Preserve before registration order, then append after-only
/// declarations in after registration order. Never infer lineage from item IDs.
/// At most 4096 supplied events and 256 items per side; duplicates count toward
/// the event bound and retain the engine's usual replay semantics.
pub fn compare_run_events_v1(
  before_run_id : String,
  before_events : Array[RuntimeEvent],
  after_run_id : String,
  after_events : Array[RuntimeEvent],
) -> RunComparisonV1 raise {
  guard before_run_id != after_run_id else {
    fail("Select two distinct run IDs")
  }
  let before = run_comparison_projection(before_run_id, before_events)
  let after = run_comparison_projection(after_run_id, after_events)
  guard before.book_id == after.book_id else {
    fail("Run comparison requires the same book_id")
  }
  let before_by_declaration : Map[String, RuntimeItem] = {}
  let after_by_declaration : Map[String, RuntimeItem] = {}
  for item in before.items {
    before_by_declaration[item.declaration_id] = item
  }
  for item in after.items {
    after_by_declaration[item.declaration_id] = item
  }
  let rows : Array[RunComparisonRowV1] = []
  for item in before.items {
    rows.push(
      run_comparison_row(
        item.declaration_id,
        Some(item),
        after_by_declaration.get(item.declaration_id),
      ),
    )
  }
  for item in after.items {
    if !before_by_declaration.contains(item.declaration_id) {
      rows.push(run_comparison_row(item.declaration_id, None, Some(item)))
    }
  }
  let heads = results_table_v1([before, after]).runs
  {
    contract_id: "moonflow.run-comparison.v1",
    before_head: heads[0],
    after_head: heads[1],
    added_count: rows.filter(r => r.change == "added").length(),
    removed_count: rows.filter(r => r.change == "removed").length(),
    changed_count: rows.filter(r => r.change == "changed").length(),
    unchanged_count: rows.filter(r => r.change == "unchanged").length(),
    rows,
  }
}

///|
fn run_comparison_text_head(label : String, head : ResultsRunV1) -> String {
  label +
  " " +
  head.run_id.to_json().stringify() +
  " revision=" +
  head.declaration_revision.to_json().stringify() +
  " source=" +
  head.source_digest.to_json().stringify() +
  " outcome=" +
  head.run_outcome.to_json().stringify() +
  " head=" +
  head.last_sequence.to_string() +
  " " +
  head.last_event_id.to_json().stringify() +
  " recorded_at=" +
  head.recorded_at.to_json().stringify()
}

///|
/// Render exact before/after values for changed fields, and full item snapshots
/// for additions/removals. JSON escaping keeps arbitrary evidence on one line.
pub fn run_comparison_text_v1(report : RunComparisonV1) -> String raise {
  let lines = [
    "Book " + report.before_head.book_id.to_json().stringify(),
    run_comparison_text_head("Before", report.before_head),
    run_comparison_text_head("After", report.after_head),
    "Declarations: " +
    report.added_count.to_string() +
    " added, " +
    report.removed_count.to_string() +
    " removed, " +
    report.changed_count.to_string() +
    " changed, " +
    report.unchanged_count.to_string() +
    " unchanged.",
    "Caller-selected direction; ancestry is not verified. Each run is observed separately.",
    "Recorded internal state only; acceptance does not establish customer approval or payment.",
  ]
  for row in report.rows {
    lines.push(
      row.change + " declaration=" + row.declaration_id.to_json().stringify(),
    )
    match (row.before, row.after) {
      (Some(b), Some(a)) => {
        let old = wire_object(b, "before item")
        let current = wire_object(a, "after item")
        lines.push(
          "  item: " +
          old["work_item_id"].stringify() +
          " -> " +
          current["work_item_id"].stringify(),
        )
        for key in row.changed_fields {
          lines.push(
            "  " +
            key +
            ": " +
            old[key].stringify() +
            " -> " +
            current[key].stringify(),
          )
        }
      }
      (Some(b), None) => lines.push("  before: " + b.stringify())
      (None, Some(a)) => lines.push("  after: " + a.stringify())
      _ => ()
    }
    if !row.retained_artifacts_added.is_empty() {
      lines.push(
        "  retained_artifacts_added: " +
        row.retained_artifacts_added.to_json().stringify(),
      )
    }
    if !row.retained_artifacts_removed.is_empty() {
      lines.push(
        "  retained_artifacts_removed: " +
        row.retained_artifacts_removed.to_json().stringify(),
      )
    }
  }
  lines.join("\n")
}
