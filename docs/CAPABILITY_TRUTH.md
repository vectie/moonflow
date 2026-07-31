# Executable capability truth

MoonFlow does not treat a product name, canvas node or invented verb as an
executable capability. Cross-product execution is compiled from three
independent inputs:

1. the product-owned `pack.json`, which owns tool and schema declarations;
2. a host-owned `moonflow.adapter-declaration.v1`, which binds those tools to a
   concrete `moonflow.adapter.v2` implementation and claim ceiling;
3. an expiring `moonflow.adapter-health.v1` attestation, which records which
   exact versioned operations were observed healthy.

The portable source envelope is `moonflow.capability-source-bundle.v1`.
`compile_capability_catalog_v1` produces
`moonflow.capability-catalog.v1`. The catalog lists every installed pack
identity, only the operations that passed conformance, and actionable issues
for every rejected declaration.

The health attestation includes an evidence path and SHA-256 identity. The pure
compiler validates their shape and binding; the host remains responsible for
verifying those bytes before constructing the source bundle.

## Canonical identities

Pack-local names become cross-product identities only through their manifest:

```text
operation: <product-id>/<tool-id>@<pack-version>
schema:    <product-id>/<schema-id>@<schema-version>
```

For example:

```text
moonmold/spatial.operation.execute@0.2.0
moonmold/spatial-operation-request@1.0.0
moonmold/spatial-operation-receipt@1.0.0
```

Changing a pack or schema version changes its identity. MoonFlow never silently
binds an old canvas node to a newer implementation.

## Conformance dimensions

An operation is published into the executable catalog only when:

- the pack, product, tool and schema identifiers are valid and unambiguous;
- the tool owner matches the manifest product;
- input and output schema IDs resolve to versioned manifest schemas;
- the manifest authority maps to a canonical Moon Suite authority class;
- exactly one version-matched adapter declaration owns the tool;
- its protocol is `moonflow.adapter.v2`;
- its claim ceiling is supported;
- it supports reconciliation;
- exactly one matching health attestation is healthy and unexpired;
- the health observation covers the exact versioned operation;
- the health protocol, evidence reference and evidence digest conform.

The catalog may retain conformant operations while reporting problems in
unrelated installed products. Ambiguous or unhealthy operations are never
published.

## Graph compilation

`compile_work_graph_capabilities_v1` checks every Work item against the
catalog. It produces one immutable binding per accepted item and actionable
issues for:

- products absent from installed manifests;
- unversioned, invented or unhealthy operations;
- product ownership drift;
- authority drift;
- unversioned or mismatched input/output schemas;
- unsupported claims or claims above the adapter ceiling.

Suggestions come only from manifest-derived operations for the requested
product. This makes legacy canvas entries such as
`model.create-3d-assets` fail with the real installed MoonMold operation as a
suggestion. Phantom products such as MoonStat fail as not installed.

`conformant_events_from_work_graph_v1` is the fail-closed import seam. It
creates no events unless the whole graph compiles.

## CLI workflow

```sh
moon run cmd/main -- compile-capability-catalog \
  fixtures/capability-source-bundle.v1.json > /tmp/catalog.json

moon run cmd/main -- validate-work-graph-capabilities \
  fixtures/capability-work-graph.valid.v1.json \
  /tmp/catalog.json \
  2026-07-31T00:00:00Z

moon run cmd/main -- import-conformant-graph \
  /path/to/workspace \
  fixtures/capability-work-graph.valid.v1.json \
  /tmp/catalog.json \
  2026-07-31T00:00:00Z
```

The validation command emits a reviewable report, including when
`accepted=false`. The import command fails closed on the same report.

Compiled catalogs can also be passed anywhere that already consumes MoonFlow
adapter capabilities, including `select-adapter`, `prepare-next` and
`run-unattended`. The director projects each conformant catalog operation into
its existing generic adapter-selection contract; no second runtime is created.
`prepare-next` and `run-unattended` evaluate the operation's health window
again at their supplied `recorded_at`; expired operations disappear from
selection. `run-unattended` also compiles the graph before creating durable run
state when its capability artifact is a catalog.

## Pack and host adoption contract

Every participating pack must:

- publish unique tool IDs and versioned schemas in `pack.json`;
- use its own `product_id` as each tool's `owner_product`;
- declare the least authority required by each tool;
- avoid putting provider health or deployment claims in the static manifest.

Every host installation must:

- publish the exact installed pack version in its adapter declaration;
- declare claim ceilings per operation;
- support reconciliation for production operations;
- generate short-lived health evidence for the exact operation references;
- verify health evidence bytes before compiling the source bundle;
- compile and retain the catalog and graph report used for each run.

The complete portable examples are:

- [`capability-source-bundle.v1.json`](../fixtures/capability-source-bundle.v1.json)
- [`capability-work-graph.valid.v1.json`](../fixtures/capability-work-graph.valid.v1.json)
- [`capability-work-graph.rejected.v1.json`](../fixtures/capability-work-graph.rejected.v1.json)
