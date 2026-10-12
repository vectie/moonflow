///|
/// Detached event-head identity. Each run is observed separately.
pub(all) struct ResultsRunV1 {
  run_id : String
  book_id : String
  declaration_revision : String
  source_digest : String
  last_sequence : Int
  last_event_id : String
  recorded_at : String
  run_outcome : String
} derive(Debug, Eq, ToJson)

///|
/// Recorded current item state; retained artifacts may belong to earlier attempts.
pub(all) struct ResultsRowV1 {
  run_id : String
  book_id : String
  declaration_revision : String
  source_digest : String
  last_sequence : Int
  last_event_id : String
  recorded_at : String
  run_outcome : String
  work_item_id : String
  declaration_id : String
  product_id : String
  operation : String
  input_artifacts : Array[String]
  depends_on : Array[String]
  status : String
  attempt_status : String
  attempt_count : Int
  attempt_id : String
  input_digest : String
  result_id : String
  output_digest : String
  retained_artifacts : Array[String]
  review_id : String
  review_artifact : String
  reviewer_id : String
  blocker : String
  error_kind : String
} derive(Debug, Eq, ToJson)

///|
pub(all) struct ResultsTableV1 {
  contract_id : String
  runs : Array[ResultsRunV1]
  rows : Array[ResultsRowV1]
} derive(Debug, Eq, ToJson)

///|
/// Preserve caller run and item ordering, including accepted and unfinished work.
/// Reject empty selection and repeated run identities. This is not an atomic
/// cross-run snapshot, artifact verification or customer-acceptance assertion.
pub fn results_table_v1(
  projections : Array[RunProjection],
) -> ResultsTableV1 raise {
  if projections.is_empty() {
    fail("Select at least one run")
  }
  let seen : Array[String] = []
  let runs : Array[ResultsRunV1] = []
  let rows : Array[ResultsRowV1] = []
  for run in projections {
    if seen.contains(run.run_id) {
      fail("Duplicate results run: " + run.run_id)
    }
    seen.push(run.run_id)
    let head = run.applied_events.last()
    runs.push({
      run_id: run.run_id,
      book_id: run.book_id,
      declaration_revision: run.declaration_revision,
      source_digest: run.source_digest,
      last_sequence: run.last_sequence,
      last_event_id: head.map(e => e.event_id).unwrap_or(""),
      recorded_at: head.map(e => e.recorded_at).unwrap_or(""),
      run_outcome: run.outcome,
    })
    for item in run.items {
      rows.push({
        run_id: run.run_id,
        book_id: run.book_id,
        declaration_revision: run.declaration_revision,
        source_digest: run.source_digest,
        last_sequence: run.last_sequence,
        last_event_id: head.map(e => e.event_id).unwrap_or(""),
        recorded_at: head.map(e => e.recorded_at).unwrap_or(""),
        run_outcome: run.outcome,
        work_item_id: item.work_item_id,
        declaration_id: item.declaration_id,
        product_id: item.product_id,
        operation: item.operation,
        input_artifacts: item.input_artifacts.copy(),
        depends_on: item.depends_on.copy(),
        status: item.status.id(),
        attempt_status: item.attempt_status,
        attempt_count: item.attempt_count,
        attempt_id: item.active_attempt_id,
        input_digest: item.input_digest,
        result_id: item.result_id,
        output_digest: item.output_digest,
        retained_artifacts: item.artifacts.copy(),
        review_id: item.acceptance_review_id,
        review_artifact: item.acceptance_review_artifact,
        reviewer_id: item.acceptance_reviewer_id,
        blocker: item.blocker,
        error_kind: item.error_kind,
      })
    }
  }
  { contract_id: "moonflow.results-table.v1", runs, rows, }
}

///|
/// Always quote cells; quoting is not spreadsheet formula sanitization.
fn results_csv_cell(value : String) -> String {
  "\"" + value.replace_all(old="\"", new="\"\"") + "\""
}

///|
/// CSV lists are JSON-array cells; absent recorded strings remain empty.
/// Import untrusted values as text in spreadsheets to avoid formula evaluation.
pub fn results_table_csv_v1(table : ResultsTableV1) -> String {
  let lines : Array[String] = [
    "run_id,book_id,declaration_revision,source_digest,last_sequence,last_event_id,recorded_at,run_outcome,work_item_id,declaration_id,product_id,operation,input_artifacts,depends_on,status,attempt_status,attempt_count,attempt_id,input_digest,result_id,output_digest,retained_artifacts,review_id,review_artifact,reviewer_id,blocker,error_kind",
  ]
  for row in table.rows {
    let cells : Array[String] = [
      row.run_id,
      row.book_id,
      row.declaration_revision,
      row.source_digest,
      row.last_sequence.to_string(),
      row.last_event_id,
      row.recorded_at,
      row.run_outcome,
      row.work_item_id,
      row.declaration_id,
      row.product_id,
      row.operation,
      row.input_artifacts.to_json().stringify(),
      row.depends_on.to_json().stringify(),
      row.status,
      row.attempt_status,
      row.attempt_count.to_string(),
      row.attempt_id,
      row.input_digest,
      row.result_id,
      row.output_digest,
      row.retained_artifacts.to_json().stringify(),
      row.review_id,
      row.review_artifact,
      row.reviewer_id,
      row.blocker,
      row.error_kind,
    ]
    lines.push(cells.map(results_csv_cell).join(","))
  }
  lines.join("\r\n")
}
