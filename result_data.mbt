///|
/// Explicit JSON Pointer columns for one output in each current successful
/// attempt. An optional exact operation filter excludes unrelated work items.
pub(all) struct ResultDataColumnV1 {
  name : String
  pointer : String
} derive(Debug, Eq, ToJson)

///|
pub(all) struct ResultDataMappingV1 {
  contract_id : String
  operation : String?
  output_artifact_index : Int
  columns : Array[ResultDataColumnV1]
} derive(Debug, Eq, ToJson)

///|
/// Values are observed file contents, not verification of the recorded aggregate
/// output digest. No values are inferred from retained or checkpoint evidence.
pub(all) struct ResultDataRowV1 {
  source : ResultsRowV1
  data_status : String
  result_event_id : String
  artifact_ref : String
  observed_sha256 : String
  observed_size_bytes : Int
  values : Map[String, Json]
} derive(Debug, Eq, ToJson)

///|
pub(all) struct ResultDataTableV1 {
  contract_id : String
  mapping : ResultDataMappingV1
  mapping_digest : String
  runs : Array[ResultsRunV1]
  rows : Array[ResultDataRowV1]
} derive(Debug, Eq, ToJson)

///|
fn result_data_mapping(value : Json) -> ResultDataMappingV1 raise {
  let fields = wire_object(value, "result data mapping")
  for key, _ in fields {
    guard ["contract_id", "operation", "output_artifact_index", "columns"].contains(
      key,
    ) else {
      fail("unknown result data mapping field: \{key}")
    }
  }
  guard wire_string(fields, "contract_id") == "moonflow.result-data-mapping.v1" else {
    fail("unsupported result data mapping contract")
  }
  let operation = match fields.get("operation") {
    None | Some(Null) => None
    Some(String(value)) if !value.trim().is_empty() => Some(value)
    _ => fail("operation must be a nonempty string or null")
  }
  guard fields.get("output_artifact_index") is Some(Number(index, ..)) &&
    index >= 0.0 &&
    index <= 255.0 &&
    index.to_int().to_double() == index else {
    fail("output_artifact_index must be a whole number in 0..255")
  }
  guard fields.get("columns") is Some(Array(values)) &&
    values.length() > 0 &&
    values.length() <= 64 else {
    fail("result data requires 1..64 columns")
  }
  let columns : Array[ResultDataColumnV1] = []
  for value in values {
    let column = wire_object(value, "result data column")
    for key, _ in column {
      guard key == "name" || key == "pointer" else {
        fail("unknown result data column field: \{key}")
      }
    }
    let name = wire_string(column, "name")
    guard name.length() <= 80 && !columns.any(c => c.name == name) else {
      fail(
        "result data column names must be unique and at most 80 characters: \{name}",
      )
    }
    let pointer = wire_string(column, "pointer", allow_empty=true)
    guard pointer.length() <= 1024 else {
      fail("result data pointer exceeds 1024 characters")
    }
    ignore(records_plan_pointer_tokens(pointer))
    columns.push({ name, pointer, })
  }
  {
    contract_id: "moonflow.result-data-mapping.v1",
    operation,
    output_artifact_index: index.to_int(),
    columns,
  }
}

///|
fn result_data_selected_rows(
  projections : Array[RunProjection],
  mapping : ResultDataMappingV1,
) -> ResultsTableV1 raise {
  guard projections.length() <= 64 else {
    fail("result data accepts at most 64 runs")
  }
  let table = results_table_v1(projections)
  let rows = table.rows.filter(row => {
    match mapping.operation {
      Some(operation) => row.operation == operation
      None => true
    }
  })
  guard rows.length() <= 4096 else {
    fail("result data accepts at most 4096 selected items")
  }
  { ..table, rows, }
}

///|
fn result_data_output(
  projection : RunProjection,
  row : ResultsRowV1,
  mapping : ResultDataMappingV1,
) -> (String, String)? raise {
  if row.attempt_status != "succeeded" {
    return None
  }
  let mut result : RuntimeEvent? = None
  for event in projection.applied_events {
    if event.kind == AttemptReconciled &&
      event.work_item_id == row.work_item_id &&
      event.attempt_id == row.attempt_id &&
      event.result_id == row.result_id &&
      event.output_digest == row.output_digest &&
      event.attempt_status == "succeeded" {
      result = Some(event)
    }
  }
  let label = row.run_id + "/" + row.work_item_id
  guard result is Some(event) else {
    fail("\{label}: current successful attempt has no matching result event")
  }
  guard event.output_artifacts.get(mapping.output_artifact_index)
    is Some(artifact_ref) else {
    fail(
      "\{label}: result has no output at index \{mapping.output_artifact_index}",
    )
  }
  guard artifact_ref_is_workspace_relative(artifact_ref) else {
    fail("\{label}: result output must be workspace-relative")
  }
  Some((event.event_id, artifact_ref))
}

///|
/// Enumerate only the selected current-result paths, deduplicated in run/item
/// order. The native CLI reads these exact files once after canonical replay.
pub fn result_data_sources_v1(
  projections : Array[RunProjection],
  mapping_value : Json,
) -> Array[String] raise {
  let mapping = result_data_mapping(mapping_value)
  let table = result_data_selected_rows(projections, mapping)
  let sources : Array[String] = []
  for row in table.rows {
    let run = projections.filter(p => p.run_id == row.run_id)[0]
    match result_data_output(run, row, mapping) {
      Some((_, artifact_ref)) if !sources.contains(artifact_ref) =>
        sources.push(artifact_ref)
      _ => ()
    }
  }
  sources
}

///|
/// Extract typed JSON values using explicit pointers. Each selected file is at
/// most 1 MiB, total selected bytes at most 64 MiB, JSON depth at most 64. Missing
/// files, malformed JSON and unresolved pointers refuse the complete worksheet.
pub fn result_data_table_v1(
  projections : Array[RunProjection],
  mapping_value : Json,
  artifacts : Map[String, Bytes],
) -> ResultDataTableV1 raise {
  let mapping = result_data_mapping(mapping_value)
  let table = result_data_selected_rows(projections, mapping)
  let decoded : Map[String, (Json, String, Int)] = {}
  let mut total_bytes = 0
  for artifact_ref in result_data_sources_v1(projections, mapping_value) {
    guard artifacts.get(artifact_ref) is Some(bytes) else {
      fail("missing result output bytes: \{artifact_ref}")
    }
    guard bytes.length() <= 1048576 else {
      fail("result output exceeds 1 MiB: \{artifact_ref}")
    }
    total_bytes += bytes.length()
    guard total_bytes <= 67108864 else {
      fail("selected result outputs exceed 64 MiB")
    }
    let value = @json.parse(@utf8.decode(bytes), max_nesting_depth=64) catch {
      err => fail("invalid result output JSON at \{artifact_ref}: \{err}")
    }
    decoded[artifact_ref] = (
      value,
      "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
      bytes.length(),
    )
  }
  let rows : Array[ResultDataRowV1] = []
  for source in table.rows {
    let run = projections.filter(p => p.run_id == source.run_id)[0]
    let values : Map[String, Json] = {}
    let (
      data_status,
      result_event_id,
      artifact_ref,
      observed_sha256,
      observed_size_bytes,
    ) = match result_data_output(run, source, mapping) {
      None => {
        for column in mapping.columns {
          values[column.name] = Json::null()
        }
        (
          if source.attempt_status == "checkpoint-reused" {
            "checkpoint-only"
          } else {
            "no-successful-attempt"
          },
          "",
          "",
          "",
          0,
        )
      }
      Some((event_id, artifact_ref)) => {
        let (value, digest, size) = decoded[artifact_ref]
        for column in mapping.columns {
          values[column.name] = records_plan_select(
            value,
            column.pointer,
            source.run_id + "/" + source.work_item_id + " column " + column.name,
          )
        }
        ("extracted", event_id, artifact_ref, digest, size)
      }
    }
    rows.push({
      source,
      data_status,
      result_event_id,
      artifact_ref,
      observed_sha256,
      observed_size_bytes,
      values,
    })
  }
  {
    contract_id: "moonflow.result-data-table.v1",
    mapping,
    mapping_digest: "sha256:" +
    @crypto.bytes_to_hex_string(
      @crypto.sha256(@utf8.encode(mapping.to_json().stringify())),
    ),
    runs: table.runs,
    rows,
  }
}

///|
/// Mapped cells are JSON-encoded even for strings and null, so reading a CSV
/// cell with a JSON parser preserves types. Import all columns as text.
pub fn result_data_csv_v1(table : ResultDataTableV1) -> String {
  let headers = [
    "run_id", "declaration_revision", "last_sequence", "last_event_id", "work_item_id",
    "product_id", "operation", "status", "attempt_status", "attempt_id", "result_id",
    "recorded_output_digest", "review_id", "reviewer_id", "data_status", "result_event_id",
    "artifact_ref", "observed_sha256", "observed_size_bytes",
  ]
  for column in table.mapping.columns {
    headers.push("value:" + column.name)
  }
  let lines = [headers.map(results_csv_cell).join(",")]
  for row in table.rows {
    let source = row.source
    let cells = [
      source.run_id,
      source.declaration_revision,
      source.last_sequence.to_string(),
      source.last_event_id,
      source.work_item_id,
      source.product_id,
      source.operation,
      source.status,
      source.attempt_status,
      source.attempt_id,
      source.result_id,
      source.output_digest,
      source.review_id,
      source.reviewer_id,
      row.data_status,
      row.result_event_id,
      row.artifact_ref,
      row.observed_sha256,
      row.observed_size_bytes.to_string(),
    ]
    for column in table.mapping.columns {
      cells.push(row.values[column.name].stringify())
    }
    lines.push(cells.map(results_csv_cell).join(","))
  }
  lines.join("\r\n")
}
