///|
test "declared plan migration invalidates changed execution contracts and retains exact checkpoint" {
  let baseline = revised_graph()
  let parent = accepted_parent_projection()
  let before = parent.to_json().stringify()
  assert_eq(
    revise_run(
      parent, baseline, "baseline", "proposal.json", "2026-07-31T00:00:00Z",
    ).receipt.reused_count,
    1,
  )
  for
    pair in [
      ("operation", ("different-operation" : Json)),
      ("input_artifacts", (["evidence/changed.json"] : Json)),
      ("input_contracts", (["changed.input.v1"] : Json)),
      ("output_contracts", (["changed.output.v1"] : Json)),
      ("timeout_ms", (2000 : Json)),
      ("required_claim", ("digital-artifact" : Json)),
    ] {
    let graph = @json.parse(baseline.stringify())
    guard graph is Object(fields) else { fail("expected graph") }
    guard fields["items"] is Array(items) else { fail("expected items") }
    guard items[0] is Object(item) else { fail("expected item") }
    item[pair.0] = pair.1
    let result = revise_run(
      parent, graph, "changed", "proposal.json", "2026-07-31T00:00:00Z",
    )
    assert_eq(result.receipt.reused_count, 0)
  }
  assert_eq(parent.to_json().stringify(), before)
}

///|
test "declared plan migration invalidates removed dependency instead of reusing downstream checkpoint" {
  let parent = accepted_parent_projection()
  let graph = revised_graph()
  guard graph is Object(fields) else { fail("expected graph") }
  guard fields["items"] is Array(items) else { fail("expected items") }
  guard items[1] is Object(design) else { fail("expected design") }
  design["acceptance_criteria"] = parent.items[1].acceptance_criteria.to_json()
  design["required_claim"] = parent.items[1].required_claim.to_json()
  design["depends_on"] = ([] : Array[String]).to_json()
  let result = revise_run(
    parent, graph, "changed-deps", "proposal.json", "2026-07-31T00:00:00Z",
  )
  assert_eq(result.receipt.reused_count, 1)
  assert_eq(result.receipt.decisions[1].decision, "invalidated")
}

///|
test "captured opaque inputs retain checkpoints only when accepted input bytes still match" {
  let parent = accepted_parent_projection()
  let graph = revised_graph()
  let unchanged = revise_run(
    parent,
    graph,
    "captured-same",
    "proposal.json",
    "2026-07-31T00:00:00Z",
    input_digests={ "research-r2": parent.items[0].input_digest },
  )
  assert_eq(unchanged.receipt.reused_count, 1)
  let changed = revise_run(
    parent,
    graph,
    "captured-change",
    "proposal.json",
    "2026-07-31T00:00:00Z",
    input_digests={ "research-r2": "sha256:changed" },
  )
  assert_eq(changed.receipt.reused_count, 0)
  assert_eq(
    changed.receipt.decisions[0].reason,
    "captured input bytes do not match the accepted checkpoint",
  )
  // Caller-owned accepted history is never edited to force an invalidation.
  assert_eq(parent.items[0].status, Accepted)
}
