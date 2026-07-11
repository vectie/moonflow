///|
fn safe_id(id : String, label : String) -> String raise {
  if id.trim().is_empty() ||
    id.contains("/") ||
    id.contains("\\") ||
    id.contains("..") {
    fail("\{label} must be a safe identifier")
  }
  id
}

///|
fn run_dir(workspace : String, run_id : String) -> String raise {
  let safe_run_id = safe_id(run_id, "run_id")
  let root = @moonflow.normalize_workspace_path(workspace)
  let path = "\{root}/.moonsuite/products/moonflow/runs/\{safe_run_id}"
  if !@moonflow.path_is_within_workspace(root, path) {
    fail("MoonFlow run directory escapes workspace")
  }
  path
}

///|
async fn read_json(path : String) -> Json {
  let text = @fs.read_file(path).text()
  @json.parse(text)
}

///|
async fn write_json(path : String, value : Json) -> Unit {
  @fs.write_file(
    path,
    @utf8.encode(value.stringify(indent=2) + "\n"),
    create=0o644,
    truncate=true,
  )
}

///|
async fn persist_run(
  workspace : String,
  run_id : String,
  events : Array[@moonflow.RuntimeEvent],
) -> @moonflow.RunProjection {
  let directory = run_dir(workspace, run_id)
  if !@fs.exists(directory) {
    @fs.mkdir(directory, permission=0o755, recursive=true)
  }
  let projection = @moonflow.replay(run_id, events)
  write_json("\{directory}/events.json", @moonflow.event_array_json(events))
  write_json(
    "\{directory}/projection.json",
    @moonflow.projection_json(projection),
  )
  projection
}

///|
async fn load_events(
  workspace : String,
  run_id : String,
) -> Array[@moonflow.RuntimeEvent] {
  let path = "\{run_dir(workspace, run_id)}/events.json"
  @moonflow.decode_event_array(read_json(path))
}

///|
async fn validate_artifact_ref(
  workspace : String,
  artifact_ref : String,
) -> Unit {
  if !@moonflow.artifact_ref_is_workspace_relative(artifact_ref) {
    fail("MoonFlow artifact must be a workspace-relative path")
  }
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let artifact_path = root + "/" + artifact_ref
  if !@fs.exists(artifact_path) {
    fail("MoonFlow artifact does not exist: \{artifact_ref}")
  }
  let canonical_artifact = @fs.realpath(artifact_path)
  if !@moonflow.path_is_within_workspace(root, canonical_artifact) {
    fail("MoonFlow artifact resolves outside workspace: \{artifact_ref}")
  }
}

///|
fn transition_kind(action : String) -> @moonflow.EventKind raise {
  match action {
    "ready" => ItemReady
    "start" => ItemStarted
    "waiting" => ItemWaiting
    "block" => ItemBlocked
    "review" => ItemReviewRequested
    "accept" => ItemAccepted
    "fail" => ItemFailed
    "cancel" => ItemCancelled
    "supersede" => ItemSuperseded
    "artifact" => ArtifactAttached
    "approve" => ApprovalGranted
    _ => fail("unsupported transition: \{action}")
  }
}

///|
async fn import_graph(workspace : String, graph_path : String) -> Unit {
  let graph = read_json(graph_path)
  let events = @moonflow.events_from_work_graph(graph)
  let run_id = events[0].run_id
  let projection = persist_run(workspace, run_id, events)
  println(@moonflow.projection_json(projection).stringify(indent=2))
}

///|
async fn show_status(workspace : String, run_id : String) -> Unit {
  let events = load_events(workspace, run_id)
  let projection = @moonflow.replay(run_id, events)
  println(@moonflow.projection_json(projection).stringify(indent=2))
}

///|
async fn append_transition(
  workspace : String,
  run_id : String,
  work_item_id : String,
  action : String,
  detail : String,
  recorded_at : String,
) -> Unit {
  ignore(safe_id(work_item_id, "work_item_id"))
  let events = load_events(workspace, run_id)
  let projection = @moonflow.replay(run_id, events)
  guard projection.find_item(work_item_id) is Some(item) else {
    fail("MoonFlow work item does not exist: \{work_item_id}")
  }
  let kind = transition_kind(action)
  let mut artifact_id = ""
  let mut authority_id = ""
  if kind == ArtifactAttached {
    validate_artifact_ref(workspace, detail)
    artifact_id = detail
  } else if kind == ApprovalGranted {
    authority_id = detail
  }
  events.push({
    sequence: projection.last_sequence + 1,
    event_id: "event-\{run_id}-\{action}-\{work_item_id}-\{projection.last_sequence + 1}",
    run_id,
    work_item_id,
    kind,
    product_id: item.product_id,
    declaration_id: item.declaration_id,
    book_id: projection.book_id,
    declaration_revision: projection.declaration_revision,
    source_digest: projection.source_digest,
    requested_authority: item.requested_authority,
    acceptance_criteria: item.acceptance_criteria.copy(),
    request_id: "",
    result_id: "",
    attempt_id: "",
    idempotency_key: "",
    external_job_id: "",
    attempt_status: "",
    input_digest: "",
    output_digest: "",
    output_artifacts: [],
    error_kind: "",
    compensable: false,
    depends_on: [],
    detail,
    artifact_id,
    authority_id,
    recorded_at,
  })
  let updated = persist_run(workspace, run_id, events)
  println(@moonflow.projection_json(updated).stringify(indent=2))
}

///|
async fn advance(
  workspace : String,
  run_id : String,
  recorded_at : String,
) -> Unit {
  let events = load_events(workspace, run_id)
  let projection = @moonflow.replay(run_id, events)
  for ready in @moonflow.ready_events(projection, recorded_at) {
    events.push(ready)
  }
  let updated = persist_run(workspace, run_id, events)
  println(@moonflow.projection_json(updated).stringify(indent=2))
}

///|
async fn submit_attempt(
  workspace : String,
  run_id : String,
  request_path : String,
) -> Unit {
  let events = load_events(workspace, run_id)
  let projection = @moonflow.replay(run_id, events)
  let request = @moonflow.decode_adapter_request(read_json(request_path))
  let event = @moonflow.adapter_submission_event(projection, request)
  if projection.applied_event_ids.contains(event.event_id) {
    println(@moonflow.projection_json(projection).stringify(indent=2))
    return
  }
  events.push(event)
  let updated = persist_run(workspace, run_id, events)
  println(@moonflow.projection_json(updated).stringify(indent=2))
}

///|
async fn reconcile_attempt(
  workspace : String,
  run_id : String,
  result_path : String,
) -> Unit {
  let events = load_events(workspace, run_id)
  let projection = @moonflow.replay(run_id, events)
  let result = @moonflow.decode_adapter_result(read_json(result_path))
  let event = @moonflow.adapter_reconciliation_event(projection, result)
  if projection.applied_event_ids.contains(event.event_id) {
    println(@moonflow.projection_json(projection).stringify(indent=2))
    return
  }
  events.push(event)
  let updated = persist_run(workspace, run_id, events)
  println(@moonflow.projection_json(updated).stringify(indent=2))
}

///|
async fn validate_capability(capability_path : String) -> Unit {
  let capability = @moonflow.validate_adapter_capability(
    read_json(capability_path),
  )
  println(capability.to_json().stringify(indent=2))
}

///|
fn usage() -> Unit {
  println(
    "MoonFlow usage:\n" +
    "  moonflow import-graph <workspace> <graph.json>\n" +
    "  moonflow status <workspace> <run-id>\n" +
    "  moonflow transition <workspace> <run-id> <work-item-id> <action> <recorded-at> [detail]\n" +
    "  moonflow advance <workspace> <run-id> <recorded-at>\n" +
    "  moonflow submit-attempt <workspace> <run-id> <request.json>\n" +
    "  moonflow reconcile-attempt <workspace> <run-id> <result.json>\n" +
    "  moonflow validate-capability <capability.json>",
  )
}

///|
async fn main {
  let args = @env.args()
  match args[1:] {
    ["import-graph", workspace, graph_path] =>
      import_graph(workspace, graph_path)
    ["status", workspace, run_id] => show_status(workspace, run_id)
    ["transition", workspace, run_id, work_item_id, action, recorded_at, detail] =>
      append_transition(
        workspace, run_id, work_item_id, action, detail, recorded_at,
      )
    ["transition", workspace, run_id, work_item_id, action, recorded_at] =>
      append_transition(
        workspace, run_id, work_item_id, action, "", recorded_at,
      )
    ["advance", workspace, run_id, recorded_at] =>
      advance(workspace, run_id, recorded_at)
    ["submit-attempt", workspace, run_id, request_path] =>
      submit_attempt(workspace, run_id, request_path)
    ["reconcile-attempt", workspace, run_id, result_path] =>
      reconcile_attempt(workspace, run_id, result_path)
    ["validate-capability", capability_path] =>
      validate_capability(capability_path)
    ["version"] => println("MoonFlow \{@moonflow.runtime_protocol_id()}")
    _ => usage()
  }
}
