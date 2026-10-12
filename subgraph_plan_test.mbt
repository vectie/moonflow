///|
test "subgraph selects a branch with prerequisites and prepares editable child" {
  let source = plan_diamond_graph()
  let before = source.stringify()
  let selected = @moonflow.declared_plan_from_subgraph_v1(
    source,
    ["left"],
    "left-only",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(selected.target_item_ids, ["left"])
  assert_eq(selected.prerequisite_item_ids, ["root"])
  assert_eq(selected.omitted_item_ids, ["right", "join"])
  assert_eq(selected.draft.edits.map(item => item.work_item_id), [
    "root", "left",
  ])
  assert_eq(selected.draft.edits[1].depends_on, ["root"])
  let reopened = @moonflow.decode_declared_plan_draft_v1(
    selected.draft.to_json(),
  )
  assert_eq(reopened, selected.draft)
  let catalog = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(),
  )
  let prepared = @moonflow.prepare_declared_plan_v1(
    reopened, catalog, "2026-07-31T00:00:00Z",
  )
  let run = @moonflow.replay(
    prepared.preparation_id,
    @moonflow.conformant_events_from_work_graph_at_v1(
      prepared.graph,
      catalog,
      "2026-07-31T00:00:00Z",
    ),
  )
  assert_eq(run.items.length(), 2)
  for item in run.items {
    assert_eq(item.declaration_id, item.work_item_id)
    assert_eq(item.operation, "moonmold/spatial.operation.execute@0.2.0")
    assert_eq(item.product_id, "moonmold")
    assert_eq(item.requested_authority, "workspace-mutation")
    assert_eq(item.input_contracts, ["moonmold/spatial-operation-request@1.0.0"])
    assert_eq(item.output_contracts, [
      "moonmold/spatial-operation-receipt@1.0.0",
    ])
    assert_eq(item.required_claim, "digital-artifact")
    assert_eq(item.timeout_ms, 60000)
    assert_eq(item.attempt_count, 0)
    assert_eq(item.approvals, [])
  }
  let edited = @moonflow.edit_declared_plan_item_v1(reopened, {
    ..reopened.edits[1],
    acceptance_criteria: ["Review the selected left output at full scale"],
  })
  let revised = @moonflow.prepare_declared_plan_v1(
    edited, catalog, "2026-07-31T00:00:00Z",
  )
  assert_true(revised.preparation_id != prepared.preparation_id)
  assert_eq(source.stringify(), before)
  assert_eq(selected.draft.edits[1].acceptance_criteria, [
    "Review the exact left artifact",
  ])
}

///|
test "subgraph handles joins and canonical multi target selection without duplicated prerequisites" {
  let source = plan_diamond_graph()
  let joined = @moonflow.declared_plan_from_subgraph_v1(
    source,
    ["join"],
    "join",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(joined.prerequisite_item_ids, ["root", "left", "right"])
  assert_eq(joined.omitted_item_ids, [])
  assert_eq(joined.draft.edits[3].depends_on, ["left", "right"])
  let first = @moonflow.declared_plan_from_subgraph_v1(
    source,
    ["right", "left"],
    "pair",
    "2026-07-31T00:00:00Z",
  )
  let reordered = @moonflow.declared_plan_from_subgraph_v1(
    source,
    ["left", "right"],
    "pair",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(first, reordered)
  assert_eq(first.target_item_ids, ["left", "right"])
  assert_eq(first.prerequisite_item_ids, ["root"])
  assert_eq(first.omitted_item_ids, ["join"])
  let explicit_root = @moonflow.declared_plan_from_subgraph_v1(
    source,
    ["left", "root"],
    "root",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(explicit_root.target_item_ids, ["root", "left"])
  assert_eq(explicit_root.prerequisite_item_ids, [])
}

///|
test "subgraph closure is independent of source item ordering and detaches caller arrays" {
  let source = plan_diamond_graph()
  guard source is Object(fields) && fields["items"] is Array(items) else {
    fail("fixture")
  }
  fields["items"] = [items[3], items[2], items[1], items[0]].to_json()
  let targets = ["left"]
  let selected = @moonflow.declared_plan_from_subgraph_v1(
    source, targets, "unordered", "2026-07-31T00:00:00Z",
  )
  targets.push("right")
  assert_eq(selected.target_item_ids, ["left"])
  assert_eq(selected.draft.edits.map(item => item.work_item_id), [
    "left", "root",
  ])
  assert_eq(selected.draft.edits[0].depends_on, ["root"])
  assert_eq(selected.omitted_item_ids, ["join", "right"])
}

///|
test "subgraph requires known distinct targets and a valid whole source graph" {
  for targets in [[], ["missing"], ["left", "left"], [""]] {
    assert_true(
      (try? @moonflow.declared_plan_from_subgraph_v1(
        plan_diamond_graph(),
        targets,
        "invalid",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
  for dependencies in [["missing"], ["join"]] {
    let source = plan_diamond_graph()
    guard source is { "items": Array(items), .. } && items[2] is Object(right) else {
      fail("fixture")
    }
    right["depends_on"] = dependencies.to_json()
    assert_true(
      (try? @moonflow.declared_plan_from_subgraph_v1(
        source,
        ["left"],
        "invalid-source",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
}

///|
test "subgraph selects a long dependency chain at the 256 item boundary" {
  let source = plan_diamond_graph()
  guard source is Object(fields) && fields["items"] is Array(items) else {
    fail("fixture")
  }
  let template = items[0].stringify()
  let expanded = Array::makei(257, index => {
    let value = @json.parse(template)
    guard value is Object(item) else { fail("fixture") }
    item["work_item_id"] = "step-\{index}".to_json()
    item["declaration_id"] = "step-\{index}".to_json()
    item["depends_on"] = if index == 0 {
      ([] : Array[String]).to_json()
    } else {
      ["step-\{index - 1}"].to_json()
    }
    value
  })
  fields["items"] = expanded[:256].to_array().to_json()
  let selected = @moonflow.declared_plan_from_subgraph_v1(
    source,
    ["step-255"],
    "chain",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(selected.prerequisite_item_ids.length(), 255)
  assert_eq(selected.draft.edits.length(), 256)
  fields["items"] = expanded.to_json()
  assert_true(
    (try? @moonflow.declared_plan_from_subgraph_v1(
      source,
      ["step-0"],
      "oversize",
      "2026-07-31T00:00:00Z",
    ))
    is Err(_),
  )
}
