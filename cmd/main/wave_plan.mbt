///|
async fn plan_waves_command(
  workspace : String,
  source_ref : String,
  draft_id : String,
  recorded_at : String,
  max_parallel : String,
  save : Bool,
) -> Unit {
  validate_artifact_ref(workspace, source_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  guard !max_parallel.is_empty() && max_parallel.length() <= 3 else {
    fail("max_parallel must be a decimal integer in 1..256")
  }
  let mut width = 0
  for c in max_parallel {
    guard c >= '0' && c <= '9' else {
      fail("max_parallel must be a decimal integer in 1..256")
    }
    width = width * 10 + c.to_int() - '0'.to_int()
  }
  let selected = @moonflow.declared_plan_from_waves_v1(
    read_json(root + "/" + source_ref),
    width,
    draft_id,
    recorded_at,
  )
  // All retained inputs must remain inside the workspace before saving.
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
        "contract_id": "moonflow.wave-plan-receipt.v1",
        "source_ref": source_ref,
        "max_parallel": selected.max_parallel,
        "waves": selected.waves.to_json(),
        "added_edges": selected.added_edges.to_json(),
        "item_count": selected.draft.edits.length(),
        "saved": save,
        "form": @moonflow.declared_plan_form_v1(selected.draft),
        "next_action": if save {
          "plan inspect / plan edit / plan prepare"
        } else {
          "plan from-waves"
        },
      } : Json).stringify(indent=2),
  )
}
