///|
/// A complete declared workflow repeated per explicit record, with one real
/// JSON request for every step. Dependencies are cloned within each record.
pub(all) struct WorkflowPayloadPlanImportV1 {
  contract_id : String
  records_digest : String
  workflow_digest : String
  record_ids : Array[String]
  items_per_record : Int
  artifacts : Array[PayloadPlanArtifactV1]
  draft : DeclaredPlanDraftV1
} derive(Debug, Eq, ToJson)

///|
/// Materialize typed per-step request templates without inventing operations
/// or dataflow. Binding pointers address {record, record_id, step_id,
/// work_item_id}; source dependency edges stay inside each record's workflow.
/// The pure result creates no files, runs, authority decisions or attempts.
pub fn declared_plan_from_workflow_payloads_v1(
  source_graph : Json,
  workflow_value : Json,
  records_json : String,
  draft_id : String,
  recorded_at : String,
) -> WorkflowPayloadPlanImportV1 raise {
  guard records_json.length() <= 1048576 else {
    fail("workflow records export exceeds 1,048,576 characters")
  }
  let workflow_text = workflow_value.stringify()
  guard workflow_text.length() <= 1048576 else {
    fail("workflow request specification exceeds 1,048,576 characters")
  }
  let workflow = @json.parse(workflow_text, max_nesting_depth=64)
  let fields = wire_object(workflow, "workflow payload specification")
  let known = ["contract_id", "records_pointer", "record_id_pointer", "steps"]
  for key, _ in fields {
    guard known.contains(key) else {
      fail("unknown workflow payload field: \{key}")
    }
  }
  guard wire_string(fields, "contract_id") ==
    "moonflow.workflow-payload-plan.v1" else {
    fail("unsupported workflow payload plan contract")
  }
  let records_pointer = payload_pointer_field(fields, "records_pointer")
  let id_pointer = payload_pointer_field(fields, "record_id_pointer")
  let original = start_declared_plan_v1(
    source_graph, draft_id, "existing-graph", recorded_at,
  )
  guard !original.edits.is_empty() && original.edits.length() <= 256 else {
    fail("workflow source requires 1..256 steps")
  }
  let steps = catalog_json_values(fields, "steps")
  let by_step : Map[String, Json] = Map([])
  let step_options = [
    "additional_input_artifacts_pointer", "acceptance_criteria_pointer", "timeout_ms_pointer",
  ]
  for step in steps {
    let values = wire_object(step, "workflow request step")
    for key, _ in values {
      guard ["template_work_item_id", "request_template", "bindings"].contains(
          key,
        ) ||
        step_options.contains(key) else {
        fail("unknown workflow request step field: \{key}")
      }
    }
    let id = wire_string(values, "template_work_item_id")
    guard original.edits.any(edit => edit.work_item_id == id) &&
      !by_step.contains(id) else {
      fail("workflow request step must name one distinct original step: \{id}")
    }
    by_step[id] = step
  }
  guard by_step.length() == original.edits.length() else {
    fail("workflow requests require a template for every original step")
  }
  let input = mermaid_parse_json(records_json)
  guard records_plan_select(input, records_pointer, "records") is Array(records) &&
    !records.is_empty() &&
    records.length() <= 256 / original.edits.length() else {
    fail("workflow payload import requires 1..256 total expanded work items")
  }
  let record_ids : Array[String] = []
  let generated_ids : Map[String, Bool] = Map([])
  for index, record in records {
    guard record is Object(_) else {
      fail("record \{index + 1} must be an object")
    }
    guard records_plan_select(record, id_pointer, "record \{index + 1}")
      is String(id) &&
      composition_safe_id(id) &&
      !record_ids.contains(id) else {
      fail("record \{index + 1} must have a unique safe string record ID")
    }
    record_ids.push(id)
    for edit in original.edits {
      let item_id = id + "." + edit.work_item_id
      guard composition_safe_id(item_id) &&
        !generated_ids.contains(item_id) &&
        !original.edits.any(source => source.work_item_id == item_id) else {
        fail("expanded workflow work_item_id is unsafe or collides: \{item_id}")
      }
      generated_ids[item_id] = true
    }
  }
  let generated : Map[String, PayloadPlanArtifactV1] = Map([])
  let generated_edits : Map[String, PlanItemEditV1] = Map([])
  let mut total_bytes = 0
  for source_edit in original.edits {
    let step_id = source_edit.work_item_id
    let step = wire_object(by_step[step_id], "workflow request step")
    let contexts : Array[Json] = []
    for index, record in records {
      contexts.push({
        "record": record,
        "record_id": record_ids[index].to_json(),
        "step_id": step_id.to_json(),
        "work_item_id": (record_ids[index] + "." + step_id).to_json(),
      })
    }
    guard step.get("bindings") is Some(bindings) else {
      fail("workflow step \{step_id} requires bindings")
    }
    let mapping : Map[String, Json] = {
      "contract_id": "moonflow.payload-plan-mapping.v1",
      "records_pointer": "",
      "template_work_item_id": step_id.to_json(),
      "work_item_id_pointer": "/work_item_id",
      "bindings": bindings,
    }
    for name in step_options {
      if step.get(name) is Some(value) {
        mapping[name] = value
      }
    }
    let template = match step.get("request_template") {
      Some(value) => value
      None => fail("workflow step \{step_id} requires request_template")
    }
    let materialized = declared_plan_from_payloads_v1(
      source_graph,
      Json::object(mapping),
      template,
      contexts.to_json().stringify(),
      draft_id,
      recorded_at,
    ) catch {
      error => fail("workflow step \{step_id}: \{error}")
    }
    for artifact in materialized.artifacts {
      total_bytes += @utf8.encode(artifact.json_text).length()
      guard total_bytes <= 8388608 else {
        fail("workflow generated requests exceed 8 MiB total")
      }
      generated[artifact.work_item_id] = artifact
    }
    for edit in materialized.draft.edits {
      generated_edits[edit.work_item_id] = edit
    }
  }
  let edits : Array[PlanItemEditV1] = []
  let artifacts : Array[PayloadPlanArtifactV1] = []
  let added_templates : Map[String, String] = Map([])
  for record_id in record_ids {
    for source_edit in original.edits {
      let id = record_id + "." + source_edit.work_item_id
      let edit = generated_edits[id]
      edits.push({
        ..edit,
        depends_on: source_edit.depends_on.map(dependency => {
          record_id + "." + dependency
        }),
      })
      artifacts.push(generated[id])
      added_templates[id] = source_edit.work_item_id
    }
  }
  let draft = declared_plan_from_form_v1(
    {
      "contract_id": "moonflow.declared-plan-form-input.v2",
      "source_kind": "existing-graph",
      "source_graph": source_graph,
      "edits": edits.to_json(),
      "added_templates": added_templates.to_json(),
    },
    draft_id,
    recorded_at,
  )
  {
    contract_id: "moonflow.workflow-payload-plan-import.v1",
    records_digest: "sha256:" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(records_json))),
    workflow_digest: plan_digest(workflow),
    record_ids,
    items_per_record: original.edits.length(),
    artifacts,
    draft,
  }
}
