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
fn hex_digit(value : Int) -> Char {
  if value < 10 {
    ('0'.to_int() + value).unsafe_to_char()
  } else {
    ('a'.to_int() + value - 10).unsafe_to_char()
  }
}

///|
fn sha256_hex(bytes : Bytes) -> String {
  let digest = @crypto.sha256(bytes)
  let builder = StringBuilder::new()
  for byte in digest {
    let value = byte.to_int()
    builder.write_char(hex_digit(value / 16))
    builder.write_char(hex_digit(value % 16))
  }
  builder.to_string()
}

///|
async fn ensure_directory(path : String) -> Unit {
  if !@fs.exists(path) {
    @fs.mkdir(path, permission=0o755, recursive=true)
  }
}

///|
async fn revise_run_command(
  workspace : String,
  parent_run_id : String,
  child_graph_ref : String,
  proposal_ref : String,
  migration_id : String,
  recorded_at : String,
) -> Unit {
  validate_artifact_ref(workspace, child_graph_ref)
  validate_artifact_ref(workspace, proposal_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let parent = @moonflow.replay(
    parent_run_id,
    load_events(workspace, parent_run_id),
  )
  let result = @moonflow.revise_run(
    parent,
    read_json(root + "/" + child_graph_ref),
    migration_id,
    proposal_ref,
    recorded_at,
  )
  let child_directory = run_dir(workspace, result.receipt.child_run_id)
  let event_path = child_directory + "/events.json"
  let migration_path = child_directory + "/migration.json"
  let mut events_to_persist = result.events
  if @fs.exists(event_path) {
    let existing_events = @moonflow.decode_event_array(read_json(event_path))
    if result.events.any(expected => {
        !existing_events.any(persisted => persisted == expected)
      }) {
      fail("child run identity already exists with different migrated events")
    }
    events_to_persist = existing_events
  }
  if @fs.exists(migration_path) {
    if read_json(migration_path).stringify() !=
      result.receipt.to_json().stringify() {
      fail("migration identity already exists with different content")
    }
  }
  let projection = persist_run(
    workspace,
    result.receipt.child_run_id,
    events_to_persist,
  )
  if !@fs.exists(migration_path) {
    write_json(migration_path, result.receipt.to_json())
  }
  println(
    {
      "projection": @moonflow.projection_json(projection),
      "migration": result.receipt.to_json(),
    }
    .to_json()
    .stringify(indent=2),
  )
}

///|
async fn select_adapter_command(
  workspace : String,
  capabilities_ref : String,
  requirement_ref : String,
) -> Unit {
  validate_artifact_ref(workspace, capabilities_ref)
  validate_artifact_ref(workspace, requirement_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let decision = @moonflow.select_adapter(
    @moonflow.decode_adapter_capabilities(
      read_json(root + "/" + capabilities_ref),
    ),
    @moonflow.decode_director_requirement(
      read_json(root + "/" + requirement_ref),
    ),
  )
  println(decision.to_json().stringify(indent=2))
}

///|
async fn declared_input_digest(
  workspace : String,
  artifacts : Array[String],
) -> String {
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let identities : Array[String] = []
  for artifact_ref in artifacts {
    validate_artifact_ref(root, artifact_ref)
    let bytes = @fs.read_file(root + "/" + artifact_ref).binary()
    identities.push("\{artifact_ref}|sha256:\{sha256_hex(bytes)}")
  }
  "sha256:" + sha256_hex(@utf8.encode(identities.join("\n")))
}

///|
async fn prepare_next(
  workspace : String,
  run_id : String,
  capabilities_ref : String,
  recorded_at : String,
) -> Unit {
  validate_artifact_ref(workspace, capabilities_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let capabilities = @moonflow.decode_adapter_capabilities(
    read_json(root + "/" + capabilities_ref),
  )
  let events = load_events(workspace, run_id)
  let mut projection = @moonflow.replay(run_id, events)
  let dispatch_ref = ".moonsuite/products/moonflow/runs/" + run_id + "/dispatch"
  let dispatch_dir = root + "/" + dispatch_ref
  ensure_directory(dispatch_dir)
  let prepared : Array[Json] = []
  for item_id in projection.runnable_item_ids() {
    guard projection.find_item(item_id) is Some(item) else { continue }
    let requirement = @moonflow.director_requirement_for_item(item)
    let decision = @moonflow.select_adapter(capabilities, requirement)
    let decision_path = dispatch_dir +
      "/" +
      requirement.requirement_id +
      ".decision.json"
    write_json(decision_path, decision.to_json())
    if !decision.accepted {
      prepared.push({
        "work_item_id": item.work_item_id,
        "prepared": false,
        "decision": decision.to_json(),
      })
      continue
    }
    let input_digest = declared_input_digest(
      root,
      @moonflow.director_input_artifacts(projection, item),
    )
    let request = @moonflow.director_request_for_item(
      projection, item, input_digest, recorded_at,
    )
    let request_path = dispatch_dir + "/" + request.request_id + ".request.json"
    let request_ref = dispatch_ref + "/" + request.request_id + ".request.json"
    write_json(request_path, request.to_json())
    let event = @moonflow.adapter_submission_event(projection, request)
    events.push(event)
    projection = @moonflow.replay(run_id, events)
    prepared.push({
      "work_item_id": item.work_item_id,
      "prepared": true,
      "selected_adapter_id": decision.selected_adapter_id,
      "request_artifact": request_ref,
      "input_digest": input_digest,
    })
  }
  projection = persist_run(workspace, run_id, events)
  println(
    (
      {
        "contract_id": "moonflow.dispatch-preparation.v1",
        "run_id": run_id,
        "prepared": Json::array(prepared),
        "projection": @moonflow.projection_json(projection),
      } : Json).stringify(indent=2),
  )
}

///|
async fn complete_artifacts(
  workspace : String,
  run_id : String,
  work_item_id : String,
  recorded_at : String,
  output_artifacts : Array[String],
) -> Unit {
  if output_artifacts.is_empty() {
    fail("complete-artifacts requires at least one output artifact")
  }
  let events = load_events(workspace, run_id)
  let projection = @moonflow.replay(run_id, events)
  guard projection.find_item(work_item_id) is Some(item) else {
    fail("MoonFlow work item does not exist: \{work_item_id}")
  }
  let output_digest = declared_input_digest(workspace, output_artifacts)
  if item.status.id() != "active" || item.request_id.trim().is_empty() {
    if item.attempt_status == "succeeded" &&
      item.output_digest == output_digest &&
      output_artifacts.all(artifact => item.artifacts.contains(artifact)) &&
      !item.result_id.trim().is_empty() {
      let result_ref = ".moonsuite/products/moonflow/runs/" +
        run_id +
        "/dispatch/" +
        item.result_id +
        ".result.json"
      let result = read_json(
        @fs.realpath(@moonflow.normalize_workspace_path(workspace)) +
        "/" +
        result_ref,
      )
      println(
        (
          {
            "contract_id": "moonflow.artifact-completion.v1",
            "idempotent_replay": true,
            "result_artifact": result_ref,
            "result": result,
            "projection": @moonflow.projection_json(projection),
          } : Json).stringify(indent=2),
      )
      return
    }
    fail("MoonFlow work item has no active governed attempt")
  }
  let result = @moonflow.director_success_result_for_item(
    item, output_digest, output_artifacts, recorded_at,
  )
  let result_ref = ".moonsuite/products/moonflow/runs/" +
    run_id +
    "/dispatch/" +
    result.result_id +
    ".result.json"
  write_json(
    @fs.realpath(@moonflow.normalize_workspace_path(workspace)) +
    "/" +
    result_ref,
    result.to_json(),
  )
  events.push(@moonflow.adapter_reconciliation_event(projection, result))
  let updated = persist_run(workspace, run_id, events)
  println(
    (
      {
        "contract_id": "moonflow.artifact-completion.v1",
        "result_artifact": result_ref,
        "result": result.to_json(),
        "projection": @moonflow.projection_json(updated),
      } : Json).stringify(indent=2),
  )
}

///|
async fn bundle_evidence(
  workspace : String,
  spec_ref : String,
  recorded_at : String,
) -> Unit {
  validate_artifact_ref(workspace, spec_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let spec = @moonflow.decode_evidence_bundle_spec(
    read_json(root + "/" + spec_ref),
  )
  ignore(safe_id(spec.bundle_id, "bundle_id"))
  let evidence_root = root + "/.moonsuite/products/moonflow/evidence"
  let objects_dir = evidence_root + "/objects"
  let bundle_dir = evidence_root + "/bundles/" + spec.bundle_id
  ensure_directory(objects_dir)
  ensure_directory(bundle_dir)
  let entries : Array[@moonflow.EvidenceBundleEntry] = []
  for source in spec.sources {
    validate_artifact_ref(root, source.artifact_ref)
    let source_path = @fs.realpath(root + "/" + source.artifact_ref)
    let data = @fs.read_file(source_path)
    let bytes = data.binary()
    let digest_hex = sha256_hex(bytes)
    let object_ref = ".moonsuite/products/moonflow/evidence/objects/" +
      digest_hex
    entries.push({
      artifact_ref: source.artifact_ref,
      object_ref,
      producer_product_id: source.producer_product_id,
      contract_id: source.contract_id,
      claim_class: source.claim_class,
      result_id: source.result_id,
      sha256: "sha256:" + digest_hex,
      size_bytes: bytes.length(),
    })
  }
  let digest_seed = entries
    .map(entry => {
      "\{entry.artifact_ref}|\{entry.sha256}|\{entry.producer_product_id}|\{entry.contract_id}|\{entry.claim_class}|\{entry.result_id}"
    })
    .join("\n")
  let content_digest = "sha256:" + sha256_hex(@utf8.encode(digest_seed))
  let manifest = @moonflow.evidence_bundle_manifest(
    spec, entries, content_digest, recorded_at,
  )
  let manifest_path = bundle_dir + "/bundle.json"
  if @fs.exists(manifest_path) {
    if read_json(manifest_path).stringify() != manifest.to_json().stringify() {
      fail("evidence bundle identity already exists with different content")
    }
  }
  for entry in entries {
    let source_data = @fs.read_file(root + "/" + entry.artifact_ref)
    if "sha256:" + sha256_hex(source_data.binary()) != entry.sha256 {
      fail("evidence source changed while constructing its bundle")
    }
    let object_path = root + "/" + entry.object_ref
    if @fs.exists(object_path) {
      if "sha256:" + sha256_hex(@fs.read_file(object_path).binary()) !=
        entry.sha256 {
        fail("content-addressed evidence object failed digest verification")
      }
    } else {
      @fs.write_file(object_path, source_data, create=0o444, truncate=false)
    }
    if !@moonflow.path_is_within_workspace(root, @fs.realpath(object_path)) {
      fail("evidence object escaped workspace after mutation")
    }
  }
  if !@fs.exists(manifest_path) {
    write_json(manifest_path, manifest.to_json())
  }
  if !@moonflow.path_is_within_workspace(root, @fs.realpath(manifest_path)) {
    fail("evidence manifest escaped workspace after mutation")
  }
  println(manifest.to_json().stringify(indent=2))
}

///|
fn transition_kind(action : String) -> @moonflow.EventKind raise {
  match action {
    "ready" => ItemReady
    "start" => ItemStarted
    "waiting" => ItemWaiting
    "block" => ItemBlocked
    "review" => ItemReviewRequested
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
    operation: item.operation,
    input_contracts: item.input_contracts.copy(),
    output_contracts: item.output_contracts.copy(),
    required_claim: item.required_claim,
    input_artifacts: item.input_artifacts.copy(),
    timeout_ms: item.timeout_ms,
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
async fn write_run_control(
  workspace : String,
  run_id : String,
  action : String,
  recorded_at : String,
  detail : String,
) -> Unit {
  ignore(safe_id(run_id, "run_id"))
  let directory = run_dir(workspace, run_id)
  if !@fs.exists(directory + "/events.json") {
    fail("MoonFlow control requires an imported run")
  }
  let control_path = directory + "/control.json"
  let existing = if @fs.exists(control_path) {
    read_json(control_path)
  } else {
    (
      {
        "contract_id": "moonflow.run-control.v1",
        "run_id": run_id,
        "state": "running",
        "authority_ceiling": "",
        "reason": "",
        "recorded_at": recorded_at,
      } : Json)
  }
  let fields = match existing {
    Object(values) => values
    _ => fail("MoonFlow run control is not an object")
  }
  let mut state = match fields.get("state") {
    Some(String(value)) => value
    _ => "running"
  }
  let mut ceiling = match fields.get("authority_ceiling") {
    Some(String(value)) => value
    _ => ""
  }
  match action {
    "pause" => state = "paused"
    "resume" => {
      if state == "cancelled" {
        fail("MoonFlow cannot resume a cancelled run")
      }
      state = "running"
    }
    "cancel" => state = "cancelled"
    "narrow-authority" => {
      let proposed = @pipeline.authority_class_from_id(detail)
      if !ceiling.is_empty() {
        let current = @pipeline.authority_class_from_id(ceiling)
        if !current.allows(proposed) {
          fail("MoonFlow control may narrow but never widen authority")
        }
      }
      ceiling = proposed.id()
    }
    _ => fail("unsupported MoonFlow control action: \{action}")
  }
  write_json(control_path, {
    "contract_id": "moonflow.run-control.v1",
    "run_id": run_id,
    "state": state,
    "authority_ceiling": ceiling,
    "reason": if action == "narrow-authority" {
      ""
    } else {
      detail
    },
    "recorded_at": recorded_at,
  })
  println(read_json(control_path).stringify(indent=2))
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
async fn review_outcome(
  workspace : String,
  run_id : String,
  receipt_artifact : String,
) -> Unit {
  validate_artifact_ref(workspace, receipt_artifact)
  let events = load_events(workspace, run_id)
  let projection = @moonflow.replay(run_id, events)
  let root = @moonflow.normalize_workspace_path(workspace)
  let receipt = @moonflow.decode_acceptance_review_receipt(
    read_json("\{root}/\{receipt_artifact}"),
  )
  if receipt.receipt_artifact != receipt_artifact {
    fail(
      "acceptance receipt artifact identity does not match its workspace path",
    )
  }
  let event = @moonflow.acceptance_review_event(projection, receipt)
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
    "  moonflow control <workspace> <run-id> <pause|resume|cancel|narrow-authority> <recorded-at> [reason-or-authority]\n" +
    "  moonflow transition <workspace> <run-id> <work-item-id> <action> <recorded-at> [detail]\n" +
    "  moonflow advance <workspace> <run-id> <recorded-at>\n" +
    "  moonflow submit-attempt <workspace> <run-id> <request.json>\n" +
    "  moonflow reconcile-attempt <workspace> <run-id> <result.json>\n" +
    "  moonflow review-outcome <workspace> <run-id> <receipt-artifact>\n" +
    "  moonflow revise-run <workspace> <parent-run-id> <child-graph-artifact> <proposal-artifact> <migration-id> <recorded-at>\n" +
    "  moonflow select-adapter <workspace> <capabilities-artifact> <requirement-artifact>\n" +
    "  moonflow prepare-next <workspace> <run-id> <capabilities-artifact> <recorded-at>\n" +
    "  moonflow complete-artifacts <workspace> <run-id> <work-item-id> <recorded-at> <artifact>...\n" +
    "  moonflow bundle-evidence <workspace> <bundle-spec-artifact> <recorded-at>\n" +
    "  moonflow run-unattended <workspace> <graph-artifact> <capabilities-artifact> <manifest-artifact> <envelope-artifact> <usage-artifact> <recorded-at>\n" +
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
    ["control", workspace, run_id, action, recorded_at, detail] =>
      write_run_control(workspace, run_id, action, recorded_at, detail)
    ["control", workspace, run_id, action, recorded_at] =>
      write_run_control(workspace, run_id, action, recorded_at, "")
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
    ["review-outcome", workspace, run_id, receipt_artifact] =>
      review_outcome(workspace, run_id, receipt_artifact)
    [
      "revise-run",
      workspace,
      parent_run_id,
      child_graph_ref,
      proposal_ref,
      migration_id,
      recorded_at,
    ] =>
      revise_run_command(
        workspace, parent_run_id, child_graph_ref, proposal_ref, migration_id, recorded_at,
      )
    ["select-adapter", workspace, capabilities_ref, requirement_ref] =>
      select_adapter_command(workspace, capabilities_ref, requirement_ref)
    ["prepare-next", workspace, run_id, capabilities_ref, recorded_at] =>
      prepare_next(workspace, run_id, capabilities_ref, recorded_at)
    [
      "complete-artifacts",
      workspace,
      run_id,
      work_item_id,
      recorded_at,
      .. artifacts,
    ] =>
      complete_artifacts(
        workspace,
        run_id,
        work_item_id,
        recorded_at,
        artifacts.to_owned(),
      )
    ["bundle-evidence", workspace, spec_ref, recorded_at] =>
      bundle_evidence(workspace, spec_ref, recorded_at)
    [
      "run-unattended",
      workspace,
      graph_ref,
      capabilities_ref,
      manifest_ref,
      envelope_ref,
      usage_ref,
      recorded_at,
    ] =>
      run_unattended(
        workspace, graph_ref, capabilities_ref, manifest_ref, envelope_ref, usage_ref,
        recorded_at,
      )
    ["validate-capability", capability_path] =>
      validate_capability(capability_path)
    ["version"] => println("MoonFlow \{@moonflow.runtime_protocol_id()}")
    _ => usage()
  }
}
