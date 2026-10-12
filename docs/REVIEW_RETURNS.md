# Return findings from an offline result review

The [review packet](REVIEW_PACKETS.md) gives a reviewer the exact pending output
bytes and criteria. This return client turns the reviewer's explicit findings
into the existing `moonflow.acceptance-review.v1` receipt, ready for the canonical
host's separate `review-outcome` action. It never submits that action or accepts
work. It creates no new authority and authenticates no reviewer identity.

This closes the packet workflow's manual re-entry gap: the reviewer no longer
has to transcribe attempt/result identities or construct the native receipt
schema. MF-W03/W05, MOONFLOW-B07 and MOONFLOW-N05 require exact result review and
usable artifact/authority context. A generated blank worksheet is not a review.

## 1. Export and inspect the pending result

Use the existing packet exporter and an already installed trusted MoonFlow CLI:

```sh
python3 -B scripts/review_packet.py /absolute/workspace \
  --cli /absolute/path/to/moonflow --run prototype-r1 --item inspect-prototype \
  --output /absolute/reviews/prototype-r1.zip
```

Review the packet's original outputs and criteria. Keep the original ZIP
unchanged; the worksheet binds its exact bytes, including any ZIP comment. An
independently re-exported or repacked ZIP needs its own worksheet, even if its
semantic result is equal. No sharing is performed by either client.

## 2. Create and fill the criterion worksheet

This command is fully offline and does not require a workspace or native CLI:

```sh
python3 -B scripts/review_return.py worksheet /absolute/reviews/prototype-r1.zip \
  --output /absolute/reviews/prototype-r1-findings.json
```

Open the JSON in a text editor. Fill only these fields:

- `review_id`: an explicit new review identity chosen for the canonical workflow
- `reviewer_id`: the actual reviewer identity, supplied by the operator
- `review_authority_id`: an existing applicable review authority identity
- `recorded_at`: the review's explicit UTC time, `YYYY-MM-DDTHH:MM:SSZ`
- `decision`: either `accepted` or `rejected`
- In every `criteria` entry, `satisfied`: an explicit JSON `true` or `false`;
  `note`: a nonblank explanation of what was inspected or what needs revision;
  and `evidence_refs`: exact original references selected from `available_evidence`

Every new decision and finding starts `null`, identifiers/time/notes start empty,
and no evidence is preselected. A satisfied finding requires at least one
current-output reference. An accepted decision requires every finding to be
satisfied. Rejection requires at least one unsatisfied finding and its concrete
note; an unsatisfied finding may have no evidence reference. These are the
existing native review semantics, not inferred quality judgments.

For example, the reviewer's completed dimension finding might look like this:

```json
{
  "criterion": "Width is 120 mm.",
  "satisfied": true,
  "evidence_refs": ["outputs/metrics.json"],
  "note": "Read width_mm in the retained measurement output: 120."
}
```

Preserve the original criterion text and order. Do not edit the packet hash,
head/item bindings, result event ID or available evidence. The client deliberately
supports evidence from the packet's exact current outputs only. Earlier-attempt
files, unrelated attached notes and newly authored evidence must use the normal
canonical review workflow. Notes and authority strings are user claims; the
client does not validate the truth of a note, possession of an identity, grant
ownership, authority expiry or whether a reviewer should accept the result.

## 3. Reload the current result and prepare its native receipt

Back on the canonical host, choose a new workspace-relative receipt path in an
existing directory outside `.moonsuite`:

```sh
python3 -B scripts/review_return.py prepare \
  /absolute/reviews/prototype-r1.zip /absolute/reviews/prototype-r1-findings.json \
  /absolute/workspace --cli /absolute/path/to/moonflow \
  --receipt reviews/prototype-r1-review.json
```

Preparation validates the original ZIP's history/output hashes and ordered result
digest, then validates every finding against that ZIP. It calls the existing
packet export read logic: `status`, selected-item `run-history`, reads/re-hashes
current artifact files, then `status` again. No temporary packet is published.
The two status responses must be identical during collection. The current
run/book/revision/source, declaration/product/operation/request/idempotency/input,
attempt/result/output, criteria, result event and output bytes must still match
the reviewed packet. A later unrelated event head is allowed if those exact
facts remain current. Review already completed, replaced result, changed files,
revised graph and observation changes block preparation before any receipt write.

On success, the client exclusively creates mode-0600 native receipt JSON. Its
`receipt_artifact` is the exact requested workspace-relative path. It prints a
`moonflow.prepared-review-receipt.v1` report with the receipt, packet and worksheet
hashes, the freshly observed head and the exact `submit_argv` for the existing
native action. `submitted`, `reviewer_identity_authenticated` and
`review_authority_verified` are all explicitly `false`.

Inspect that receipt and use the established authorized host review procedure.
The existing native action is, for the example above:

```sh
/absolute/path/to/moonflow review-outcome /absolute/workspace prototype-r1 \
  reviews/prototype-r1-review.json
```

Only run that separate command when the actual reviewer/authority and intended
decision have been approved under your host's rules. This client never runs it,
retries it, or reads an effectful result. Canonical native acceptance still checks
the selected item/result/attempt/digest/criteria/evidence contract at submission.
Preparation is not an atomic reservation: workspace state, files or authority
can change afterward. Coordinate receipt publication in a trusted local workspace
without concurrent path/symlink replacement. Internal review is separate from
customer acceptance, delivery approval and payment.

## Bounds, preservation and qualification

Python 3.9+ standard library only; no installs or network requests. The CLI exits
0 with a JSON report, or 2 with the blocker on stderr. It never overwrites an
existing worksheet/receipt, including symlinks. Parents must already exist.
Packet and worksheet remain unchanged during preparation. Keep the caller-chosen
worksheet destination outside canonical stores; receipt preparation enforces this
for its workspace. The client never directly changes run events/controls/attempts. Failure during a final filesystem write can leave a partial new file;
there is no success receipt in that case, so preserve it and choose a new path.

- Packet input: at most 88 MiB + 128 KiB; at most 128 output files, 16 MiB per
  member, 64 MiB total output bytes. ZIP members are read in memory, never
  extracted. Only the existing packet member layout is supported.
- Worksheet: at most 2 MiB and 256 distinct original criteria; at most 256
  characters for reviewer/review/authority IDs; notes at most 16,384 characters.
- Native calls inherit the exporter's 8 MiB accepted-response and 0.1–300 second
  timeout limits (default 30 seconds per call). Native responses are buffered
  before the size check, so use only a trusted executable.
- Hashes establish byte identity, not signatures or trustworthy reviewer content.
- No native compilation, native receipt submission, browser, live adapter,
  MoonDesk, remote authority, provider/hardware or full-product qualification.

Run focused executable tests from this repository:

```sh
python3 -B -m unittest discover -s scripts -p 'test_review_return.py' -v
python3 -B -m unittest discover -s scripts -p 'test_review_packet.py' -v
```

Tests execute the real Python exporter and return CLI, reopen actual ZIPs and
receipt files, independently assert the existing native schema, preserve source
bytes, exercise both explicit decisions and current-result changes, and inspect
every requested native command. The native read process is a labeled retained
status/history protocol fixture, not event replay or a substitute MoonFlow
runtime. The PRD's live adapter/restart/restore release gates remain open.
