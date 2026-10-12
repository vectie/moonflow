///|
/// One original step's artifact and review text templates. Exact operations,
/// schemas, authority, timeouts and dependency topology remain source-owned.
pub(all) struct TablePlanBindingV1 {
  template_work_item_id : String
  input_artifacts : Array[String]
  acceptance_criteria : Array[String]?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TablePlanTemplateV1 {
  contract_id : String
  item_bindings : Array[TablePlanBindingV1]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TablePlanExpansionV1 {
  contract_id : String
  csv_digest : String
  template_digest : String
  row_keys : Array[String]
  items_per_row : Int
  draft : DeclaredPlanDraftV1
} derive(Debug, Eq, ToJson)

///|
fn table_plan_column_name(value : String) -> Bool {
  !value.is_empty() &&
  value
  .to_array()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_'
  })
}

///|
/// A single pass prevents CSV values containing braces from becoming a second
/// template. This substitutes text only, never payload JSON, code or commands.
fn table_plan_expand_text(
  template : String,
  cells : Map[String, String],
) -> String raise {
  let chars = template.to_array()
  let output = StringBuilder::new()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '{' && chars.get(i + 1) == Some('{') {
      let column = StringBuilder::new()
      i += 2
      while i < chars.length() &&
            !(chars[i] == '}' && chars.get(i + 1) == Some('}')) {
        column.write_char(chars[i])
        i += 1
      }
      guard i < chars.length() else {
        fail("unclosed table placeholder in: \{template}")
      }
      let name = column.to_string()
      guard table_plan_column_name(name) && cells.get(name) is Some(value) else {
        fail("unknown table column in placeholder: \{name}")
      }
      guard !value.trim().is_empty() else {
        fail("table column \{name} is blank for row " + cells["key"])
      }
      output.write_string(value)
      i += 2
    } else {
      guard !(chars[i] == '}' && chars.get(i + 1) == Some('}')) else {
        fail("unmatched table placeholder close in: \{template}")
      }
      output.write_char(chars[i])
      i += 1
    }
  }
  output.to_string()
}

///|
/// Expand the complete original workflow once per explicit CSV row. Each row
/// is an independent branch: key--step IDs and same-row dependencies preserve
/// the original DAG. The result uses the existing editable v2 draft contract.
pub fn declared_plan_from_table_v1(
  source_graph : Json,
  template_value : Json,
  csv : String,
  draft_id : String,
  recorded_at : String,
) -> TablePlanExpansionV1 raise {
  let original = start_declared_plan_v1(
    source_graph, draft_id, "existing-graph", recorded_at,
  )
  let template : TablePlanTemplateV1 = @json.from_json(template_value)
  guard template.contract_id == "moonflow.table-plan-template.v1" else {
    fail("unsupported table plan template contract")
  }
  let bindings : Map[String, TablePlanBindingV1] = {}
  for binding in template.item_bindings {
    let id = binding.template_work_item_id
    guard !bindings.contains(id) &&
      original.edits.any(edit => edit.work_item_id == id) else {
      fail("table binding must name one distinct original step: \{id}")
    }
    plan_unique_strings(
      binding.input_artifacts,
      "artifact templates for \{id}",
      nonempty=true,
    )
    if binding.acceptance_criteria is Some(criteria) {
      plan_unique_strings(
        criteria,
        "criteria templates for \{id}",
        nonempty=true,
      )
    }
    bindings[id] = binding
  }
  guard bindings.length() == original.edits.length() else {
    fail("table template requires a binding for every original workflow step")
  }
  let records = plan_csv_records(csv)
  guard (records.length() - 1) * original.edits.length() <= 256 else {
    fail("expanded table plan exceeds 256 work items")
  }
  let headers = records[0].map(value => value.trim().to_string())
  plan_unique_strings(headers, "table header", nonempty=true)
  guard headers.contains("key") && headers.all(table_plan_column_name) else {
    fail(
      "table requires key and column names containing only letters, digits or underscore",
    )
  }
  let row_keys : Array[String] = []
  let edits : Array[PlanItemEditV1] = []
  let added_templates : Map[String, String] = {}
  for record_index in 1..<records.length() {
    let row = records[record_index]
    guard row.length() == headers.length() else {
      fail(
        "table record \{record_index + 1} has \{row.length()} cells; expected \{headers.length()}",
      )
    }
    let cells : Map[String, String] = {}
    for index, header in headers {
      cells[header] = row[index].trim().to_string()
    }
    let key = cells["key"]
    guard catalog_safe_identifier(key) &&
      key != "." &&
      !key.contains("..") &&
      !key.contains("--") &&
      !row_keys.contains(key) else {
      fail(
        "table key must be unique, safe and contain neither '..' nor '--': \{key}",
      )
    }
    row_keys.push(key)
    for edit in original.edits {
      let binding = bindings[edit.work_item_id]
      let id = key + "--" + edit.work_item_id
      guard !original.edits.any(item => item.work_item_id == id) else {
        fail("expanded table ID collides with an original step: \{id}")
      }
      edits.push({
        work_item_id: id,
        input_artifacts: binding.input_artifacts.map(value => {
          table_plan_expand_text(value, cells)
        }),
        depends_on: edit.depends_on.map(dependency => key + "--" + dependency),
        acceptance_criteria: match binding.acceptance_criteria {
          Some(criteria) =>
            criteria.map(value => table_plan_expand_text(value, cells))
          None => edit.acceptance_criteria.copy()
        },
        timeout_ms: edit.timeout_ms,
      })
      added_templates[id] = edit.work_item_id
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
    contract_id: "moonflow.table-plan-expansion.v1",
    csv_digest: "sha256:" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(csv))),
    template_digest: plan_digest(template_value),
    row_keys,
    items_per_row: original.edits.length(),
    draft,
  }
}
