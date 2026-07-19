///|
async fn fixture_text(name : String) -> String {
  @fs.read_file("conformance/golden/v2/" + name).text()
}

///|
async fn fixture_json(name : String) -> Json {
  @json.parse(fixture_text(name))
}

///|
async fn golden_events() -> Array[@moonflow.RuntimeEvent] {
  @moonflow.decode_event_array(fixture_json("event-stream.json"))
}

///|
async test "FLOW-2 golden current source-linked graph import is byte exact" {
  let graph = @json.parse(
    @fs.read_file("fixtures/source-linked-work-graph.json").text(),
  )
  let events = @moonflow.events_from_work_graph(graph)
  assert_eq(
    @moonflow.event_array_json(events).stringify(indent=2) + "\n",
    fixture_text("source-linked-events.json"),
  )
  let projection = @moonflow.replay("flow-source-linked-fixture-r1", events)
  assert_eq(
    @moonflow.projection_json(projection).stringify(indent=2) + "\n",
    fixture_text("source-linked-projection.json"),
  )
}

///|
async test "FLOW-2 golden v2 graph import and event serialization are exact" {
  let imported = @moonflow.events_from_work_graph(
    fixture_json("work-graph.json"),
  )
  let events = golden_events()
  assert_eq(imported.length(), 4)
  for index in 0..<imported.length() {
    assert_true(imported[index] == events[index])
  }
  assert_eq(
    @moonflow.event_array_json(events).stringify(indent=2) + "\n",
    fixture_text("event-stream.json"),
  )
}

///|
async test "FLOW-2 golden v2 replay and restart projection are byte exact" {
  let events = golden_events()
  let first = @moonflow.replay("flow2-golden-v2", events)
  let restarted = @moonflow.replay("flow2-golden-v2", events)
  assert_true(first == restarted)
  assert_eq(
    @moonflow.projection_json(restarted).stringify(indent=2) + "\n",
    fixture_text("projection.json"),
  )
}

///|
async test "FLOW-2 golden v2 exact duplicate is a no-op and changed content conflicts" {
  let events = golden_events()
  let projection = @moonflow.replay("flow2-golden-v2", events)
  let last_sequence = projection.last_sequence
  let event_count = projection.applied_events.length()
  projection.apply(events[9])
  assert_eq(projection.last_sequence, last_sequence)
  assert_eq(projection.applied_events.length(), event_count)
  let conflicting = { ..events[9], detail: "changed duplicate content" }
  try projection.apply(conflicting) catch {
    error =>
      assert_true("\{error.to_repr()}".contains("ConflictingDuplicateEvent"))
  } noraise {
    _ => fail("expected same-identity changed-content conflict")
  }
}

///|
async test "FLOW-2 golden accepted dependency alone becomes ready" {
  let events = golden_events()
  let accepted_dependency = @moonflow.replay(
    "flow2-golden-v2",
    events[:7].to_owned(),
  )
  let ready = @moonflow.ready_events(
    accepted_dependency, "2026-07-16T00:00:04Z",
  )
  assert_eq(ready.length(), 1)
  assert_true(ready[0] == events[7])
}

///|
async test "FLOW-2 golden adapter reconciliation is exact idempotent and stops in Review" {
  let events = golden_events()
  let request = @moonflow.decode_adapter_request(
    fixture_json("adapter-request-observe.json"),
  )
  let result = @moonflow.decode_adapter_result(
    fixture_json("adapter-result-observe.json"),
  )
  let submitted = @moonflow.replay("flow2-golden-v2", events[:5].to_owned())
  assert_true(
    @moonflow.adapter_submission_event(submitted, request) == events[4],
  )
  let reconciled = @moonflow.replay("flow2-golden-v2", events[:6].to_owned())
  assert_true(
    @moonflow.adapter_reconciliation_event(reconciled, result) == events[5],
  )
  let changed = { ..result, output_digest: "sha256:changed-output" }
  try @moonflow.adapter_reconciliation_event(reconciled, changed) catch {
    error =>
      assert_true("\{error.to_repr()}".contains("AdapterReceiptConflict"))
  } noraise {
    _ => fail("expected changed adapter result conflict")
  }
  let completed = @moonflow.replay("flow2-golden-v2", events)
  guard completed.find_item("work-validate") is Some(item) else {
    fail("expected validation item")
  }
  assert_true(item.status is Review)
  assert_false(item.status is Accepted)
}

///|
async test "FLOW-2 golden acceptance receipt remains exact-bound and cannot be skipped" {
  let events = golden_events()
  let review = @moonflow.decode_acceptance_review_receipt(
    fixture_json("acceptance-review-observe.json"),
  )
  let projection = @moonflow.replay("flow2-golden-v2", events[:6].to_owned())
  assert_true(
    @moonflow.acceptance_review_event(projection, review) == events[6],
  )
  let changed_digest = { ..review, output_digest: "sha256:changed-output" }
  try @moonflow.acceptance_review_event(projection, changed_digest) catch {
    error => assert_true("\{error.to_repr()}".contains("output_digest"))
  } noraise {
    _ => fail("expected review output binding failure")
  }
  let changed_evidence = {
    ..review,
    criteria: [
      { ..review.criteria[0], evidence_refs: ["artifacts/not-attached.json"] },
    ],
  }
  try @moonflow.acceptance_review_event(projection, changed_evidence) catch {
    error => assert_true("\{error.to_repr()}".contains("not attached"))
  } noraise {
    _ => fail("expected review evidence binding failure")
  }
  let skipped = { ..events[6], detail: "", artifact_id: "", authority_id: "" }
  try projection.apply(skipped) catch {
    error =>
      assert_true("\{error.to_repr()}".contains("MissingAcceptanceReviewField"))
  } noraise {
    _ => fail("expected direct acceptance without review receipt to fail")
  }
}

///|
test "FLOW-2 golden workspace-relative artifact rules reject absolute and traversal paths" {
  assert_true(
    @moonflow.artifact_ref_is_workspace_relative("artifacts/evidence.json"),
  )
  assert_false(
    @moonflow.artifact_ref_is_workspace_relative("/tmp/evidence.json"),
  )
  assert_false(
    @moonflow.artifact_ref_is_workspace_relative("artifacts/../outside.json"),
  )
  assert_false(
    @moonflow.artifact_ref_is_workspace_relative("artifacts//evidence.json"),
  )
  assert_false(
    @moonflow.path_is_within_workspace(
      "/workspace/root", "/workspace/root/../outside/evidence.json",
    ),
  )
}
