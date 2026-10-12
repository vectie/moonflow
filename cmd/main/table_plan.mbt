///|
async fn plan_table_command(
  workspace : String,
  source_ref : String,
  template_ref : String,
  csv_ref : String,
  draft_id : String,
  recorded_at : String,
  save : Bool,
) -> Unit {
  validate_artifact_ref(workspace, source_ref)
  validate_artifact_ref(workspace, template_ref)
  validate_artifact_ref(workspace, csv_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let expanded = @moonflow.declared_plan_from_table_v1(
    read_json(root + "/" + source_ref),
    read_json(root + "/" + template_ref),
    @fs.read_file(root + "/" + csv_ref).text(),
    draft_id,
    recorded_at,
  )
  for edit in expanded.draft.edits {
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
      guard plan_load_draft(root, draft_id) == expanded.draft else {
        fail(
          "draft identity already exists; reopen it or choose a new draft_id",
        )
      }
    } else {
      @flow_host.atomic_replace_named_json_v1(
        directory,
        draft_id + ".json",
        expanded.draft.to_json().stringify(indent=2),
      )
    }
  }
  println(
    (
      {
        "contract_id": "moonflow.table-plan-receipt.v1",
        "source_ref": source_ref,
        "template_ref": template_ref,
        "template_digest": expanded.template_digest,
        "csv_ref": csv_ref,
        "csv_digest": expanded.csv_digest,
        "row_keys": expanded.row_keys,
        "items_per_row": expanded.items_per_row,
        "item_count": expanded.draft.edits.length(),
        "saved": save,
        "form": @moonflow.declared_plan_form_v1(expanded.draft),
        "next_action": if save {
          "plan inspect / plan edit / plan prepare"
        } else {
          "plan from-table"
        },
      } : Json).stringify(indent=2),
  )
}
