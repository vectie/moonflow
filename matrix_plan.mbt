///|
/// An explicit parameter matrix and its materialized ordinary editable plan.
/// Combination records are detached from the caller's JSON. No effects run.
pub(all) struct MatrixPlanImportV1 {
  contract_id : String
  matrix_digest : String
  combinations : Array[Json]
  payloads : PayloadPlanImportV1
} derive(Debug, Eq, ToJson)

///|
fn matrix_plan_key(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 64 &&
  !value.contains("--") &&
  value
  .to_array()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_' ||
    c == '-'
  }) &&
  !value.has_prefix("-") &&
  !value.has_suffix("-")
}

///|
/// Expand the declared Cartesian product, with the last axis varying fastest.
/// Keys name combinations; JSON values retain their types and are applied only
/// through explicit request-template bindings. The source operation is frozen.
pub fn declared_plan_from_matrix_v1(
  source_graph : Json,
  matrix_value : Json,
  request_template : Json,
  draft_id : String,
  recorded_at : String,
) -> MatrixPlanImportV1 raise {
  let matrix_text = matrix_value.stringify()
  guard matrix_text.length() <= 1048576 else {
    fail("matrix exceeds 1,048,576 characters")
  }
  let matrix = @json.parse(matrix_text, max_nesting_depth=64)
  let fields = wire_object(matrix, "matrix plan")
  for key, _ in fields {
    guard [
      "contract_id", "item_prefix", "template_work_item_id", "axes", "bindings",
    ].contains(key) else {
      fail("unknown matrix field: \{key}")
    }
  }
  guard wire_string(fields, "contract_id") == "moonflow.matrix-plan.v1" else {
    fail("unsupported matrix plan contract")
  }
  let prefix = wire_string(fields, "item_prefix")
  guard matrix_plan_key(prefix) else {
    fail("matrix item_prefix must be a safe key without '--' or edge hyphens")
  }
  let template_id = wire_string(fields, "template_work_item_id")
  guard fields.get("axes") is Some(Array(axes)) &&
    !axes.is_empty() &&
    axes.length() <= 8 else {
    fail("matrix requires 1..8 axes")
  }
  let names : Array[String] = []
  let choices : Array[Array[Json]] = []
  let mut count = 1
  for axis in axes {
    let axis_fields = wire_object(axis, "matrix axis")
    for key, _ in axis_fields {
      guard key == "name" || key == "values" else {
        fail("unknown matrix axis field: \{key}")
      }
    }
    let name = wire_string(axis_fields, "name")
    guard table_plan_column_name(name) &&
      name.length() <= 64 &&
      !names.contains(name) else {
      fail("matrix axis names must be distinct letters/digits/underscore names")
    }
    guard axis_fields.get("values") is Some(Array(values)) &&
      !values.is_empty() &&
      values.length() <= 256 else {
      fail("matrix axis \{name} requires 1..256 keyed values")
    }
    guard count <= 256 / values.length() else {
      fail("matrix Cartesian product exceeds 256 combinations")
    }
    count *= values.length()
    let keys : Array[String] = []
    for choice in values {
      let value_fields = wire_object(choice, "matrix choice")
      for key, _ in value_fields {
        guard key == "key" || key == "value" else {
          fail("unknown matrix choice field: \{key}")
        }
      }
      let key = wire_string(value_fields, "key")
      guard matrix_plan_key(key) && !keys.contains(key) else {
        fail(
          "matrix choice keys must be distinct safe keys without '--' or edge hyphens",
        )
      }
      guard value_fields.contains("value") else {
        fail("matrix choice \{key} requires value; explicit null is allowed")
      }
      keys.push(key)
    }
    names.push(name)
    choices.push(values)
  }
  guard fields.get("bindings") is Some(bindings) else {
    fail("matrix requires explicit payload bindings")
  }
  let records : Array[Json] = []
  let mut record_chars = 2
  for row in 0..<count {
    let parameters : Map[String, Json] = {}
    let keys : Map[String, Json] = {}
    let parts = [prefix]
    let mut stride = count
    for axis_index, name in names {
      let values = choices[axis_index]
      stride /= values.length()
      let choice = wire_object(
        values[row / stride % values.length()],
        "matrix choice",
      )
      let key = wire_string(choice, "key")
      parts.push(key)
      keys[name] = key.to_json()
      parameters[name] = choice["value"]
    }
    let id = parts.join("--")
    guard id.length() <= 128 else {
      fail("matrix combination work_item_id exceeds 128 characters: \{id}")
    }
    let record : Json = {
      "id": id.to_json(),
      "keys": Json::object(keys),
      "parameters": Json::object(parameters),
    }
    record_chars += record.stringify().length() + (if row == 0 { 0 } else { 1 })
    guard record_chars <= 1048576 else {
      fail("expanded matrix records exceed 1,048,576 characters")
    }
    records.push(record)
  }
  let payloads = declared_plan_from_payloads_v1(
    source_graph,
    {
      "contract_id": "moonflow.payload-plan-mapping.v1",
      "records_pointer": "",
      "work_item_id_pointer": "/id",
      "template_work_item_id": template_id.to_json(),
      "bindings": bindings,
    },
    request_template,
    records.to_json().stringify(),
    draft_id,
    recorded_at,
  )
  {
    contract_id: "moonflow.matrix-plan-import.v1",
    matrix_digest: plan_digest(matrix),
    combinations: records,
    payloads,
  }
}
