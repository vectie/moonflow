# Export a pending result for offline review

An operator can give a reviewer one local ZIP containing the exact current result
files, its original acceptance criteria and a readable index. The reviewer can
inspect those bytes without access to the original workspace. Creating the ZIP
does not send it, accept the result or authorize another attempt.

This Python 3.9+ operator client uses the existing trusted MoonFlow executable.
From this repository:

```sh
python3 -B scripts/review_packet.py /absolute/workspace \
  --cli /absolute/path/to/moonflow \
  --run prototype-r1 --item inspect-prototype \
  --output /absolute/reviews/prototype-r1.zip
```

Select one exact imported run and item. The result must have item status `review`,
current attempt status `succeeded`, complete criteria and a matching successful
`attempt-reconciled` event. Accepted, failed, unknown, executing and reused
checkpoint results are outside this pending-review workflow. The destination's
parent must already exist. The ZIP is created exclusively with mode `0600`;
existing files are never overwritten, and the canonical `.moonsuite` store is
not an allowed destination. Inspect the packet before sharing it through a
separately authorized channel: it contains selected-item history, criteria,
input references and original output bytes, which can be private.

Optional `--recorded-at 2026-10-11T16:00:00Z` controls the packet's recorded time.
Without it, the client uses current UTC. This is packet time, not event time or
an authority/freshness deadline. `--timeout SECONDS` bounds each native read
(default 30, range 0.1–300). Run IDs use 1–128 ASCII letters, digits, underscores,
hyphens and dots, excluding `.` and `..` anywhere. Item IDs are nonblank and at
most 256 characters.

## Review the exported files

Extract the ZIP locally using a trusted archive tool, then open `index.html`.
The index shows run/book/revision, event head, current attempt/result, original
criteria in order and links to every current result output. Output names are
neutral ordinal names preserving a simple file extension; their exact original
workspace references remain in the index and manifest. All artifact bytes are
unchanged, including binary data, UTF-8 and CRLF line endings. Artifacts are
untrusted adapter outputs: use an appropriate viewer; do not execute them.
The index contains no scripts or remote resources and does not embed artifacts.

The packet contains:

- `index.html`: readable pending-review context, criteria, artifact links and
  instructions to return to the canonical review workflow
- `manifest.json`: `moonflow.review-packet.v1`, selected item only, canonical
  observed head, current result event ID, recorded and verified ordered output
  digest, artifact references/packet paths/byte counts/SHA-256 hashes, and the
  SHA-256 of the retained timeline bytes
- `history.json`: the native selected-item `moonflow.run-history.v1` response
  bytes, including earlier recorded states and references, without copying their
  old artifacts
- `artifacts/output-0001.ext` and following: only the matching current success
  event's `output_artifacts`, in their declared order

Use the [review return worksheet](REVIEW_RETURNS.md) to record explicit criterion
findings against the original ZIP and prepare a native receipt after current-state
validation. The export format itself remains undecided.

The manifest has `review_decision: null`. It is not an acceptance receipt and
cannot be imported with `review-outcome`. Keep review notes separately or in that packet-bound worksheet. Return
to the canonical host, reload the exact run/attempt/result and use the existing
governed review action. The packet alone cannot establish that the result is
still current. Internal review, customer acceptance and payment remain separate.

## Exact result binding and the existing product surface

The client invokes only these existing read operations, without a shell:

```text
NATIVE_CLI status WORKSPACE RUN
NATIVE_CLI run-history WORKSPACE RUN --json ITEM
NATIVE_CLI status WORKSPACE RUN
```

The engine owns canonical event replay. This client does not read cached
`projection.json`, replay raw events or implement a replacement runtime. It
compares run/book/revision/source/sequence/outcome between status and history;
selects the exact current successful result by item, attempt and result; then
checks request, idempotency, input/output digest, declaration/product and
criteria against status. It reads that event's output paths, not the cumulative
`artifacts` list, so old attempt files and separately attached notes cannot
silently become current result outputs.

This first version supports the ordered local-artifact digest used by native
`complete-artifacts`, the operator receiver and applicable unattended output
snapshots. It calculates each file's SHA-256, constructs the ordered lines
`ORIGINAL_REF|sha256:FILE_HEX` joined by one LF with no trailing LF, then compares
`sha256:SHA256(UTF8(lines))` with the recorded result output digest. An adapter
using a different digest convention cannot export through this version; a
mismatch is a blocker, never a claim that the files were verified. Missing files,
escaping paths, mismatched current result or changed status fail before
publication. The second status must equal the first complete status observation.

This is distinct from `bundle-evidence`: that existing command takes a manually
specified source/provenance descriptor and creates content-addressed objects in
the workspace. It does not select a pending current result from canonical
history, attach its original review criteria or export a reviewer-facing portable
packet. Existing `run-history` and `results-table` exports keep artifact
references only. Review packets consume those existing facts and copy the exact
current output bytes without changing their owning contracts.

## Bounds and failure behavior

- 1–128 distinct current output files, at most 16 MiB each and 64 MiB total
- At most 8 MiB accepted per native JSON response; subprocess responses are
  buffered before this check, so this is not a bound on a malicious executable's
  memory usage. Use only an existing trusted executable
- Native history retains its existing 4,096-input-event/8 MiB limits
- Relative portable paths only, no `.`/`..` segments, backslashes or control
  characters; symlinks must resolve to regular files inside the workspace
- Complete bytes and ZIP are held in memory before exclusive output creation;
  there is no streaming large-result mode or compression
- Exit 0 prints `moonflow.review-packet-export.v1` with the ZIP SHA-256, exact
  result and artifact count. Exit 2 reports the blocker on stderr
- Validation errors publish no ZIP. A disk failure or process interruption
  during the final write can leave an incomplete new ZIP; no success receipt
  exists in that case. Preserve it for inspection and choose a fresh destination

The status sandwich detects observed state changes but is not an atomic lock or
live freshness guarantee. Files and run state can change after the reads. The
packet's stored bytes must match the recorded aggregate digest; this is not a
claim about subsequent workspace bytes, external effects or artifact quality.
There is no signing, encryption, restore, automatic sharing, approval creation,
retry, scheduler, customer acceptance or payment handling.

## Qualification

```sh
python3 -B -m unittest discover -s scripts -p 'test_review_packet.py' -v
```

The tests execute this Python CLI against a clearly labeled local process that
serves retained native-format status/history protocol fixtures. They reopen
actual ZIPs, independently check stored bytes/hashes and HTML links, verify exact
selection, repeatability, current-result changes and no workspace mutation.
Source assertions anchor the native command and digest shapes. The sample
fixtures are hand-authored protocol evidence, not results from native replay.
No native MoonFlow binary, browser rendering, external adapter or full-product
journey was run or qualified for this feature. It adds a bounded MF-W03/W05,
MOONFLOW-B07/N05 review handoff; the PRD's live adapter, backup/restore and restart
release gates remain open.
