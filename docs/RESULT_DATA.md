# Compare the values inside recorded results

Use `result-data` to compare scores, measurements, names or other JSON values
across existing runs. A small mapping names the fields you want. MoonFlow replays
each selected canonical event history, finds the output list of each current
successful attempt, reads the selected local JSON file and exports a typed
worksheet. No adapter is invoked and no workspace file is written.

```sh
moonflow result-data WORKSPACE mapping.json --json study-a study-b > results.json
moonflow result-data WORKSPACE mapping.json --csv study-a study-b > results.csv
```

Unlike `results-table`, which reports recorded states and references, this
command reads the actual result files. Unlike `bundle-evidence`, it does not
copy artifacts or require a manually assembled source list. It is useful for
comparing a declared batch without opening every result JSON separately.

## Choose the output and columns

```json
{
  "contract_id": "moonflow.result-data-mapping.v1",
  "operation": "synthetic-metrics/evaluate@1",
  "output_artifact_index": 1,
  "columns": [
    { "name": "score", "pointer": "/metrics/score" },
    { "name": "label", "pointer": "/label" },
    { "name": "tags", "pointer": "/tags" }
  ]
}
```

The mapping is a workspace-relative JSON file. `output_artifact_index` is
zero-based in the exact matching `attempt-reconciled` event's `output_artifacts`
list. It is not an index in the projection's cumulative retained artifacts.
`operation` is an optional exact operation string; omitted or null includes
all items. An unmatched operation yields a header-only CSV or empty JSON rows
with the observed run identities retained.

Columns retain mapping order. Names must be unique, nonblank and at most 80
UTF-16 code units. JSON Pointer selectors use the existing records importer
syntax: empty selects the whole document, `/` selects an empty object key,
`~1` represents `/`, `~0` represents `~`, and array indices are canonical
zero-based decimal integers. There are no expressions, wildcards, type coercion,
implicit defaults or network requests. Configured pointers must resolve in
every selected successful result. A present JSON null remains a valid value.
An absent field is an error, not an invented null. Unknown mapping fields fail.

## Read the worksheet

JSON contract `moonflow.result-data-table.v1` includes the normalized mapping,
its canonical SHA-256, each separately observed run head, and rows in selected
run/item order. Each row contains:

- `source`: the existing results-table row, including revision, event head,
  operation, current attempt/result identity, recorded digest, review and blocker
- `data_status`: `extracted`, `no-successful-attempt` or `checkpoint-only`
- `result_event_id` and `artifact_ref`: the exact selected result event and file
- `observed_sha256` and `observed_size_bytes`: the file bytes read by this command
- `values`: the named JSON values, preserving numbers, strings, booleans, null,
  arrays and objects

Waiting, active, failed, unknown and never-attempted work remains visible with
`no-successful-attempt` and null value cells. A newly submitted attempt cannot
reuse an earlier successful attempt's values. Current successful results may
be review-pending, accepted or later blocked; consult `source.status` and review
fields rather than interpreting an extracted value as acceptance.

Checkpoint reuse is reported as `checkpoint-only` with null cells. The current
checkpoint contract carries cumulative parent evidence, which cannot identify
one exact attempt-output list. Open the original parent run to extract its
recorded result. Attached review notes, older attempt outputs and arbitrary
retained artifacts are never silently substituted.

CSV metadata columns describe run/item identity, recorded status and review,
result event, selected path and observed digest/size. Mapped columns are named
`value:<name>`. Every mapped cell is JSON-encoded, including strings and null;
parse each such cell as JSON after reading CSV to recover the original type.
All CSV cells are quoted and embedded quotes are doubled. Import all columns
as text in spreadsheet software, especially untrusted IDs or references that
start with formula characters. Quoting is not formula sanitization.

## Evidence and limits

The observed file SHA-256 is deliberately separate from the recorded
`source.output_digest`, which may be an adapter-owned aggregate. Reading and
hashing current bytes does not prove that they are unchanged since execution.
If a file changes, a later export reports its changed values and observed hash
without rewriting the recorded result digest. Use immutable artifact storage
or the owning adapter's receipt verification when execution-time integrity is
required. No schema/domain validity or customer approval is asserted.

Each selected path is read once and reused for identical references. Missing
files, a missing selected output index, malformed JSON, unsafe/outside-workspace
paths or unresolved columns refuse the entire report before printing it. Check
the exit code: the inherited native error handler prints diagnostics on stdout,
so a failed redirected file is not a worksheet. Cached `projection.json` files
are ignored. Runs are observed separately, not as an atomic multi-run snapshot.
There is no concurrent-adversary filesystem guarantee.

Bounds: 1..64 runs, 4096 selected work items, 1..64 columns, 1024 UTF-16 code
units per pointer, output indices 0..255, 1 MiB per selected JSON file, 64 MiB
of selected file bytes and JSON depth 64. Native mapping input is limited to
64 KiB and reads require regular files. Existing event-store loading limits are
unchanged. No provider, credentials, execution, retry, review mutation, backup
or restore operation is part of the command.

Pure embedding APIs are `result_data_sources_v1(projections, mapping)`,
`result_data_table_v1(projections, mapping, artifacts)` and
`result_data_csv_v1(table)`. Supply canonical consistent projections and exact
path-to-Bytes inputs; these library functions do not perform filesystem reads.
The native command establishes replay and workspace containment.

Try the [retained synthetic example](../examples/result-data/README.md).
