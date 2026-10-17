///|
fn single_step_reply(
  projection : @moonflow.RunProjection,
  action : Json,
) -> Json raise {
  let status = plan_string(action, "status")
  {
    "contract_id": "moonflow.single-step-result.v1",
    "run_id": projection.run_id,
    "work_item_id": plan_string(action, "work_item_id"),
    "request_id": plan_string(action, "request_id"),
    "adapter_request_id": plan_string(
      plan_value(action, "adapter_request"),
      "request_id",
    ),
    "attempt_id": plan_string(
      plan_value(action, "adapter_request"),
      "attempt_id",
    ),
    "status": status,
    "message": plan_string(action, "message"),
    "reconcile_required": status == "reconcile-required",
    "projection": @moonflow.projection_json(projection),
    "qualification": plan_fields(action, "single-step action")
    .get("qualification")
    .unwrap_or(Json::null()),
  }
}

///|
async fn single_step_command_inner(
  workspace : String,
  run_id : String,
  item_id : String,
  request_id : String,
  config_ref : String,
  at : String,
  reconcile : Bool,
  safety : SingleStepSafety,
) -> Unit {
  ignore(single_step_id(run_id))
  ignore(single_step_id(item_id))
  ignore(single_step_id(request_id))
  guard at.length() == 20 && @pipeline.autonomy_timestamp_is_canonical(at) else {
    fail("single-step requires a canonical trusted UTC timestamp")
  }
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let lock_dir = plan_directory(
    root, ".moonsuite/products/moonflow/single-step",
  )
  if @fs.exists(lock_dir + "/.writer.lock") {
    ignore(
      plan_regular_path(
        root, ".moonsuite/products/moonflow/single-step/.writer.lock",
      ),
    )
  }
  let lock = @flow_host.acquire_named_writer_lock_v1(lock_dir, "writer")
  defer @flow_host.release_named_writer_lock_v1(lock)
  let run_ref = ".moonsuite/products/moonflow/runs/" + run_id
  let events = @moonflow.decode_event_array(
    plan_read_json(root, run_ref + "/events.json"),
  )
  let mut projection = @moonflow.replay(run_id, events)
  guard projection.find_item(item_id) is Some(item) else {
    fail("Selected item is unavailable")
  }
  let action_ref = run_ref + "/single-step"
  let directory = plan_directory(root, action_ref)
  let action_name = item_id + ".action.json"
  let index_name = "request-" + request_id + ".json"
  if @fs.exists(directory + "/" + index_name) {
    guard plan_string(
        plan_read_json(root, action_ref + "/" + index_name),
        "work_item_id",
      ) ==
      item_id else {
      fail("single-step request identity already belongs to another item")
    }
  }
  let existing = if @fs.exists(directory + "/" + action_name) {
    Some(plan_read_json(root, action_ref + "/" + action_name))
  } else {
    None
  }
  safety.no_attempt_created = existing is None &&
    item.request_id == "" &&
    item.attempt_count == 0
  let request = match existing {
    Some(action) => {
      guard plan_string(action, "request_id") == request_id &&
        plan_string(action, "source_digest") == projection.source_digest else {
        fail(
          "This item already has a different action identity; reopen its original action",
        )
      }
      let request = @moonflow.decode_adapter_request(
        plan_value(action, "adapter_request"),
      )
      guard request.run_id == run_id && request.work_item_id == item_id else {
        fail("Stored action correlation differs")
      }
      if plan_string(action, "status") is ("review" | "failed" | "not-applied") ||
        !reconcile {
        println(single_step_reply(projection, action).stringify(indent=2))
        return
      }
      request
    }
    None => {
      guard !reconcile else {
        fail("There is no persisted selected attempt to reconcile")
      }
      let request = @moonflow.single_step_request_for_item(
        projection,
        item,
        declared_input_digest(
          root,
          @moonflow.director_input_artifacts(projection, item),
        ),
        at,
      )
      ignore(single_step_id(request.attempt_id))
      request
    }
  }
  let control = unattended_control(root, run_id)
  guard control.0 == "running" &&
    (
      control.1 == "" ||
      @pipeline.authority_class_from_id(control.1).allows(
        @pipeline.authority_class_from_id(request.requested_authority),
      )
    ) else {
    fail("The run control blocks this single-step action")
  }
  let config : SingleStepConfig = @json.from_json(
    plan_read_json(root, config_ref),
  )
  guard config.contract_id == "moonflow.single-step-config.v2" else {
    fail(
      "single-step requires v2 config with the pinned owner adapter verifier",
    )
  }
  let operation = single_step_owner_capability(root, config, item, at)
  single_step_executable(config.adapter_executable, config.adapter_sha256)
  let prepare_exchange = single_step_verification_payload(
    root,
    operation,
    request,
    "prepare",
    reconcile~,
  )
  let legacy = match existing {
    Some(previous) =>
      !plan_fields(previous, "existing action").contains("owner_verification") &&
      !plan_fields(previous, "existing action").contains("adapter_sha256")
    None => false
  }
  if legacy {
    guard reconcile else {
      fail("legacy attempts may only reconcile their original action")
    }
    plan_fields(prepare_exchange, "verification")["legacy_action"] = existing.unwrap()
  }
  let proof = single_step_verify(
    root,
    config,
    operation,
    request,
    prepare_exchange,
    action_ref,
    item_id + ".prepare.verification.json",
  )
  let expected : Array[String] = @json.from_json(
    plan_value(proof, "expected_artifacts"),
  )
  let artifact_paths : Array[String] = @json.from_json(
    plan_value(proof, "artifact_paths"),
  )
  if existing is Some(previous) {
    if legacy {
      guard plan_value(proof, "legacy_reconciliation") == true.to_json() else {
        fail("owner verifier refused legacy reconciliation")
      }
    } else {
      guard plan_string(previous, "adapter_sha256") == config.adapter_sha256 else {
        fail("stored attempt belongs to another verifier identity")
      }
      let previous_proof = plan_value(previous, "owner_verification")
      for
        field in [
          "receipt_ref", "expected_artifacts", "artifact_paths", "adapter_id", "pack_version",
          "qualification",
        ] {
        guard plan_value(previous_proof, field) == plan_value(proof, field) else {
          fail("stored attempt owner verification changed")
        }
      }
    }
  }
  guard declared_input_digest(root, request.input_artifacts) ==
    request.input_digest else {
    fail("Stored single-step input bytes changed")
  }
  let envelope_bytes = plan_read_bytes(root, config.envelope_ref)
  let reserved = single_step_gate(
    root, config, projection, request, action_ref, artifact_paths, at, reconcile,
  )
  guard plan_read_bytes(root, config.envelope_ref) == envelope_bytes else {
    fail("Single-step authority changed during Gate evaluation")
  }
  if legacy {
    let original_bytes = plan_read_bytes(root, action_ref + "/" + action_name)
    guard @json.parse(@utf8.decode(original_bytes)) == existing.unwrap() else {
      fail("legacy action changed during verification")
    }
    ignore(
      plan_freeze_bytes(
        root,
        action_ref,
        item_id + ".legacy.action.json",
        original_bytes,
      ),
    )
  }
  let action_fields : Map[String, Json] = {
    "contract_id": "moonflow.single-step-action.v1".to_json(),
    "run_id": run_id.to_json(),
    "work_item_id": item_id.to_json(),
    "request_id": request_id.to_json(),
    "source_digest": projection.source_digest.to_json(),
    "adapter_request": request.to_json(),
    "adapter_sha256": config.adapter_sha256.to_json(),
    "owner_verification": proof,
    "qualification": plan_value(proof, "qualification"),
    "status": "reconcile-required".to_json(),
    "message": "The original attempt may have started. Reconcile before any further action.".to_json(),
    "recorded_at": at.to_json(),
  }
  safety.no_attempt_created = false
  @flow_host.atomic_replace_named_json_v1(
    directory,
    index_name,
    ({ "work_item_id": item_id, "request_id": request_id } : Json).stringify(),
  )
  @flow_host.atomic_replace_named_json_v1(
    directory,
    action_name,
    Json::object(action_fields).stringify(indent=2),
  )
  // Reserve conservatively before any possible product effect. A crash cannot
  // cause a second dispatch or erase usage by rolling it back.
  let usage_parts = config.usage_ref.split("/").to_array()
  let usage_name = usage_parts.last().unwrap().to_owned()
  let usage_dir_ref = usage_parts[:usage_parts.length() - 1]
    .map(x => x.to_owned())
    .join("/")
  let usage_dir = if usage_dir_ref == "" {
    root
  } else {
    plan_directory(root, usage_dir_ref)
  }
  @flow_host.atomic_replace_named_json_v1(
    usage_dir,
    usage_name,
    @pipeline.autonomy_budget_usage_json(reserved).stringify(indent=2),
  )
  if item.request_id == "" {
    events.push(@moonflow.adapter_submission_event(projection, request))
    projection = single_step_persist(root, run_id, events)
  } else {
    guard item.request_id == request.request_id &&
      item.active_attempt_id == request.attempt_id else {
      fail("The imported item's active attempt changed")
    }
  }
  let native_request_name = item_id + ".request.json"
  @flow_host.atomic_replace_named_json_v1(
    directory,
    native_request_name,
    request.to_json().stringify(indent=2),
  )
  // A changed executable or input after Gate is still fail closed; the action
  // is already durable and can only be reconciled, never redispatched.
  single_step_executable(config.adapter_executable, config.adapter_sha256)
  guard plan_read_bytes(root, config.envelope_ref) == envelope_bytes else {
    fail("Single-step authority changed after Gate evaluation")
  }
  guard declared_input_digest(root, request.input_artifacts) ==
    request.input_digest else {
    fail("Single-step input changed after authorization")
  }
  try {
    let output = single_step_process(
      config.adapter_executable,
      [
        if reconcile {
          "reconcile-report"
        } else {
          "invoke"
        },
        root,
        directory + "/" + native_request_name,
      ],
      root,
      item.timeout_ms.min(120000),
    )
    @flow_host.atomic_replace_named_json_v1(
      directory,
      item_id + ".process.json",
      (
        {
          "status": output.status,
          "stdout": output.stdout,
          "stderr": output.stderr,
        } : Json).stringify(indent=2),
    )
    guard output.status == 0 else {
      fail(
        "Native adapter did not return successfully; reconcile the original attempt",
      )
    }
    let wire = @json.parse(output.stdout)
    let result_json = if reconcile {
      guard plan_string(wire, "contract_id") ==
        "moonflow.adapter-reconciliation.v1" &&
        plan_string(wire, "adapter_id") == operation.adapter_id &&
        plan_string(wire, "request_id") == request.request_id &&
        plan_string(wire, "attempt_id") == request.attempt_id else {
        fail("Adapter reconciliation report correlation differs")
      }
      if plan_string(wire, "decision") == "not-applied" {
        action_fields["status"] = "not-applied".to_json()
        action_fields["message"] = "The adapter found no applied effect. This route will not retry or create another attempt.".to_json()
        @flow_host.atomic_replace_named_json_v1(
          directory,
          action_name,
          Json::object(action_fields).stringify(indent=2),
        )
        println(
          single_step_reply(projection, Json::object(action_fields)).stringify(
            indent=2,
          ),
        )
        return
      }
      guard plan_string(wire, "decision") == "recovered-succeeded" &&
        plan_value(wire, "retry_allowed") == false.to_json() else {
        fail("Adapter did not recover a successful terminal result")
      }
      plan_value(wire, "result")
    } else {
      wire
    }
    let result = @moonflow.decode_adapter_result(result_json)
    let receipt_ref = plan_string(proof, "receipt_ref")
    let receipt_bytes = plan_read_bytes(root, receipt_ref)
    @moonflow.single_step_validate_result(
      request,
      result,
      receipt_ref,
      "sha256:" + sha256_hex(receipt_bytes),
      expected,
    )
    let result_exchange = single_step_verification_payload(
      root,
      operation,
      request,
      "result",
      reconcile~,
    )
    let exchange_fields = plan_fields(result_exchange, "result verification")
    if legacy {
      exchange_fields["legacy_action"] = existing.unwrap()
    }
    exchange_fields["result"] = result_json
    exchange_fields["receipt_ref"] = receipt_ref.to_json()
    exchange_fields["receipt_digest"] = ("sha256:" + sha256_hex(receipt_bytes)).to_json()
    let result_proof = single_step_verify(
      root,
      config,
      operation,
      request,
      result_exchange,
      action_ref,
      item_id + ".result.verification.json",
    )
    for
      field in [
        "receipt_ref", "expected_artifacts", "artifact_paths", "adapter_id", "pack_version",
        "qualification",
      ] {
      guard plan_value(result_proof, field) == plan_value(proof, field) else {
        fail(
          "terminal owner proof differs from the authorized operation policy",
        )
      }
    }
    guard declared_input_digest(root, request.input_artifacts) ==
      request.input_digest else {
      fail("single-step input changed before durable result import")
    }
    let evidence : Array[Json] = []
    for reference in result.output_artifacts {
      let bytes = plan_read_bytes(root, reference)
      evidence.push({
        "reference": reference,
        "sha256": "sha256:" + sha256_hex(bytes),
        "byte_length": bytes.length(),
      })
    }
    @flow_host.atomic_replace_named_json_v1(
      directory,
      item_id + ".result.json",
      result_json.stringify(indent=2),
    )
    @flow_host.atomic_replace_named_json_v1(
      directory,
      item_id + ".evidence.json",
      evidence.to_json().stringify(indent=2),
    )
    let event = @moonflow.adapter_reconciliation_event(projection, result)
    if !projection.applied_event_ids.contains(event.event_id) {
      events.push(event)
    }
    projection = single_step_persist(root, run_id, events)
    guard projection.find_item(item_id) is Some(review_item) &&
      review_item.status == Review else {
      fail("Single-step success did not stop at Review")
    }
    action_fields["status"] = "review".to_json()
    action_fields["message"] = "The selected digital reference step finished and awaits explicit review. No dependent work was dispatched.".to_json()
  } catch {
    error => action_fields["message"] = error.to_string().to_json()
  }
  @flow_host.atomic_replace_named_json_v1(
    directory,
    action_name,
    Json::object(action_fields).stringify(indent=2),
  )
  println(
    single_step_reply(projection, Json::object(action_fields)).stringify(
      indent=2,
    ),
  )
}

///|
struct SingleStepSafety {
  mut no_attempt_created : Bool
}

///|
async fn single_step_command(
  workspace : String,
  run_id : String,
  item_id : String,
  request_id : String,
  config_ref : String,
  at : String,
  reconcile : Bool,
) -> Unit {
  let safety = { no_attempt_created: false, }
  single_step_command_inner(
    workspace, run_id, item_id, request_id, config_ref, at, reconcile, safety,
  ) catch {
    error => {
      guard safety.no_attempt_created else { raise error }
      println(
        (
          {
            "contract_id": "moonflow.single-step-blocker.v1",
            "run_id": run_id,
            "work_item_id": item_id,
            "request_id": request_id,
            "status": "blocked",
            "no_attempt_created": true,
            "message": error.to_string(),
          } : Json).stringify(indent=2),
      )
    }
  }
}
