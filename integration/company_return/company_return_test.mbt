///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn text(value : Json, key : String) -> String {
  match field(value, key) {
    String(value) => value
    _ => ""
  }
}

///|
async test "serialized approved revised Proj attempt replays once and reviews exact output without company acceptance" {
  let pointer = @env.get_env_var("MOONPROJ_FLOW_V2_FIXTURE_POINTER").unwrap_or(
    "",
  )
  if pointer.is_empty() {
    return
  }
  let fixture = @json.parse(@fs.read_file(pointer).text())
  let workspace = text(fixture, "workspace")
  let request_json = @json.parse(
    @fs.read_file(workspace + "/" + text(fixture, "request_ref")).text(),
  )
  let result_json = @json.parse(
    @fs.read_file(workspace + "/" + text(fixture, "result_ref")).text(),
  )
  let request = @moonflow.decode_adapter_request(request_json)
  let result = @moonflow.decode_adapter_result(result_json)
  assert_true(
    @moonflow.reconcile_adapter_result(request, result) is ImportSuccess,
  )
  let events = @moonflow.events_from_work_graph({
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": request.run_id,
    "book_id": request.book_id,
    "declaration_revision": "company-revision-2",
    "source_digest": request.input_digest,
    "recorded_at": request.created_at,
    "items": [
      {
        "work_item_id": request.work_item_id,
        "declaration_id": request.declaration_id,
        "product_id": request.product_id,
        "requested_authority": request.requested_authority,
        "acceptance_criteria": request.acceptance_criteria,
        "operation": request.operation,
        "input_contracts": request.input_contracts,
        "output_contracts": request.output_contracts,
        "required_claim": request.required_claim,
        "input_artifacts": request.input_artifacts,
        "timeout_ms": request.timeout_ms,
        "depends_on": [],
      },
    ],
  })
  let before = @moonflow.replay(request.run_id, events)
  let submission = @moonflow.adapter_submission_event(before, request)
  events.push(submission)
  let restarted = @moonflow.replay(
    request.run_id,
    events.map(event => {
      @moonflow.decode_runtime_event(@moonflow.runtime_event_json(event))
    }),
  )
  assert_eq(@moonflow.adapter_submission_event(restarted, request), submission)
  let imported = @moonflow.adapter_reconciliation_event(restarted, result)
  events.push(imported)
  let completed = @moonflow.replay(request.run_id, events)
  assert_eq(@moonflow.adapter_reconciliation_event(completed, result), imported)
  completed.apply(imported)
  let item = completed.find_item(request.work_item_id).unwrap()
  assert_eq(item.attempt_count, 1)
  assert_true(item.status is Review)
  let review : @moonflow.AcceptanceReviewReceipt = {
    contract_id: "moonflow.acceptance-review.v1",
    review_id: "review-company-revision-two",
    run_id: request.run_id,
    work_item_id: request.work_item_id,
    declaration_id: request.declaration_id,
    result_id: result.result_id,
    attempt_id: request.attempt_id,
    output_digest: result.output_digest,
    decision: "accepted",
    criteria: request.acceptance_criteria.map(criterion => {
      criterion,
      satisfied: true,
      evidence_refs: result.output_artifacts.copy(),
      note: "Synthetic independent review of the exact digital plan artifact",
    }),
    reviewer_id: "fixture-independent-reviewer",
    review_authority_id: "fixture-plan-review-authority",
    receipt_artifact: "flow-review.json",
    recorded_at: "2026-10-08T12:00:00Z",
  }
  let changed = { ..result, output_digest: "sha256:changed", }
  try @moonflow.adapter_reconciliation_event(completed, changed) catch {
    _ => ()
  } noraise {
    _ => fail("changed output cannot replace settled result")
  }
  let wrong_review = { ..review, attempt_id: "another-revised-attempt", }
  try @moonflow.acceptance_review_event(completed, wrong_review) catch {
    _ => ()
  } noraise {
    _ => fail("review cannot move to a child attempt")
  }
  events.push(@moonflow.acceptance_review_event(completed, review))
  let accepted = @moonflow.replay(
    request.run_id,
    events.map(event => {
      @moonflow.decode_runtime_event(@moonflow.runtime_event_json(event))
    }),
  )
  assert_true(
    accepted.find_item(request.work_item_id).unwrap().status is Accepted,
  )
  assert_eq(accepted.find_item(request.work_item_id).unwrap().attempt_count, 1)
  @fs.write_file(
    workspace + "/flow-review.json",
    review.to_json().stringify(indent=2),
    create_mode=@fs.CreateOrTruncate,
  )
  let parent = workspace[:workspace.rev_find("/").unwrap()].to_owned()
  @fs.write_file(
    parent + "/flow-replay-receipt.json",
    (
      {
        "engine": "actual MoonFlow event submission reconciliation review and serialized replay",
        "run_id": request.run_id,
        "attempt_id": request.attempt_id,
        "input_digest": request.input_digest,
        "output_digest": result.output_digest,
        "attempt_count": 1,
        "flow_review": "accepted exact synthetic digital artifact",
        "company_task_acceptance": "unchanged",
        "events": events.map(event => @moonflow.runtime_event_json(event)),
        "customer_acceptance": "not_recorded_here",
        "cash": "not_recorded_here",
      } : Json).stringify(indent=2),
    create_mode=@fs.CreateOrTruncate,
  )
}
