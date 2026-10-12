///|
async fn read_comparison_events(
  workspace : String,
  run_id : String,
) -> Array[@moonflow.RuntimeEvent] {
  let event_ref = ".moonsuite/products/moonflow/runs/" + run_id + "/events.json"
  validate_artifact_ref(workspace, event_ref)
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  let data = @fs.read_file(root + "/" + event_ref)
  guard data.binary().length() <= 8388608 else {
    fail("Run comparison event store exceeds 8,388,608 bytes")
  }
  @moonflow.decode_event_array(@json.parse(data.text(), max_nesting_depth=64))
}

///|
async fn show_run_comparison(
  workspace : String,
  before_run_id : String,
  after_run_id : String,
  format : String,
) -> Unit {
  guard format == "--json" || format == "--text" else {
    fail("Use --json or --text")
  }
  ignore(safe_id(before_run_id, "before_run_id"))
  ignore(safe_id(after_run_id, "after_run_id"))
  guard before_run_id != after_run_id else {
    fail("Select two distinct run IDs")
  }
  let before = read_comparison_events(workspace, before_run_id)
  let after = read_comparison_events(workspace, after_run_id)
  let report = @moonflow.compare_run_events_v1(
    before_run_id, before, after_run_id, after,
  )
  println(
    if format == "--text" {
      @moonflow.run_comparison_text_v1(report)
    } else {
      report.to_json().stringify(indent=2)
    },
  )
}
