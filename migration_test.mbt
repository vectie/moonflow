///|
fn accepted_checkpoint(
  work_item_id : String,
  declaration_id : String,
  depends_on : Array[String],
  criterion : String,
) -> RuntimeItem {
  {
    work_item_id,
    declaration_id,
    product_id: if declaration_id == "research" {
      "moonwiki"
    } else {
      "moonrobo"
    },
    requested_authority: "sandbox-execution",
    acceptance_criteria: [criterion],
    operation: declaration_id,
    input_contracts: ["test.input.v1"],
    output_contracts: ["test.output.v1"],
    required_claim: "research-evidence",
    input_artifacts: ["evidence/input.json"],
    timeout_ms: 1000,
    depends_on,
    status: Accepted,
    attempt_count: 1,
    request_id: "request-\{work_item_id}",
    result_id: "result-\{work_item_id}",
    active_attempt_id: "attempt-\{work_item_id}",
    idempotency_key: "idempotency-\{work_item_id}",
    external_job_id: "job-\{work_item_id}",
    attempt_status: "succeeded",
    input_digest: "sha256:input-\{work_item_id}",
    output_digest: "sha256:output-\{work_item_id}",
    error_kind: "",
    compensable: false,
    blocker: "",
    acceptance_review_id: "review-\{work_item_id}",
    acceptance_review_artifact: "evidence/review-\{work_item_id}.json",
    acceptance_reviewer_id: "reviewer-\{work_item_id}",
    artifacts: ["evidence/output-\{work_item_id}.json"],
    approvals: ["reviewer-\{work_item_id}"],
  }
}

///|
fn accepted_parent_projection() -> RunProjection {
  {
    run_id: "robot-r1",
    book_id: "robot-book",
    declaration_revision: "r1",
    source_digest: "sha256:r1",
    last_sequence: 20,
    items: [
      accepted_checkpoint("research-r1", "research", [], "sources are reviewed"),
      accepted_checkpoint(
        "design-r1",
        "design",
        ["research-r1"],
        "robot boundary includes excavation only",
      ),
    ],
    applied_event_ids: [],
    applied_events: [],
    outcome: "accepted",
  }
}

///|
fn revised_graph() -> Json {
  {
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "robot-r2",
    "book_id": "robot-book",
    "declaration_revision": "r2",
    "source_digest": "sha256:r2",
    "items": [
      {
        "work_item_id": "research-r2",
        "declaration_id": "research",
        "product_id": "moonwiki",
        "requested_authority": "sandbox-execution",
        "acceptance_criteria": ["sources are reviewed"],
        "operation": "query-evidence",
        "input_contracts": ["test.input.v1"],
        "output_contracts": ["test.output.v1"],
        "required_claim": "research-evidence",
        "input_artifacts": ["evidence/input.json"],
        "timeout_ms": 1000,
        "depends_on": [],
      },
      {
        "work_item_id": "design-r2",
        "declaration_id": "design",
        "product_id": "moonrobo",
        "requested_authority": "sandbox-execution",
        "acceptance_criteria": [
          "robot boundary includes excavation, haul, and safe return",
        ],
        "operation": "build",
        "input_contracts": ["test.input.v1"],
        "output_contracts": ["test.output.v1"],
        "required_claim": "digital-artifact",
        "input_artifacts": ["evidence/input.json"],
        "timeout_ms": 1000,
        "depends_on": ["research-r2"],
      },
      {
        "work_item_id": "validation-r2",
        "declaration_id": "validation",
        "product_id": "moonmoon",
        "requested_authority": "sandbox-execution",
        "acceptance_criteria": ["negative scenarios are reproduced"],
        "operation": "validate",
        "input_contracts": ["test.input.v1"],
        "output_contracts": ["test.output.v1"],
        "required_claim": "simulation-evidence",
        "input_artifacts": ["evidence/input.json"],
        "timeout_ms": 1000,
        "depends_on": ["design-r2"],
      },
    ],
    "recorded_at": "2026-07-12T10:00:00+08:00",
  }
}

///|
test "native revision reuses exact checkpoints and invalidates changed work" {
  let parent = accepted_parent_projection()
  let result = revise_run(
    parent,
    revised_graph(),
    "migration-robot-r1-r2",
    ".moonsuite/products/moonbook/revisions/robot-r2.json",
    "2026-07-12T10:01:00+08:00",
  )
  assert_eq(result.receipt.reused_count, 1)
  assert_eq(result.receipt.invalidated_count, 1)
  assert_eq(result.receipt.new_count, 1)
  let child = replay("robot-r2", result.events)
  guard child.find_item("research-r2") is Some(research) else {
    fail("expected migrated research")
  }
  assert_true(research.status is Accepted)
  assert_eq(research.attempt_status, "checkpoint-reused")
  assert_eq(research.request_id, "request-research-r1")
  assert_eq(research.input_digest, "sha256:input-research-r1")
  assert_eq(research.idempotency_key, "idempotency-research-r1")
  guard child.find_item("design-r2") is Some(design) else {
    fail("expected changed design")
  }
  assert_true(design.status is Proposed)
  assert_eq(parent.declaration_revision, "r1")
  assert_eq(parent.items[0].work_item_id, "research-r1")
}

///|
test "revision cannot rewrite the same run or revision" {
  let parent = accepted_parent_projection()
  let same_run = revised_graph()
  guard same_run is Object(fields) else { fail("expected graph") }
  fields["graph_id"] = Json::string("robot-r1")
  try
    revise_run(
      parent, same_run, "migration-invalid", ".moonsuite/revision.json", "2026-07-12T10:01:00+08:00",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected history rewrite rejection")
  }
}
