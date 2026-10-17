///|
fn plan_prepared_ref(preparation_id : String) -> String raise {
  guard preparation_id.has_prefix("plan-") &&
    preparation_id.length() == 69 &&
    preparation_id
    .substring(start=5)
    .iter()
    .all(ch => ch.is_ascii_digit() || (ch >= 'a' && ch <= 'f')) else {
    fail("preparation_id must identify a saved content-addressed plan")
  }
  ".moonsuite/products/moonflow/prepared-plans/" + preparation_id
}

///|
async fn plan_writer_lock(root : String) -> Int {
  let directory = plan_directory(root, ".moonsuite/products/moonflow/planning")
  if @fs.exists(directory + "/.writer.lock") {
    ignore(
      plan_regular_path(
        root, ".moonsuite/products/moonflow/planning/.writer.lock",
      ),
    )
  }
  @flow_host.acquire_named_writer_lock_v1(directory, "writer")
}

///|
async fn plan_parent_bytes(root : String, source_graph_id : String) -> Bytes? {
  let reference = ".moonsuite/products/moonflow/runs/" +
    safe_id(source_graph_id, "source_graph_id") +
    "/events.json"
  if @fs.exists(root + "/" + reference) {
    Some(plan_read_bytes(root, reference))
  } else {
    None
  }
}

///|
fn plan_bytes_digest(bytes : Bytes?) -> String {
  match bytes {
    Some(value) => "sha256:" + sha256_hex(value)
    None => "absent"
  }
}

///|
async fn plan_check_pins(
  root : String,
  state : Json,
  catalog_ref : String,
) -> @moonflow.CapabilityCatalogV1 {
  let source_ref = plan_string(state, "source_ref")
  let source_bytes = plan_read_bytes(root, source_ref)
  guard "sha256:" + sha256_hex(source_bytes) ==
    plan_string(state, "source_sha256") else {
    fail("source_graph: selected source bytes changed; prepare a new child")
  }
  let form_bytes = plan_read_bytes(root, plan_string(state, "form_ref"))
  guard "sha256:" + sha256_hex(form_bytes) == plan_string(state, "form_sha256") else {
    fail("form: selected form bytes changed; prepare a new child")
  }
  let catalog_bytes = plan_read_bytes(root, catalog_ref)
  guard "sha256:" + sha256_hex(catalog_bytes) ==
    plan_string(state, "catalog_sha256") else {
    fail("catalog: capability catalog bytes changed; prepare a new child")
  }
  let captures : Array[PlanInputCapture] = @json.from_json(
    plan_value(state, "input_captures"),
  )
  plan_validate_captures(root, captures)
  @moonflow.decode_capability_catalog_v1(
    @json.parse(@utf8.decode(catalog_bytes)),
  )
}

///|
async fn plan_prepare_form_result(
  workspace : String,
  form_ref : String,
  catalog_ref : String,
  draft_id : String,
  recorded_at : String,
) -> Json {
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let lock = plan_writer_lock(root)
  defer @flow_host.release_named_writer_lock_v1(lock)
  let id = safe_id(draft_id, "draft_id")
  let index_ref = ".moonsuite/products/moonflow/planning/" + id + ".json"
  if @fs.exists(root + "/" + index_ref) {
    let index = plan_read_json(root, index_ref)
    let prepared_ref = plan_prepared_ref(plan_string(index, "preparation_id"))
    let state = plan_read_json(root, prepared_ref + "/state.json")
    guard plan_string(state, "form_ref") == form_ref &&
      plan_string(state, "recorded_at") == recorded_at else {
      fail(
        "draft_id already belongs to another form; choose a new preparation request",
      )
    }
    let catalog = plan_check_pins(root, state, catalog_ref)
    let draft = @moonflow.decode_declared_plan_draft_v1(
      plan_value(state, "draft"),
    )
    ignore(
      @moonflow.prepare_declared_plan_v1(
        draft,
        catalog,
        recorded_at,
        input_capture_digest=plan_string(state, "input_capture_digest"),
      ),
    )
    return plan_read_json(root, prepared_ref + "/receipt.json")
  }
  let form_bytes = plan_read_bytes(root, form_ref)
  let form = @json.parse(@utf8.decode(form_bytes))
  // The host supplies this from its selected Book, never from a browser path.
  let source_ref = plan_string(form, "source_ref")
  let source_bytes = plan_read_bytes(root, source_ref)
  guard @json.parse(@utf8.decode(source_bytes)) ==
    plan_value(form, "source_graph") else {
    fail("source_graph: form does not match the selected source file")
  }
  let catalog_bytes = plan_read_bytes(root, catalog_ref)
  let catalog = @moonflow.decode_capability_catalog_v1(
    @json.parse(@utf8.decode(catalog_bytes)),
  )
  let original = @moonflow.declared_plan_from_form_v1(form, id, recorded_at)
  // Validate syntax, dependency topology and owner capability before capture.
  ignore(@moonflow.prepare_declared_plan_v1(original, catalog, recorded_at))
  let catalog_value = @json.parse(@utf8.decode(catalog_bytes))
  let policies = @moonflow.decode_input_capture_policies_v1(catalog_value)
  let (captured_form, captures, input_digests) = plan_capture_form(
    root,
    form,
    policies~,
  )
  let capture_digest = "sha256:" +
    sha256_hex(@utf8.encode(captures.to_json().stringify()))
  let draft = @moonflow.declared_plan_from_form_v1(
    captured_form, id, recorded_at,
  )
  let prepared = @moonflow.prepare_declared_plan_v1(
    draft,
    catalog,
    recorded_at,
    input_capture_digest=capture_digest,
  )
  let prepared_ref = plan_prepared_ref(prepared.preparation_id)
  let graph_ref = prepared_ref + "/graph.json"
  let proposal_ref = prepared_ref + "/proposal.json"
  let parent_bytes = plan_parent_bytes(root, prepared.source_graph_id)
  let migration = match parent_bytes {
    Some(bytes) => {
      let parent = @moonflow.replay(
        prepared.source_graph_id,
        @moonflow.decode_event_array(@json.parse(@utf8.decode(bytes))),
      )
      Some(
        @moonflow.preview_declared_plan_revision_v1(
          draft,
          prepared,
          parent,
          proposal_ref,
          recorded_at,
          input_digests~,
        ).receipt,
      )
    }
    None => None
  }
  let receipt : Json = {
    "contract_id": "moonflow.declared-plan-preparation-receipt.v1",
    "prepared": prepared.to_json(),
    "graph_ref": graph_ref,
    "proposal_ref": proposal_ref,
    "receipt_ref": prepared_ref + "/receipt.json",
    "catalog_ref": catalog_ref,
    "evaluated_at": recorded_at,
    "migration_preview": match migration {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "source_ref": source_ref,
    "source_sha256": "sha256:" + sha256_hex(source_bytes),
    "catalog_sha256": "sha256:" + sha256_hex(catalog_bytes),
    "input_capture_digest": capture_digest,
    "input_captures": captures.to_json(),
    "capture_scope": "declared-input-bytes-and-explicit-spatial-reference-evidence",
    "capture_limitations": "Runtime/product state is not frozen. Opaque contracts keep original references and their selected bytes are revalidated at apply; unknown nested dependencies are not captured.",
    "original_reference_bindings": captures
    .filter(entry => entry.binding_mode == "original-reference-revalidated")
    .map(entry => entry.original_ref),
    "dispatched": false,
    "next_action": if migration is Some(_) {
      "revise-run"
    } else {
      "import-conformant-graph"
    },
  }
  let state : Json = {
    "contract_id": "moonflow.saved-plan-preparation.v1",
    "draft": draft.to_json(),
    "form_ref": form_ref,
    "form_sha256": "sha256:" + sha256_hex(form_bytes),
    "source_ref": source_ref,
    "source_sha256": "sha256:" + sha256_hex(source_bytes),
    "catalog_sha256": "sha256:" + sha256_hex(catalog_bytes),
    "recorded_at": recorded_at,
    "input_captures": captures.to_json(),
    "input_capture_digest": capture_digest,
    "input_digests": input_digests.to_json(),
    "parent_events_digest": plan_bytes_digest(parent_bytes),
    "receipt_sha256": "sha256:" +
    sha256_hex(@utf8.encode(receipt.stringify(indent=2) + "\n")),
  }
  // Detect mid-preparation mutation before publishing the complete receipt.
  ignore(plan_check_pins(root, state, catalog_ref))
  guard plan_bytes_digest(plan_parent_bytes(root, prepared.source_graph_id)) ==
    plan_bytes_digest(parent_bytes) else {
    fail("parent run changed during preparation; prepare a new child")
  }
  ignore(plan_store_json(root, prepared_ref, "graph.json", prepared.graph))
  ignore(
    plan_store_json(
      root,
      ".moonsuite/products/moonflow/plan-drafts",
      id + ".json",
      original.to_json(),
    ),
  )
  ignore(
    plan_store_json(root, prepared_ref, "proposal.json", prepared.proposal),
  )
  ignore(plan_freeze_bytes(root, prepared_ref, "source.json", source_bytes))
  ignore(plan_freeze_bytes(root, prepared_ref, "form.json", form_bytes))
  ignore(plan_freeze_bytes(root, prepared_ref, "catalog.json", catalog_bytes))
  ignore(plan_store_json(root, prepared_ref, "state.json", state))
  ignore(plan_store_json(root, prepared_ref, "receipt.json", receipt))
  ignore(
    plan_store_json(
      root,
      ".moonsuite/products/moonflow/planning",
      id + ".json",
      { "preparation_id": prepared.preparation_id },
    ),
  )
  receipt
}

///|
async fn plan_apply_prepared_result(
  workspace : String,
  preparation_id : String,
  catalog_ref : String,
  evaluated_at : String,
) -> Json {
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let lock = plan_writer_lock(root)
  defer @flow_host.release_named_writer_lock_v1(lock)
  let prepared_ref = plan_prepared_ref(preparation_id)
  let state = plan_read_json(root, prepared_ref + "/state.json")
  for name in ["source", "form", "catalog"] {
    let saved_bytes = plan_read_bytes(root, prepared_ref + "/" + name + ".json")
    guard "sha256:" + sha256_hex(saved_bytes) ==
      plan_string(state, name + "_sha256") else {
      fail("retained \{name} bytes changed or are incomplete")
    }
  }
  let receipt_bytes = plan_read_bytes(root, prepared_ref + "/receipt.json")
  guard "sha256:" + sha256_hex(receipt_bytes) ==
    plan_string(state, "receipt_sha256") else {
    fail("saved preparation receipt bytes changed")
  }
  let receipt = @json.parse(@utf8.decode(receipt_bytes))
  let catalog = plan_check_pins(root, state, catalog_ref)
  let draft = @moonflow.decode_declared_plan_draft_v1(
    plan_value(state, "draft"),
  )
  let capture_digest = plan_string(state, "input_capture_digest")
  guard "sha256:" +
    sha256_hex(@utf8.encode(plan_value(state, "input_captures").stringify())) ==
    capture_digest else {
    fail("saved capture identity changed")
  }
  let prepared = @moonflow.prepare_declared_plan_v1(
    draft,
    catalog,
    evaluated_at,
    input_capture_digest=capture_digest,
  )
  guard prepared.preparation_id == preparation_id &&
    prepared.to_json() == plan_value(receipt, "prepared") &&
    plan_read_bytes(root, prepared_ref + "/graph.json") ==
    @utf8.encode(prepared.graph.stringify(indent=2) + "\n") &&
    plan_read_bytes(root, prepared_ref + "/proposal.json") ==
    @utf8.encode(prepared.proposal.stringify(indent=2) + "\n") else {
    fail(
      "prepared graph or proposal changed; the displayed plan cannot be applied",
    )
  }
  let parent_bytes = plan_parent_bytes(root, prepared.source_graph_id)
  guard plan_bytes_digest(parent_bytes) ==
    plan_string(state, "parent_events_digest") else {
    fail(
      "parent run changed after preview; prepare and review a new child revision",
    )
  }
  let input_digests : Map[String, String] = @json.from_json(
    plan_value(state, "input_digests"),
  )
  let (events, migration) = match parent_bytes {
    Some(bytes) => {
      let parent = @moonflow.replay(
        prepared.source_graph_id,
        @moonflow.decode_event_array(@json.parse(@utf8.decode(bytes))),
      )
      let result = @moonflow.preview_declared_plan_revision_v1(
        draft,
        prepared,
        parent,
        prepared_ref + "/proposal.json",
        plan_string(state, "recorded_at"),
        input_digests~,
      )
      guard result.receipt.to_json() == plan_value(receipt, "migration_preview") else {
        fail("migration preview changed; review a new child revision")
      }
      (result.events, result.receipt.to_json())
    }
    None => {
      guard plan_value(receipt, "migration_preview") is Null else {
        fail("saved parent migration is missing")
      }
      (
        @moonflow.conformant_events_from_work_graph_at_v1(
          prepared.graph,
          catalog,
          evaluated_at,
        ),
        Json::null(),
      )
    }
  }
  guard events.all(event => event.kind != @moonflow.AttemptSubmitted) else {
    fail("planning must not submit an execution attempt")
  }
  let projection = @moonflow.replay(preparation_id, events)
  let run_ref = ".moonsuite/products/moonflow/runs/" + preparation_id
  let run_directory = plan_directory(root, run_ref)
  let applied_ref = prepared_ref + "/applied.json"
  if @fs.exists(root + "/" + applied_ref) {
    let saved = plan_read_json(root, applied_ref)
    guard plan_value(saved, "projection") ==
      @moonflow.projection_json(projection) &&
      plan_value(saved, "migration") == migration else {
      fail("saved applied result differs from the prepared plan")
    }
    // Never reset a run that has advanced since its original import.
    let persisted = @moonflow.decode_event_array(
      plan_read_json(root, run_ref + "/events.json"),
    )
    guard persisted.length() >= events.length() &&
      events
      .mapi((index, event) => persisted[index] == event)
      .all(value => value) else {
      fail("imported run history differs from its prepared events")
    }
    return saved
  }
  let intent_ref = prepared_ref + "/apply-intent.json"
  let intent = if @fs.exists(root + "/" + intent_ref) {
    plan_read_json(root, intent_ref)
  } else {
    let value : Json = {
      "preparation_id": preparation_id,
      "applied_at": evaluated_at,
    }
    ignore(plan_store_json(root, prepared_ref, "apply-intent.json", value))
    value
  }
  // Each component is atomic and repeatable. If the reply or process is lost,
  // the next call completes the same intent without replacing child history.
  ignore(plan_check_pins(root, state, catalog_ref))
  guard plan_bytes_digest(plan_parent_bytes(root, prepared.source_graph_id)) ==
    plan_string(state, "parent_events_digest") else {
    fail("parent run changed during apply; prepare a new revision")
  }
  ignore(
    plan_store_json(
      root,
      run_ref,
      "events.json",
      @moonflow.event_array_json(events),
    ),
  )
  ignore(
    plan_store_json(
      root,
      run_ref,
      "projection.json",
      @moonflow.projection_json(projection),
    ),
  )
  if !(migration is Null) {
    ignore(plan_store_json(root, run_ref, "migration.json", migration))
  }
  persist_operator_capability_catalog(root, preparation_id, catalog)
  publish_operator_handoffs(root, run_directory, projection)
  let result : Json = {
    "contract_id": "moonflow.declared-plan-apply-receipt.v1",
    "preparation_id": preparation_id,
    "status": "applied",
    "projection": @moonflow.projection_json(projection),
    "migration": migration,
    "applied_at": plan_string(intent, "applied_at"),
    "dispatched": false,
  }
  ignore(plan_store_json(root, prepared_ref, "applied.json", result))
  result
}

///|
async fn plan_prepare_form_command(
  workspace : String,
  form_ref : String,
  catalog_ref : String,
  draft_id : String,
  recorded_at : String,
) -> Unit {
  let result = plan_prepare_form_result(
    workspace, form_ref, catalog_ref, draft_id, recorded_at,
  ) catch {
    error => {
      @stdio.stderr.write(error.to_string() + "\n")
      raise error
    }
  }
  println(result.stringify(indent=2))
}

///|
async fn plan_apply_prepared_command(
  workspace : String,
  preparation_id : String,
  catalog_ref : String,
  evaluated_at : String,
) -> Unit {
  let result = plan_apply_prepared_result(
    workspace, preparation_id, catalog_ref, evaluated_at,
  ) catch {
    error => {
      @stdio.stderr.write(error.to_string() + "\n")
      raise error
    }
  }
  println(result.stringify(indent=2))
}
