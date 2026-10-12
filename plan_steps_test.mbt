///|
fn steps_form(graph : Json) -> Json raise {
  let draft = @moonflow.start_declared_plan_v1(
    graph, "steps", "existing-graph", "2026-07-31T00:00:00Z",
  )
  guard draft.to_json() is Object(fields) else { fail("draft") }
  {
    "contract_id": "moonflow.declared-plan-form-input.v2",
    "source_kind": "existing-graph",
    "source_graph": graph,
    "edits": fields["edits"],
    "added_templates": {},
  }
}

///|
fn steps_add(
  form : Json,
  id : String,
  template : String,
  input : String,
) -> Unit raise {
  guard form
    is { "edits": Array(edits), "added_templates": Object(templates), .. } else {
    fail("form")
  }
  guard edits
    .filter(edit => {
      edit is { "work_item_id": String(value), .. } && value == template
    })
    .get(0)
    is Some(original) else {
    fail("template")
  }
  let item = @json.parse(original.stringify())
  guard item is Object(fields) else { fail("item") }
  fields["work_item_id"] = id.to_json()
  fields["input_artifacts"] = [input]
  edits.push(item)
  templates[id] = template.to_json()
}

///|
test "v2 declared steps duplicate two operations remove leaf and preserve exact source contracts" {
  let source = plan_diamond_graph()
  let before = source.stringify()
  let form = steps_form(source)
  steps_add(form, "left-copy-1", "left", "requests/another.json")
  steps_add(form, "left-copy-2", "left", "requests/third.json")
  guard form is Object(fields) && fields["edits"] is Array(edits) else {
    fail("form")
  }
  fields["edits"] = edits
    .filter(edit => !(edit is { "work_item_id": "join", .. }))
    .to_json()
  let draft = @moonflow.declared_plan_from_form_v1(
    form, "steps", "2026-07-31T00:00:00Z",
  )
  assert_eq(@moonflow.decode_declared_plan_draft_v1(draft.to_json()), draft)
  let prepared = @moonflow.prepare_declared_plan_v1(
    draft,
    @moonflow.compile_capability_catalog_v1(conformance_source_bundle()),
    "2026-07-31T00:00:00Z",
  )
  let events = @moonflow.events_from_work_graph(prepared.graph)
  let child = @moonflow.replay(prepared.preparation_id, events)
  assert_eq(child.items.length(), 5)
  assert_true(child.find_item("join") is None)
  let original = child.find_item("left").unwrap()
  for id in ["left-copy-1", "left-copy-2"] {
    let item = child.find_item(id).unwrap()
    assert_eq(item.product_id, original.product_id)
    assert_eq(item.operation, original.operation)
    assert_eq(item.input_contracts, original.input_contracts)
    assert_eq(item.output_contracts, original.output_contracts)
    assert_eq(item.requested_authority, original.requested_authority)
    assert_eq(item.required_claim, original.required_claim)
    assert_true(item.declaration_id != original.declaration_id)
    assert_eq(item.attempt_count, 0)
    assert_true(item.approvals.is_empty())
  }
  assert_true(child.items[3].declaration_id != child.items[4].declaration_id)
  assert_eq(source.stringify(), before)
  try
    @moonflow.prepare_declared_plan_v1(
      draft,
      @moonflow.compile_capability_catalog_v1(conformance_source_bundle()),
      "2026-08-02T00:00:00Z",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("v2 draft accepted expired health")
  }
}

///|
test "v2 steps reject dangling removed dependency cycles unsafe duplicate unknown and empty plans" {
  for
    scenario in [
      "dangling", "cycle", "unsafe", "dotdot", "duplicate", "unknown", "empty", "remap-source",
      "unused-template", "legacy",
    ] {
    let form = steps_form(plan_diamond_graph())
    guard form is Object(fields) &&
      fields["edits"] is Array(edits) &&
      fields["added_templates"] is Object(templates) else {
      fail("form")
    }
    match scenario {
      "dangling" =>
        fields["edits"] = edits
          .filter(edit => !(edit is { "work_item_id": "root", .. }))
          .to_json()
      "cycle" => {
        guard edits[0] is Object(item) else { fail("item") }
        item["depends_on"] = ["join"]
      }
      "unsafe" => steps_add(form, "../unsafe", "left", "requests/other.json")
      "dotdot" => steps_add(form, "a..b", "left", "requests/other.json")
      "duplicate" => edits.push(edits[0])
      "unknown" => {
        steps_add(form, "new", "left", "requests/other.json")
        templates["new"] = "absent"
      }
      "empty" => fields["edits"] = ([] : Array[Json]).to_json()
      "remap-source" => templates["left"] = "root"
      "unused-template" => templates["unused"] = "left"
      _ => {
        fields["contract_id"] = "moonflow.declared-plan-form-input.v1"
        steps_add(form, "new", "left", "requests/other.json")
      }
    }
    try
      @moonflow.declared_plan_from_form_v1(
        form, "steps", "2026-07-31T00:00:00Z",
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid " + scenario)
    }
  }
}

///|
test "reintroduced duplicate in later source revision receives distinct checkpoint lineage" {
  let source = plan_diamond_graph()
  let first_form = steps_form(source)
  steps_add(first_form, "left-copy", "left", "requests/left.json")
  let first = @moonflow.declared_plan_from_form_v1(
    first_form, "first", "2026-07-31T00:00:00Z",
  )
  let first_view = @moonflow.declared_plan_form_v1(first)
  guard first_view is { "items": Array(first_items), .. } else { fail("first") }
  let first_added = first_items.filter(item => {
      item is { "work_item_id": "left-copy", .. }
    })[0]
  // A later source revision has removed the prior copy, but retained its
  // original operation. Reusing the item label cannot resurrect its checkpoint.
  let later_source = @json.parse(source.stringify())
  guard later_source is Object(fields) else { fail("source") }
  fields["graph_id"] = "diamond-r3"
  fields["declaration_revision"] = "r3"
  fields["source_digest"] = "sha256:later-source"
  let later_form = steps_form(later_source)
  steps_add(later_form, "left-copy", "left", "requests/left.json")
  let later = @moonflow.declared_plan_from_form_v1(
    later_form, "later", "2026-07-31T00:00:00Z",
  )
  guard @moonflow.declared_plan_form_v1(later)
    is { "items": Array(later_items), .. } else {
    fail("later")
  }
  let later_added = later_items.filter(item => {
      item is { "work_item_id": "left-copy", .. }
    })[0]
  guard first_added is { "declaration_id": String(first_id), .. } &&
    later_added is { "declaration_id": String(later_id), .. } else {
    fail("lineage")
  }
  assert_true(first_id != later_id)
}

///|
test "v2 duplicate declaration never inherits same-operation checkpoint while original can reuse" {
  let source = revised_graph()
  let form = steps_form(source)
  steps_add(form, "research-copy", "research-r2", "evidence/input.json")
  let draft = @moonflow.declared_plan_from_form_v1(
    form, "steps", "2026-07-31T00:00:00Z",
  )
  let authored = @moonflow.declared_plan_form_v1(draft)
  guard authored is { "items": Array(items), .. } && source is Object(fields) else {
    fail("graph")
  }
  fields["items"] = items.to_json()
  let parent = accepted_parent_projection()
  let before = parent.to_json().stringify()
  let revised = @moonflow.revise_run(
    parent, source, "duplicate-revision", "proposal.json", "2026-07-31T00:00:00Z",
  )
  assert_eq(revised.receipt.reused_count, 1)
  let child = @moonflow.replay("robot-r2", revised.events)
  assert_true(
    child.find_item("research-r2").unwrap().status is @moonflow.Accepted,
  )
  assert_false(
    child.find_item("research-copy").unwrap().status is @moonflow.Accepted,
  )
  assert_eq(
    revised.receipt.decisions.filter(decision => {
      decision.child_work_item_id == "research-copy"
    })[0].decision,
    "new",
  )
  assert_eq(child.find_item("research-copy").unwrap().attempt_count, 0)
  assert_true(child.find_item("research-copy").unwrap().approvals.is_empty())
  assert_eq(parent.to_json().stringify(), before)
}

///|
test "legacy saved draft without extension field decodes with original preparation identity" {
  let draft = plan_draft()
  let value = draft.to_json()
  guard value is Object(fields) else { fail("draft") }
  fields.remove("added_templates")
  assert_eq(@moonflow.decode_declared_plan_draft_v1(value), draft)
}

///|
test "v2 new ID restriction does not rename or reject retained legacy source labels" {
  let graph = plan_diamond_graph()
  guard graph is Object(fields) &&
    fields["items"] is Array(items) &&
    items[0] is Object(root) else {
    fail("source")
  }
  root["work_item_id"] = "root..legacy"
  fields["items"] = [items[0]]
  let form = steps_form(graph)
  steps_add(form, "safe-copy", "root..legacy", "requests/other.json")
  let draft = @moonflow.declared_plan_from_form_v1(
    form, "legacy", "2026-07-31T00:00:00Z",
  )
  guard @moonflow.declared_plan_form_v1(draft)
    is { "items": Array(authored), .. } else {
    fail("form")
  }
  assert_true(authored[0] is { "work_item_id": "root..legacy", .. })
  assert_true(authored[1] is { "work_item_id": "safe-copy", .. })
}
