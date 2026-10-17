# Repeat selected steps with shared setup and a final join

A workflow operator can now repeat an explicit subset of an existing graph per
CSV row while retaining every other step once. A shared setup can feed each
variant's diamond-shaped work, and a shared final step can wait for every
variant. No operations, dependencies, payloads or approvals are inferred.

The Python standard-library authoring client writes the existing
`moonflow.declared-plan-form-input.v2` contract. Native `plan from-form`,
`plan inspect` and `plan prepare` remain the authoritative engine boundary.
The client does actual graph expansion; it does not replace the engine's
capability validation, filesystem checks, declaration lineage or preparation.

## Declare what repeats

A `moonflow.shared-table-template.v1` document contains:

```json
{
  "contract_id": "moonflow.shared-table-template.v1",
  "repeated_work_item_ids": ["left", "right", "rowjoin"],
  "item_bindings": [
    {"template_work_item_id": "left", "input_artifacts": ["requests/{{key}}-left.json"], "acceptance_criteria": ["Review {{label}} left result"]},
    {"template_work_item_id": "right", "input_artifacts": ["requests/{{key}}-right.json"]},
    {"template_work_item_id": "rowjoin", "input_artifacts": ["requests/{{key}}-rowjoin.json"]}
  ]
}
```

Supply exactly one binding for each selected step. Bindings for shared steps,
unknown selections, duplicate selections and unrecognized template fields are
errors. An omitted `acceptance_criteria` retains the source criteria exactly.
Inputs for repeated steps are explicit. Shared inputs and criteria remain
unchanged. Substitution happens only in the two binding text arrays; inserted
CSV values are never interpreted again as placeholders.

CSV uses a unique `key` column and ASCII letters/digits/underscore in column
names. Keys use safe IDs of at most 128 ASCII characters and cannot contain
`..` or `--`. `key--source-id` must also fit 128 characters and cannot collide
with any original ID, including one selected for replacement. UTF-8 BOM,
commas, doubled quotes and LF/CRLF are supported, including quoted multiline
cells. CRLF becomes LF and cell edges are trimmed. Malformed quoting, duplicate
headers/keys, wrong cell counts and blank values used by a binding are refused.

## Exact edge rules

For each original dependency from a step to a prerequisite:

- Repeated step → repeated prerequisite: the same row only
- Repeated step → shared prerequisite: the original prerequisite ID
- Shared step → repeated prerequisite: every CSV row's corresponding step
- Shared step → shared prerequisite: the original prerequisite ID

All unselected steps remain, including unrelated shared branches. The source
need not be topologically ordered. Output follows original step order, expanding
each selected step in CSV row order; selection-list order has no effect. Reordering
rows preserves work item IDs and native declaration lineage, but can change the
ordered graph and prepared child identity.

For rows `compact` and `wide`, the supplied sample keeps `setup`, `audit` and
`final` once. Each row's `rowjoin` waits on its own `left` and `right`.
`final` waits on `compact--rowjoin`, `wide--rowjoin` and the shared `setup`.

## Review, save and use the native engine

Set `SOURCE` to the checkout and `WORKSPACE` to an isolated directory containing
the [shared study example](../examples/shared-table-plan/README.md). Use a trusted,
compatible native MoonFlow executable as `MOONFLOW_CLI`.

```sh
python3 -B "$SOURCE/scripts/shared_table_plan.py" preview "$WORKSPACE/source-graph.json" "$WORKSPACE/template.json" "$WORKSPACE/variants.csv"
python3 -B "$SOURCE/scripts/shared_table_plan.py" save "$WORKSPACE/source-graph.json" "$WORKSPACE/template.json" "$WORKSPACE/variants.csv" "$WORKSPACE/shared-form.json"
"$MOONFLOW_CLI" plan from-form "$WORKSPACE" shared-form.json shared-study 2026-07-31T00:00:00Z
"$MOONFLOW_CLI" plan inspect "$WORKSPACE" shared-study
"$MOONFLOW_CLI" plan prepare "$WORKSPACE" shared-study catalog.json 2026-07-31T00:00:00Z
```

`preview` prints the complete native form. `save` creates a new form file and
refuses any existing target; it reports that native validation is still pending.
Neither command reads domain payload files or dispatches anything. Native
`from-form` validates the graph and saves a normal editable draft. It does not
prove input files exist or validate current catalog health. `prepare` checks
current capability identity/health and input existence/containment before writing
a child graph/proposal. It still dispatches nothing. Use actual current catalog
health and timestamps for real work; the fixed date above is the synthetic
example's deliberately fixed health window.

The form retains an unchanged copy of the source graph and an `added_templates`
entry for each repeated copy. Native MoonFlow assigns fresh declaration IDs to
copies and retains original declaration IDs for shared steps. Identical native
imports are idempotent; changed content under an existing draft ID is refused.
Existing `plan export` and `plan edit` remain available. The source graph and
input files are never rewritten by the authoring client.

## Limits and evidence

- 1–256 source steps, 1–256 CSV rows and at least one explicitly repeated step
- At most 256 total output steps, counting shared steps once
- At most 4 MiB per input file and emitted form; at most 1,048,576 CSV UTF-16 units
- Every bound is checked before opening a save target; existing output files are never replaced
- Source dependencies must be acyclic and known; native validation remains authoritative for full product contracts
- No Cartesian expansion, generated domain requests, inferred sharing, future-output binding, adapter dispatch, host canvas or scheduler

`test_shared_table_plan.py` covers the pure authoring contract. The separate
`verify_shared_table_plan.py` executes the retained native binary through
from-form/inspect/export/prepare and catalog compilation, including the 256-item
edge, exact graph/declaration checks, idempotency, row reorder, source preservation,
and native refusals for cycles, unknown operations, missing files and expired health.
`verify_shared_table_native.py` binds reuse to the executable SHA-256 and all 395
retained repository native source/config/interface/C files. This is reuse evidence,
not a fresh reproducible build or independent binary attestation.

PRD mapping: MOONFLOW-B02 / MF-W01 is exercised at the graph import/preparation
boundary with exact declarations and zero attempts. MOONFLOW-B09 / MF-W04 is
supported by immutable source retention, fresh copy lineage and distinct prepared
child identity after input edits. These tests do not qualify checkpoint reuse,
accepted parent event history, restart recovery or a live external adapter journey.
