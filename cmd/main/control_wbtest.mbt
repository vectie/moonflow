///|
async test "run control pauses, resumes, cancels, and only narrows authority" {
  let workspace = "/tmp/moonflow-run-control-test"
  let run_id = "control-run"
  let directory = run_dir(workspace, run_id)
  if !@fs.exists(directory) {
    @fs.mkdir(directory, permission=0o755, recursive=true)
  }
  let events = @moonflow.events_from_work_graph({
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": run_id,
    "book_id": "control-book",
    "declaration_revision": "r1",
    "source_digest": "sha256:control",
    "items": [
      {
        "work_item_id": "work-control",
        "declaration_id": "control",
        "product_id": "moonwiki",
        "requested_authority": "observe",
        "acceptance_criteria": ["control remains bounded"],
        "operation": "research-goal",
        "input_contracts": ["goal.v1"],
        "output_contracts": ["evidence.v1"],
        "required_claim": "research-evidence",
        "input_artifacts": ["inputs/goal.txt"],
        "timeout_ms": 60000,
        "depends_on": [],
      },
    ],
    "recorded_at": "2026-07-12T00:00:00Z",
  })
  write_json(directory + "/events.json", @moonflow.event_array_json(events))
  write_json(directory + "/control.json", {
    "contract_id": "moonflow.run-control.v1",
    "run_id": run_id,
    "state": "running",
    "authority_ceiling": "",
    "reason": "",
    "recorded_at": "2026-07-12T00:00:00Z",
  })
  write_run_control(
    workspace, run_id, "pause", "2026-07-12T00:00:00Z", "operator inspection",
  )
  let paused = read_json(directory + "/control.json").stringify()
  assert_true(paused.contains("\"state\":\"paused\""))
  write_run_control(workspace, run_id, "resume", "2026-07-12T00:01:00Z", "")
  write_run_control(
    workspace, run_id, "narrow-authority", "2026-07-12T00:02:00Z", "sandbox-execution",
  )
  write_run_control(
    workspace, run_id, "narrow-authority", "2026-07-12T00:03:00Z", "observe",
  )
  let narrowed = read_json(directory + "/control.json").stringify()
  assert_true(narrowed.contains("\"authority_ceiling\":\"observe\""))
  let widened = try
    write_run_control(
      workspace, run_id, "narrow-authority", "2026-07-12T00:04:00Z", "workspace-mutation",
    )
    |> Ok
  catch {
    error => Err(error)
  }
  assert_true(widened is Err(_))
  write_run_control(
    workspace, run_id, "cancel", "2026-07-12T00:05:00Z", "stop requested",
  )
  let cancelled = read_json(directory + "/control.json").stringify()
  assert_true(cancelled.contains("\"state\":\"cancelled\""))
}

///|
async test "adapter circuit opens after three failures and a probe resets it" {
  let workspace = "/tmp/moonflow-adapter-circuit-test"
  let adapter_id = "test-adapter"
  record_adapter_health(workspace, adapter_id, true, "2026-07-12T01:00:00Z")
  let health_path = adapter_health_path(workspace, adapter_id)
  assert_eq(json_int_or(read_json(health_path), "consecutive_failures", -1), 0)
  for index in 1..<=3 {
    record_adapter_health(
      workspace,
      adapter_id,
      false,
      "2026-07-12T01:0\{index}:00Z",
    )
  }
  assert_eq(json_int_or(read_json(health_path), "consecutive_failures", -1), 3)
  assert_true(
    acquire_adapter_probe(workspace, adapter_id, "2026-07-12T01:04:00Z"),
  )
  assert_false(
    acquire_adapter_probe(workspace, adapter_id, "2026-07-12T01:05:00Z"),
  )
  record_adapter_health(workspace, adapter_id, true, "2026-07-12T01:10:00Z")
  assert_eq(json_int_or(read_json(health_path), "consecutive_failures", -1), 0)
}

///|
async test "unattended source mutations fail closed with a durable receipt" {
  let events = @moonflow.events_from_work_graph({
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "source-bound-run",
    "book_id": "source-bound-book",
    "declaration_revision": "r1",
    "source_digest": "sha256:source-bound",
    "items": [
      {
        "work_item_id": "work-source",
        "declaration_id": "source",
        "product_id": "moonwiki",
        "requested_authority": "observe",
        "acceptance_criteria": ["source identity remains immutable"],
        "operation": "research-goal",
        "input_contracts": ["goal.v1"],
        "output_contracts": ["evidence.v1"],
        "required_claim": "research-evidence",
        "input_artifacts": ["inputs/goal.txt"],
        "timeout_ms": 60000,
        "depends_on": [],
      },
    ],
    "recorded_at": "2026-07-12T00:00:00Z",
  })
  let projection = @moonflow.replay("source-bound-run", events)
  let mismatch = try
    reject_unattended_binding(
      "/tmp/moonflow-source-binding-test",
      projection.run_id,
      "source_digest",
      projection.source_digest,
      "sha256:mutated",
      "2026-07-12T00:01:00Z",
    )
    |> Ok
  catch {
    error => Err(error)
  }
  assert_true(mismatch is Err(_))
  let receipt = read_json(
    run_dir("/tmp/moonflow-source-binding-test", projection.run_id) +
    "/autonomy-binding-rejection.json",
  ).stringify()
  assert_true(receipt.contains("\"field\":\"source_digest\""))
  assert_true(receipt.contains("sha256:mutated"))
}

///|
async test "product finals are snapshotted immutably before review" {
  let workspace = "/tmp/moonflow-immutable-output-test"
  let dispatch_ref = ".moonsuite/products/moonflow/runs/output-test/dispatch"
  if !@fs.exists(workspace + "/" + dispatch_ref) {
    @fs.mkdir(workspace + "/" + dispatch_ref, permission=0o755, recursive=true)
  }
  if !@fs.exists(workspace + "/books/output-test/flow/outputs") {
    @fs.mkdir(
      workspace + "/books/output-test/flow/outputs",
      permission=0o755,
      recursive=true,
    )
  }
  let source_ref = "books/output-test/flow/outputs/result.json"
  @fs.write_file(
    workspace + "/" + source_ref,
    @utf8.encode("{\"version\":1}"),
    create=0o644,
    truncate=true,
  )
  let snapshots = snapshot_unattended_outputs(
    workspace,
    dispatch_ref,
    "attempt-output-1",
    [source_ref],
  )
  assert_eq(snapshots.length(), 1)
  @fs.write_file(
    workspace + "/" + source_ref,
    @utf8.encode("{\"version\":2}"),
    create=0o644,
    truncate=true,
  )
  assert_true(
    @fs.read_file(workspace + "/" + snapshots[0]).text().contains("version\":1"),
  )
  let conflict = try
    snapshot_unattended_outputs(workspace, dispatch_ref, "attempt-output-1", [
      source_ref,
    ])
    |> Ok
  catch {
    error => Err(error)
  }
  assert_true(conflict is Err(_))
}
