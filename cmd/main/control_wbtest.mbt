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
