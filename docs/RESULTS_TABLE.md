# Compare recorded batch results

Export every work item across explicitly selected canonical runs:

```sh
moonflow results-table /path/to/workspace --csv study-b study-a > results.csv
moonflow results-table /path/to/workspace --json study-b study-a > results.json
```

Select one or more unique run IDs. Rows preserve that order and each replay's
item order. Accepted items are included alongside proposed, waiting, blocked,
failed and review-ready work; repeated work-item IDs remain qualified by run.
No workspace discovery, execution, retries, artifact copying or writes occur.

The command validates IDs and reads/replays every selected events.json before
printing the report. Missing or invalid input fails without a partial worksheet.
Check the process exit code: the inherited native error handler prints error
diagnostics on stdout, so a failed output file must not be imported as CSV.
A caller's shell may still create an empty redirected output file. Cached
projection.json is ignored. Each run has a separately observed event head:
this is not an atomic cross-run snapshot or a guarantee about later changes.

JSON contract moonflow.results-table.v1 has runs (observation identities,
including zero-item runs) and rows. Each row repeats run/book/revision/source
digest, last sequence/event ID/recorded timestamp and recorded run outcome.
It supplies declaration/work-item/product/operation, ordered input references
and dependencies, raw recorded item and attempt statuses, attempt count/ID,
input digest, result ID/output digest, retained artifact references,
review ID/artifact/reviewer, blocker and error kind. Missing recorded strings
are empty. Empty lists remain arrays. Timestamps are event timestamps, not
export time. No next actor is inferred.

These are replay's recorded current fields, not a history of every attempt.
Retained artifacts can include previous-attempt or review evidence; they are
not necessarily the latest attempt's outputs. References are not checked for
existence and digests are not recalculated. Unknown attempt status stays
separate from item status. Internal accepted work does not establish customer
approval, payment or permission to execute.

CSV uses the same row field names, quotes every data cell, doubles embedded
quotes and preserves Unicode and embedded newlines. Ordered list cells contain
JSON arrays; parse those cells as JSON instead of splitting on commas.
The header is present even when no work items are recorded. CSV cannot represent
zero-item run identities; use JSON when those observations matter.
Import all columns as text in spreadsheets, especially untrusted identifiers,
blockers or references beginning with =, +, - or @. CSV quoting does not prevent
spreadsheet formula evaluation; no string sanitization or normalization occurs.

Pure library APIs: results_table_v1(projections), results_table_csv_v1(table).
The table copies mutable arrays and values so later projection changes do not
rewrite the report. The projection API assumes caller-supplied projections;
the CLI alone establishes canonical file replay.
