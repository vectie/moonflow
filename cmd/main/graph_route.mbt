///|
async fn show_graph_route(
  workspace : String,
  source_ref : String,
  from_id : String,
  to_id : String,
  format : String,
) -> Unit {
  guard format == "--json" || format == "--text" else {
    fail("Use --json or --text")
  }
  let (graph, input_file) = read_comparison_graph(workspace, source_ref)
  let report = @moonflow.declared_graph_route_v1(graph, from_id, to_id)
  if format == "--text" {
    println("Source file: " + input_file.stringify())
    println(@moonflow.declared_graph_route_text_v1(report))
  } else {
    guard report.to_json() is Object(fields) else {
      fail("Invalid route report")
    }
    fields["input_file"] = input_file
    println(fields.to_json().stringify(indent=2))
  }
}
