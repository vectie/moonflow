///|
async fn show_results_table(
  workspace : String,
  format : String,
  run_ids : Array[String],
) -> Unit {
  if format != "--csv" && format != "--json" {
    fail("Use --csv or --json")
  }
  if run_ids.is_empty() {
    fail("Select at least one run")
  }
  let seen : Array[String] = []
  for id in run_ids {
    ignore(safe_id(id, "run_id"))
    if seen.contains(id) {
      fail("Duplicate results run: " + id)
    }
    seen.push(id)
  }
  let runs : Array[@moonflow.RunProjection] = []
  for id in run_ids {
    runs.push(@moonflow.replay(id, load_events(workspace, id)))
  }
  let table = @moonflow.results_table_v1(runs)
  println(
    if format == "--csv" {
      @moonflow.results_table_csv_v1(table)
    } else {
      table.to_json().stringify(indent=2)
    },
  )
}
