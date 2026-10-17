///|
/// One generated JSON request. The digest covers the exact UTF-8 json_text,
/// including its trailing newline; the ordinary plan references these bytes.
pub(all) struct PayloadPlanArtifactV1 {
  work_item_id : String
  artifact_ref : String
  sha256 : String
  json_text : String
} derive(Debug, Eq, ToJson)

///|
/// Typed record values applied to an explicit request template, alongside the
/// ordinary editable plan. This pure result performs no filesystem writes.
pub(all) struct PayloadPlanImportV1 {
  contract_id : String
  records_digest : String
  mapping_digest : String
  template_digest : String
  artifacts : Array[PayloadPlanArtifactV1]
  draft : DeclaredPlanDraftV1
} derive(Debug, Eq, ToJson)

///|
fn payload_pointer_field(
  fields : Map[String, Json],
  name : String,
) -> String raise {
  guard fields.get(name) is Some(String(pointer)) else {
    fail("\{name} must be a JSON Pointer string")
  }
  pointer
}

///|
fn payload_pointer_prefix(left : Array[String], right : Array[String]) -> Bool {
  if left.length() > right.length() {
    return false
  }
  for index, token in left {
    if right[index] != token {
      return false
    }
  }
  true
}

///|
// The template is already detached. Only existing locations may be replaced;
// selecting first also validates canonical array indices and all parent paths.
fn payload_replace(
  value : Json,
  pointer : String,
  replacement : Json,
) -> Unit raise {
  ignore(records_plan_select(value, pointer, "request template"))
  let tokens = records_plan_pointer_tokens(pointer)
  let mut parent = value
  for i = 0; i < tokens.length() - 1; i = i + 1 {
    parent = match parent {
      Object(fields) => fields[tokens[i]]
      Array(values) => values[@string.parse_int(tokens[i])]
      _ => fail("request target traverses a scalar")
    }
  }
  let key = tokens[tokens.length() - 1]
  match parent {
    Object(fields) => fields[key] = replacement
    Array(values) => values[@string.parse_int(key)] = replacement
    _ => fail("request target traverses a scalar")
  }
}

///|
/// Materialize one JSON input per record by replacing explicitly mapped,
/// existing template locations. Values retain JSON types; strings are never
/// interpolated or evaluated. Operation declarations remain source-owned.
pub fn declared_plan_from_payloads_v1(
  source_graph : Json,
  mapping_value : Json,
  request_template : Json,
  records_json : String,
  draft_id : String,
  recorded_at : String,
) -> PayloadPlanImportV1 raise {
  guard records_json.length() <= 1048576 else {
    fail("payload records export exceeds 1,048,576 characters")
  }
  guard request_template is Object(_) else {
    fail("request template must be a JSON object")
  }
  let template_text = request_template.stringify()
  guard template_text.length() <= 1048576 else {
    fail("request template exceeds 1,048,576 characters")
  }
  let fields = wire_object(mapping_value, "payload plan mapping")
  let optional = [
    "depends_on_pointer", "acceptance_criteria_pointer", "timeout_ms_pointer", "additional_input_artifacts_pointer",
  ]
  let required = [
    "contract_id", "records_pointer", "template_work_item_id", "work_item_id_pointer",
    "bindings",
  ]
  for key, _ in fields {
    guard required.contains(key) || optional.contains(key) else {
      fail("unknown payload plan mapping field: \{key}")
    }
  }
  guard wire_string(fields, "contract_id") == "moonflow.payload-plan-mapping.v1" else {
    fail("unsupported payload plan mapping contract")
  }
  let records_pointer = payload_pointer_field(fields, "records_pointer")
  let template_id = wire_string(fields, "template_work_item_id")
  let id_pointer = payload_pointer_field(fields, "work_item_id_pointer")
  guard fields.get("bindings") is Some(Array(bindings)) &&
    !bindings.is_empty() &&
    bindings.length() <= 64 else {
    fail("payload mapping requires 1..64 bindings")
  }
  let targets : Array[String] = []
  let target_tokens : Array[Array[String]] = []
  let selectors : Array[String] = []
  for binding in bindings {
    let values = wire_object(binding, "payload binding")
    for key, _ in values {
      guard key == "target_pointer" || key == "value_pointer" else {
        fail("unknown payload binding field: \{key}")
      }
    }
    let target = payload_pointer_field(values, "target_pointer")
    let selector = payload_pointer_field(values, "value_pointer")
    let tokens = records_plan_pointer_tokens(target)
    guard !tokens.is_empty() else {
      fail("payload target cannot replace the request root")
    }
    ignore(records_plan_select(request_template, target, "request template"))
    ignore(records_plan_pointer_tokens(selector))
    for prior in target_tokens {
      guard !payload_pointer_prefix(prior, tokens) &&
        !payload_pointer_prefix(tokens, prior) else {
        fail("payload targets must be distinct and non-overlapping: \{target}")
      }
    }
    targets.push(target)
    target_tokens.push(tokens)
    selectors.push(selector)
  }
  let selected_options : Map[String, String] = {}
  for name in optional {
    match fields.get(name) {
      None | Some(Null) => ()
      Some(String(pointer)) => {
        ignore(records_plan_pointer_tokens(pointer))
        selected_options[name] = pointer
      }
      _ => fail("\{name} must be a JSON Pointer string or null")
    }
  }
  let input = mermaid_parse_json(records_json)
  guard records_plan_select(input, records_pointer, "records") is Array(records) &&
    !records.is_empty() &&
    records.length() <= 256 else {
    fail("payload import requires 1..256 records")
  }
  let artifacts : Array[PayloadPlanArtifactV1] = []
  let normalized : Array[Json] = []
  let mut total_bytes = 0
  for index, record in records {
    let label = "record \{index + 1}"
    guard record is Object(_) else { fail("\{label} must be an object") }
    guard records_plan_select(record, id_pointer, label) is String(id) else {
      fail("\{label} work_item_id must select a string")
    }
    let payload = @json.parse(template_text, max_nesting_depth=64)
    for binding_index, target in targets {
      let selected = records_plan_select(
        record,
        selectors[binding_index],
        label,
      )
      payload_replace(payload, target, selected)
    }
    let json_text = plan_canonical_json(payload) + "\n"
    let bytes = @utf8.encode(json_text)
    total_bytes += bytes.length()
    guard bytes.length() <= 1048576 && total_bytes <= 8388608 else {
      fail("generated requests exceed 1 MiB per file or 8 MiB per import")
    }
    let digest = @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
    let artifact_ref = ".moonsuite/products/moonflow/plan-inputs/" +
      digest +
      "/artifact"
    let inputs = [artifact_ref]
    if selected_options.get("additional_input_artifacts_pointer")
      is Some(pointer) {
      inputs.append(
        records_plan_strings(records_plan_select(record, pointer, label), label),
      )
    }
    let row : Map[String, Json] = {
      "id": id.to_json(),
      "inputs": inputs.to_json(),
    }
    for name, pointer in selected_options {
      if name != "additional_input_artifacts_pointer" {
        row[name] = records_plan_select(record, pointer, label)
      }
    }
    normalized.push(Json::object(row))
    artifacts.push({
      work_item_id: id,
      artifact_ref,
      sha256: "sha256:" + digest,
      json_text,
    })
  }
  let record_mapping : Map[String, Json] = {
    "contract_id": "moonflow.records-plan-mapping.v1",
    "records_pointer": "",
    "template_work_item_id": template_id.to_json(),
    "work_item_id_pointer": "/id",
    "input_artifacts_pointer": "/inputs",
  }
  for name, _ in selected_options {
    if name != "additional_input_artifacts_pointer" {
      record_mapping[name] = ("/" + name).to_json()
    }
  }
  let imported = declared_plan_from_records_v1(
    source_graph,
    Json::object(record_mapping),
    normalized.to_json().stringify(),
    draft_id,
    recorded_at,
  )
  {
    contract_id: "moonflow.payload-plan-import.v1",
    records_digest: "sha256:" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(records_json))),
    mapping_digest: plan_digest(mapping_value),
    template_digest: plan_digest(request_template),
    artifacts,
    draft: imported.draft,
  }
}
