///|
async fn prepared_test_workspace() -> String {
  let root = @fs.realpath(@fs.tmpdir(prefix="moonflow-prepared-"))
  ignore(plan_directory(root, "requests"))
  let graph = read_json("fixtures/capability-work-graph.valid.v1.json")
  write_json(root + "/source.json", graph)
  let catalog = @moonflow.compile_capability_catalog_json_v1(
    read_json("fixtures/capability-source-bundle.v1.json"),
  )
  write_json(root + "/catalog.json", catalog)
  write_json(root + "/requests/model.json", {
    "contract_id": "moonmold.spatial-operation-request.v1",
    "request_id": "r12-spatial",
    "idempotency_key": "r12-spatial",
    "project_id": "r12-fixture",
    "model_id": "r12-model",
    "expected_parent_digest": "mm1-empty-scene",
    "authority": "WorkspaceMutation",
    "reference_artifacts": [],
    "backend_preference": "mock-reference",
    "operation": {
      "method": "scene.create-model",
      "params": {
        "name": "r12",
        "units": "mm",
        "coordinateFrame": "z-up-right-handed",
      },
    },
  })
  let draft = @moonflow.start_declared_plan_v1(
    graph, "test", "existing-graph", "2026-07-31T00:00:00Z",
  )
  write_json(root + "/form.json", {
    "contract_id": "moonflow.declared-plan-form-input.v1",
    "source_kind": "existing-graph",
    "source_graph": graph,
    "source_ref": "source.json",
    "edits": plan_value(draft.to_json(), "edits"),
  })
  root
}

///|
async test "v2 duplicated spatial operation captures nested evidence and imports zero attempts" {
  let root = prepared_test_workspace()
  defer @fs.rmdir(root, recursive=true)
  write_json(root + "/requests/evidence.json", { "evidence": "retained" })
  let request = plan_read_json(root, "requests/model.json")
  let request_fields = plan_fields(request, "request")
  request_fields["reference_artifacts"] = ["requests/evidence.json"]
  write_json(root + "/requests/second.json", request)
  let form = plan_read_json(root, "form.json")
  let fields = plan_fields(form, "form")
  guard fields["edits"] is Array(edits) else { fail("edits") }
  let template = plan_string(edits[0], "work_item_id")
  let copy = @json.parse(edits[0].stringify())
  let copy_fields = plan_fields(copy, "copy")
  copy_fields["work_item_id"] = "copy"
  copy_fields["input_artifacts"] = ["requests/second.json"]
  edits.push(copy)
  fields["contract_id"] = "moonflow.declared-plan-form-input.v2"
  fields["added_templates"] = { "copy": template }
  write_json(root + "/form.json", form)
  let source = plan_read_bytes(root, "source.json")
  let prepared = prepared_test_prepare(root)
  let captures : Array[PlanInputCapture] = @json.from_json(
    plan_value(prepared, "input_captures"),
  )
  assert_true(
    captures.any(capture => {
      capture.work_item_id == "copy" &&
      capture.role == "pack-reference-evidence" &&
      capture.binding_mode == "captured-reference"
    }),
  )
  let id = prepared_test_id(prepared)
  let first = plan_apply_prepared_result(
    root, id, "catalog.json", "2026-07-31T00:01:00Z",
  )
  assert_eq(
    plan_apply_prepared_result(root, id, "catalog.json", "2026-07-31T00:02:00Z"),
    first,
  )
  let child = @moonflow.replay(id, load_events(root, id))
  assert_eq(child.items.length(), 2)
  assert_eq(child.find_item("copy").unwrap().attempt_count, 0)
  assert_true(
    child.find_item("copy").unwrap().declaration_id !=
    child.find_item(template).unwrap().declaration_id,
  )
  assert_eq(plan_read_bytes(root, "source.json"), source)
}

///|
async fn prepared_test_prepare(root : String, draft? : String = "test") -> Json {
  plan_prepare_form_result(
    root, "form.json", "catalog.json", draft, "2026-07-31T00:00:00Z",
  )
}

///|
fn prepared_test_id(receipt : Json) -> String raise {
  plan_string(plan_value(receipt, "prepared"), "preparation_id")
}

///|
async test "prepared plan captures bytes imports once and recovers interrupted reply" {
  let root = prepared_test_workspace()
  defer @fs.rmdir(root, recursive=true)
  let source_before = plan_read_bytes(root, "source.json")
  let prepared = prepared_test_prepare(root)
  assert_eq(prepared_test_prepare(root), prepared)
  let id = prepared_test_id(prepared)
  let applied = plan_apply_prepared_result(
    root, id, "catalog.json", "2026-07-31T00:01:00Z",
  )
  assert_eq(
    plan_apply_prepared_result(root, id, "catalog.json", "2026-07-31T00:02:00Z"),
    applied,
  )
  let ref = plan_prepared_ref(id)
  // Lost response/process after run persisted but before final apply receipt.
  @fs.remove(root + "/" + ref + "/applied.json")
  assert_eq(
    plan_apply_prepared_result(root, id, "catalog.json", "2026-07-31T00:03:00Z"),
    applied,
  )
  assert_eq(plan_read_bytes(root, "source.json"), source_before)
  let events = load_events(root, id)
  assert_eq(
    events.filter(event => event.kind == @moonflow.AttemptSubmitted).length(),
    0,
  )
  let projection = @moonflow.replay(id, events)
  assert_eq(projection.items[0].attempt_count, 0)
  assert_true(
    projection.items[0].input_artifacts[0].has_prefix(
      ".moonsuite/products/moonflow/plan-inputs/",
    ),
  )
  assert_eq(
    plan_read_bytes(root, projection.items[0].input_artifacts[0]),
    plan_read_bytes(root, "requests/model.json"),
  )
}

///|
async test "prepared plan pins source catalog input capture graph and health on every apply" {
  for
    field in [
      "source", "catalog", "input", "capture", "graph", "proposal", "receipt", "health",
    ] {
    let root = prepared_test_workspace()
    defer @fs.rmdir(root, recursive=true)
    let prepared = prepared_test_prepare(root)
    let id = prepared_test_id(prepared)
    let ref = plan_prepared_ref(id)
    let path = match field {
      "source" => "source.json"
      "catalog" => "catalog.json"
      "input" => "requests/model.json"
      "capture" => {
        let captures : Array[PlanInputCapture] = @json.from_json(
          plan_value(prepared, "input_captures"),
        )
        captures[0].captured_ref
      }
      "graph" => ref + "/graph.json"
      "proposal" => ref + "/proposal.json"
      "receipt" => ref + "/receipt.json"
      _ => ""
    }
    if path != "" {
      @fs.write_file(root + "/" + path, @utf8.encode("{}"), truncate=true)
    }
    let result = try
      plan_apply_prepared_result(
        root,
        id,
        "catalog.json",
        if field == "health" {
          "2026-08-02T00:00:00Z"
        } else {
          "2026-07-31T00:01:00Z"
        },
      )
      |> Ok
    catch {
      error => Err(error)
    }
    assert_true(result is Err(_), msg="changed \{field} must block")
    assert_false(@fs.exists(run_dir(root, id) + "/events.json"))
  }
}

///|
async test "prepared plan missing artifact unsafe path symlink and cycle are rejected without run" {
  for
    mode in ["missing", "traversal", "symlink", "cycle", "incomplete", "schema"] {
    let root = prepared_test_workspace()
    defer @fs.rmdir(root, recursive=true)
    let form = plan_read_json(root, "form.json")
    guard plan_value(form, "edits") is Array(edits) else { fail("edits") }
    let edit = plan_fields(edits[0], "edit")
    match mode {
      "missing" => edit["input_artifacts"] = ["requests/missing.json"]
      "traversal" => edit["input_artifacts"] = ["../outside"]
      "symlink" => {
        @fs.symlink(
          target=root + "/requests/model.json",
          root + "/requests/link.json",
        )
        edit["input_artifacts"] = ["requests/link.json"]
      }
      "cycle" => edit["depends_on"] = ["make-model"]
      "incomplete" => edit["acceptance_criteria"] = []
      "schema" => {
        let source = plan_value(form, "source_graph")
        guard plan_value(source, "items") is Array(items) else { fail("items") }
        plan_fields(items[0], "item")["input_contracts"] = [
          "moonmold/wrong@1.0.0",
        ]
        write_json(root + "/source.json", source)
      }
      _ => ()
    }
    write_json(root + "/form.json", form)
    let result = try prepared_test_prepare(root) |> Ok catch {
      error => Err(error)
    }
    assert_true(result is Err(_), msg="\{mode} must block")
  }
}

///|
async test "prepared revision preserves original parent and exact preview; parent change blocks" {
  let root = prepared_test_workspace()
  defer @fs.rmdir(root, recursive=true)
  let graph = plan_read_json(root, "source.json")
  let parent_id = plan_string(graph, "graph_id")
  ignore(persist_run(root, parent_id, @moonflow.events_from_work_graph(graph)))
  let parent_ref = ".moonsuite/products/moonflow/runs/" +
    parent_id +
    "/events.json"
  let before = plan_read_bytes(root, parent_ref)
  let prepared = prepared_test_prepare(root)
  assert_eq(plan_string(prepared, "next_action"), "revise-run")
  let id = prepared_test_id(prepared)
  let applied = plan_apply_prepared_result(
    root, id, "catalog.json", "2026-07-31T00:01:00Z",
  )
  assert_eq(
    plan_value(applied, "migration"),
    plan_value(prepared, "migration_preview"),
  )
  assert_eq(plan_read_bytes(root, parent_ref), before)
  @fs.write_file(
    root + "/" + parent_ref,
    @utf8.encode(@utf8.decode(before) + "\n"),
    truncate=true,
  )
  let result = try
    plan_apply_prepared_result(root, id, "catalog.json", "2026-07-31T00:02:00Z")
    |> Ok
  catch {
    error => Err(error)
  }
  assert_true(result is Err(_))
}

///|
async test "spatial evidence is rebound while exact originals remain inspectable" {
  let root = prepared_test_workspace()
  defer @fs.rmdir(root, recursive=true)
  let primary = plan_read_json(root, "requests/model.json")
  plan_fields(primary, "primary")["reference_artifacts"] = [
    "requests/reference.bin",
  ]
  write_json(root + "/requests/model.json", primary)
  @fs.write_file(
    root + "/requests/reference.bin",
    b"\x00\xff\x7f",
    create=0o600,
  )
  let prepared = prepared_test_prepare(root)
  let captures : Array[PlanInputCapture] = @json.from_json(
    plan_value(prepared, "input_captures"),
  )
  assert_eq(captures.length(), 3)
  let evidence = captures[1]
  assert_eq(plan_read_bytes(root, evidence.captured_ref), b"\x00\xff\x7f")
  let rebound = plan_read_json(root, captures[2].captured_ref)
  assert_eq(
    plan_value(rebound, "reference_artifacts"),
    [evidence.captured_ref].to_json(),
  )
  ignore(
    plan_apply_prepared_result(
      root,
      prepared_test_id(prepared),
      "catalog.json",
      "2026-07-31T00:01:00Z",
    ),
  )
}

///|
async test "changed input produces distinct child; old preparation remains inspectable" {
  let root = prepared_test_workspace()
  defer @fs.rmdir(root, recursive=true)
  let first = prepared_test_prepare(root)
  let primary = plan_read_json(root, "requests/model.json")
  plan_fields(primary, "primary")["intent"] = "new intent"
  write_json(root + "/requests/model.json", primary)
  let second = prepared_test_prepare(root, draft="changed")
  assert_true(prepared_test_id(first) != prepared_test_id(second))
  assert_eq(
    plan_read_json(
      root,
      plan_prepared_ref(prepared_test_id(first)) + "/receipt.json",
    ),
    first,
  )
  let result = try
    plan_apply_prepared_result(
      root,
      prepared_test_id(first),
      "catalog.json",
      "2026-07-31T00:01:00Z",
    )
    |> Ok
  catch {
    error => Err(error)
  }
  assert_true(result is Err(_))
}

///|
async test "opaque capture keeps original relative semantics and discloses limited scope" {
  let root = prepared_test_workspace()
  defer @fs.rmdir(root, recursive=true)
  let form = plan_read_json(root, "form.json")
  guard plan_value(plan_value(form, "source_graph"), "items") is Array(items) else {
    fail("items")
  }
  plan_fields(items[0], "item")["input_contracts"] = ["opaque.input.v1"]
  @fs.write_file(root + "/requests/model.json", b"\x00\xfe\xff", truncate=true)
  let (captured, captures, _) = plan_capture_form(root, form)
  guard plan_value(captured, "edits") is Array(edits) else { fail("edits") }
  assert_eq(
    plan_value(edits[0], "input_artifacts"),
    ["requests/model.json"].to_json(),
  )
  assert_eq(captures[0].binding_mode, "original-reference-revalidated")
  assert_eq(plan_read_bytes(root, captures[0].captured_ref), b"\x00\xfe\xff")
}

///|
async test "reapply preserves advanced child history and missing retained evidence blocks" {
  let root = prepared_test_workspace()
  defer @fs.rmdir(root, recursive=true)
  let prepared = prepared_test_prepare(root)
  let id = prepared_test_id(prepared)
  let applied = plan_apply_prepared_result(
    root, id, "catalog.json", "2026-07-31T00:01:00Z",
  )
  let events = load_events(root, id)
  let base = events[events.length() - 1]
  events.push({
    ..base,
    sequence: base.sequence + 1,
    event_id: "cancel-after-import",
    kind: @moonflow.ItemCancelled,
    recorded_at: "2026-07-31T00:02:00Z",
  })
  ignore(persist_run(root, id, events))
  let event_bytes = plan_read_bytes(
    root,
    ".moonsuite/products/moonflow/runs/" + id + "/events.json",
  )
  assert_eq(
    plan_apply_prepared_result(root, id, "catalog.json", "2026-07-31T00:03:00Z"),
    applied,
  )
  assert_eq(
    plan_read_bytes(
      root,
      ".moonsuite/products/moonflow/runs/" + id + "/events.json",
    ),
    event_bytes,
  )
  @fs.remove(root + "/" + plan_prepared_ref(id) + "/source.json")
  let result = try
    plan_apply_prepared_result(root, id, "catalog.json", "2026-07-31T00:04:00Z")
    |> Ok
  catch {
    error => Err(error)
  }
  assert_true(result is Err(_))
}
