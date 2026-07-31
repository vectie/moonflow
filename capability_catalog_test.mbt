///|
fn conformance_source_bundle(
  status? : String = "healthy",
  valid_until? : String = "2026-08-01T00:00:00Z",
) -> Json {
  {
    "contract_id": "moonflow.capability-source-bundle.v1",
    "catalog_id": "installed-packs-2026-07-31",
    "compiled_at": "2026-07-31T00:00:00Z",
    "pack_manifests": [
      {
        "id": "moonmold",
        "product_id": "moonmold",
        "version": "0.2.0",
        "schemas": [
          {
            "id": "spatial-operation-request",
            "version": "1.0.0",
            "path": "schemas/spatial-operation-request.schema.json",
          },
          {
            "id": "spatial-operation-receipt",
            "version": "1.0.0",
            "path": "schemas/spatial-operation-receipt.schema.json",
          },
        ],
        "tools": [
          {
            "id": "spatial.operation.execute",
            "owner_product": "moonmold",
            "input_schema_id": "spatial-operation-request",
            "output_schema_id": "spatial-operation-receipt",
            "authority": "WorkspaceMutation",
            "idempotent": true,
            "evidence_outputs": ["records/operations", "artifacts/models"],
            "review_required": true,
          },
        ],
      },
    ],
    "adapter_declarations": [
      {
        "contract_id": "moonflow.adapter-declaration.v1",
        "adapter_id": "moonmold-pack-local-v1",
        "product_id": "moonmold",
        "pack_id": "moonmold",
        "pack_version": "0.2.0",
        "protocol": "moonflow.adapter.v2",
        "operations": [
          {
            "operation_id": "spatial.operation.execute",
            "claim_ceiling": "digital-artifact",
            "supports_cancel": true,
            "supports_reconcile": true,
          },
        ],
      },
    ],
    "health_attestations": [
      {
        "contract_id": "moonflow.adapter-health.v1",
        "adapter_id": "moonmold-pack-local-v1",
        "product_id": "moonmold",
        "pack_id": "moonmold",
        "pack_version": "0.2.0",
        "protocol": "moonflow.adapter.v2",
        "status": status,
        "checked_at": "2026-07-30T23:59:00Z",
        "valid_until": valid_until,
        "operation_refs": ["moonmold/spatial.operation.execute@0.2.0"],
        "evidence_ref": "health/moonmold-pack-local-v1.json",
        "evidence_digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      },
    ],
  }
}

///|
fn conformant_work_graph(
  product_id? : String = "moonmold",
  operation? : String = "moonmold/spatial.operation.execute@0.2.0",
  authority? : String = "workspace-mutation",
  input_contract? : String = "moonmold/spatial-operation-request@1.0.0",
) -> Json {
  {
    "contract_id": "moonsuite.work-model.v1",
    "graph_id": "capability-graph-r1",
    "book_id": "robot-design",
    "declaration_revision": "r1",
    "source_digest": "sha256:robot-design-r1",
    "items": [
      {
        "work_item_id": "make-model",
        "declaration_id": "make-model",
        "product_id": product_id,
        "requested_authority": authority,
        "acceptance_criteria": ["reviewed model exists"],
        "operation": operation,
        "input_contracts": [input_contract],
        "output_contracts": ["moonmold/spatial-operation-receipt@1.0.0"],
        "required_claim": "digital-artifact",
        "input_artifacts": ["requests/model.json"],
        "timeout_ms": 60000,
        "depends_on": [],
      },
    ],
    "recorded_at": "2026-07-31T00:00:00Z",
  }
}

///|
test "pack manifest and observed adapter compile into executable capability truth" {
  let catalog = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(),
  )
  assert_true(catalog.conformant)
  assert_eq(catalog.products.length(), 1)
  assert_eq(catalog.operations.length(), 1)
  let operation = catalog.operations[0]
  assert_eq(operation.operation_ref, "moonmold/spatial.operation.execute@0.2.0")
  assert_eq(
    operation.input_schema_ref,
    "moonmold/spatial-operation-request@1.0.0",
  )
  assert_eq(operation.authority, "workspace-mutation")
  assert_true(operation.review_required)
  let report = @moonflow.compile_work_graph_capabilities_v1(
    conformant_work_graph(),
    catalog,
  )
  assert_true(report.accepted)
  assert_eq(report.bindings.length(), 1)
  assert_eq(report.bindings[0].adapter_id, "moonmold-pack-local-v1")
  assert_eq(
    @moonflow.conformant_events_from_work_graph_v1(
      conformant_work_graph(),
      catalog,
    ).length(),
    3,
  )
  assert_eq(
    @moonflow.capability_guarded_events_from_work_graph_v1(
      conformant_work_graph(),
      catalog.to_json(),
      "2026-07-31T00:00:00Z",
    ).length(),
    3,
  )
}

///|
test "existing director consumes a compiled catalog without a parallel runtime" {
  let catalog = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(),
  )
  let capabilities = @moonflow.decode_adapter_capabilities(catalog.to_json())
  assert_eq(capabilities.length(), 1)
  let decision = @moonflow.select_adapter(capabilities, {
    requirement_id: "make-model-a1",
    product_id: "moonmold",
    operation: "moonmold/spatial.operation.execute@0.2.0",
    requested_authority: "workspace-mutation",
    input_contracts: ["moonmold/spatial-operation-request@1.0.0"],
    output_contracts: ["moonmold/spatial-operation-receipt@1.0.0"],
    required_claim: "digital-artifact",
  })
  assert_true(decision.accepted)
  assert_eq(decision.selected_adapter_id, "moonmold-pack-local-v1")
  let expired_capabilities = @moonflow.decode_adapter_capabilities_at_v1(
    catalog.to_json(),
    "2026-08-01T00:00:01Z",
  )
  assert_true(expired_capabilities.is_empty())
  let expired_report = @moonflow.compile_work_graph_capabilities_at_v1(
    conformant_work_graph(),
    catalog,
    "2026-08-01T00:00:01Z",
  )
  assert_false(expired_report.accepted)
  assert_true(
    expired_report.issues.any(issue => {
      issue.code == "operation-health-window-invalid"
    }),
  )
}

///|
test "invented and unversioned canvas operation fails with manifest suggestions" {
  let catalog = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(),
  )
  let report = @moonflow.compile_work_graph_capabilities_v1(
    conformant_work_graph(operation="model.create-3d-assets"),
    catalog,
  )
  assert_false(report.accepted)
  assert_eq(report.issues[0].code, "operation-not-versioned")
  assert_true(
    report.issues[0].suggestions.contains(
      "moonmold/spatial.operation.execute@0.2.0",
    ),
  )
}

///|
test "phantom canvas product fails instead of becoming an adapter" {
  let catalog = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(),
  )
  let report = @moonflow.compile_work_graph_capabilities_v1(
    conformant_work_graph(
      product_id="moonstat",
      operation="moonstat/evaluation.score@0.1.0",
    ),
    catalog,
  )
  assert_false(report.accepted)
  assert_eq(report.issues[0].code, "product-not-installed")
  assert_true(report.issues[0].detail.contains("moonstat"))
}

///|
test "schema and authority drift are reported independently" {
  let catalog = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(),
  )
  let report = @moonflow.compile_work_graph_capabilities_v1(
    conformant_work_graph(
      authority="sandbox-execution",
      input_contract="spatial-operation-request",
    ),
    catalog,
  )
  assert_false(report.accepted)
  assert_true(report.issues.any(issue => issue.code == "authority-mismatch"))
  assert_true(report.issues.any(issue => issue.code == "input-schema-mismatch"))
}

///|
test "expired or unhealthy evidence cannot publish an executable operation" {
  let expired = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(valid_until="2026-07-30T23:59:59Z"),
  )
  assert_false(expired.conformant)
  assert_true(expired.operations.is_empty())
  assert_true(expired.issues.any(issue => issue.code == "health-expired"))
  let unhealthy = @moonflow.compile_capability_catalog_v1(
    conformance_source_bundle(status="degraded"),
  )
  assert_false(unhealthy.conformant)
  assert_true(unhealthy.operations.is_empty())
  assert_true(unhealthy.issues.any(issue => issue.code == "adapter-unhealthy"))
}
