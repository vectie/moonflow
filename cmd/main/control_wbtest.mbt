///|
async test "run control pauses, resumes, cancels, and only narrows authority" {
  let workspace = "/tmp/moonflow-run-control-test"
  let run_id = "control-run"
  let directory = run_dir(workspace, run_id)
  @fs.mkdir(directory, permission=0o755, recursive=true)
  write_json(directory + "/events.json", Json::array([]))
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
