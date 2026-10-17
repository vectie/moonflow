///|
/// A left-preserving keyed dataset join and the ordinary editable workflow it
/// prepares. All data is detached; this function performs no effects.
pub(all) struct JoinedWorkflowPlanImportV1 {
  contract_id : String
  primary_digest : String
  lookup_digest : String
  join_digest : String
  joined_records : Array[Json]
  unmatched_primary_rows : Array[Int]
  unused_lookup_rows : Array[Int]
  workflow : WorkflowPayloadPlanImportV1
} derive(Debug, Eq, ToJson)

///|
fn joined_workflow_key(
  value : Json,
  pointer : String,
  label : String,
) -> String raise {
  let selected = records_plan_select(value, pointer, label)
  match selected {
    String(_) | Number(_) | True | False => selected.stringify()
    _ => fail("\{label} join key must be a string, number or boolean")
  }
}

///|
/// Enrich each primary record with at most one explicit reference record before
/// generating a complete per-record workflow. Keys are typed scalar identities;
/// numbers use exact source spelling, never floating rounding or string coercion. Unmatched primary rows
/// either reject the batch or retain a null lookup, according to the join spec.
pub fn declared_plan_from_joined_workflow_v1(
  source_graph : Json,
  workflow_value : Json,
  join_value : Json,
  primary_json : String,
  lookup_json : String,
  draft_id : String,
  recorded_at : String,
) -> JoinedWorkflowPlanImportV1 raise {
  guard primary_json.length() <= 1048576 && lookup_json.length() <= 1048576 else {
    fail("each join dataset must be at most 1,048,576 characters")
  }
  let fields = wire_object(join_value, "workflow join specification")
  let known = [
    "contract_id", "primary_records_pointer", "lookup_records_pointer", "primary_key_pointer",
    "lookup_key_pointer", "unmatched",
  ]
  for key, _ in fields {
    guard known.contains(key) else {
      fail("unknown workflow join field: \{key}")
    }
  }
  guard wire_string(fields, "contract_id") == "moonflow.workflow-record-join.v1" else {
    fail("unsupported workflow join contract")
  }
  let unmatched = wire_string(fields, "unmatched")
  guard unmatched == "error" || unmatched == "null" else {
    fail("unmatched must explicitly be error or null")
  }
  let primary_pointer = payload_pointer_field(fields, "primary_records_pointer")
  let lookup_pointer = payload_pointer_field(fields, "lookup_records_pointer")
  let primary_key = payload_pointer_field(fields, "primary_key_pointer")
  let lookup_key = payload_pointer_field(fields, "lookup_key_pointer")
  ignore(records_plan_pointer_tokens(primary_key))
  ignore(records_plan_pointer_tokens(lookup_key))
  // Share the established raw JSON reader: ordinary floating parsing can merge
  // distinct decimal keys before the join gets a chance to compare them.
  let primary_value = mermaid_parse_json(primary_json)
  let lookup_value = mermaid_parse_json(lookup_json)
  guard records_plan_select(primary_value, primary_pointer, "primary dataset")
    is Array(primary) &&
    !primary.is_empty() &&
    primary.length() <= 256 else {
    fail("primary dataset must select 1..256 records")
  }
  guard records_plan_select(lookup_value, lookup_pointer, "lookup dataset")
    is Array(lookup) &&
    lookup.length() <= 4096 else {
    fail("lookup dataset must select at most 4096 records")
  }
  let workflow_fields = wire_object(
    workflow_value, "workflow payload specification",
  )
  guard payload_pointer_field(workflow_fields, "records_pointer") == "" else {
    fail("joined workflow records_pointer must select the joined root array")
  }
  let index : Map[String, Int] = {}
  for row, record in lookup {
    guard record is Object(_) else {
      fail("lookup row \{row + 1} must be an object")
    }
    let key = joined_workflow_key(record, lookup_key, "lookup row \{row + 1}")
    guard !index.contains(key) else {
      fail(
        "lookup row \{row + 1} duplicates an earlier join key; select one reference row explicitly",
      )
    }
    index[key] = row
  }
  let records : Array[Json] = []
  let unmatched_rows : Array[Int] = []
  let used : Map[Int, Bool] = {}
  for row, record in primary {
    guard record is Object(_) else {
      fail("primary row \{row + 1} must be an object")
    }
    let key = joined_workflow_key(record, primary_key, "primary row \{row + 1}")
    let selected = match index.get(key) {
      Some(position) => {
        used[position] = true
        lookup[position]
      }
      None => {
        guard unmatched == "null" else {
          fail("primary row \{row + 1} has no matching lookup record")
        }
        unmatched_rows.push(row + 1)
        Json::null()
      }
    }
    records.push({ "primary": record, "lookup": selected })
  }
  let unused : Array[Int] = []
  for row in 0..<lookup.length() {
    if !used.contains(row) {
      unused.push(row + 1)
    }
  }
  let workflow = declared_plan_from_workflow_payloads_v1(
    source_graph,
    workflow_value,
    records.to_json().stringify(),
    draft_id,
    recorded_at,
  )
  {
    contract_id: "moonflow.joined-workflow-plan-import.v1",
    primary_digest: "sha256:" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(primary_json))),
    lookup_digest: "sha256:" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(lookup_json))),
    join_digest: plan_digest(join_value),
    joined_records: records,
    unmatched_primary_rows: unmatched_rows,
    unused_lookup_rows: unused,
    workflow,
  }
}
