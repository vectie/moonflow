///|
test "results worksheet includes accepted and unfinished rows with independent run heads" {
  let events = owner_test_events()
  events.push(owner_test_result("succeeded"))
  events.push(
    event(
      5,
      "accepted",
      ItemAccepted,
      work_item_id="research",
      detail="review-1",
      artifact_id="evidence/review.json",
      authority_id="reviewer",
      result_id="result-1",
      attempt_id="attempt-1",
      output_digest="sha256:output",
    ),
  )
  events.push(
    event(
      6,
      "pending",
      ItemRegistered,
      work_item_id="pending",
      product_id="moonmoon",
    ),
  )
  let first = @moonflow.replay("flow-selene-r1", events)
  let second_events = owner_test_events().map(e => { ..e, run_id: "run-two", })
  second_events.push({ ..owner_test_result("unknown"), run_id: "run-two", })
  let second = @moonflow.replay("run-two", second_events)
  let before = @moonflow.projection_json(first).stringify()
  let table = @moonflow.results_table_v1([second, first])
  assert_eq(table.contract_id, "moonflow.results-table.v1")
  assert_eq(table.rows.length(), 3)
  assert_eq(table.runs[0].run_id, "run-two")
  assert_eq(table.runs[0].last_sequence, 4)
  assert_eq(table.runs[1].last_event_id, "pending")
  assert_eq(table.rows[0].status, second.items[0].status.id())
  assert_eq(table.rows[0].attempt_status, "unknown")
  assert_eq(table.rows[0].output_digest, "")
  assert_eq(table.rows[1].status, "accepted")
  assert_eq(table.rows[1].review_id, "review-1")
  assert_eq(table.rows[1].reviewer_id, "reviewer")
  assert_eq(table.rows[1].attempt_id, "attempt-1")
  assert_eq(table.rows[1].result_id, "result-1")
  assert_eq(table.rows[2].status, "proposed")
  assert_eq(table.rows[2].attempt_count, 0)
  assert_eq(table.rows[1].book_id, "selene")
  assert_eq(table.rows[1].declaration_revision, "r1")
  assert_eq(table.rows[1].source_digest, "sha256:selene-r1")
  assert_eq(before, @moonflow.projection_json(first).stringify())
  first.items[0].artifacts.push("later")
  first.items[0].input_artifacts.push("later")
  first.items[0].depends_on.push("later")
  first.items[0].status = Failed
  assert_eq(table.rows[1].status, "accepted")
  assert_eq(table.rows[1].retained_artifacts, [
    "evidence/exact-output.json", "evidence/review.json",
  ])
  assert_eq(table.rows[1].input_artifacts, ["evidence/input.json"])
  assert_eq(table.rows[1].depends_on, [])
}

///|
test "results CSV preserves quoted Unicode multiline cells and JSON arrays" {
  let run = @moonflow.replay("flow-selene-r1", owner_test_events())
  run.items[0].blocker = "=untrusted, \"résumé\"\r\n第二行"
  run.items[0].input_artifacts.push("input/雪,\"x\"\n.json")
  let table = @moonflow.results_table_v1([run])
  let csv = @moonflow.results_table_csv_v1(table)
  assert_true(csv.contains("\"=untrusted, \"\"résumé\"\"\r\n第二行\""))
  assert_true(
    csv.contains(
      "\"[\"\"evidence/input.json\"\",\"\"input/雪,\\\"\"x\\\"\"\\n.json\"\"]\"",
    ),
  )
  assert_true(csv.contains("\"[]\""))
  assert_eq(table.rows[0].input_artifacts, run.items[0].input_artifacts)
  assert_true(table.to_json().stringify().contains("moonflow.results-table.v1"))
}

///|
test "results rejects duplicate and empty selections but keeps zero-item run identity" {
  let run = @moonflow.empty_projection("empty")
  assert_true((try? @moonflow.results_table_v1([])) is Err(_))
  assert_true((try? @moonflow.results_table_v1([run, run])) is Err(_))
  let table = @moonflow.results_table_v1([run])
  assert_eq(table.runs.length(), 1)
  assert_eq(table.rows.length(), 0)
  assert_eq(table.runs[0].last_event_id, "")
}
