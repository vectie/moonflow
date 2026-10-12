///|
/// A sheet expanded into a normal editable declared-plan draft. The raw CSV
/// digest identifies the input, while the draft retains the selected graph.
pub(all) struct CsvPlanImportV1 {
  contract_id : String
  template_work_item_id : String
  csv_digest : String
  row_count : Int
  draft : DeclaredPlanDraftV1
} derive(Debug, Eq, ToJson)

///|
/// CSV records use commas, doubled quotes and LF/CRLF. Quoted cells may span
/// lines, so spreadsheets can supply lists using their normal multiline cells.
/// Worksheet identity cells opt into exact quoted carriage-return preservation;
/// existing batch importers retain their original CRLF-to-LF normalization.
fn plan_csv_records(
  csv : String,
  preserve_quoted_cr? : Bool = false,
) -> Array[Array[String]] raise {
  guard csv.length() <= 1048576 else {
    fail("CSV exceeds 1,048,576 characters")
  }
  let chars = csv.to_array()
  let records : Array[Array[String]] = []
  let mut row : Array[String] = []
  let mut cell = StringBuilder::new()
  let mut quoted = false
  let mut closed_quote = false
  let mut started = false
  let mut i = if chars.get(0) == Some('\u{FEFF}') { 1 } else { 0 }
  while i < chars.length() {
    let c = chars[i]
    if quoted {
      if c == '"' {
        if chars.get(i + 1) == Some('"') {
          cell.write_char('"')
          i += 1
        } else {
          quoted = false
          closed_quote = true
        }
      } else if c == '\r' && !preserve_quoted_cr {
        guard chars.get(i + 1) == Some('\n') else {
          fail("CSV uses an unpaired carriage return")
        }
        cell.write_char('\n')
        i += 1
      } else {
        cell.write_char(c)
      }
    } else if c == ',' || c == '\n' || c == '\r' {
      row.push(cell.to_string())
      cell = StringBuilder::new()
      closed_quote = false
      started = false
      if c != ',' {
        if c == '\r' {
          guard chars.get(i + 1) == Some('\n') else {
            fail("CSV uses an unpaired carriage return")
          }
          i += 1
        }
        records.push(row)
        row = []
        guard records.length() <= 257 else {
          fail("CSV supports a header and at most 256 work items")
        }
      }
    } else {
      guard !closed_quote else {
        fail(
          "CSV has text after a closing quote in record \{records.length() + 1}",
        )
      }
      if c == '"' {
        guard !started else { fail("CSV has a quote inside an unquoted cell") }
        quoted = true
      } else {
        cell.write_char(c)
      }
      started = true
    }
    i += 1
  }
  guard !quoted else { fail("CSV has an unterminated quoted cell") }
  if started || closed_quote || !row.is_empty() {
    row.push(cell.to_string())
    records.push(row)
  }
  guard records.length() >= 2 && records.length() <= 257 else {
    fail("CSV must contain one header and 1..256 work items")
  }
  records
}

///|
fn plan_csv_list(cell : String, label : String) -> Array[String] raise {
  if cell.trim().is_empty() {
    return []
  }
  let values = cell.split("\n").map(value => value.trim().to_string()).collect()
  plan_unique_strings(values, label, nonempty=true)
  values
}

///|
/// Expand explicit rows from one exact declared operation. Source nodes are
/// replaced by the row set; only CSV dependencies are used. No domain payload
/// is generated, adapter dispatched, run imported, or approval copied.
pub fn declared_plan_from_csv_v1(
  source_graph : Json,
  template_work_item_id : String,
  csv : String,
  draft_id : String,
  recorded_at : String,
) -> CsvPlanImportV1 raise {
  let original = start_declared_plan_v1(
    source_graph, draft_id, "existing-graph", recorded_at,
  )
  guard original.edits
    .filter(edit => edit.work_item_id == template_work_item_id)
    .get(0)
    is Some(template) else {
    fail(
      "CSV template is not an original source item: \{template_work_item_id}",
    )
  }
  let records = plan_csv_records(csv)
  let headers = records[0].map(value => value.trim().to_string())
  plan_unique_strings(headers, "CSV header", nonempty=true)
  let known = [
    "work_item_id", "input_artifacts", "depends_on", "acceptance_criteria", "timeout_ms",
  ]
  for header in headers {
    guard known.contains(header) else { fail("unknown CSV column: \{header}") }
  }
  guard headers.contains("work_item_id") && headers.contains("input_artifacts") else {
    fail("CSV requires work_item_id and input_artifacts columns")
  }
  let edits : Array[PlanItemEditV1] = []
  let templates : Map[String, String] = {}
  for record_index in 1..<records.length() {
    let row = records[record_index]
    guard row.length() == headers.length() else {
      fail(
        "CSV record \{record_index + 1} has \{row.length()} cells; expected \{headers.length()}",
      )
    }
    let cells : Map[String, String] = {}
    for index, header in headers {
      cells[header] = row[index].trim().to_string()
    }
    let id = cells["work_item_id"]
    guard !original.edits.any(edit => edit.work_item_id == id) else {
      fail("CSV row must use a new work_item_id, not a source ID: \{id}")
    }
    let inputs = plan_csv_list(
      cells["input_artifacts"],
      "input_artifacts for \{id}",
    )
    let dependencies = plan_csv_list(
      cells.get("depends_on").unwrap_or(""),
      "depends_on for \{id}",
    )
    let criteria_cell = cells.get("acceptance_criteria").unwrap_or("")
    let criteria = if criteria_cell.is_empty() {
      template.acceptance_criteria.copy()
    } else {
      plan_csv_list(criteria_cell, "acceptance_criteria for \{id}")
    }
    let timeout_cell = cells.get("timeout_ms").unwrap_or("")
    let timeout_ms = if timeout_cell.is_empty() {
      template.timeout_ms
    } else {
      guard timeout_cell.to_array().all(c => c >= '0' && c <= '9') else {
        fail("timeout_ms for \{id} must be a whole number")
      }
      @string.parse_int(timeout_cell)
    }
    edits.push({
      work_item_id: id,
      input_artifacts: inputs,
      depends_on: dependencies,
      acceptance_criteria: criteria,
      timeout_ms,
    })
    templates[id] = template_work_item_id
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
    contract_id: "moonflow.csv-plan-import.v1",
    template_work_item_id,
    csv_digest: "sha256:" +
    @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(csv))),
    row_count: edits.length(),
    draft,
  }
}
