///|
fn plan_diamond_graph() -> Json {
  let items = [
    ("root", []),
    ("left", ["root"]),
    ("right", ["root"]),
    ("join", ["left", "right"]),
  ].map(pair => {
    let (id, dependencies) = pair
    (
      {
        "work_item_id": id,
        "declaration_id": id,
        "product_id": "moonmold",
        "requested_authority": "workspace-mutation",
        "acceptance_criteria": ["Review the exact " + id + " artifact"],
        "operation": "moonmold/spatial.operation.execute@0.2.0",
        "input_contracts": ["moonmold/spatial-operation-request@1.0.0"],
        "output_contracts": ["moonmold/spatial-operation-receipt@1.0.0"],
        "required_claim": "digital-artifact",
        "input_artifacts": ["requests/" + id + ".json"],
        "timeout_ms": 60000,
        "depends_on": dependencies,
      } : Json)
  })
  {
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "diamond-r1",
    "book_id": "fixture-plan",
    "declaration_revision": "r1",
    "source_digest": "sha256:fixture-source",
    "items": items,
    "recorded_at": "2026-07-31T00:00:00Z",
  }
}

///|
fn plan_draft() -> @moonflow.DeclaredPlanDraftV1 raise {
  @moonflow.start_declared_plan_v1(
    plan_diamond_graph(),
    "diamond-edit",
    "existing-graph",
    "2026-07-31T00:00:00Z",
  )
}

///|
fn plan_left_edit() -> @moonflow.PlanItemEditV1 {
  {
    work_item_id: "left",
    input_artifacts: ["requests/left-v2.json"],
    depends_on: ["root"],
    acceptance_criteria: ["Exact revised left output is reviewed"],
    timeout_ms: 90000,
  }
}

///|
test "plan authoring edits diamond and prepares deterministic immutable child without dispatch" {
  let source = plan_diamond_graph()
  let before = source.stringify()
  let original = @moonflow.start_declared_plan_v1(
    source, "diamond-edit", "existing-graph", "2026-07-31T00:00:00Z",
  )
  let original_bytes = original.to_json().stringify()
  let edit = plan_left_edit()
  let draft = @moonflow.edit_declared_plan_item_v1(original, edit)
  edit.input_artifacts.push("requests/caller-mutation.json")
  let catalog = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(),
  )
  let first = @moonflow.prepare_declared_plan_v1(
    draft, catalog, "2026-07-31T00:00:00Z",
  )
  let duplicate = @moonflow.prepare_declared_plan_v1(
    draft, catalog, "2026-07-31T01:00:00Z",
  )
  assert_eq(first, duplicate)
  assert_eq(source.stringify(), before)
  assert_eq(original.to_json().stringify(), original_bytes)
  let events = @moonflow.conformant_events_from_work_graph_at_v1(
    first.graph,
    catalog,
    "2026-07-31T00:00:00Z",
  )
  assert_eq(
    events.filter(event => event.kind == @moonflow.AttemptSubmitted).length(),
    0,
  )
  let child = @moonflow.replay(first.preparation_id, events)
  assert_true(child.run_id != "diamond-r1")
  assert_true(child.source_digest.has_prefix("sha256:"))
  assert_eq(child.source_digest.length(), 71)
  assert_eq(child.find_item("left").unwrap().input_artifacts, [
    "requests/left-v2.json",
  ])
  assert_eq(child.find_item("left").unwrap().timeout_ms, 90000)
  assert_eq(child.find_item("join").unwrap().depends_on, ["left", "right"])
  let untouched = @moonflow.prepare_declared_plan_v1(
    original, catalog, "2026-07-31T00:00:00Z",
  )
  assert_true(untouched.preparation_id != first.preparation_id)
}

///|
test "plan saved draft reopens exactly and source tamper rejects" {
  let draft = @moonflow.edit_declared_plan_item_v1(
    plan_draft(),
    plan_left_edit(),
  )
  let reopened = @moonflow.decode_declared_plan_draft_v1(
    @json.parse(draft.to_json().stringify()),
  )
  assert_eq(reopened, draft)
  let value = draft.to_json()
  guard value is Object(fields) else { fail("expected draft") }
  fields["source_graph_digest"] = "sha256:wrong"
  try @moonflow.decode_declared_plan_draft_v1(value) catch {
    _ => ()
  } noraise {
    _ => fail("source tampering accepted")
  }
}

///|
test "plan invalid dependencies cycles duplicate bindings and timeouts block editing" {
  let base = plan_left_edit()
  for
    edit in [
      { ..base, depends_on: ["missing"], },
      { ..base, depends_on: ["join"], },
      { ..base, depends_on: ["left"], },
      { ..base, depends_on: ["root", "root"], },
      { ..base, timeout_ms: 0, },
      { ..base, timeout_ms: 86400001, },
      { ..base, acceptance_criteria: [], },
      { ..base, input_artifacts: ["../outside.json"], },
      { ..base, input_artifacts: ["a.json", "a.json"], },
    ] {
    try @moonflow.edit_declared_plan_item_v1(plan_draft(), edit) catch {
      _ => ()
    } noraise {
      _ => fail("invalid edit accepted")
    }
  }
}

///|
test "plan preparation refuses incompatible operation schema and stale health every time" {
  let catalog = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(),
  )
  let draft = plan_draft()
  ignore(
    @moonflow.prepare_declared_plan_v1(draft, catalog, "2026-07-31T00:00:00Z"),
  )
  try
    @moonflow.prepare_declared_plan_v1(draft, catalog, "2026-08-02T00:00:00Z")
  catch {
    _ => ()
  } noraise {
    _ => fail("expired preparation accepted")
  }
  for
    graph in [
      conformant_work_graph(operation="moonmold/missing.operation@0.2.0"),
      conformant_work_graph(input_contract="moonmold/wrong-request@1.0.0"),
    ] {
    let invalid = @moonflow.start_declared_plan_v1(
      graph, "invalid", "product-preset", "2026-07-31T00:00:00Z",
    )
    try
      @moonflow.prepare_declared_plan_v1(
        invalid, catalog, "2026-07-31T00:00:00Z",
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("incompatible preparation accepted")
    }
  }
}

///|
test "plan typed host form preserves source owner semantics and validates all edits" {
  let original = plan_draft()
  let saved = original.to_json()
  guard saved is Object(fields) else { fail("expected draft") }
  let form : Json = {
    "contract_id": "moonflow.declared-plan-form-input.v1",
    "source_kind": "existing-graph",
    "source_graph": plan_diamond_graph(),
    "edits": fields["edits"],
  }
  let reopened = @moonflow.declared_plan_from_form_v1(
    form, "diamond-edit", "2026-07-31T00:00:00Z",
  )
  assert_eq(reopened, original)
}

///|
test "plan identity canonicalizes source object order" {
  let graph = plan_diamond_graph()
  guard graph is Object(fields) else { fail("expected graph") }
  let reordered : Map[String, Json] = Map([])
  let keys = fields.keys().to_array()
  keys.sort()
  for key in keys {
    reordered[key] = fields[key]
  }
  let a = @moonflow.start_declared_plan_v1(
    graph, "same", "existing-graph", "2026-07-31T00:00:00Z",
  )
  let b = @moonflow.start_declared_plan_v1(
    Json::object(reordered),
    "same",
    "existing-graph",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(a, b)
}

///|
test "plan integer decoder refuses fractional timeout instead of truncating it" {
  let value = plan_left_edit().to_json()
  guard value is Object(fields) else { fail("expected edit") }
  fields["timeout_ms"] = 1.5
  try @moonflow.decode_plan_item_edit_v1(value) catch {
    _ => ()
  } noraise {
    _ => fail("fractional timeout was truncated")
  }
}

///|
test "plan captured byte identity changes child without changing legacy preparation" {
  let draft = plan_draft()
  let catalog = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(),
  )
  let legacy = @moonflow.prepare_declared_plan_v1(
    draft, catalog, "2026-07-31T00:00:00Z",
  )
  let a = @moonflow.prepare_declared_plan_v1(
    draft,
    catalog,
    "2026-07-31T00:00:00Z",
    input_capture_digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let b = @moonflow.prepare_declared_plan_v1(
    draft,
    catalog,
    "2026-07-31T00:00:00Z",
    input_capture_digest="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  )
  assert_true(a.preparation_id != b.preparation_id)
  assert_true(a.preparation_id != legacy.preparation_id)
  assert_eq(
    @moonflow.prepare_declared_plan_v1(draft, catalog, "2026-07-31T00:00:00Z"),
    legacy,
  )
}
