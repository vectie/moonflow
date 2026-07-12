///|
priv struct UnattendedCommandResult {
  status : Int
  stdout : String
  stderr : String
}

///|
async fn run_unattended_process(
  executable : String,
  arguments : Array[String],
  cwd : String,
  timeout_ms : Int,
) -> UnattendedCommandResult {
  let completed = @async.with_timeout_opt(timeout_ms, () => {
    @async.with_task_group(group => {
      fn capture() raise {
        let (pipe, output) = @process.read_from_process()
        let task = group.spawn(() => {
          defer pipe.close()
          @utf8.decode_lossy(pipe.read_all().binary())
        })
        (task, output)
      }

      let stdout = capture()
      let stderr = capture()
      let status = @process.run(
        executable,
        arguments,
        cwd~,
        stdout=stdout.1,
        stderr=stderr.1,
      ) catch {
        _ => -1
      }
      { status, stdout: stdout.0.wait(), stderr: stderr.0.wait() }
    })
  })
  match completed {
    Some(result) => result
    None =>
      {
        status: 124,
        stdout: "",
        stderr: "MoonFlow process exceeded its declared timeout",
      }
  }
}

///|
fn unattended_usage_add(
  usage : @pipeline.AutonomyBudgetUsage,
  request : @pipeline.AutonomyBudgetUsage,
) -> @pipeline.AutonomyBudgetUsage {
  {
    model_tokens: usage.model_tokens + request.model_tokens,
    tool_calls: usage.tool_calls + request.tool_calls,
    storage_bytes: usage.storage_bytes + request.storage_bytes,
    attempts: usage.attempts + request.attempts,
    concurrency: if usage.concurrency > request.concurrency {
      usage.concurrency
    } else {
      request.concurrency
    },
  }
}

///|
fn unattended_block_event(
  projection : @moonflow.RunProjection,
  item : @moonflow.RuntimeItem,
  detail : String,
  recorded_at : String,
) -> @moonflow.RuntimeEvent {
  {
    sequence: projection.last_sequence + 1,
    event_id: "event-\{projection.run_id}-supervisor-block-\{item.work_item_id}-\{projection.last_sequence + 1}",
    run_id: projection.run_id,
    work_item_id: item.work_item_id,
    kind: ItemBlocked,
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
    request_id: item.request_id,
    result_id: item.result_id,
    attempt_id: item.active_attempt_id,
    idempotency_key: item.idempotency_key,
    external_job_id: item.external_job_id,
    attempt_status: item.attempt_status,
    input_digest: item.input_digest,
    output_digest: item.output_digest,
    output_artifacts: item.artifacts.copy(),
    error_kind: "supervisor-blocked",
    compensable: false,
    depends_on: [],
    detail,
    artifact_id: "",
    authority_id: "moongate",
    recorded_at,
  }
}

///|
async fn unattended_control(
  workspace : String,
  run_id : String,
) -> (String, String) {
  let path = run_dir(workspace, run_id) + "/control.json"
  if !@fs.exists(path) {
    return ("running", "")
  }
  match read_json(path) {
    Object(fields) => {
      let state = match fields.get("state") {
        Some(String(value)) => value
        _ => "running"
      }
      let ceiling = match fields.get("authority_ceiling") {
        Some(String(value)) => value
        _ => ""
      }
      (state, ceiling)
    }
    _ => fail("MoonFlow run control is not an object")
  }
}

///|
fn unattended_cancel_event(
  projection : @moonflow.RunProjection,
  item : @moonflow.RuntimeItem,
  recorded_at : String,
) -> @moonflow.RuntimeEvent {
  {
    sequence: projection.last_sequence + 1,
    event_id: "event-\{projection.run_id}-operator-cancel-\{item.work_item_id}-\{projection.last_sequence + 1}",
    run_id: projection.run_id,
    work_item_id: item.work_item_id,
    kind: ItemCancelled,
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
    request_id: item.request_id,
    result_id: item.result_id,
    attempt_id: item.active_attempt_id,
    idempotency_key: item.idempotency_key,
    external_job_id: item.external_job_id,
    attempt_status: "cancelled",
    input_digest: item.input_digest,
    output_digest: item.output_digest,
    output_artifacts: item.artifacts.copy(),
    error_kind: "operator-cancelled",
    compensable: item.compensable,
    depends_on: [],
    detail: "cancelled through bounded MoonFlow run control",
    artifact_id: "",
    authority_id: "operator-control",
    recorded_at,
  }
}

///|
async fn unattended_block(
  workspace : String,
  run_id : String,
  events : Array[@moonflow.RuntimeEvent],
  item_id : String,
  detail : String,
  recorded_at : String,
) -> @moonflow.RunProjection {
  let projection = @moonflow.replay(run_id, events)
  guard projection.find_item(item_id) is Some(item) else {
    fail("unattended supervisor lost work item: \{item_id}")
  }
  events.push(unattended_block_event(projection, item, detail, recorded_at))
  persist_run(workspace, run_id, events)
}

///|
async fn write_unattended_log(
  directory : String,
  name : String,
  result : UnattendedCommandResult,
) -> Unit {
  write_json(directory + "/" + name + ".json", {
    "status": result.status,
    "stdout": result.stdout,
    "stderr": result.stderr,
  })
}

///|
async fn reject_unattended_binding(
  workspace : String,
  run_id : String,
  field : String,
  expected : String,
  actual : String,
  recorded_at : String,
) -> Unit {
  let reason = "autonomy envelope \{field} differs from the compiled run"
  let directory = run_dir(workspace, run_id)
  if !@fs.exists(directory) {
    @fs.mkdir(directory, permission=0o755, recursive=true)
  }
  write_json(directory + "/autonomy-binding-rejection.json", {
    "contract_id": "moonflow.autonomy-binding-rejection.v1",
    "run_id": run_id,
    "field": field,
    "expected": expected,
    "actual": actual,
    "reason": reason,
    "recorded_at": recorded_at,
  })
  fail(reason)
}

///|
async fn write_attempt_lease(
  workspace : String,
  dispatch_ref : String,
  item : @moonflow.RuntimeItem,
  driver : @moonflow.UnattendedDriver,
  stage : String,
  recorded_at : String,
) -> Unit {
  write_json(
    workspace +
    "/" +
    dispatch_ref +
    "/lease-" +
    item.active_attempt_id +
    ".json",
    {
      "contract_id": "moonflow.adapter-lease.v1",
      "attempt_id": item.active_attempt_id,
      "work_item_id": item.work_item_id,
      "adapter_id": driver.adapter_id,
      "stage": stage,
      "timeout_ms": item.timeout_ms,
      "heartbeat_at": recorded_at,
      "orphan_policy": "reconcile-durable-checkpoints-before-retry",
      "idempotency_key": item.idempotency_key,
    },
  )
}

///|
fn json_int_or(value : Json, key : String, fallback : Int) -> Int {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(Number(number, ..)) => number.to_int()
        _ => fallback
      }
    _ => fallback
  }
}

///|
async fn adapter_health_path(workspace : String, adapter_id : String) -> String {
  let safe_adapter = safe_id(adapter_id, "adapter_id")
  let root = workspace + "/.moonsuite/products/moonflow/supervisor/adapters"
  if !@fs.exists(root) {
    @fs.mkdir(root, permission=0o755, recursive=true)
  }
  root + "/" + safe_adapter + ".json"
}

///|
async fn acquire_adapter_probe(
  workspace : String,
  adapter_id : String,
  recorded_at : String,
) -> Bool {
  let path = adapter_health_path(workspace, adapter_id)
  if !@fs.exists(path) {
    return true
  }
  let health = read_json(path)
  if json_int_or(health, "consecutive_failures", 0) < 3 {
    return true
  }
  let state = match health {
    Object(fields) =>
      match fields.get("state") {
        Some(String(value)) => value
        _ => "circuit-open"
      }
    _ => "circuit-open"
  }
  if state == "half-open" {
    return false
  }
  write_json(path, {
    "contract_id": "moonflow.adapter-health.v1",
    "adapter_id": adapter_id,
    "state": "half-open",
    "consecutive_failures": json_int_or(health, "consecutive_failures", 3),
    "last_observed_at": recorded_at,
    "recovery_policy": "one governed probe; success resets and failure reopens",
  })
  true
}

///|
async fn record_adapter_health(
  workspace : String,
  adapter_id : String,
  success : Bool,
  recorded_at : String,
) -> Unit {
  let path = adapter_health_path(workspace, adapter_id)
  let previous = if @fs.exists(path) {
    read_json(path)
  } else {
    Json::object({})
  }
  let failures = if success {
    0
  } else {
    json_int_or(previous, "consecutive_failures", 0) + 1
  }
  write_json(path, {
    "contract_id": "moonflow.adapter-health.v1",
    "adapter_id": adapter_id,
    "state": if failures >= 3 {
      "circuit-open"
    } else if failures > 0 {
      "degraded"
    } else {
      "healthy"
    },
    "consecutive_failures": failures,
    "last_observed_at": recorded_at,
    "recovery_policy": "successful governed probe resets the circuit",
  })
}

///|
async fn gate_unattended_attempt(
  root : String,
  run_id : String,
  item : @moonflow.RuntimeItem,
  driver : @moonflow.UnattendedDriver,
  manifest : @moonflow.UnattendedManifest,
  envelope_ref : String,
  usage_ref : String,
  dispatch_ref : String,
  dispatch_dir : String,
  recorded_at : String,
) -> Bool {
  let event_ref = dispatch_ref +
    "/gate-" +
    item.active_attempt_id +
    ".event.json"
  let event_path = root + "/" + event_ref
  write_json(
    event_path,
    @pipeline.autonomy_event_request_json({
      contract_id: "moongate.autonomy-event-request.v1",
      event_id: "event-" + item.active_attempt_id,
      run_id,
      product_id: item.product_id,
      operation: item.operation,
      requested_authority: @pipeline.authority_class_from_id(
        item.requested_authority,
      ),
      claim: @pipeline.claim_class_from_id(item.required_claim),
      artifact_paths: driver.draft_output_artifacts +
      driver.expected_output_artifacts,
      external_destination: "",
      budget_request: driver.budget_request,
      recorded_at,
    }),
  )
  let decision_id = "decision-" + item.active_attempt_id
  let arguments = manifest.gate_arguments +
    [
      "--root",
      root,
      "--envelope",
      root + "/" + envelope_ref,
      "--event",
      event_path,
      "--usage",
      root + "/" + usage_ref,
      "--decision",
      decision_id,
      "--checked-at",
      recorded_at,
    ]
  let result = run_unattended_process(
    manifest.gate_executable,
    arguments,
    root,
    30000,
  )
  write_unattended_log(dispatch_dir, decision_id + ".gate", result)
  result.status == 0
}

///|
async fn run_unattended_item(
  root : String,
  run_id : String,
  events : Array[@moonflow.RuntimeEvent],
  capabilities : Array[@moonflow.AdapterCapability],
  manifest : @moonflow.UnattendedManifest,
  envelope_ref : String,
  usage_ref : String,
  usage : @pipeline.AutonomyBudgetUsage,
  item_id : String,
  recorded_at : String,
) -> @pipeline.AutonomyBudgetUsage {
  let projection = @moonflow.replay(run_id, events)
  guard projection.find_item(item_id) is Some(current_item) else {
    return usage
  }
  let requirement = @moonflow.director_requirement_for_item(current_item)
  let decision = @moonflow.select_adapter(capabilities, requirement)
  if !decision.accepted {
    ignore(
      unattended_block(
        root,
        run_id,
        events,
        item_id,
        "no conforming healthy adapter: " + decision.to_json().stringify(),
        recorded_at,
      ),
    )
    return usage
  }
  guard manifest.find_driver(decision.selected_adapter_id) is Some(driver) else {
    ignore(
      unattended_block(
        root, run_id, events, item_id, "selected adapter has no executable driver",
        recorded_at,
      ),
    )
    return usage
  }
  let dispatch_ref = ".moonsuite/products/moonflow/runs/" + run_id + "/dispatch"
  let dispatch_dir = root + "/" + dispatch_ref
  ensure_directory(dispatch_dir)
  write_json(
    dispatch_dir + "/" + requirement.requirement_id + ".decision.json",
    decision.to_json(),
  )
  let request_ref = if current_item.status == @moonflow.Ready {
    let input_digest = declared_input_digest(
      root,
      @moonflow.director_input_artifacts(projection, current_item),
    )
    let fresh_request = @moonflow.director_request_for_item(
      projection, current_item, input_digest, recorded_at,
    )
    let fresh_ref = dispatch_ref +
      "/" +
      fresh_request.request_id +
      ".request.json"
    write_json(root + "/" + fresh_ref, fresh_request.to_json())
    events.push(@moonflow.adapter_submission_event(projection, fresh_request))
    ignore(persist_run(root, run_id, events))
    fresh_ref
  } else {
    if current_item.request_id.trim().is_empty() {
      fail("recoverable unattended item is missing request identity")
    }
    dispatch_ref + "/" + current_item.request_id + ".request.json"
  }
  if !@fs.exists(root + "/" + request_ref) {
    fail("recoverable unattended item is missing its durable request")
  }
  let request = @moonflow.decode_adapter_request(
    read_json(root + "/" + request_ref),
  )
  let active = @moonflow.replay(run_id, events)
  guard active.find_item(item_id) is Some(active_item) else { return usage }
  let control = unattended_control(root, run_id)
  if !control.1.is_empty() {
    let ceiling = @pipeline.authority_class_from_id(control.1)
    let requested = @pipeline.authority_class_from_id(
      active_item.requested_authority,
    )
    if !ceiling.allows(requested) {
      ignore(
        unattended_block(
          root,
          run_id,
          events,
          item_id,
          "operator authority ceiling refused \{active_item.requested_authority}",
          recorded_at,
        ),
      )
      return usage
    }
  }
  if active_item.status != @moonflow.Review &&
    !gate_unattended_attempt(
      root, run_id, active_item, driver, manifest, envelope_ref, usage_ref, dispatch_ref,
      dispatch_dir, recorded_at,
    ) {
    ignore(
      unattended_block(
        root, run_id, events, item_id, "MoonGate refused unattended adapter execution",
        recorded_at,
      ),
    )
    return usage
  }
  if !acquire_adapter_probe(root, driver.adapter_id, recorded_at) {
    ignore(
      unattended_block(
        root, run_id, events, item_id, "adapter circuit is open after repeated failures",
        recorded_at,
      ),
    )
    return usage
  }
  write_attempt_lease(
    root, dispatch_ref, active_item, driver, "authorized", recorded_at,
  )
  let result_ref = dispatch_ref +
    "/result-" +
    active_item.active_attempt_id +
    ".json"
  let receipt_ref = dispatch_ref +
    "/review-" +
    active_item.active_attempt_id +
    ".json"
  let review_packet_ref = dispatch_ref +
    "/review-packet-" +
    active_item.active_attempt_id +
    ".json"
  let attestation_ref = dispatch_ref +
    "/product-attestation-" +
    active_item.active_attempt_id +
    ".json"
  if !@fs.exists(root + "/" + result_ref) {
    let adapter_args = @moonflow.render_unattended_arguments(
      driver.arguments,
      root,
      request_ref,
      result_ref,
      receipt_ref,
      review_packet_ref,
    )
    let adapter_run = run_unattended_process(
      driver.executable,
      adapter_args,
      root,
      active_item.timeout_ms,
    )
    write_unattended_log(
      dispatch_dir,
      "adapter-" + active_item.active_attempt_id,
      adapter_run,
    )
    if adapter_run.status != 0 || !@fs.exists(root + "/" + result_ref) {
      record_adapter_health(root, driver.adapter_id, false, recorded_at)
      ignore(
        unattended_block(
          root, run_id, events, item_id, "adapter process failed or omitted its result receipt",
          recorded_at,
        ),
      )
      return unattended_usage_add(usage, driver.budget_request)
    }
  }
  let result = @moonflow.decode_adapter_result(
    read_json(root + "/" + result_ref),
  )
  record_adapter_health(root, driver.adapter_id, true, recorded_at)
  write_attempt_lease(
    root, dispatch_ref, active_item, driver, "result-observed", recorded_at,
  )
  if result.output_artifacts != driver.draft_output_artifacts {
    ignore(
      unattended_block(
        root, run_id, events, item_id, "adapter drafts differ from pre-authorized artifacts",
        recorded_at,
      ),
    )
    return unattended_usage_add(usage, driver.budget_request)
  }
  let verified_digest = declared_input_digest(root, result.output_artifacts)
  if verified_digest != result.output_digest {
    ignore(
      unattended_block(
        root, run_id, events, item_id, "adapter output digest failed independent verification",
        recorded_at,
      ),
    )
    return unattended_usage_add(usage, driver.budget_request)
  }
  if !@fs.exists(root + "/" + attestation_ref) {
    let attestor_run = run_unattended_process(
      driver.attestor_executable,
      @moonflow.render_unattended_attestor_arguments(
        driver.attestor_arguments,
        root,
        request_ref,
        result_ref,
        attestation_ref,
        driver.draft_output_artifacts[0],
        driver.expected_output_artifacts[0],
      ),
      root,
      active_item.timeout_ms,
    )
    write_unattended_log(
      dispatch_dir,
      "attestor-" + active_item.active_attempt_id,
      attestor_run,
    )
    if attestor_run.status != 0 || !@fs.exists(root + "/" + attestation_ref) {
      ignore(
        unattended_block(
          root, run_id, events, item_id, "product attestor failed or omitted its receipt",
          recorded_at,
        ),
      )
      return unattended_usage_add(usage, driver.budget_request)
    }
  }
  let attestation_issues = @moonflow.product_attestation_issues(
    read_json(root + "/" + attestation_ref),
    driver,
    request,
    result,
  )
  if !attestation_issues.is_empty() {
    ignore(
      unattended_block(
        root,
        run_id,
        events,
        item_id,
        "product attestation refused: " + attestation_issues.join("; "),
        recorded_at,
      ),
    )
    return unattended_usage_add(usage, driver.budget_request)
  }
  write_attempt_lease(
    root, dispatch_ref, active_item, driver, "product-attested", recorded_at,
  )
  for artifact in driver.expected_output_artifacts {
    if !@fs.exists(root + "/" + artifact) {
      ignore(
        unattended_block(
          root, run_id, events, item_id, "product attestor accepted without materializing its declared final artifact",
          recorded_at,
        ),
      )
      return unattended_usage_add(usage, driver.budget_request)
    }
  }
  let final_digest = declared_input_digest(
    root,
    driver.expected_output_artifacts,
  )
  let final_result = @moonflow.director_success_result_for_item(
    active_item,
    final_digest,
    driver.expected_output_artifacts.copy(),
    recorded_at,
  )
  let final_result_ref = dispatch_ref +
    "/final-result-" +
    active_item.active_attempt_id +
    ".json"
  write_json(root + "/" + final_result_ref, final_result.to_json())
  if active_item.status != @moonflow.Review {
    events.push(@moonflow.adapter_reconciliation_event(active, final_result))
    ignore(persist_run(root, run_id, events))
  }
  write_json(
    root + "/" + review_packet_ref,
    (
      {
        "contract_id": "moonflow.acceptance-review-request.v1",
        "run_id": run_id,
        "work_item_id": active_item.work_item_id,
        "declaration_id": active_item.declaration_id,
        "result_id": final_result.result_id,
        "attempt_id": final_result.attempt_id,
        "output_digest": final_result.output_digest,
        "acceptance_criteria": active_item.acceptance_criteria.to_json(),
        "evidence_refs": final_result.output_artifacts.to_json(),
        "product_attestation_ref": attestation_ref,
        "reviewer_id": driver.reviewer_id,
        "review_authority_id": driver.review_authority_id,
        "receipt_artifact": receipt_ref,
        "recorded_at": recorded_at,
      } : Json),
  )
  if !@fs.exists(root + "/" + receipt_ref) {
    let review_args = @moonflow.render_unattended_arguments(
      driver.reviewer_arguments,
      root,
      request_ref,
      final_result_ref,
      receipt_ref,
      review_packet_ref,
    )
    let review_run = run_unattended_process(
      driver.reviewer_executable,
      review_args,
      root,
      active_item.timeout_ms,
    )
    write_unattended_log(
      dispatch_dir,
      "reviewer-" + active_item.active_attempt_id,
      review_run,
    )
    if review_run.status != 0 || !@fs.exists(root + "/" + receipt_ref) {
      ignore(
        unattended_block(
          root, run_id, events, item_id, "independent reviewer failed or omitted its receipt",
          recorded_at,
        ),
      )
      return unattended_usage_add(usage, driver.budget_request)
    }
  }
  let receipt = @moonflow.decode_acceptance_review_receipt(
    read_json(root + "/" + receipt_ref),
  )
  if receipt.reviewer_id != driver.reviewer_id ||
    receipt.review_authority_id != driver.review_authority_id {
    ignore(
      unattended_block(
        root, run_id, events, item_id, "review receipt identity differs from the governed driver manifest",
        recorded_at,
      ),
    )
    return unattended_usage_add(usage, driver.budget_request)
  }
  let review_projection = @moonflow.replay(run_id, events)
  events.push(@moonflow.acceptance_review_event(review_projection, receipt))
  ignore(persist_run(root, run_id, events))
  write_attempt_lease(
    root, dispatch_ref, active_item, driver, "reviewed", recorded_at,
  )
  unattended_usage_add(usage, driver.budget_request)
}

///|
async fn run_unattended(
  workspace : String,
  graph_ref : String,
  capabilities_ref : String,
  manifest_ref : String,
  envelope_ref : String,
  usage_ref : String,
  recorded_at : String,
) -> Unit {
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  for
    artifact in [
      graph_ref, capabilities_ref, manifest_ref, envelope_ref, usage_ref,
    ] {
    validate_artifact_ref(root, artifact)
  }
  let graph_events = @moonflow.events_from_work_graph(
    read_json(root + "/" + graph_ref),
  )
  let run_id = graph_events[0].run_id
  let event_path = run_dir(root, run_id) + "/events.json"
  let events = if @fs.exists(event_path) {
    load_events(root, run_id)
  } else {
    ignore(persist_run(root, run_id, graph_events))
    graph_events
  }
  let capabilities = @moonflow.decode_adapter_capabilities(
    read_json(root + "/" + capabilities_ref),
  )
  let manifest = @moonflow.decode_unattended_manifest(
    read_json(root + "/" + manifest_ref),
  )
  let envelope = @pipeline.decode_autonomy_envelope(
    read_json(root + "/" + envelope_ref),
  )
  if envelope.workspace_root != root {
    reject_unattended_binding(
      root,
      run_id,
      "workspace_root",
      root,
      envelope.workspace_root,
      recorded_at,
    )
  }
  let initial_projection = @moonflow.replay(run_id, events)
  if envelope.source_digest != initial_projection.source_digest {
    reject_unattended_binding(
      root,
      run_id,
      "source_digest",
      initial_projection.source_digest,
      envelope.source_digest,
      recorded_at,
    )
  }
  let mut usage = @pipeline.decode_autonomy_budget_usage(
    read_json(root + "/" + usage_ref),
  )
  write_json(run_dir(root, run_id) + "/autonomy-binding.json", {
    "contract_id": "moonflow.autonomy-binding.v1",
    "run_id": run_id,
    "envelope": @pipeline.autonomy_envelope_json(envelope),
    "usage_ref": usage_ref,
    "usage": @pipeline.autonomy_budget_usage_json(usage),
    "recorded_at": recorded_at,
  })
  let mut cycles = 0
  for ;; {
    cycles += 1
    if cycles > manifest.max_cycles {
      fail("MoonFlow unattended supervisor exhausted max_cycles")
    }
    let control = unattended_control(root, run_id)
    if control.0 == "paused" {
      return
    }
    if control.0 == "cancelled" {
      let mut cancellation = @moonflow.replay(run_id, events)
      for item in cancellation.items {
        if !item.status.is_terminal() {
          events.push(unattended_cancel_event(cancellation, item, recorded_at))
          cancellation = @moonflow.replay(run_id, events)
        }
      }
      ignore(persist_run(root, run_id, events))
      return
    }
    let before = @moonflow.replay(run_id, events)
    if before.outcome == "accepted" ||
      before.outcome == "blocked" ||
      before.outcome == "failed" {
      break
    }
    for ready in @moonflow.ready_events(before, recorded_at) {
      events.push(ready)
    }
    ignore(persist_run(root, run_id, events))
    let ready = @moonflow.replay(run_id, events)
    let runnable = ready.items.filter_map(item => {
      if item.status == @moonflow.Ready ||
        item.status == @moonflow.Active ||
        item.status == @moonflow.Review {
        Some(item.work_item_id)
      } else {
        None
      }
    })
    if runnable.is_empty() {
      fail("MoonFlow unattended supervisor made no progress")
    }
    for item_id in runnable {
      usage = run_unattended_item(
        root, run_id, events, capabilities, manifest, envelope_ref, usage_ref, usage,
        item_id, recorded_at,
      )
      write_json(
        root + "/" + usage_ref,
        @pipeline.autonomy_budget_usage_json(usage),
      )
      write_json(run_dir(root, run_id) + "/autonomy-binding.json", {
        "contract_id": "moonflow.autonomy-binding.v1",
        "run_id": run_id,
        "envelope": @pipeline.autonomy_envelope_json(envelope),
        "usage_ref": usage_ref,
        "usage": @pipeline.autonomy_budget_usage_json(usage),
        "recorded_at": recorded_at,
      })
    }
  }
  let final_projection = persist_run(root, run_id, events)
  let projection_path = run_dir(root, run_id) + "/projection.json"
  let mut observer_succeeded = false
  let mut observer_finding = "event-driven Bookkeeper observer is not configured"
  if !manifest.observer_executable.trim().is_empty() {
    let observer_run = run_unattended_process(
      manifest.observer_executable,
      @moonflow.render_unattended_observer_arguments(
        manifest.observer_arguments,
        root,
        run_id,
        final_projection.book_id,
        projection_path,
        recorded_at,
      ),
      root,
      120000,
    )
    write_unattended_log(
      run_dir(root, run_id),
      "bookkeeper-observer",
      observer_run,
    )
    observer_succeeded = observer_run.status == 0
    observer_finding = if observer_succeeded {
      ""
    } else {
      "event-driven Bookkeeper reconciliation failed"
    }
  }
  let scorecard_path = run_dir(root, run_id) + "/intervention-scorecard.json"
  write_json(scorecard_path, {
    "contract_id": "moonflow.intervention-scorecard.v1",
    "run_id": run_id,
    "constitutional_authority_count": 1,
    "optional_observation_count": 0,
    "required_intervention_count": 0,
    "hidden_orchestration_count": 0,
    "normal_path_manual_count": 0,
    "unattended_qualified": final_projection.outcome == "accepted" &&
    observer_succeeded,
    "finalization_findings": if observer_finding.is_empty() {
      Json::array([])
    } else {
      [observer_finding].to_json()
    },
    "recorded_at": recorded_at,
  })
  println(
    (
      {
        "contract_id": "moonflow.unattended-run.v1",
        "cycles": cycles,
        "intervention_scorecard": ".moonsuite/products/moonflow/runs/" +
        run_id +
        "/intervention-scorecard.json",
        "projection": @moonflow.projection_json(final_projection),
      } : Json).stringify(indent=2),
  )
}
