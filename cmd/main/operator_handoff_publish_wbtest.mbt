///|
fn receiver_test_action(catalog : Json, status : String) -> Json raise {
  guard catalog is Object(fields) &&
    fields.get("actions") is Some(Array(actions)) else {
    fail("missing receiver actions")
  }
  for action in actions {
    guard action is Object(action_fields) else { continue }
    if operator_json_string(action_fields, "status") == Some(status) {
      return action
    }
  }
  fail("missing receiver action status \{status}")
}

///|
fn receiver_test_binding(action : Json) -> Map[String, Json] raise {
  guard action is Object(fields) &&
    fields.get("receiver") is Some(Object(receiver)) else {
    fail("missing receiver binding")
  }
  receiver
}

///|
async test "generic receiver handoff accepts, unlocks, denies, and recovers without replay" {
  let workspace = "/tmp/moonflow-operator-handoff-" + @async.now().to_string()
  let run_id = "generic-handoff-run"
  @fs.mkdir(workspace + "/requests", permission=0o755, recursive=true)
  @fs.mkdir(workspace + "/evidence", permission=0o755, recursive=true)
  @fs.write_file(
    workspace + "/requests/build.json",
    @utf8.encode("{\"request\":\"build\"}\n"),
    create=0o644,
    truncate=true,
  )
  @fs.write_file(
    workspace + "/evidence/output.json",
    @utf8.encode("{\"result\":\"built\"}\n"),
    create=0o644,
    truncate=true,
  )
  @fs.write_file(
    workspace + "/evidence/authority.json",
    @utf8.encode("{\"decision\":\"granted\"}\n"),
    create=0o644,
    truncate=true,
  )
  let events = @moonflow.events_from_work_graph({
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": run_id,
    "book_id": "operator-book",
    "declaration_revision": "r1",
    "source_digest": "sha256:operator-source",
    "items": [
      {
        "work_item_id": "build-output",
        "declaration_id": "build-output-r1",
        "product_id": "product-one",
        "requested_authority": "workspace-mutation",
        "acceptance_criteria": ["reviewed output exists"],
        "operation": "product-one/build@1.0.0",
        "input_contracts": ["product-one/request@1.0.0"],
        "output_contracts": ["product-one/receipt@1.0.0"],
        "required_claim": "digital-artifact",
        "input_artifacts": ["requests/build.json"],
        "timeout_ms": 60000,
        "depends_on": [],
      },
      {
        "work_item_id": "review-output",
        "declaration_id": "review-output-r1",
        "product_id": "product-two",
        "requested_authority": "observe",
        "acceptance_criteria": ["review disposition exists"],
        "operation": "product-two/review@1.0.0",
        "input_contracts": ["product-one/receipt@1.0.0"],
        "output_contracts": ["product-two/receipt@1.0.0"],
        "required_claim": "reviewed-evidence",
        "input_artifacts": ["evidence/output.json"],
        "timeout_ms": 60000,
        "depends_on": ["build-output"],
      },
    ],
    "recorded_at": "2026-07-31T00:00:00Z",
  })
  ignore(persist_run(workspace, run_id, events))
  let directory = run_dir(workspace, run_id)
  let initial_catalog = read_json(directory + "/operator-actions.json")
  assert_true(
    initial_catalog.stringify().contains("\"contract_version\":\"2.1.0\""),
  )
  let pending = receiver_test_action(initial_catalog, "pending")
  let binding = receiver_test_binding(pending)
  let token = receiver_string(binding, "handoff_token")
  let digest = receiver_string(binding, "handoff_digest")
  assert_true(operator_token_is_safe(token))
  assert_eq(
    receiver_string(binding, "intake_path"),
    "/api/moonflow/runs/\{run_id}/handoffs/\{token}",
  )
  guard pending is Object(pending_fields) &&
    operator_json_string(pending_fields, "handoff_ref") is Some(handoff_ref) else {
    fail("missing handoff ref")
  }
  let handoff = read_json(directory + "/" + handoff_ref)
  assert_true(
    handoff
    .stringify()
    .contains("\"contract_id\":\"moonflow.operator-handoff.v2\""),
  )
  let outputs = ["evidence/authority.json", "evidence/output.json"]
  let output_digest = declared_input_digest(workspace, outputs)
  @fs.mkdir(workspace + "/submissions", permission=0o755, recursive=true)
  let receipt : Json = {
    "contract_id": "moonflow.receiver-receipt.v1",
    "contract_version": "1.0.0",
    "receipt_id": "receipt-build-1",
    "handoff_token": token,
    "handoff_digest": digest,
    "run_id": run_id,
    "work_item_id": "build-output",
    "declaration_id": "build-output-r1",
    "product_id": "product-one",
    "operation": "product-one/build@1.0.0",
    "request_id": receiver_string(binding, "request_id"),
    "attempt_id": receiver_string(binding, "attempt_id"),
    "idempotency_key": receiver_string(binding, "idempotency_key"),
    "decision": "accepted",
    "output_contracts": ["product-one/receipt@1.0.0"],
    "output_artifacts": outputs,
    "output_digest": output_digest,
    "authority": {
      "requested_authority": "workspace-mutation",
      "decision": "granted",
      "receipt_ref": "evidence/authority.json",
    },
    "review": {
      "review_id": "review-build-1",
      "decision": "accepted",
      "reviewer_id": "receiver-reviewer",
      "review_authority_id": "receiver-review-authority",
      "criteria": [
        {
          "criterion": "reviewed output exists",
          "satisfied": true,
          "evidence_refs": ["evidence/output.json"],
          "note": "The declared output was reviewed.",
        },
      ],
    },
    "owner_id": "product-one-operator",
    "recorded_at": "2026-07-31T00:01:00Z",
  }
  write_json(workspace + "/submissions/accepted.json", receipt)
  receive_operator_receipt(
    workspace, run_id, token, "submissions/accepted.json",
  )
  let accepted_projection = @moonflow.replay(
    run_id,
    load_events(workspace, run_id),
  )
  assert_eq(
    accepted_projection.find_item("build-output").unwrap().status,
    @moonflow.Accepted,
  )
  assert_eq(
    accepted_projection.find_item("review-output").unwrap().status,
    @moonflow.Ready,
  )
  let after_accept = read_json(directory + "/operator-actions.json")
  ignore(receiver_test_action(after_accept, "accepted"))
  let second_pending = receiver_test_action(after_accept, "pending")
  let second_binding = receiver_test_binding(second_pending)
  let second_token = receiver_string(second_binding, "handoff_token")
  let denied : Json = {
    "contract_id": "moonflow.receiver-receipt.v1",
    "contract_version": "1.0.0",
    "receipt_id": "receipt-review-denied-1",
    "handoff_token": second_token,
    "handoff_digest": receiver_string(second_binding, "handoff_digest"),
    "run_id": run_id,
    "work_item_id": "review-output",
    "declaration_id": "review-output-r1",
    "product_id": "product-two",
    "operation": "product-two/review@1.0.0",
    "request_id": receiver_string(second_binding, "request_id"),
    "attempt_id": receiver_string(second_binding, "attempt_id"),
    "idempotency_key": receiver_string(second_binding, "idempotency_key"),
    "decision": "denied",
    "output_contracts": ["product-two/receipt@1.0.0"],
    "output_artifacts": [],
    "output_digest": "",
    "authority": {
      "requested_authority": "observe",
      "decision": "denied",
      "receipt_ref": "",
    },
    "review": {
      "review_id": "review-output-denied-1",
      "decision": "rejected",
      "reviewer_id": "receiver-reviewer",
      "review_authority_id": "receiver-review-authority",
      "criteria": [
        {
          "criterion": "review disposition exists",
          "satisfied": false,
          "evidence_refs": [],
          "note": "The receiver denied this result.",
        },
      ],
    },
    "owner_id": "product-two-operator",
    "recorded_at": "2026-07-31T00:02:00Z",
  }
  write_json(workspace + "/submissions/denied.json", denied)
  receive_operator_receipt(
    workspace, run_id, second_token, "submissions/denied.json",
  )
  let denied_projection = @moonflow.replay(
    run_id,
    load_events(workspace, run_id),
  )
  assert_eq(
    denied_projection.find_item("review-output").unwrap().status,
    @moonflow.Failed,
  )
  ignore(
    receiver_test_action(
      read_json(directory + "/operator-actions.json"),
      "denied",
    ),
  )
  let record_path = directory + "/operator-receipts/" + token + ".json"
  let staged = operator_receiver_record_json(
    run_id,
    load_operator_handoff_for_token(directory, run_id, token),
    decode_operator_receiver_receipt(receipt),
    "received",
  )
  write_json(record_path, staged)
  recover_operator_receipts(workspace, run_id)
  assert_eq(receiver_record_stage(read_json(record_path)), "applied")
}

///|
async test "explicit v1 authority action catalogs remain authoritative" {
  let workspace = "/tmp/moonflow-operator-v1-" + @async.now().to_string()
  let run_id = "authority-action-run"
  let directory = run_dir(workspace, run_id)
  @fs.mkdir(directory, permission=0o755, recursive=true)
  let explicit : Json = {
    "contract_id": "moonflow.operator-actions.v1",
    "contract_version": "1.0.0",
    "run_id": run_id,
    "actions": [],
  }
  write_json(directory + "/operator-actions.json", explicit)
  let events = @moonflow.events_from_work_graph({
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": run_id,
    "book_id": "operator-book",
    "declaration_revision": "r1",
    "source_digest": "sha256:operator-v1",
    "items": [
      {
        "work_item_id": "operate",
        "declaration_id": "operate-r1",
        "product_id": "product-one",
        "requested_authority": "observe",
        "acceptance_criteria": ["receipt exists"],
        "operation": "product-one/observe@1.0.0",
        "input_contracts": ["product-one/observe-request@1.0.0"],
        "output_contracts": ["product-one/observe-receipt@1.0.0"],
        "required_claim": "research-evidence",
        "input_artifacts": ["requests/observe.json"],
        "timeout_ms": 1000,
        "depends_on": [],
      },
    ],
    "recorded_at": "2026-07-31T00:00:00Z",
  })
  ignore(persist_run(workspace, run_id, events))
  assert_eq(read_json(directory + "/operator-actions.json"), explicit)
}
