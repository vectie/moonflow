///|
/// Static execution waves. Every item in a later wave waits for the complete
/// preceding wave using ordinary declared dependencies, including review gates.
pub(all) struct WavePlanV1 {
  contract_id : String
  max_parallel : Int
  waves : Array[Array[String]]
  added_edges : Array[DeclaredRouteEdgeV1]
  draft : DeclaredPlanDraftV1
} derive(Debug, Eq, ToJson)

///|
/// Bound a graph's ready frontier without changing operations or authority.
/// Source-order ties are deterministic. Waves contain only items whose original
/// prerequisites are in earlier waves. Barriers intentionally trade throughput
/// for an inspectable static bound; this is not a runtime scheduler or rate limit.
pub fn declared_plan_from_waves_v1(
  source_graph : Json,
  max_parallel : Int,
  draft_id : String,
  recorded_at : String,
) -> WavePlanV1 raise {
  guard max_parallel >= 1 && max_parallel <= 256 else {
    fail("max_parallel must be in 1..256")
  }
  let original = start_declared_plan_v1(
    source_graph, draft_id, "existing-graph", recorded_at,
  )
  guard original.edits.length() <= 256 else {
    fail("wave source must contain at most 256 work items")
  }
  let completed : Map[String, Bool] = {}
  let waves : Array[Array[String]] = []
  let additions : Map[String, Array[String]] = {}
  let edges : Array[DeclaredRouteEdgeV1] = []
  let mut previous : Array[String] = []
  while completed.length() < original.edits.length() {
    let wave : Array[String] = []
    for edit in original.edits {
      if wave.length() < max_parallel &&
        !completed.contains(edit.work_item_id) &&
        edit.depends_on.all(id => completed.contains(id)) {
        wave.push(edit.work_item_id)
        let added = previous.filter(id => !edit.depends_on.contains(id))
        additions[edit.work_item_id] = added
        for id in added {
          edges.push({ prerequisite_id: id, consumer_id: edit.work_item_id, })
        }
      }
    }
    guard !wave.is_empty() else {
      fail("wave source has unresolved dependencies")
    }
    for id in wave {
      completed[id] = true
    }
    waves.push(wave)
    previous = wave
  }
  let edits = original.edits.map(edit => {
    let dependencies = edit.depends_on.copy()
    for id in additions[edit.work_item_id] {
      dependencies.push(id)
    }
    { ..edit, depends_on: dependencies, }
  })
  let draft = declared_plan_from_form_v1(
    {
      "contract_id": "moonflow.declared-plan-form-input.v2",
      "source_kind": "existing-graph",
      "source_graph": source_graph,
      "edits": edits.to_json(),
      "added_templates": {},
    },
    draft_id,
    recorded_at,
  )
  {
    contract_id: "moonflow.wave-plan.v1",
    max_parallel,
    waves,
    added_edges: edges,
    draft,
  }
}
