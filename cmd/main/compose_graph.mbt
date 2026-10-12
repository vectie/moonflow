///|
async fn compose_graph_command(
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
    fail("composition manifest exceeds 2 MiB")
  }
  let request = @json.parse(bytes.text())
  let fields = plan_fields(request, "composition manifest")
  guard fields.get("contract_id") ==
    Some("moonflow.graph-composition-manifest.v1") else {
    fail("unsupported graph composition manifest")
  }
  guard fields.get("sources") is Some(Array(sources)) &&
    sources.length() >= 2 &&
    sources.length() <= 16 else {
    fail("composition requires 2..16 sources")
  }
  let loaded : Array[Json] = []
  let mut total = bytes.binary().length()
  for source in sources {
    let source_ref = plan_string(source, "graph_ref")
    validate_artifact_ref(root, source_ref)
    let graph_bytes = @fs.read_file(root + "/" + source_ref)
    total += graph_bytes.binary().length()
    guard total <= 2097152 else {
      fail("composition inputs exceed 2 MiB total")
    }
    loaded.push({
      "alias": plan_value(source, "alias"),
      "graph": @json.parse(graph_bytes.text()),
    })
  }
  fields["sources"] = loaded.to_json()
  fields["contract_id"] = "moonflow.graph-composition-input.v1"
  let result = @moonflow.compose_declared_graph_v1(request)
  println(
    (if format == "--graph" { plan_value(result, "graph") } else { result }).stringify(
      indent=2,
    ),
  )
}
