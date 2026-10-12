///|
async fn show_run_history(
  workspace : String,
  run_id : String,
  format : String,
  item_id : String?,
) -> Unit {
  guard format == "--json" || format == "--text" else {
    fail("Use --json or --text")
  }
  ignore(safe_id(run_id, "run_id"))
  let event_ref = ".moonsuite/products/moonflow/runs/" + run_id + "/events.json"
  validate_artifact_ref(workspace, event_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let data = @fs.read_file(root + "/" + event_ref)
  guard data.binary().length() <= 8388608 else {
    fail("Run history event store exceeds 8,388,608 bytes")
  }
  let events = @moonflow.decode_event_array(
    @json.parse(data.text(), max_nesting_depth=64),
  )
  let history = match item_id {
    Some(id) => @moonflow.run_history_v1(run_id, events, work_item_id=id)
    None => @moonflow.run_history_v1(run_id, events)
  }
  println(
    if format == "--text" {
      @moonflow.run_history_text_v1(history)
    } else {
      history.to_json().stringify(indent=2)
    },
  )
}
