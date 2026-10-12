"""Functional operator-client tests. The native process below is a protocol fixture."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "scripts/batch_pause.py"
STAMP = "2026-10-11T15:00:00Z"

# This is intentionally not a MoonFlow replay engine or a qualified native binary.
# It implements only the observed `status` and `control pause` process boundary.
FIXTURE = r'''
import json, os, pathlib, sys, time
command, workspace, run_id, *rest = sys.argv[1:]
with open(os.environ["FLOW_FIXTURE_LOG"], "a") as out:
    out.write(json.dumps(sys.argv[1:]) + "\n")
directory = pathlib.Path(workspace)/".moonsuite/products/moonflow/runs"/run_id
if not directory.exists():
    print("missing imported run"); sys.exit(1)
projection = json.loads((directory/"projection.fixture.json").read_text())
behavior = projection.pop("fixture_behavior", "")
if command == "status":
    if behavior == "invalid-status":
        print("not a projection"); sys.exit(0)
    print(json.dumps(projection)); sys.exit(0)
assert command == "control" and rest[0] == "pause"
assert projection["outcome"] not in ["accepted", "blocked", "failed"]
path = directory/"control.json"
previous = json.loads(path.read_text()) if path.exists() else {"authority_ceiling":""}
control = {"contract_id":"moonflow.run-control.v1", "run_id":run_id, "state":"paused",
           "authority_ceiling":previous["authority_ceiling"], "recorded_at":rest[1], "reason":rest[2]}
path.write_text(json.dumps(control)+"\n")
if behavior == "lost-ack":
    print("response lost after retained control"); sys.exit(9)
if behavior == "timeout":
    time.sleep(2)
if behavior == "wrong-response":
    control["run_id"] = "different-run"
print(json.dumps(control))
'''


class BatchPauseWorkflow(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="moonflow-batch-pause-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.workspace = self.root / "workspace with spaces"
        self.workspace.mkdir()
        self.cli = self.root / "fixture flow"
        self.cli.write_text(f"#!{sys.executable}\n" + FIXTURE)
        self.cli.chmod(0o755)
        self.log = self.root / "native-calls.jsonl"
        self.receipt_number = 0

    def run_dir(self, run_id):
        return self.workspace / ".moonsuite/products/moonflow/runs" / run_id

    def seed(self, run_id, outcome="ready", state=None, ceiling="observe", behavior=""):
        directory = self.run_dir(run_id)
        directory.mkdir(parents=True)
        projection = {"protocol": "moonflow.run-projection.v3", "run_id": run_id,
                      "book_id": "operations-book", "declaration_revision": "r1",
                      "source_digest": "sha256:synthetic-source", "last_sequence": 3,
                      "outcome": outcome, "items": [{"work_item_id": "job", "status": "ready"}],
                      "fixture_behavior": behavior}
        (directory / "projection.fixture.json").write_text(json.dumps(projection))
        # An opaque sentinel: the client must never replay or write event history itself.
        (directory / "events.json").write_text('[{"synthetic_immutable_history":true}]\n')
        if state:
            control = {"contract_id": "moonflow.run-control.v1", "run_id": run_id,
                       "state": state, "authority_ceiling": ceiling,
                       "reason": "prior operator choice", "recorded_at": STAMP}
            (directory / "control.json").write_text(json.dumps(control))

    def call(self, mode, runs, extra=(), receipt=None, quiesced=True):
        args = [sys.executable, str(CLIENT), mode, str(self.workspace), "--cli", str(self.cli),
                "--reason", "adapter unavailable; inspect before resuming", "--recorded-at", STAMP]
        for run_id in runs:
            args += ["--run", run_id]
        if mode == "apply":
            self.receipt_number += 1
            receipt = receipt or self.root / f"receipt-{self.receipt_number}.jsonl"
            args += ["--receipt", str(receipt)]
            if quiesced:
                args.append("--controls-quiesced")
        result = subprocess.run(args + list(extra), capture_output=True, text=True,
                                env={**os.environ, "FLOW_FIXTURE_LOG": str(self.log)}, timeout=10)
        report = json.loads(result.stdout) if result.stdout else None
        journal = [json.loads(line) for line in receipt.read_text().splitlines()] if receipt and receipt.exists() else []
        return result, report, journal

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def snapshot(self):
        return {str(p.relative_to(self.workspace)): p.read_bytes()
                for p in self.workspace.rglob("*") if p.is_file()}

    def test_preview_exact_selection_is_read_only_and_explains_skips(self):
        self.seed("active", "active", "running")
        self.seed("paused", state="paused")
        self.seed("cancelled", state="cancelled")
        self.seed("complete", "accepted")
        self.seed("unselected")
        before = self.snapshot()
        result, report, journal = self.call("preview", ["active", "paused", "cancelled", "complete"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, self.snapshot())
        self.assertEqual([r["result"] for r in report["results"]],
                         ["would-pause", "already-paused", "cancelled", "terminal"])
        self.assertFalse(report["all_selected_paused"])
        self.assertEqual(len(self.calls()), 4)
        self.assertTrue(all(c[0] == "status" for c in self.calls()))
        self.assertEqual(journal, [])

    def test_apply_preserves_authority_history_and_existing_operator_choices(self):
        self.seed("first", state="running", ceiling="observe")
        self.seed("second")
        self.seed("cancelled", state="cancelled")
        self.seed("terminal", "blocked")
        before = self.snapshot()
        result, report, journal = self.call("apply", ["first", "second", "cancelled", "terminal"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(report["counts"], {"paused": 2, "cancelled": 1, "terminal": 1})
        self.assertFalse(report["all_selected_paused"])
        control = json.loads((self.run_dir("first") / "control.json").read_text())
        self.assertEqual(control["authority_ceiling"], "observe")
        for key, value in before.items():
            if key.endswith("/control.json") and "/first/" in key:
                continue
            self.assertEqual((self.workspace / key).read_bytes(), value)
        self.assertEqual([x["event"] for x in journal],
                         ["batch-started", "pause-requested", "run-result", "pause-requested",
                          "run-result", "run-result", "run-result", "batch-finished"])
        controls = [c for c in self.calls() if c[0] == "control"]
        self.assertEqual([c[2] for c in controls], ["first", "second"])
        self.assertTrue(all(c[3:] == ["pause", STAMP, report["reason"]] for c in controls))

    def test_reopen_after_apply_does_not_repeat_native_pause(self):
        self.seed("job")
        _, first, _ = self.call("apply", ["job"])
        before = self.snapshot()
        result, reopened, journal = self.call("apply", ["job"])
        self.assertEqual(result.returncode, 0)
        self.assertTrue(first["all_selected_paused"])
        self.assertTrue(reopened["all_selected_paused"])
        self.assertEqual(reopened["results"][0]["result"], "already-paused")
        self.assertEqual(before, self.snapshot())
        self.assertEqual(len([c for c in self.calls() if c[0] == "control"]), 1)
        self.assertFalse(any(x["event"] == "pause-requested" for x in journal))

    def test_partial_missing_run_does_not_hide_or_prevent_other_pause(self):
        self.seed("available")
        result, report, _ = self.call("apply", ["missing", "available"])
        self.assertEqual(result.returncode, 2)
        self.assertEqual([r["result"] for r in report["results"]], ["blocked", "paused"])
        self.assertFalse(report["completed_without_errors"])
        self.assertFalse(report["all_selected_paused"])

    def test_lost_response_retains_unknown_then_reopen_observes_pause_without_retry(self):
        self.seed("interrupted", behavior="lost-ack")
        self.seed("remaining")
        result, report, journal = self.call("apply", ["interrupted", "remaining"])
        self.assertEqual(result.returncode, 2)
        self.assertEqual([r["result"] for r in report["results"]], ["unconfirmed", "paused"])
        self.assertEqual(journal[1]["event"], "pause-requested")
        self.assertEqual(journal[2]["result"], "unconfirmed")
        _, reopened, _ = self.call("apply", ["interrupted"])
        self.assertEqual(reopened["results"][0]["result"], "already-paused")
        self.assertEqual(len([c for c in self.calls() if c[0] == "control" and c[2] == "interrupted"]), 1)

    def test_timeout_after_retention_is_unconfirmed_not_failed_or_retried(self):
        self.seed("slow", behavior="timeout")
        result, report, journal = self.call("apply", ["slow"], extra=["--timeout", "0.2"])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(report["results"][0]["result"], "unconfirmed")
        self.assertIn("timed out", report["results"][0]["detail"])
        self.assertEqual(json.loads((self.run_dir("slow") / "control.json").read_text())["state"], "paused")
        self.assertEqual(journal[1]["event"], "pause-requested")

    def test_wrong_native_response_never_becomes_confirmed_pause(self):
        self.seed("job", behavior="wrong-response")
        result, report, _ = self.call("apply", ["job"])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(report["counts"], {"unconfirmed": 1})
        self.assertFalse(report["all_selected_paused"])

    def test_unreadable_projection_or_control_is_not_permission_to_pause(self):
        self.seed("projection", behavior="invalid-status")
        self.seed("control", state="running")
        (self.run_dir("control") / "control.json").write_text('{"state":"cancelled"}')
        result, report, _ = self.call("apply", ["projection", "control"])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(report["counts"], {"blocked": 2})
        self.assertTrue(all(c[0] == "status" for c in self.calls()))

    def test_apply_requires_exclusive_operator_acknowledgement_before_calls(self):
        self.seed("job")
        result, report, _ = self.call("apply", ["job"], quiesced=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--controls-quiesced", result.stderr)
        self.assertIsNone(report)
        self.assertEqual(self.calls(), [])

    def test_existing_receipt_is_preserved_and_blocks_new_operations(self):
        self.seed("job")
        receipt = self.root / "existing.jsonl"
        receipt.write_text('{"existing_evidence":true}\n')
        result, report, _ = self.call("apply", ["job"], receipt=receipt)
        self.assertEqual(result.returncode, 2)
        self.assertIsNone(report)
        self.assertEqual(self.calls(), [])
        self.assertEqual(receipt.read_text(), '{"existing_evidence":true}\n')

    def test_native_source_has_the_protocol_consumed_by_this_client(self):
        main = (ROOT / "cmd/main/main.mbt").read_text()
        wire = (ROOT / "wire.mbt").read_text()
        self.assertIn('["status", workspace, run_id] => show_status(workspace, run_id)', main)
        self.assertIn('["control", workspace, run_id, action, recorded_at, detail]', main)
        self.assertIn('["accepted", "blocked", "failed"].contains(projection.outcome)', main)
        self.assertIn('"pause" => state = "paused"', main)
        self.assertIn('"protocol": "moonflow.run-projection.v3"', wire)
        self.assertIn('"last_sequence": projection.last_sequence', wire)


if __name__ == "__main__":
    unittest.main()
