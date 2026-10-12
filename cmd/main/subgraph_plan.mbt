///|
async fn plan_subgraph_command(
  workspace : String,
  source_ref : String,
  draft_id : String,
  recorded_at : String,
  target_item_ids : Array[String],
  save : Bool,
) -> Unit {
  validate_artifact_ref(workspace, source_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let selected = @moonflow.declared_plan_from_subgraph_v1(
    read_json(root + "/" + source_ref),
    target_item_ids,
    draft_id,
    recorded_at,
  )
  // Omitted branches do not require their local input files. Retained inputs
  // must exist and remain inside the workspace before any draft is written.
  for edit in selected.draft.edits {
    for artifact in edit.input_artifacts {
      validate_artifact_ref(root, artifact)
    }
  }
  if save {
    let directory = plan_draft_directory(root)
    let lock = @flow_host.acquire_named_writer_lock_v1(
      directory,
      safe_id(draft_id, "draft_id"),
    )
    defer @flow_host.release_named_writer_lock_v1(lock)
    let path = directory + "/" + draft_id + ".json"
    if @fs.exists(path) {
      guard plan_load_draft(root, draft_id) == selected.draft else {
        fail(
          "draft identity already exists; reopen it or choose a new draft_id",
        )
      }
    } else {
      @flow_host.atomic_replace_named_json_v1(
        directory,
        draft_id + ".json",
        selected.draft.to_json().stringify(indent=2),
      )
    }
  }
  println(
    (
      {
        "contract_id": "moonflow.subgraph-plan-receipt.v1",
        "source_ref": source_ref,
        "target_item_ids": selected.target_item_ids,
        "prerequisite_item_ids": selected.prerequisite_item_ids,
        "omitted_item_ids": selected.omitted_item_ids,
        "item_count": selected.draft.edits.length(),
        "saved": save,
        "form": @moonflow.declared_plan_form_v1(selected.draft),
        "next_action": if save {
          "plan inspect / plan edit / plan prepare"
        } else {
          "plan from-subgraph"
        },
      } : Json).stringify(indent=2),
  )
}
