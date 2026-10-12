///|
fn table_plan_template() -> Json {
  {
    "contract_id": "moonflow.table-plan-template.v1",
    "item_bindings": ["root", "left", "right", "join"].map(id => {
      (
        {
          "template_work_item_id": id,
          "input_artifacts": ["requests/{{key}}/" + id + ".json"],
          "acceptance_criteria": ["Review {{label}}: " + id],
        } : Json)
    }),
  }
}

///|
test "table expands diamond branches with stable IDs local joins and editable outputs" {
  let source = plan_diamond_graph()
  let before = source.stringify()
  let template = table_plan_template()
  let csv = "key,label\ncompact,Compact furniture\nwide,Wide furniture\n"
  let first = @moonflow.declared_plan_from_table_v1(
    source, template, csv, "study", "2026-07-31T00:00:00Z",
  )
  assert_eq(first.items_per_row, 4)
  assert_eq(first.row_keys, ["compact", "wide"])
  assert_eq(first.csv_digest.length(), 71)
  assert_eq(first.template_digest.length(), 71)
  assert_eq(first.draft.edits.length(), 8)
  assert_eq(first.draft.edits[3].depends_on, ["compact--left", "compact--right"])
  assert_eq(first.draft.edits[7].depends_on, ["wide--left", "wide--right"])
  assert_eq(first.draft.edits[4].input_artifacts, ["requests/wide/root.json"])
  assert_eq(first.draft.edits[7].acceptance_criteria, [
    "Review Wide furniture: join",
  ])
  assert_eq(
    first,
    @moonflow.declared_plan_from_table_v1(
      source, template, csv, "study", "2026-07-31T00:00:00Z",
    ),
  )
  let reopened = @moonflow.decode_declared_plan_draft_v1(first.draft.to_json())
  assert_eq(reopened, first.draft)
  let catalog = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(),
  )
  let prepared = @moonflow.prepare_declared_plan_v1(
    first.draft,
    catalog,
    "2026-07-31T00:00:00Z",
  )
  let run = @moonflow.replay(
    prepared.preparation_id,
    @moonflow.events_from_work_graph(prepared.graph),
  )
  for item in run.items {
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
  assert_true(run.items[0].declaration_id != run.items[4].declaration_id)
  let edited = @moonflow.edit_declared_plan_item_v1(first.draft, {
    ..first.draft.edits[7],
    acceptance_criteria: ["Review the revised wide furniture display"],
  })
  let changed = @moonflow.prepare_declared_plan_v1(
    edited, catalog, "2026-07-31T00:00:00Z",
  )
  assert_true(changed.preparation_id != prepared.preparation_id)
  assert_eq(first.draft.edits[7].acceptance_criteria, [
    "Review Wide furniture: join",
  ])
  assert_eq(source.stringify(), before)
  assert_true(
    (try? @moonflow.prepare_declared_plan_v1(
      first.draft,
      catalog,
      "2026-08-02T00:00:00Z",
    ))
    is Err(_),
  )
}

///|
test "table keeps mixed product contracts and does not recursively evaluate CSV text" {
  let source = plan_diamond_graph()
  guard source is { "items": Array(items), .. } && items[1] is Object(fields) else {
    fail("fixture")
  }
  fields["product_id"] = "synthetic-validator"
  fields["operation"] = "synthetic-validator/validate@1.0.0"
  fields["requested_authority"] = "observe"
  fields["input_contracts"] = ["synthetic-validator/request@1.0.0"]
  fields["output_contracts"] = ["synthetic-validator/result@1.0.0"]
  let expanded = @moonflow.declared_plan_from_table_v1(
    source,
    table_plan_template(),
    "\u{FEFF}label,key\r\n\"Check \"\"café\"\", {{key}}\",french\r\n",
    "mixed",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(expanded.draft.edits[1].acceptance_criteria, [
    "Review Check \"café\", {{key}}: left",
  ])
  let form = @moonflow.declared_plan_form_v1(expanded.draft)
  guard form is { "items": Array(result), .. } else { fail("form") }
  assert_true(
    result[1]
    is {
      "work_item_id": "french--left",
      "product_id": "synthetic-validator",
      "operation": "synthetic-validator/validate@1.0.0",
      "requested_authority": "observe",
      "input_contracts": ["synthetic-validator/request@1.0.0"],
      ..
    },
  )
  assert_true(result[2] is { "product_id": "moonmold", .. })
}

///|
test "table retains literal source criteria when no criteria template is supplied" {
  let template : Json = {
    "contract_id": "moonflow.table-plan-template.v1",
    "item_bindings": ["root", "left", "right", "join"].map(id => {
      (
        {
          "template_work_item_id": id,
          "input_artifacts": ["requests/{{key}}/" + id + ".json"],
        } : Json)
    }),
  }
  let expanded = @moonflow.declared_plan_from_table_v1(
    plan_diamond_graph(),
    template,
    "key\na\n",
    "literal",
    "2026-07-31T00:00:00Z",
  )
  assert_eq(expanded.draft.edits[3].acceptance_criteria, [
    "Review the exact join artifact",
  ])
}

///|
test "table rejects ambiguous rows unsafe substituted paths and graph size overflow" {
  for
    csv in [
      "key,label\na,first\na,duplicate\n", "key,label\na--b,label\n", "key,label\na..b,label\n",
      "key,label\na/b,label\n", "key,label\na,\n", "key,label\na,label,extra\n",
      "key,key\na,b\n", "key,bad-label\na,b\n", "label\na\n",
    ] {
    assert_true(
      (try? @moonflow.declared_plan_from_table_v1(
        plan_diamond_graph(),
        table_plan_template(),
        csv,
        "invalid",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
  let csv = "key,label\n" + Array::makei(65, i => "r\{i},Label\n").join("")
  assert_true(
    (try? @moonflow.declared_plan_from_table_v1(
      plan_diamond_graph(),
      table_plan_template(),
      csv,
      "oversize",
      "2026-07-31T00:00:00Z",
    ))
    is Err(_),
  )
  for
    artifact in [
      "requests/{{missing}}.json", "requests/{{key.json", "requests/key}}.json",
      "../{{key}}.json",
    ] {
    let template = table_plan_template()
    guard template is { "item_bindings": Array(bindings), .. } &&
      bindings[0] is Object(fields) else {
      fail("fixture")
    }
    fields["input_artifacts"] = [artifact]
    assert_true(
      (try? @moonflow.declared_plan_from_table_v1(
        plan_diamond_graph(),
        template,
        "key,label\na,Label\n",
        "bad",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
}

///|
test "table requires one complete original step binding and refuses colliding source IDs" {
  for scenario in ["missing", "duplicate", "unknown"] {
    let template = table_plan_template()
    guard template is { "item_bindings": Array(bindings), .. } else {
      fail("fixture")
    }
    if scenario == "missing" {
      ignore(bindings.pop())
    } else if scenario == "duplicate" {
      bindings.push(bindings[0])
    } else {
      guard bindings[0] is Object(fields) else { fail("fixture") }
      fields["template_work_item_id"] = "unknown"
    }
    assert_true(
      (try? @moonflow.declared_plan_from_table_v1(
        plan_diamond_graph(),
        template,
        "key,label\na,Label\n",
        "bad",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
  let source = plan_diamond_graph()
  guard source is { "items": Array(items), .. } && items[3] is Object(fields) else {
    fail("fixture")
  }
  fields["work_item_id"] = "a--root"
  let template = table_plan_template()
  guard template is { "item_bindings": Array(bindings), .. } &&
    bindings[3] is Object(binding) else {
    fail("fixture")
  }
  binding["template_work_item_id"] = "a--root"
  assert_true(
    (try? @moonflow.declared_plan_from_table_v1(
      source, template, "key,label\na,Label\n", "collision", "2026-07-31T00:00:00Z",
    ))
    is Err(_),
  )
}

///|
test "table row reorder keeps keyed branch identity and accepts the exact item limit" {
  let source = plan_diamond_graph()
  let template = table_plan_template()
  let first = @moonflow.declared_plan_from_table_v1(
    source, template, "key,label\na,First\nb,Second\n", "stable", "2026-07-31T00:00:00Z",
  )
  let reordered = @moonflow.declared_plan_from_table_v1(
    source, template, "key,label\nb,Second\na,First\n", "stable", "2026-07-31T00:00:00Z",
  )
  assert_eq(first.draft.edits[0], reordered.draft.edits[4])
  assert_eq(first.draft.edits[7], reordered.draft.edits[3])
  guard @moonflow.declared_plan_form_v1(first.draft)
    is { "items": Array(a), .. } &&
    @moonflow.declared_plan_form_v1(reordered.draft)
    is { "items": Array(b), .. } else {
    fail("forms")
  }
  assert_eq(a[0], b[4])
  let csv = "key,label\n" + Array::makei(64, i => "r\{i},Label\n").join("")
  let full = @moonflow.declared_plan_from_table_v1(
    source, template, csv, "full", "2026-07-31T00:00:00Z",
  )
  assert_eq(full.draft.edits.length(), 256)
  guard template is { "item_bindings": Array(bindings), .. } &&
    bindings[0] is Object(fields) else {
    fail("template")
  }
  fields["input_artifacts"] = ["{{file}}"]
  for path in ["../secret.json", "/absolute.json", "requests/../secret.json"] {
    assert_true(
      (try? @moonflow.declared_plan_from_table_v1(
        source,
        template,
        "key,label,file\na,Label," + path + "\n",
        "path",
        "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
}
