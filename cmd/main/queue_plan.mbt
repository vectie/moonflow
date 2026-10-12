///|
async fn plan_queue_command(
  workspace : String,
  source_ref : String,
  mapping_ref : String,
  queue_ref : String,
  draft_id : String,
  recorded_at : String,
  save : Bool,
) -> Unit {
  validate_artifact_ref(workspace, source_ref)
  validate_artifact_ref(workspace, mapping_ref)
  validate_artifact_ref(workspace, queue_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let source_data = @fs.read_file(root + "/" + source_ref)
  let mapping_data = @fs.read_file(root + "/" + mapping_ref)
  let queue_data = @fs.read_file(root + "/" + queue_ref)
  guard source_data.binary().length() +
    mapping_data.binary().length() +
    queue_data.binary().length() <=
    2097152 else {
    fail("JSONL queue CLI input exceeds 2,097,152 aggregate bytes")
  }
  let imported = @moonflow.declared_plan_from_queue_v1(
    @json.parse(source_data.text(), max_nesting_depth=64),
    @json.parse(mapping_data.text(), max_nesting_depth=64),
    queue_data.text(),
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
        "contract_id": "moonflow.queue-plan-receipt.v1",
        "source_ref": source_ref,
        "mapping_ref": mapping_ref,
        "mapping_digest": imported.mapping_digest,
        "queue_ref": queue_ref,
        "queue_digest": imported.queue_digest,
        "entries": imported.entries,
        "record_count": imported.entries.length(),
        "saved": save,
        "form": @moonflow.declared_plan_form_v1(imported.draft),
        "next_action": if save {
          "plan inspect / plan edit / plan prepare"
        } else {
          "plan from-queue"
        },
      } : Json).stringify(indent=2),
  )
}
