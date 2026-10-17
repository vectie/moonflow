///|
async fn plan_joined_workflow_command(
  workspace : String,
  source_ref : String,
  workflow_ref : String,
  join_ref : String,
  primary_ref : String,
  lookup_ref : String,
  draft_id : String,
  recorded_at : String,
  save : Bool,
) -> Unit {
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let source = plan_read_bytes(root, source_ref)
  let workflow = plan_read_bytes(root, workflow_ref)
  let join = plan_read_bytes(root, join_ref)
  let primary = plan_read_bytes(root, primary_ref)
  let lookup = plan_read_bytes(root, lookup_ref)
  guard source.length() +
    workflow.length() +
    join.length() +
    primary.length() +
    lookup.length() <=
    4194304 else {
    fail("joined workflow CLI inputs exceed 4 MiB total")
  }
  let result = @moonflow.declared_plan_from_joined_workflow_v1(
    @json.parse(@utf8.decode(source), max_nesting_depth=64),
    @json.parse(@utf8.decode(workflow), max_nesting_depth=64),
    @json.parse(@utf8.decode(join), max_nesting_depth=64),
    @utf8.decode(primary),
    @utf8.decode(lookup),
    draft_id,
    recorded_at,
  )
  plan_materialize_payload_artifacts(
    root,
    result.workflow.artifacts,
    result.workflow.draft,
    draft_id,
    save,
  )
  println(
    (
      {
        "contract_id": "moonflow.joined-workflow-plan-receipt.v1",
        "source_ref": source_ref,
        "workflow_ref": workflow_ref,
        "join_ref": join_ref,
        "primary_ref": primary_ref,
        "lookup_ref": lookup_ref,
        "primary_digest": result.primary_digest,
        "lookup_digest": result.lookup_digest,
        "join_digest": result.join_digest,
        "workflow_digest": result.workflow.workflow_digest,
        "joined_records": result.joined_records.to_json(),
        "unmatched_primary_rows": result.unmatched_primary_rows.to_json(),
        "unused_lookup_rows": result.unused_lookup_rows.to_json(),
        "record_ids": result.workflow.record_ids.to_json(),
        "artifacts": result.workflow.artifacts.to_json(),
        "saved": save,
        "form": @moonflow.declared_plan_form_v1(result.workflow.draft),
        "next_action": if save {
          "plan inspect / plan edit / plan prepare"
        } else {
          "plan from-joined-workflow"
        },
      } : Json).stringify(indent=2),
  )
}
