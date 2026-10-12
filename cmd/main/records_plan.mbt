///|
async fn plan_records_command(
  workspace : String,
  source_ref : String,
  mapping_ref : String,
  records_ref : String,
  draft_id : String,
  recorded_at : String,
  save : Bool,
) -> Unit {
  validate_artifact_ref(workspace, source_ref)
  validate_artifact_ref(workspace, mapping_ref)
  validate_artifact_ref(workspace, records_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let imported = @moonflow.declared_plan_from_records_v1(
    read_json(root + "/" + source_ref),
    read_json(root + "/" + mapping_ref),
    @fs.read_file(root + "/" + records_ref).text(),
    draft_id,
    recorded_at,
  )
  for edit in imported.draft.edits {
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
    if @fs.exists(directory + "/" + draft_id + ".json") {
      guard plan_load_draft(root, draft_id) == imported.draft else {
        fail(
          "draft identity already exists; reopen it or choose a new draft_id",
        )
      }
    } else {
      @flow_host.atomic_replace_named_json_v1(
        directory,
        draft_id + ".json",
        imported.draft.to_json().stringify(indent=2),
      )
    }
  }
  println(
    (
      {
        "contract_id": "moonflow.records-plan-receipt.v1",
        "source_ref": source_ref,
        "mapping_ref": mapping_ref,
        "mapping_digest": imported.mapping_digest,
        "records_ref": records_ref,
        "records_digest": imported.records_digest,
        "records_pointer": imported.records_pointer,
        "template_work_item_id": imported.template_work_item_id,
        "record_ids": imported.record_ids,
        "record_count": imported.record_ids.length(),
        "saved": save,
        "form": @moonflow.declared_plan_form_v1(imported.draft),
        "next_action": if save {
          "plan inspect / plan edit / plan prepare"
        } else {
          "plan from-records"
        },
      } : Json).stringify(indent=2),
  )
}
