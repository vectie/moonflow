///|
pub(all) struct ChangeImpactItemV1 {
  work_item_id : String
  dependency_distance : Int
  impacted_prerequisite_ids : Array[String]
} derive(Debug, Eq, ToJson)

///|
pub(all) struct ChangeImpactV1 {
  contract_id : String
  source_graph_digest : String
  changed_item_ids : Array[String]
  affected_items : Array[ChangeImpactItemV1]
  unaffected_item_ids : Array[String]
} derive(Debug, Eq, ToJson)

///|
/// Explore the declared downstream impact of explicit potential changes.
/// Distance is the shortest dependency path from any changed item, not an
/// execution order or a claim that an existing checkpoint is invalid.
pub fn declared_change_impact_v1(
  source_graph : Json,
  changed_item_ids : Array[String],
) -> ChangeImpactV1 raise {
  let edits = plan_edits_from_graph(source_graph)
  guard edits.length() <= 256 else {
    fail("change impact source must contain at most 256 work items")
  }
  plan_unique_strings(changed_item_ids, "changed_item_ids", nonempty=true)
  let distance : Map[String, Int] = {}
  for id in changed_item_ids {
    guard edits.any(edit => edit.work_item_id == id) else {
      fail("unknown changed work item: \{id}")
    }
    distance[id] = 0
  }
  // Process one complete frontier at a time so source order cannot affect
  // shortest distance, even when the input graph is not topologically sorted.
  for depth = 0; depth < edits.length(); depth = depth + 1 {
    let next = edits.filter(edit => {
      !distance.contains(edit.work_item_id) &&
      edit.depends_on.any(id => distance.get(id) == Some(depth))
    })
    if next.is_empty() {
      break
    }
    for edit in next {
      distance[edit.work_item_id] = depth + 1
    }
  }
  let affected = edits
    .filter(edit => {
      distance.contains(edit.work_item_id) &&
      !changed_item_ids.contains(edit.work_item_id)
    })
    .map(edit => ChangeImpactItemV1::{
      work_item_id: edit.work_item_id,
      dependency_distance: distance[edit.work_item_id],
      impacted_prerequisite_ids: edit.depends_on.filter(id => {
        distance.contains(id)
      }),
    })
  {
    contract_id: "moonflow.change-impact.v1",
    source_graph_digest: plan_digest(source_graph),
    changed_item_ids: edits
    .filter(edit => changed_item_ids.contains(edit.work_item_id))
    .map(edit => edit.work_item_id),
    affected_items: affected,
    unaffected_item_ids: edits
    .filter(edit => !distance.contains(edit.work_item_id))
    .map(edit => edit.work_item_id),
  }
}
