///|
test "waves serialize diamond branches and prepare a conformant immutable plan" {
  let source = plan_diamond_graph()
  let before = source.stringify()
  let selected = @moonflow.declared_plan_from_waves_v1(
    source, 1, "serial", "2026-07-31T00:00:00Z",
  )
  assert_eq(selected.waves, [["root"], ["left"], ["right"], ["join"]])
  assert_eq(selected.added_edges.length(), 1)
  assert_eq(selected.added_edges[0].prerequisite_id, "left")
  assert_eq(selected.added_edges[0].consumer_id, "right")
  assert_eq(selected.draft.edits[2].depends_on, ["root", "left"])
  let reopened = @moonflow.decode_declared_plan_draft_v1(
    selected.draft.to_json(),
  )
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
  assert_eq(run.items.length(), 4)
  for item in run.items {
    assert_eq(item.operation, "moonmold/spatial.operation.execute@0.2.0")
    assert_eq(item.requested_authority, "workspace-mutation")
    assert_eq(item.attempt_count, 0)
    assert_eq(item.approvals, [])
  }
  assert_eq(source.stringify(), before)
}

///|
test "waves keep already bounded graph unchanged and handle unsorted source" {
  let source = plan_diamond_graph()
  let selected = @moonflow.declared_plan_from_waves_v1(
    source, 2, "parallel", "2026-07-31T00:00:00Z",
  )
  assert_eq(selected.waves, [["root"], ["left", "right"], ["join"]])
  assert_eq(selected.added_edges, [])
  guard source is Object(fields) && fields["items"] is Array(items) else {
    fail("fixture")
  }
  fields["items"] = [items[3], items[2], items[1], items[0]].to_json()
  let reversed = @moonflow.declared_plan_from_waves_v1(
    source, 1, "reverse", "2026-07-31T00:00:00Z",
  )
  assert_eq(reversed.waves, [["root"], ["right"], ["left"], ["join"]])
  assert_eq(reversed.draft.edits.map(edit => edit.work_item_id), [
    "join", "right", "left", "root",
  ])
  for width in [0, -1, 257] {
    assert_true(
      (try? @moonflow.declared_plan_from_waves_v1(
        source, width, "bad", "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
  }
}

///|
test "waves bound every reachable ready frontier across all four item DAGs" {
  // Enumerate all forward-edge graphs, then every completed-item subset.
  for mask in 0..<64 {
    let source = plan_diamond_graph()
    guard source is Object(fields) && fields["items"] is Array(items) else {
      fail("fixture")
    }
    let ids = ["root", "left", "right", "join"]
    let mut bit = 1
    for i in 0..<4 {
      let deps : Array[String] = []
      for j in 0..<i {
        if mask / bit % 2 == 1 {
          deps.push(ids[j])
        }
        bit *= 2
      }
      guard items[i] is Object(item) else { fail("fixture") }
      item["depends_on"] = deps.to_json()
    }
    for width in 1..<5 {
      let plan = @moonflow.declared_plan_from_waves_v1(
        source, width, "bounded", "2026-07-31T00:00:00Z",
      )
      assert_true(plan.waves.all(wave => wave.length() <= width))
      for subset in 0..<16 {
        let done : Array[String] = []
        let mut flag = 1
        for id in ids {
          if subset / flag % 2 == 1 {
            done.push(id)
          }
          flag *= 2
        }
        // Only downward-closed completion sets are reachable.
        if plan.draft.edits.all(edit => {
            !done.contains(edit.work_item_id) ||
            edit.depends_on.all(id => done.contains(id))
          }) {
          let ready = plan.draft.edits.filter(edit => {
            !done.contains(edit.work_item_id) &&
            edit.depends_on.all(id => done.contains(id))
          })
          assert_true(ready.length() <= width)
        }
      }
    }
  }
}

///|
test "waves refuse cycles and unknown dependencies without editing source" {
  for deps in [["join"], ["missing"]] {
    let source = plan_diamond_graph()
    guard source is Object(fields) &&
      fields["items"] is Array(items) &&
      items[0] is Object(root) else {
      fail("fixture")
    }
    root["depends_on"] = deps.to_json()
    let before = source.stringify()
    assert_true(
      (try? @moonflow.declared_plan_from_waves_v1(
        source, 2, "bad", "2026-07-31T00:00:00Z",
      ))
      is Err(_),
    )
    assert_eq(source.stringify(), before)
  }
}
