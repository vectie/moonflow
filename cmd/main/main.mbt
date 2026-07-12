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
  if @fs.exists(event_path) &&
    read_json(event_path).stringify() !=
    @moonflow.event_array_json(result.events).stringify() {
    fail("child run identity already exists with different migrated events")
  }
  if @fs.exists(migration_path) &&
    read_json(migration_path).stringify() != result.receipt.to_json().stringify() {
    fail("migration identity already exists with different content")
  }
  let projection = persist_run(
    workspace,
    result.receipt.child_run_id,
    result.events,
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
      if "sha256:" + sha256_hex(@fs.read_file(object_path).binary()) != entry.sha256 {
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
    "  moonflow transition <workspace> <run-id> <work-item-id> <action> <recorded-at> [detail]\n" +
    "  moonflow advance <workspace> <run-id> <recorded-at>\n" +
    "  moonflow submit-attempt <workspace> <run-id> <request.json>\n" +
    "  moonflow reconcile-attempt <workspace> <run-id> <result.json>\n" +
    "  moonflow review-outcome <workspace> <run-id> <receipt-artifact>\n" +
    "  moonflow revise-run <workspace> <parent-run-id> <child-graph-artifact> <proposal-artifact> <migration-id> <recorded-at>\n" +
    "  moonflow select-adapter <workspace> <capabilities-artifact> <requirement-artifact>\n" +
    "  moonflow bundle-evidence <workspace> <bundle-spec-artifact> <recorded-at>\n" +
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
    ["bundle-evidence", workspace, spec_ref, recorded_at] =>
      bundle_evidence(workspace, spec_ref, recorded_at)
    ["validate-capability", capability_path] =>
      validate_capability(capability_path)
    ["version"] => println("MoonFlow \{@moonflow.runtime_protocol_id()}")
    _ => usage()
  }
}
