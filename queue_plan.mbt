///|
/// Pointers select typed fields from each JSONL queue object. Template IDs
/// must name original source items; queue data cannot declare new operations.
pub(all) struct QueuePlanMappingV1 {
  contract_id : String
  template_work_item_id_pointer : String
  work_item_id_pointer : String
  input_artifacts_pointer : String
  depends_on_pointer : String?
  acceptance_criteria_pointer : String?
  timeout_ms_pointer : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Physical line numbers are one-based and preserve the queue's input order.
pub(all) struct QueuePlanEntryV1 {
  line_number : Int
  work_item_id : String
  template_work_item_id : String
} derive(Debug, Eq, ToJson)

///|
/// A heterogeneous JSONL queue materialized as an ordinary editable draft.
/// Retain this receipt and the original queue separately for provenance.
pub(all) struct QueuePlanImportV1 {
  contract_id : String
  queue_digest : String
  mapping_digest : String
  entries : Array[QueuePlanEntryV1]
  draft : DeclaredPlanDraftV1
} derive(Debug, Eq, ToJson)

///|
/// Import 1..256 JSON objects, one per physical line, as a mixed work queue.
/// LF/CRLF and one terminal newline are accepted; blank lines and BOM are
/// refused. Generic plan fields are mapped explicitly, and every item's
/// operation/schema/authority/claim comes exclusively from its source template.
/// No runs, approvals, payloads or adapter effects are created.
pub fn declared_plan_from_queue_v1(
  source_graph : Json,
  mapping_value : Json,
  queue_jsonl : String,
  draft_id : String,
  recorded_at : String,
) -> QueuePlanImportV1 raise {
  let bytes = @utf8.encode(queue_jsonl)
  guard bytes.length() <= 1048576 else {
    fail("JSONL queue exceeds 1,048,576 UTF-8 bytes")
  }
  guard !queue_jsonl.has_prefix("\u{FEFF}") else {
    fail("JSONL queue line 1: UTF-8 BOM is not supported")
  }
  let original = start_declared_plan_v1(
    source_graph, draft_id, "existing-graph", recorded_at,
  )
  let fields = wire_object(mapping_value, "queue plan mapping")
  let known = [
    "contract_id", "template_work_item_id_pointer", "work_item_id_pointer", "input_artifacts_pointer",
    "depends_on_pointer", "acceptance_criteria_pointer", "timeout_ms_pointer",
  ]
  let nullable = [
    "depends_on_pointer", "acceptance_criteria_pointer", "timeout_ms_pointer",
  ]
  let normalized : Map[String, Json] = {}
  for key, value in fields {
    guard known.contains(key) else {
      fail("unknown queue plan mapping field: \{key}")
    }
    if !(nullable.contains(key) && value is Null) {
      normalized[key] = value
    }
  }
  let mapping : QueuePlanMappingV1 = @json.from_json(Json::object(normalized))
  guard mapping.contract_id == "moonflow.queue-plan-mapping.v1" else {
    fail("unsupported queue plan mapping contract")
  }
  let lines = queue_jsonl.split("\n").to_array()
  let count = if queue_jsonl.has_suffix("\n") {
    lines.length() - 1
  } else {
    lines.length()
  }
  guard count > 0 && count <= 256 else {
    fail("JSONL queue import requires 1..256 object lines")
  }
  let edits : Array[PlanItemEditV1] = []
  let templates : Map[String, String] = {}
  let entries : Array[QueuePlanEntryV1] = []
  for index in 0..<count {
    let label = "JSONL queue line \{index + 1}"
    let line = lines[index].to_string()
    guard !line.trim().is_empty() else {
      fail("\{label}: blank lines are not allowed")
    }
    let record = @json.parse(line, max_nesting_depth=64) catch {
      error => fail("\{label}: invalid JSON: \{error}")
    }
    guard record is Object(_) else { fail("\{label} must be an object") }
    guard records_plan_select(
        record,
        mapping.template_work_item_id_pointer,
        label,
      )
      is String(template_id) else {
      fail("\{label} template_work_item_id must select a string")
    }
    guard original.edits.filter(edit => edit.work_item_id == template_id).get(0)
      is Some(template) else {
      fail("\{label}: template is not an original source item: \{template_id}")
    }
    guard records_plan_select(record, mapping.work_item_id_pointer, label)
      is String(id) else {
      fail("\{label} work_item_id must select a string")
    }
    guard !original.edits.any(edit => edit.work_item_id == id) else {
      fail("\{label} must use a new work_item_id, not a source ID: \{id}")
    }
    guard !templates.contains(id) else {
      fail("\{label}: duplicate work_item_id: \{id}")
    }
    let inputs = records_plan_strings(
      records_plan_select(record, mapping.input_artifacts_pointer, label),
      "\{label} input_artifacts",
    )
    let dependencies = match mapping.depends_on_pointer {
      Some(pointer) =>
        records_plan_strings(
          records_plan_select(record, pointer, label),
          "\{label} depends_on",
        )
      None => []
    }
    let criteria = match mapping.acceptance_criteria_pointer {
      Some(pointer) =>
        records_plan_strings(
          records_plan_select(record, pointer, label),
          "\{label} acceptance_criteria",
        )
      None => template.acceptance_criteria.copy()
    }
    let timeout_ms = match mapping.timeout_ms_pointer {
      Some(pointer) => {
        let selected = records_plan_select(record, pointer, label)
        guard selected is Number(number, ..) &&
          number >= 1.0 &&
          number <= 86400000.0 &&
          number.to_int().to_double() == number else {
          fail("\{label} timeout_ms must select a whole number in 1..86400000")
        }
        number.to_int()
      }
      None => template.timeout_ms
    }
    edits.push({
      work_item_id: id,
      input_artifacts: inputs,
      depends_on: dependencies,
      acceptance_criteria: criteria,
      timeout_ms,
    })
    templates[id] = template_id
    entries.push({
      line_number: index + 1,
      work_item_id: id,
      template_work_item_id: template_id,
    })
  }
  let draft = declared_plan_from_form_v1(
    {
      "contract_id": "moonflow.declared-plan-form-input.v2",
      "source_kind": "existing-graph",
      "source_graph": source_graph,
      "edits": edits.to_json(),
      "added_templates": templates.to_json(),
    },
    draft_id,
    recorded_at,
  ) catch {
    error => fail("JSONL queue batch: \{error}")
  }
  {
    contract_id: "moonflow.queue-plan-import.v1",
    queue_digest: "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
    mapping_digest: plan_digest(mapping_value),
    entries,
    draft,
  }
}
