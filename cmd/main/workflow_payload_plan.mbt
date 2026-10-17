///|
async fn plan_workflow_payloads_command(
  workspace : String,
  source_ref : String,
  workflow_ref : String,
  records_ref : String,
  draft_id : String,
  recorded_at : String,
  save : Bool,
) -> Unit {
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let source_bytes = plan_read_bytes(root, source_ref)
  let workflow_bytes = plan_read_bytes(root, workflow_ref)
  let records_bytes = plan_read_bytes(root, records_ref)
  guard source_bytes.length() + workflow_bytes.length() + records_bytes.length() <=
    4194304 else {
    fail("workflow payload CLI inputs exceed 4 MiB total")
  }
  let imported = @moonflow.declared_plan_from_workflow_payloads_v1(
    @json.parse(@utf8.decode(source_bytes), max_nesting_depth=64),
    @json.parse(@utf8.decode(workflow_bytes), max_nesting_depth=64),
    @utf8.decode(records_bytes),
    draft_id,
    recorded_at,
  )
  plan_materialize_payload_artifacts(
    root,
    imported.artifacts,
    imported.draft,
    draft_id,
    save,
  )
  println(
    (
      {
        "contract_id": "moonflow.workflow-payload-plan-receipt.v1",
        "source_ref": source_ref,
        "workflow_ref": workflow_ref,
        "records_ref": records_ref,
        "workflow_digest": imported.workflow_digest,
        "records_digest": imported.records_digest,
        "record_ids": imported.record_ids.to_json(),
        "items_per_record": imported.items_per_record.to_json(),
        "artifacts": imported.artifacts.to_json(),
        "saved": save,
        "form": @moonflow.declared_plan_form_v1(imported.draft),
        "next_action": if save {
          "plan inspect / plan edit / plan prepare"
        } else {
          "plan from-workflow-payloads"
        },
      } : Json).stringify(indent=2),
  )
}
