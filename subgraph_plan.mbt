///|
/// An explicit target selection plus every declared prerequisite. IDs are in
/// source order; the draft is an ordinary editable removal-only v2 plan.
pub(all) struct SubgraphPlanSelectionV1 {
  contract_id : String
  target_item_ids : Array[String]
  prerequisite_item_ids : Array[String]
  omitted_item_ids : Array[String]
  draft : DeclaredPlanDraftV1
} derive(Debug, Eq, ToJson)

///|
/// Keep selected outputs and their transitive dependency closure. This does
/// not include downstream consumers, infer dependencies from artifact paths,
/// skip accepted work, grant authority, or create execution attempts.
pub fn declared_plan_from_subgraph_v1(
  source_graph : Json,
  target_item_ids : Array[String],
  draft_id : String,
  recorded_at : String,
) -> SubgraphPlanSelectionV1 raise {
  let original = start_declared_plan_v1(
    source_graph, draft_id, "existing-graph", recorded_at,
  )
  guard original.edits.length() <= 256 else {
    fail("subgraph source must contain at most 256 work items")
  }
  plan_unique_strings(target_item_ids, "target_item_ids", nonempty=true)
  let items : Map[String, PlanItemEditV1] = {}
  for edit in original.edits {
    items[edit.work_item_id] = edit
  }
  for id in target_item_ids {
    guard items.contains(id) else { fail("unknown subgraph target: \{id}") }
  }
  let included : Map[String, Bool] = {}
  let pending = target_item_ids.copy()
  let mut cursor = 0
  while cursor < pending.length() {
    let id = pending[cursor]
    cursor += 1
    if !included.contains(id) {
      included[id] = true
      for dependency in items[id].depends_on {
        pending.push(dependency)
      }
    }
  }
  let edits = original.edits.filter(edit => included.contains(edit.work_item_id))
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
    contract_id: "moonflow.subgraph-plan-selection.v1",
    target_item_ids: edits
    .filter(edit => target_item_ids.contains(edit.work_item_id))
    .map(edit => edit.work_item_id),
    prerequisite_item_ids: edits
    .filter(edit => !target_item_ids.contains(edit.work_item_id))
    .map(edit => edit.work_item_id),
    omitted_item_ids: original.edits
    .filter(edit => !included.contains(edit.work_item_id))
    .map(edit => edit.work_item_id),
    draft,
  }
}
