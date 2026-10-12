#!/usr/bin/env python3
"""Pause explicitly selected imported MoonFlow runs through the native operator CLI."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys


TERMINAL = {"accepted", "blocked", "failed"}  # cmd/main/main.mbt write_run_control
OUTCOMES = TERMINAL | {"proposed", "active", "review", "ready", "waiting"}
GOOD = {"paused", "already-paused", "cancelled", "terminal", "would-pause"}


class PauseError(Exception):
    """An operator-visible blocker, never permission to retry an unknown effect."""


def parse_json(text):
    try:
        return json.loads(text)
    except (ValueError, UnicodeError) as error:
        raise PauseError("expected one complete JSON response") from error


def control_at(workspace, run_id):
    path = workspace / ".moonsuite/products/moonflow/runs" / run_id / "control.json"
    # Match the native default, but do not treat malformed existing files as running.
    if not path.resolve().is_relative_to(workspace):
        raise PauseError("run control path escapes the workspace")
    if not path.exists():
        return {"contract_id": "moonflow.run-control.v1", "run_id": run_id,
                "state": "running", "authority_ceiling": ""}
    value = parse_json(path.read_text(encoding="utf-8"))
    if (not isinstance(value, dict)
            or value.get("contract_id") != "moonflow.run-control.v1"
            or value.get("run_id") != run_id
            or value.get("state") not in {"running", "paused", "cancelled"}
            or not isinstance(value.get("authority_ceiling"), str)):
        raise PauseError("invalid or mismatched native run control")
    return value


def invoke(cli, arguments, timeout):
    try:
        result = subprocess.run([str(cli), *arguments], stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, encoding="utf-8",
                                timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        raise PauseError("native command timed out; inspect this run before another action") from error
    except (OSError, UnicodeError) as error:
        raise PauseError(f"native command could not be observed: {error}") from error
    if result.returncode:
        # The inherited native CLI may put diagnostics on stdout.
        detail = (result.stderr or result.stdout).strip()[:2000]
        raise PauseError(f"native command exited {result.returncode}: {detail}")
    return parse_json(result.stdout)


def inspect(cli, workspace, run_id, timeout):
    value = invoke(cli, ["status", str(workspace), run_id], timeout)
    if (not isinstance(value, dict)
            or value.get("protocol") != "moonflow.run-projection.v3"
            or value.get("run_id") != run_id
            or value.get("outcome") not in OUTCOMES
            or type(value.get("last_sequence")) is not int
            or value["last_sequence"] < 0
            or not isinstance(value.get("items"), list) or not value["items"]):
        raise PauseError("status is not the selected imported run projection")
    return value, control_at(workspace, run_id)


def pause_batch(cli, workspace, run_ids, reason, recorded_at, timeout, apply, record):
    results = []
    for run_id in run_ids:
        row = {"run_id": run_id}
        attempted = False
        try:
            projection, before = inspect(cli, workspace, run_id, timeout)
            row.update(outcome_before=projection["outcome"],
                       last_sequence=projection["last_sequence"],
                       book_id=projection.get("book_id"),
                       declaration_revision=projection.get("declaration_revision"),
                       source_digest=projection.get("source_digest"),
                       control_before=before)
            if before["state"] == "cancelled":
                row["result"] = "cancelled"
            elif before["state"] == "paused":
                row["result"] = "already-paused"
            elif projection["outcome"] in TERMINAL:
                row["result"] = "terminal"
            elif not apply:
                row["result"] = "would-pause"
            else:
                # Persist intention before entering the effectful native command.
                # A final result absent after this entry means the outcome is unknown.
                record({"event": "pause-requested", **row})
                attempted = True
                response = invoke(cli, ["control", str(workspace), run_id, "pause",
                                        recorded_at, reason], timeout)
                after = control_at(workspace, run_id)
                expected = {"contract_id": "moonflow.run-control.v1", "run_id": run_id,
                            "state": "paused", "authority_ceiling": before["authority_ceiling"],
                            "reason": reason, "recorded_at": recorded_at}
                if response != expected or after != expected:
                    raise PauseError("pause response or retained control differs; inspect the run")
                row.update(result="paused", control_after=after)
        except (PauseError, OSError, UnicodeError) as error:
            row.update(result="unconfirmed" if attempted else "blocked", detail=str(error))
        results.append(row)
        record({"event": "run-result", **row})
    counts = dict(Counter(row["result"] for row in results))
    return {"contract_id": "moonflow.batch-pause-report.v1",
            "mode": "apply" if apply else "preview", "workspace": str(workspace),
            "reason": reason, "recorded_at": recorded_at, "results": results,
            "counts": counts,
            "completed_without_errors": all(row["result"] in GOOD for row in results),
            "all_selected_paused": apply and all(row["result"] in {"paused", "already-paused"}
                                                 for row in results)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["preview", "apply"])
    parser.add_argument("workspace", type=Path)
    parser.add_argument("--cli", required=True, type=Path, help="existing trusted native MoonFlow executable")
    parser.add_argument("--run", dest="run_ids", action="append", required=True,
                        help="exact imported run ID; repeat for each selected run")
    parser.add_argument("--reason", required=True)
    parser.add_argument("--recorded-at", default=None, help="UTC timestamp; defaults to current time")
    parser.add_argument("--timeout", type=float, default=30, help="seconds per native call, 0.1 through 300")
    parser.add_argument("--receipt", type=Path, help="new JSONL file required for apply; never overwritten")
    parser.add_argument("--controls-quiesced", action="store_true",
                        help="confirm no other operator/controller will change these runs' controls")
    args = parser.parse_args(argv)
    try:
        if (not 1 <= len(args.run_ids) <= 128 or len(set(args.run_ids)) != len(args.run_ids)
                or any(not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", r) or r == "." or ".." in r
                       for r in args.run_ids)):
            raise PauseError("select 1 through 128 distinct safe run IDs")
        if not args.reason.strip() or len(args.reason) > 4096:
            raise PauseError("reason must contain 1 through 4096 characters")
        if not math.isfinite(args.timeout) or not .1 <= args.timeout <= 300:
            raise PauseError("timeout must be 0.1 through 300 seconds")
        if args.mode == "apply" and (not args.receipt or not args.controls_quiesced):
            raise PauseError("apply requires --receipt and --controls-quiesced")
        if args.mode == "preview" and (args.receipt or args.controls_quiesced):
            raise PauseError("preview uses neither --receipt nor --controls-quiesced")
        workspace, cli = args.workspace.resolve(strict=True), args.cli.resolve(strict=True)
        if not workspace.is_dir() or not cli.is_file() or not os.access(cli, os.X_OK):
            raise PauseError("workspace must be a directory and cli an executable file")
        recorded_at = args.recorded_at or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        if not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", recorded_at):
            raise PauseError("recorded-at must be UTC YYYY-MM-DDTHH:MM:SSZ")
        datetime.strptime(recorded_at, "%Y-%m-%dT%H:%M:%SZ")
        receipt = None
        if args.receipt:
            # Keep the journal out of Flow's canonical store and create before mutation.
            receipt_path = args.receipt.resolve()
            if receipt_path.is_relative_to(workspace / ".moonsuite"):
                raise PauseError("receipt must be outside the workspace's .moonsuite store")
            receipt = receipt_path.open("x", encoding="utf-8")
        try:
            def record(value):
                if receipt:
                    receipt.write(json.dumps(value, ensure_ascii=False) + "\n")
                    receipt.flush()
                    os.fsync(receipt.fileno())
            record({"event": "batch-started", "contract_id": "moonflow.batch-pause-journal.v1",
                    "workspace": str(workspace), "cli": str(cli), "run_ids": args.run_ids,
                    "reason": args.reason, "recorded_at": recorded_at})
            report = pause_batch(cli, workspace, args.run_ids, args.reason, recorded_at,
                                 args.timeout, args.mode == "apply", record)
            record({"event": "batch-finished", "report": report})
        finally:
            if receipt:
                receipt.close()
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0 if report["completed_without_errors"] else 2
    except (PauseError, OSError, ValueError) as error:
        print(f"batch-pause: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
