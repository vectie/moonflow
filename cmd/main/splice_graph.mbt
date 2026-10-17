///|
async fn splice_graph_command(
  workspace : String,
  manifest_ref : String,
  format : String,
) -> Unit {
  guard format == "--json" || format == "--graph" else {
    fail("Use --json or --graph")
  }
  let root = @fs.realpath(@moonflow.normalize_workspace_path(workspace))
  validate_artifact_ref(root, manifest_ref)
  let bytes = @fs.read_file(root + "/" + manifest_ref)
  guard bytes.binary().length() <= 2097152 else {
    fail("splice manifest exceeds 2 MiB")
  }
  let request = @json.parse(bytes.text())
  let fields = plan_fields(request, "splice manifest")
  guard fields.get("contract_id") == Some("moonflow.graph-splice-manifest.v1") else {
    fail("unsupported graph splice manifest")
  }
  let mut total = bytes.binary().length()
  for
    (reference, field) in [
      ("source_graph_ref", "graph"),
      ("module_graph_ref", "module"),
    ] {
    let source_ref = plan_string(request, reference)
    validate_artifact_ref(root, source_ref)
    let graph_bytes = @fs.read_file(root + "/" + source_ref)
    total += graph_bytes.binary().length()
    guard total <= 2097152 else { fail("splice inputs exceed 2 MiB total") }
    fields[field] = @json.parse(graph_bytes.text())
    fields.remove(reference)
  }
  fields["contract_id"] = "moonflow.graph-splice-input.v1"
  let result = @moonflow.splice_declared_graph_v1(request)
  println(
    (if format == "--graph" { plan_value(result, "graph") } else { result }).stringify(
      indent=2,
    ),
  )
}
