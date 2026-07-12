///|
test "Work graph import registers all items before readiness" {
  let graph : Json = {
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "flow-generic-r1",
    "book_id": "generic",
    "declaration_revision": "r1",
    "source_digest": "sha256:generic-r1",
    "items": [
      {
        "work_item_id": "research",
        "declaration_id": "research",
        "product_id": "moonwiki",
        "requested_authority": "observe",
        "acceptance_criteria": ["reviewed evidence is attached"],
        "operation": "query-evidence",
        "input_contracts": ["test.input.v1"],
        "output_contracts": ["test.output.v1"],
        "required_claim": "research-evidence",
        "input_artifacts": ["evidence/input.json"],
        "timeout_ms": 1000,
        "depends_on": [],
      },
      {
        "work_item_id": "validate",
        "declaration_id": "validate",
        "product_id": "moonmoon",
        "requested_authority": "sandbox-execution",
        "acceptance_criteria": ["simulation gate passes"],
        "operation": "simulate",
        "input_contracts": ["test.input.v1"],
        "output_contracts": ["test.output.v1"],
        "required_claim": "simulation-evidence",
        "input_artifacts": ["evidence/input.json"],
        "timeout_ms": 1000,
        "depends_on": ["research"],
      },
    ],
    "recorded_at": "2026-07-11T00:00:00Z",
  }
  let events = @moonflow.events_from_work_graph(graph)
  assert_eq(events.length(), 4)
  assert_true(events[1].kind is ItemRegistered)
  assert_true(events[2].kind is ItemRegistered)
  assert_true(events[3].kind is ItemReady)
  let projection = @moonflow.replay("flow-generic-r1", events)
  json_inspect(projection.runnable_item_ids(), content=["research"])
  assert_eq(projection.book_id, "generic")
  assert_eq(projection.declaration_revision, "r1")
  assert_eq(projection.items[0].declaration_id, "research")
  assert_eq(projection.items[1].requested_authority, "sandbox-execution")
}

///|
test "Work graph import fails closed on missing source linkage" {
  let graph : Json = {
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "flow-invalid-r1",
    "book_id": "invalid",
    "declaration_revision": "r1",
    "source_digest": "sha256:invalid-r1",
    "items": [
      {
        "work_item_id": "research",
        "product_id": "moonwiki",
        "requested_authority": "observe",
        "acceptance_criteria": ["evidence is reviewed"],
        "operation": "query-evidence",
        "input_contracts": ["test.input.v1"],
        "output_contracts": ["test.output.v1"],
        "required_claim": "research-evidence",
        "input_artifacts": ["evidence/input.json"],
        "timeout_ms": 1000,
        "depends_on": [],
      },
    ],
    "recorded_at": "2026-07-11T00:00:00Z",
  }
  try @moonflow.events_from_work_graph(graph) catch {
    error => assert_true("\{error}".contains("declaration_id"))
  } noraise {
    _ => fail("expected missing declaration linkage to fail")
  }
}

///|
test "Work graph import fails closed on unknown dependencies" {
  let graph : Json = {
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "flow-invalid-dependency-r1",
    "book_id": "invalid",
    "declaration_revision": "r1",
    "source_digest": "sha256:invalid-dependency-r1",
    "items": [
      {
        "work_item_id": "validate",
        "declaration_id": "validate",
        "product_id": "moonmoon",
        "requested_authority": "sandbox-execution",
        "acceptance_criteria": ["simulation gate passes"],
        "operation": "simulate",
        "input_contracts": ["test.input.v1"],
        "output_contracts": ["test.output.v1"],
        "required_claim": "simulation-evidence",
        "input_artifacts": ["evidence/input.json"],
        "timeout_ms": 1000,
        "depends_on": ["missing-research"],
      },
    ],
    "recorded_at": "2026-07-11T00:00:00Z",
  }
  try @moonflow.events_from_work_graph(graph) catch {
    error => assert_true("\{error}".contains("unknown dependency"))
  } noraise {
    _ => fail("expected unknown dependency to fail")
  }
}

///|
test "Work graph import fails closed on cycles" {
  let graph : Json = {
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "flow-cycle-r1",
    "book_id": "cycle",
    "declaration_revision": "r1",
    "source_digest": "sha256:cycle-r1",
    "items": [
      {
        "work_item_id": "a",
        "declaration_id": "a",
        "product_id": "moonwiki",
        "requested_authority": "observe",
        "acceptance_criteria": ["a passes"],
        "operation": "test-a",
        "input_contracts": ["test.input.v1"],
        "output_contracts": ["test.output.v1"],
        "required_claim": "execution-result",
        "input_artifacts": ["evidence/input.json"],
        "timeout_ms": 1000,
        "depends_on": ["b"],
      },
      {
        "work_item_id": "b",
        "declaration_id": "b",
        "product_id": "moonwiki",
        "requested_authority": "observe",
        "acceptance_criteria": ["b passes"],
        "operation": "test-b",
        "input_contracts": ["test.input.v1"],
        "output_contracts": ["test.output.v1"],
        "required_claim": "execution-result",
        "input_artifacts": ["evidence/input.json"],
        "timeout_ms": 1000,
        "depends_on": ["a"],
      },
    ],
    "recorded_at": "2026-07-11T00:00:00Z",
  }
  try @moonflow.events_from_work_graph(graph) catch {
    error => assert_true("\{error}".contains("dependency cycle"))
  } noraise {
    _ => fail("expected dependency cycle to fail")
  }
}

///|
test "Work graph import rejects unknown authority" {
  let graph : Json = {
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "flow-authority-r1",
    "book_id": "authority",
    "declaration_revision": "r1",
    "source_digest": "sha256:authority-r1",
    "items": [
      {
        "work_item_id": "publish",
        "declaration_id": "publish",
        "product_id": "mooncode",
        "requested_authority": "unbounded",
        "acceptance_criteria": ["published"],
        "operation": "publish",
        "input_contracts": ["test.input.v1"],
        "output_contracts": ["test.output.v1"],
        "required_claim": "external-effect-claim",
        "input_artifacts": ["evidence/input.json"],
        "timeout_ms": 1000,
        "depends_on": [],
      },
    ],
    "recorded_at": "2026-07-11T00:00:00Z",
  }
  try @moonflow.events_from_work_graph(graph) catch {
    error => {
      assert_true("\{error}".contains("requested_authority"))
      assert_true("\{error}".contains("unbounded"))
    }
  } noraise {
    _ => fail("expected unknown authority to fail")
  }
}

///|
test "ready event generation advances only accepted dependencies" {
  let events = [
    event(0, "event-run", RunCreated),
    event(
      1,
      "register-a",
      ItemRegistered,
      work_item_id="a",
      product_id="moonwiki",
    ),
    event(
      2,
      "register-b",
      ItemRegistered,
      work_item_id="b",
      product_id="moonmoon",
      depends_on=["a"],
    ),
    event(3, "ready-a", ItemReady, work_item_id="a"),
  ]
  let projection = @moonflow.replay("flow-selene-r1", events)
  let request : @moonflow.AdapterRequest = {
    request_id: "request-a",
    run_id: projection.run_id,
    work_item_id: "a",
    declaration_id: "declaration-a",
    attempt_id: "attempt-a",
    idempotency_key: "idem-a",
    product_id: "moonwiki",
    operation: "query-evidence",
    requested_authority: "observe",
    acceptance_criteria: ["result is reviewed"],
    input_contracts: ["goal.v1"],
    output_contracts: ["evidence.v1"],
    required_claim: "research-evidence",
    input_digest: "sha256:input-a",
    input_artifacts: [],
    timeout_ms: 1000,
    created_at: "2026-07-11T00:00:01Z",
  }
  projection.apply(@moonflow.adapter_submission_event(projection, request))
  let result : @moonflow.AdapterResult = {
    result_id: "result-a",
    request_id: "request-a",
    attempt_id: "attempt-a",
    idempotency_key: "idem-a",
    product_id: "moonwiki",
    external_job_id: "job-a",
    status: Succeeded,
    output_digest: "sha256:output-a",
    output_artifacts: ["books/selene/outputs/a.json"],
    error_kind: "",
    compensable: false,
    recorded_at: "2026-07-11T00:00:02Z",
  }
  projection.apply(@moonflow.adapter_reconciliation_event(projection, result))
  let receipt : @moonflow.AcceptanceReviewReceipt = {
    contract_id: "moonflow.acceptance-review.v1",
    review_id: "review-a",
    run_id: projection.run_id,
    work_item_id: "a",
    declaration_id: "declaration-a",
    result_id: "result-a",
    attempt_id: "attempt-a",
    output_digest: "sha256:output-a",
    decision: "accepted",
    criteria: [
      {
        criterion: "declared criteria pass",
        satisfied: true,
        evidence_refs: ["books/selene/outputs/a.json"],
        note: "The attached evidence satisfies the declaration.",
      },
    ],
    reviewer_id: "reviewer-a",
    review_authority_id: "book-owner-review",
    receipt_artifact: "books/selene/reviews/a.json",
    recorded_at: "2026-07-11T00:00:03Z",
  }
  projection.apply(@moonflow.acceptance_review_event(projection, receipt))
  let ready = @moonflow.ready_events(projection, "2026-07-11T00:01:00Z")
  assert_eq(ready.length(), 1)
  assert_eq(ready[0].work_item_id, "b")
}
