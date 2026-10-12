# Pause a selected group of imported runs

When an adapter is unavailable or an incident needs operator inspection, use one
explicit batch to pause the affected runs instead of issuing and checking many
individual controls. This is a Python 3.9+ operator client for the existing
MoonFlow native CLI. It is not another runtime, event replay engine or scheduler.
It does not discover runs or choose which work should stop.

## Preview, then apply

From this repository, use an existing trusted native MoonFlow executable and the
same workspace it operates on. Repeat `--run` for each exact imported run ID.
The reason is operator-supplied incident context, never execution permission.

```sh
python3 scripts/batch_pause.py preview /absolute/workspace \
  --cli /absolute/path/to/moonflow \
  --run release-render --run release-summary \
  --reason 'Adapter outage; inspect before resuming'
```

Preview performs native `status WORKSPACE RUN` reads and reads each run's
`control.json`. It makes no writes. It reports `would-pause`, `already-paused`,
`cancelled`, `terminal` or `blocked` for every selected run. The native status
projection does not contain the control state, which is why both sources are
needed. Preview is an observation, not a reservation or permission to act.

After reviewing the selection, coordinate with other operators and stop other
controllers from changing these selected runs' controls. Then apply with that
explicit acknowledgement and a fresh receipt path whose parent already exists:

```sh
python3 scripts/batch_pause.py apply /absolute/workspace \
  --cli /absolute/path/to/moonflow \
  --run release-render --run release-summary \
  --reason 'Adapter outage; inspect before resuming' \
  --controls-quiesced --receipt /absolute/incidents/outage-01.jsonl
```

`--controls-quiesced` is the operator's acknowledgement that no other controller
will change these run controls during this command; the client cannot enforce it.
The native control API has no atomic compare-and-set or shared control lock.
In particular, its inherited `pause` action can overwrite a concurrent
cancellation. Do not apply concurrently with another operator's control actions.
If exclusive control cannot be established, use preview only and coordinate the
pause through the controlling host. This client does not add a dependency route
or replace the native executable.

Apply re-inspects every run rather than trusting an earlier preview. For a
nonterminal running control it invokes exactly:

```text
NATIVE_CLI control WORKSPACE RUN pause RECORDED_AT REASON
```

There is no shell, parallel dispatch, automatic retry or implicit resume. By
default the timestamp is current UTC; `--recorded-at YYYY-MM-DDTHH:MM:SSZ` sets an
explicit recorded value. `--timeout SECONDS` bounds each native call (default 30,
range 0.1–300). Select 1–128 distinct IDs, each 1–128 ASCII letters, digits,
hyphens, underscores or dots, excluding `.` and `..` anywhere. This selection
syntax is intentionally narrower than the inherited native identifier syntax.

## What happens to each run

- Existing `paused` and `cancelled` controls are left byte-for-byte unchanged.
- Native terminal outcomes `accepted`, `blocked` and `failed` are skipped when
  their control is running, matching the native command's refusal rules.
- Missing or unreadable history/status/control blocks that run. A missing
  control file alone means `running` with an empty ceiling, matching native Flow.
- A successful pause must return the exact selected run's native control object,
  retain the prior authority ceiling, and match the newly read `control.json`.
- Event history, attempts, reviews, outputs and other runs are not edited by the
  client. The native command remains the only writer of selected run controls.
- A timeout, failed command, malformed receipt or mismatched retained control
  after invocation is `unconfirmed`. The native operation may already have
  happened. The client never repeats it automatically.
- Independent selected runs continue after one run's blocker or unconfirmed
  result. A partial batch is not rolled back and never reported as all paused.

The JSON report records each observed outcome, sequence, book, source/revision
identity and previous control, then its result and confirmed new control if any.
`all_selected_paused` is true only in apply mode when every selected control was
observed paused. It is false for terminal/cancelled skips as well as errors.
`completed_without_errors` can be true with terminal/cancelled skips; inspect the
per-run counts. Exit 0 means no per-run error, not that every run was paused.
Exit 2 means a setup blocker or at least one blocked/unconfirmed result.

## Receipt and interrupted operation

Apply creates a new JSONL receipt exclusively before any native operation and
never overwrites an earlier receipt. Keep it outside the workspace's `.moonsuite`
store. Each entry is flushed and fsynced. `batch-started` records the selection,
workspace, executable path, reason and time. Each `pause-requested` is written
before its native invocation; `run-result` records the observation afterward.
`batch-finished` embeds the complete report also printed to stdout.

If a process stops or receipt writing fails, an unmatched `pause-requested` is an
unknown outcome, not an invitation to retry. Inspect that exact run and its
control using the canonical host/CLI. No `batch-finished` means no complete batch
report. The journal is local operator evidence, not a canonical Flow event or an
authority/acceptance receipt. A new explicit invocation observes retained paused
controls and skips them instead of overwriting their original reason/time.

## Boundaries and qualification

A pause is cooperative control for paths which honor the run control (including
the existing single-step and unattended routes). It does not kill an in-flight
adapter, cancel an external effect, revoke authority, reconcile an unknown
attempt, or guarantee every other host path honors control. Sequential per-run
reads and writes are not an atomic fleet snapshot. A later action can change
control after this observation. Internal acceptance, customer approval and cash
receipt remain separate.

The focused tests run the real Python entry point against a clearly labeled
local executable protocol fixture and inspect actual control/journal files.
They cover preview, mixed states, partial completion, authority preservation,
reopen, lost acknowledgements and timeouts. Source assertions anchor the client
to the existing native command/JSON shapes; they do not execute native Flow.
No native product, browser, provider, adapter effect or full restart journey was
built or qualified for this feature. No dependencies were installed.

```sh
python3 -B -m unittest discover -s scripts -p 'test_batch_pause.py' -v
```

This implements a bounded MF-W05 operator action and supports MOONFLOW-B03's
invocation control boundary. It does not satisfy the PRD's live adapter,
backup/restore or cross-product release gates.
