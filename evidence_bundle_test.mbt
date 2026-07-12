///|
test "evidence bundle requires governed workspace-relative sources" {
  let spec = decode_evidence_bundle_spec({
    "contract_id": "moonflow.evidence-bundle-request.v1",
    "bundle_id": "bundle-robot-research",
    "sources": [
      {
        "artifact_ref": ".moonsuite/products/moonwiki/research/report.json",
        "producer_product_id": "moonwiki",
        "contract_id": "moonsuite.evidence-envelope.v1",
        "claim_class": "research-evidence",
        "result_id": "result-research-1",
      },
    ],
  })
  let digest = "sha256:" + "a".repeat(64)
  let manifest = evidence_bundle_manifest(
    spec,
    [
      {
        artifact_ref: spec.sources[0].artifact_ref,
        object_ref: ".moonsuite/products/moonflow/evidence/objects/" +
        "a".repeat(64),
        producer_product_id: "moonwiki",
        contract_id: "moonsuite.evidence-envelope.v1",
        claim_class: "research-evidence",
        result_id: "result-research-1",
        sha256: digest,
        size_bytes: 42,
      },
    ],
    digest,
    "2026-07-12T11:00:00+08:00",
  )
  assert_true(manifest.quality_issues().is_empty())
  assert_eq(manifest.entries[0].producer_product_id, "moonwiki")
}

///|
test "evidence bundle rejects source traversal and unknown claims" {
  for
    source in [
      {
        "artifact_ref": "../outside.json",
        "producer_product_id": "moonwiki",
        "contract_id": "moonsuite.evidence-envelope.v1",
        "claim_class": "research-evidence",
        "result_id": "result-1",
      },
      {
        "artifact_ref": "evidence/report.json",
        "producer_product_id": "moonwiki",
        "contract_id": "moonsuite.evidence-envelope.v1",
        "claim_class": "physically-perfect",
        "result_id": "result-2",
      },
    ] {
    try
      decode_evidence_bundle_spec({
        "contract_id": "moonflow.evidence-bundle-request.v1",
        "bundle_id": "invalid",
        "sources": [source],
      })
    catch {
      _ => ()
    } noraise {
      _ => fail("expected invalid evidence source")
    }
  }
}
