///|
/// A complete worksheet edit, ready for the ordinary plan inspection and
/// preparation path. Changed IDs and edits follow the original graph order.
pub(all) struct PlanWorksheetImportV1 {
  contract_id : String
  csv_digest : String
  row_count : Int
  changed_item_ids : Array[String]
  draft : DeclaredPlanDraftV1
} derive(Debug, Eq, ToJson)

///|
fn plan_worksheet_headers() -> Array[String] {
  [
    "source_graph_digest", "work_item_id", "product_id", "operation", "input_artifacts",
    "depends_on", "acceptance_criteria", "timeout_ms",
  ]
}

///|
/// Export an existing graph for whole-workflow editing. Array cells contain
/// JSON, retaining commas, newlines, whitespace and Unicode without guessing
/// list separators. Every source item occurs exactly once.
pub fn declared_plan_worksheet_csv_v1(source_graph : Json) -> String raise {
  let original = start_declared_plan_v1(
    source_graph,
    "worksheet-export",
    "existing-graph",
    wire_string(wire_object(source_graph, "source graph"), "recorded_at"),
  )
  guard original.edits.length() <= 256 else {
    fail("worksheet source must contain at most 256 work items")
  }
  let items = events_from_work_graph(source_graph).filter(event => {
    event.kind == ItemRegistered
  })
  let rows = [plan_worksheet_headers().join(",")]
  for item in items {
    rows.push(
      [
        original.source_graph_digest,
        item.work_item_id,
        item.product_id,
        item.operation,
        item.input_artifacts.to_json().stringify(),
        item.depends_on.to_json().stringify(),
        item.acceptance_criteria.to_json().stringify(),
        item.timeout_ms.to_string(),
      ]
      .map(results_csv_cell)
      .join(","),
    )
  }
  let csv = rows.join("\n") + "\n"
  guard csv.length() <= 1048576 else {
    fail("worksheet CSV exceeds 1,048,576 characters")
  }
  csv
}

///|
fn plan_worksheet_list(cell : String, label : String) -> Array[String] raise {
  let value = @json.parse(cell) catch {
    _ => fail("worksheet \{label} must be a JSON array of strings")
  }
  guard value is Array(values) else {
    fail("worksheet \{label} must be a JSON array of strings")
  }
  values.map(value => {
    guard value is String(text) else {
      fail("worksheet \{label} must be a JSON array of strings")
    }
    text
  })
}

///|
/// Import all edits together so dependency rewiring never passes through a
/// partially edited graph. Source identity and read-only operation columns
/// must match; rows may be sorted but cannot add, omit or rename source items.
pub fn declared_plan_from_worksheet_v1(
  source_graph : Json,
  csv : String,
  draft_id : String,
  recorded_at : String,
) -> PlanWorksheetImportV1 raise {
  let original = start_declared_plan_v1(
    source_graph, draft_id, "existing-graph", recorded_at,
  )
  guard original.edits.length() <= 256 else {
    fail("worksheet source must contain at most 256 work items")
  }
  let items = events_from_work_graph(source_graph).filter(event => {
    event.kind == ItemRegistered
  })
  let records = plan_csv_records(csv, preserve_quoted_cr=true)
  let headers = records[0].map(value => value.trim().to_string())
  plan_unique_strings(headers, "worksheet header", nonempty=true)
  let expected_headers = plan_worksheet_headers()
  guard headers.length() == expected_headers.length() &&
    expected_headers.all(header => headers.contains(header)) else {
    fail(
      "worksheet requires exactly these columns: " + expected_headers.join(","),
    )
  }
  let edits : Map[String, PlanItemEditV1] = {}
  for index in 1..<records.length() {
    let row = records[index]
    guard row.length() == headers.length() else {
      fail("worksheet record \{index + 1} has the wrong number of cells")
    }
    let cells : Map[String, String] = {}
    for column, header in headers {
      cells[header] = row[column]
    }
    let id = cells["work_item_id"]
    guard !edits.contains(id) else {
      fail("duplicate worksheet work item: \{id}")
    }
    guard items.filter(item => item.work_item_id == id).get(0) is Some(item) else {
      fail("unknown worksheet work item: \{id}")
    }
    guard cells["source_graph_digest"] == original.source_graph_digest else {
      fail("worksheet source graph changed; export the selected graph again")
    }
    guard cells["product_id"] == item.product_id &&
      cells["operation"] == item.operation else {
      fail("worksheet product_id and operation are read-only for \{id}")
    }
    let timeout = cells["timeout_ms"].trim().to_string()
    guard !timeout.is_empty() &&
      timeout.to_array().all(c => c >= '0' && c <= '9') else {
      fail("worksheet timeout_ms for \{id} must be a whole number")
    }
    edits[id] = {
      work_item_id: id,
      input_artifacts: plan_worksheet_list(
        cells["input_artifacts"],
        "input_artifacts for \{id}",
      ),
      depends_on: plan_worksheet_list(
        cells["depends_on"],
        "depends_on for \{id}",
      ),
      acceptance_criteria: plan_worksheet_list(
        cells["acceptance_criteria"],
        "acceptance_criteria for \{id}",
      ),
      timeout_ms: @string.parse_int(timeout),
    }
  }
  guard edits.length() == original.edits.length() else {
    fail("worksheet must retain every source work item exactly once")
  }
  let ordered = original.edits.map(edit => edits[edit.work_item_id])
  let draft = declared_plan_from_form_v1(
    {
      "contract_id": "moonflow.declared-plan-form-input.v1",
      "source_kind": "existing-graph",
      "source_graph": source_graph,
      "edits": ordered.to_json(),
    },
    draft_id,
    recorded_at,
  )
  {
    contract_id: "moonflow.plan-worksheet-import.v1",
    csv_digest: "sha256:" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(csv))),
    row_count: ordered.length(),
    changed_item_ids: original.edits
    .filter(edit => edits[edit.work_item_id] != edit)
    .map(edit => edit.work_item_id),
    draft,
  }
}
