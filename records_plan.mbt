///|
/// JSON Pointers select an array from an export and typed fields from each
/// record. Optional selectors omitted from the mapping use template defaults
/// (or no dependencies); a configured selector must resolve in every record.
pub(all) struct RecordsPlanMappingV1 {
  contract_id : String
  records_pointer : String
  template_work_item_id : String
  work_item_id_pointer : String
  input_artifacts_pointer : String
  depends_on_pointer : String?
  acceptance_criteria_pointer : String?
  timeout_ms_pointer : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A JSON export expanded into the ordinary editable v2 plan draft. Digests
/// identify the raw export text and canonical mapping used for this import.
pub(all) struct RecordsPlanImportV1 {
  contract_id : String
  records_digest : String
  mapping_digest : String
  records_pointer : String
  template_work_item_id : String
  record_ids : Array[String]
  draft : DeclaredPlanDraftV1
} derive(Debug, Eq, ToJson)

///|
fn records_plan_pointer_tokens(pointer : String) -> Array[String] raise {
  if pointer.is_empty() {
    return []
  }
  guard pointer.has_prefix("/") else {
    fail("JSON Pointer must be empty or start with '/': \{pointer}")
  }
  let tokens : Array[String] = []
  for token in pointer.substring(start=1).split("/") {
    let chars = token.to_array()
    let decoded = StringBuilder()
    let mut i = 0
    while i < chars.length() {
      if chars[i] == '~' {
        match chars.get(i + 1) {
          Some('0') => decoded.write_char('~')
          Some('1') => decoded.write_char('/')
          _ => fail("JSON Pointer has an invalid '~' escape: \{pointer}")
        }
        i += 2
      } else {
        decoded.write_char(chars[i])
        i += 1
      }
    }
    tokens.push(decoded.to_string())
  }
  tokens
}

///|
fn records_plan_select(
  value : Json,
  pointer : String,
  label : String,
) -> Json raise {
  let mut current = value
  for token in records_plan_pointer_tokens(pointer) {
    current = match current {
      Object(fields) => {
        guard fields.get(token) is Some(selected) else {
          fail("\{label}: JSON Pointer does not resolve: \{pointer}")
        }
        selected
      }
      Array(values) => {
        guard !token.is_empty() &&
          (token == "0" || !token.has_prefix("0")) &&
          token.to_array().all(c => c >= '0' && c <= '9') else {
          fail(
            "\{label}: JSON Pointer requires a canonical array index: \{pointer}",
          )
        }
        let index = @string.parse_int(token) catch {
          _ =>
            fail("\{label}: JSON Pointer array index is too large: \{pointer}")
        }
        guard values.get(index) is Some(selected) else {
          fail("\{label}: JSON Pointer array index is out of range: \{pointer}")
        }
        selected
      }
      _ => fail("\{label}: JSON Pointer traverses a scalar: \{pointer}")
    }
  }
  current
}

///|
fn records_plan_strings(value : Json, label : String) -> Array[String] raise {
  guard value is Array(values) else {
    fail("\{label} must select an array of strings")
  }
  values.map(value => {
    guard value is String(text) else {
      fail("\{label} must select an array of strings")
    }
    text
  })
}

///|
/// Import nested JSON records without flattening arrays into spreadsheet
/// cells. Each record creates a new item using one exact source operation;
/// only explicitly mapped generic plan fields are editable. No payloads,
/// approvals, runs or adapter effects are created by this pure operation.
pub fn declared_plan_from_records_v1(
  source_graph : Json,
  mapping_value : Json,
  records_json : String,
  draft_id : String,
  recorded_at : String,
) -> RecordsPlanImportV1 raise {
  guard records_json.length() <= 1048576 else {
    fail("JSON records export exceeds 1,048,576 characters")
  }
  let original = start_declared_plan_v1(
    source_graph, draft_id, "existing-graph", recorded_at,
  )
  let fields = wire_object(mapping_value, "records plan mapping")
  let known = [
    "contract_id", "records_pointer", "template_work_item_id", "work_item_id_pointer",
    "input_artifacts_pointer", "depends_on_pointer", "acceptance_criteria_pointer",
    "timeout_ms_pointer",
  ]
  let nullable = [
    "depends_on_pointer", "acceptance_criteria_pointer", "timeout_ms_pointer",
  ]
  let normalized : Map[String, Json] = {}
  for key, value in fields {
    guard known.contains(key) else {
      fail("unknown records plan mapping field: \{key}")
    }
    // Derived optional record fields recognize absence, but not explicit JSON
    // null. Normalize only these selectors without mutating the supplied map;
    // the receipt still digests the original mapping for provenance.
    if !(nullable.contains(key) && value is Null) {
      normalized[key] = value
    }
  }
  let mapping : RecordsPlanMappingV1 = @json.from_json(Json::object(normalized))
  guard mapping.contract_id == "moonflow.records-plan-mapping.v1" else {
    fail("unsupported records plan mapping contract")
  }
  guard original.edits
    .filter(edit => edit.work_item_id == mapping.template_work_item_id)
    .get(0)
    is Some(template) else {
    fail(
      "records template is not an original source item: \{mapping.template_work_item_id}",
    )
  }
  let source = @json.parse(records_json, max_nesting_depth=64)
  guard records_plan_select(source, mapping.records_pointer, "records")
    is Array(records) else {
    fail("records_pointer must select a JSON array")
  }
  guard records.length() > 0 && records.length() <= 256 else {
    fail("JSON records import requires 1..256 records")
  }
  let edits : Array[PlanItemEditV1] = []
  let templates : Map[String, String] = {}
  let record_ids : Array[String] = []
  for index, record in records {
    let label = "record \{index + 1}"
    guard record is Object(_) else { fail("\{label} must be an object") }
    guard records_plan_select(record, mapping.work_item_id_pointer, label)
      is String(id) else {
      fail("\{label} work_item_id must select a string")
    }
    guard !original.edits.any(edit => edit.work_item_id == id) else {
      fail("\{label} must use a new work_item_id, not a source ID: \{id}")
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
    record_ids.push(id)
    templates[id] = mapping.template_work_item_id
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
  )
  {
    contract_id: "moonflow.records-plan-import.v1",
    records_digest: "sha256:" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(records_json))),
    mapping_digest: plan_digest(mapping_value),
    records_pointer: mapping.records_pointer,
    template_work_item_id: mapping.template_work_item_id,
    record_ids,
    draft,
  }
}
