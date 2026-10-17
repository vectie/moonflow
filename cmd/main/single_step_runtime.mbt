///|
struct SingleStepConfig {
  contract_id : String
  capability_ref : String
  envelope_ref : String
  usage_ref : String
  gate_executable : String
  gate_sha256 : String
  adapter_executable : String
  adapter_sha256 : String
} derive(FromJson)

///|
fn single_step_id(value : String) -> String raise {
  guard value.length() > 0 &&
    value.length() <= 160 &&
    !value.has_prefix("-") &&
    value.all(ch => {
      ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '-' || ch == '_'
    }) else {
    fail("single-step requires bounded safe identifiers")
  }
  value
}

///|
async fn single_step_executable(path : String, digest : String) -> Unit {
  guard path.has_prefix("/") &&
    @fs.realpath(path) == path &&
    @fs.kind(path, follow_symlink=false) == Regular &&
    digest == "sha256:" + sha256_hex(@fs.read_file(path).binary()) else {
    fail("single-step configured native executable identity changed")
  }
}

///|
async fn single_step_read_output(reader : &@io.Reader) -> String {
  let bytes : Array[Byte] = []
  for ;; {
    guard reader.read_some(max_len=8192) is Some(chunk) else { break }
    guard bytes.length() + chunk.length() <= 4 * 1024 * 1024 else {
      fail("single-step native output exceeded 4 MiB")
    }
    for byte in chunk {
      bytes.push(byte)
    }
  }
  @utf8.decode(Bytes::from_array(bytes))
}

///|
async fn single_step_process(
  executable : String,
  arguments : Array[String],
  root : String,
  timeout_ms : Int,
) -> UnattendedCommandResult {
  let result = @async.with_timeout_opt(timeout_ms, () => {
    @async.with_task_group(group => {
      let (out_pipe, stdout) = @process.read_from_process()
      let (err_pipe, stderr) = @process.read_from_process()
      let out_task = group.spawn(() => {
        defer out_pipe.close()
        single_step_read_output(out_pipe)
      })
      let err_task = group.spawn(() => {
        defer err_pipe.close()
        single_step_read_output(err_pipe)
      })
      let status = @process.run(
        executable,
        arguments,
        cwd=root,
        inherit_env=false,
        extra_env={ "HOME": "/dev/null", "PATH": "/dev/null" },
        stdout~,
        stderr~,
        cancel_handler=@process.hard_cancel(),
      )
      { status, stdout: out_task.wait(), stderr: err_task.wait(), }
    })
  })
  result.unwrap_or({
    status: 124,
    stdout: "",
    stderr: "Native single-step timeout; reconcile the original attempt",
  })
}

///|
async fn single_step_persist(
  root : String,
  run_id : String,
  events : Array[@moonflow.RuntimeEvent],
) -> @moonflow.RunProjection {
  let directory = plan_directory(
    root,
    ".moonsuite/products/moonflow/runs/" + run_id,
  )
  let projection = @moonflow.replay(run_id, events)
  @flow_host.atomic_replace_named_json_v1(
    directory,
    "events.json",
    @moonflow.event_array_json(events).stringify(indent=2),
  )
  @flow_host.atomic_replace_named_json_v1(
    directory,
    "projection.json",
    @moonflow.projection_json(projection).stringify(indent=2),
  )
  // No reviewer, observer, ready-event advance, or dependent handoff publishing.
  projection
}

///|
async fn single_step_gate(
  root : String,
  config : SingleStepConfig,
  projection : @moonflow.RunProjection,
  request : @moonflow.AdapterRequest,
  action_ref : String,
  artifact_paths : Array[String],
  at : String,
  reconcile : Bool,
) -> @pipeline.AutonomyBudgetUsage {
  let envelope = @pipeline.decode_autonomy_envelope(
    plan_read_json(root, config.envelope_ref),
  )
  guard envelope.workspace_root == root &&
    envelope.source_digest == projection.source_digest else {
    fail("single-step authority workspace or source binding differs")
  }
  let usage = @pipeline.decode_autonomy_budget_usage(
    plan_read_json(root, config.usage_ref),
  )
  let budget : @pipeline.AutonomyBudgetUsage = {
    model_tokens: 0,
    tool_calls: 1,
    storage_bytes: 1024 * 1024,
    attempts: if reconcile {
      0
    } else {
      1
    },
    concurrency: 1,
  }
  let suffix = if reconcile { "-reconcile" } else { "-execute" }
  let event_id = "event-" + request.attempt_id + suffix
  let event = @pipeline.autonomy_event_request_json({
    contract_id: "moongate.autonomy-event-request.v1",
    event_id,
    run_id: request.run_id,
    product_id: request.product_id,
    operation: request.operation,
    requested_authority: @pipeline.authority_class_from_id(
      request.requested_authority,
    ),
    claim: @pipeline.claim_class_from_id(request.required_claim),
    artifact_paths,
    external_destination: "",
    budget_request: budget,
    recorded_at: at,
  })
  let event_ref = action_ref + "/" + event_id + ".json"
  let directory = plan_directory(root, action_ref)
  @flow_host.atomic_replace_named_json_v1(
    directory,
    event_id + ".json",
    event.stringify(indent=2),
  )
  single_step_executable(config.gate_executable, config.gate_sha256)
  let decision_id = "decision-" + request.attempt_id + suffix
  let output = single_step_process(
    config.gate_executable,
    [
      "suite",
      "autonomy-check",
      "--root",
      root,
      "--envelope",
      root + "/" + config.envelope_ref,
      "--event",
      root + "/" + event_ref,
      "--usage",
      root + "/" + config.usage_ref,
      "--decision",
      decision_id,
      "--checked-at",
      at,
    ],
    root,
    30000,
  )
  @flow_host.atomic_replace_named_json_v1(
    directory,
    decision_id + ".process.json",
    (
      {
        "status": output.status,
        "stdout": output.stdout,
        "stderr": output.stderr,
      } : Json).stringify(indent=2),
  )
  guard output.status == 0 else {
    fail("MoonGate refused the selected single-step action")
  }
  let decision = @json.parse(output.stdout) catch {
    _ => fail("MoonGate returned no valid decision")
  }
  guard output.status == 0 &&
    plan_value(decision, "accepted") == true.to_json() &&
    plan_string(decision, "contract_id") == "moongate.autonomy-decision.v1" &&
    plan_string(decision, "decision_id") == decision_id &&
    plan_string(decision, "envelope_id") == envelope.envelope_id &&
    plan_string(decision, "event_id") == event_id &&
    plan_string(decision, "checked_at") == at else {
    fail("MoonGate refused the selected single-step action")
  }
  unattended_usage_add(usage, budget)
}
