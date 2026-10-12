///|
fn single_fixture_projection(run_id : String) -> @moonflow.RunProjection raise {
  @moonflow.replay(
    run_id,
    @moonflow.events_from_work_graph({
      "contract_id": "moonsuite.work-model.v1",
      "graph_id": run_id,
      "book_id": "single-step-book",
      "declaration_revision": "r23",
      "source_digest": "sha256:" + "a".repeat(64),
      "items": [
        for id in ["selected", "other"] => {
          {
            "work_item_id": id,
            "declaration_id": id,
            "product_id": "moonmold",
            "requested_authority": "workspace-mutation",
            "acceptance_criteria": ["Explicit review remains required"],
            "operation": "moonmold/spatial.operation.execute@0.2.0",
            "input_contracts": ["moonmold/spatial-operation-request@1.0.0"],
            "output_contracts": ["moonmold/spatial-operation-receipt@1.0.0"],
            "required_claim": "digital-artifact",
            "input_artifacts": ["requests/" + id + ".json"],
            "timeout_ms": 60000,
            "depends_on": [],
          }
        }
      ],
      "recorded_at": "2026-10-07T07:00:00Z",
    }),
  )
}

///|
fn single_fixture_receipt(request : @moonflow.AdapterRequest) -> Json {
  {
    "contract_id": "moonmold.spatial-operation-receipt.v1",
    "operation_ref": "moonmold/spatial.operation.execute@0.2.0",
    "request_id": request.request_id,
    "attempt_id": request.attempt_id,
    "idempotency_key": request.idempotency_key,
    "outcome": "applied",
    "claim_ceiling": "digital-artifact",
    "physical_authority": false,
    "review_required": true,
    "artifacts": [],
    "backend_qualification": {
      "evidence_class": "fixture-reference-only",
      "production_qualified": false,
      "physical_authority": false,
      "blender_evidence": false,
    },
  }
}

///|
test "single-step exact operation and authority are closed to version aliases" {
  let item = single_fixture_projection("single-run").items[0]
  assert_true(@moonflow.single_step_mold_item_supported(item))
  for
    operation in [
      "spatial.operation.execute", "moonmold/spatial.operation.execute@0.3.0", "moonmold/representation.validate@0.2.0",
    ] {
    assert_false(
      @moonflow.single_step_mold_item_supported({ ..item, operation, }),
    )
  }
  assert_false(
    @moonflow.single_step_mold_item_supported({
      ..item,
      requested_authority: "physical-effect",
    }),
  )
  assert_false(
    @moonflow.single_step_mold_item_supported({
      ..item,
      required_claim: "physical-readiness",
    }),
  )
}

///|
test "single-step workspace identities cannot collide across hyphenated run and item pairs" {
  let first = single_fixture_projection("a-b")
  let second = single_fixture_projection("a")
  let first_request = @moonflow.single_step_request_for_item(
    first,
    { ..first.items[0], work_item_id: "c", },
    "sha256:input",
    "2026-10-07T07:00:00Z",
  )
  let second_request = @moonflow.single_step_request_for_item(
    second,
    { ..second.items[0], work_item_id: "b-c", },
    "sha256:input",
    "2026-10-07T07:00:00Z",
  )
  assert_not_eq(first_request.attempt_id, second_request.attempt_id)
  assert_not_eq(first_request.request_id, second_request.request_id)
  assert_eq(first_request.attempt_id.length(), 72)
}

///|
test "single-step attempt identity is run-scoped and only the selected item reaches Review" {
  let projection = single_fixture_projection("single-run")
  let other = projection.items[1]
  let request = @moonflow.single_step_request_for_item(
    projection,
    projection.items[0],
    "sha256:inputs",
    "2026-10-07T07:00:00Z",
  )
  let second_run = single_fixture_projection("second-run")
  assert_not_eq(
    request.attempt_id,
    @moonflow.single_step_request_for_item(
      second_run,
      second_run.items[0],
      "sha256:inputs",
      "2026-10-07T07:00:00Z",
    ).attempt_id,
  )
  projection.apply(@moonflow.adapter_submission_event(projection, request))
  assert_eq(projection.items[1], other)
  let result = @moonflow.director_success_result_for_item(
    projection.items[0],
    "sha256:receipt",
    [@moonflow.single_step_mold_receipt_ref(request)],
    "2026-10-07T07:00:00Z",
  )
  @moonflow.single_step_validate_mold_result(
    request,
    result,
    single_fixture_receipt(request),
    "sha256:receipt",
    [],
  )
  projection.apply(@moonflow.adapter_reconciliation_event(projection, result))
  assert_eq(projection.items[0].status, @moonflow.Review)
  assert_eq(projection.items[0].attempt_count, 1)
  assert_eq(projection.items[0].acceptance_review_id, "")
  assert_eq(projection.items[1], other)
}

///|
test "single-step rejects wrong result identity digest artifacts refusal and inflated claim" {
  let projection = single_fixture_projection("single-run")
  let request = @moonflow.single_step_request_for_item(
    projection,
    projection.items[0],
    "sha256:inputs",
    "2026-10-07T07:00:00Z",
  )
  projection.apply(@moonflow.adapter_submission_event(projection, request))
  let valid = @moonflow.director_success_result_for_item(
    projection.items[0],
    "sha256:receipt",
    [@moonflow.single_step_mold_receipt_ref(request)],
    "2026-10-07T07:00:00Z",
  )
  for
    result in [
      { ..valid, request_id: "different", },
      { ..valid, attempt_id: "different", },
      { ..valid, idempotency_key: "different", },
      { ..valid, product_id: "moonrobo", },
      { ..valid, output_digest: "sha256:wrong", },
      { ..valid, output_artifacts: ["unapproved/output"], },
    ] {
    let denied = try {
      @moonflow.single_step_validate_mold_result(
        request,
        result,
        single_fixture_receipt(request),
        "sha256:receipt",
        [],
      )
      false
    } catch {
      _ => true
    }
    assert_true(denied)
  }
  for
    (field, value) in [
      ("outcome", "rejected".to_json()),
      ("claim_ceiling", "physical-readiness".to_json()),
      ("physical_authority", true.to_json()),
      ("review_required", false.to_json()),
    ] {
    guard single_fixture_receipt(request) is Object(fields) else {
      fail("fixture")
    }
    fields[field] = value
    let denied = try {
      @moonflow.single_step_validate_mold_result(
        request,
        valid,
        Json::object(fields),
        "sha256:receipt",
        [],
      )
      false
    } catch {
      _ => true
    }
    assert_true(denied)
  }
}
