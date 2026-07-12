#!/usr/bin/env python3
"""Run the restart/duplicate recovery qualification repeatedly for a wall-clock soak."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("moonflow_binary", type=Path)
    parser.add_argument("--moonbook-binary", type=Path)
    parser.add_argument("--moonclaw-binary", type=Path)
    parser.add_argument("--moongate-binary", type=Path)
    parser.add_argument("--duration-hours", type=float, default=72.0)
    parser.add_argument("--interval-seconds", type=float, default=900.0)
    parser.add_argument("--cycles", type=int)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path.home() / "moonsuite/qualification/unattended-soak",
    )
    args = parser.parse_args()
    if args.duration_hours <= 0 or args.interval_seconds < 0:
        raise SystemExit("duration-hours must be positive and interval-seconds non-negative")
    if args.cycles is not None and args.cycles <= 0:
        raise SystemExit("cycles must be positive")

    binary = args.moonflow_binary.resolve()
    moonbook = args.moonbook_binary.resolve() if args.moonbook_binary else None
    moonclaw = args.moonclaw_binary.resolve() if args.moonclaw_binary else None
    moongate = args.moongate_binary.resolve() if args.moongate_binary else None
    recovery = Path(__file__).with_name("unattended_recovery_smoke.py").resolve()
    started_wall = time.time()
    deadline = started_wall + args.duration_hours * 3600
    cycle = 0
    state_path = args.output / "state.json"
    log_path = args.output / "cycles.jsonl"
    args.output.mkdir(parents=True, exist_ok=True)
    stop_requested = threading.Event()

    def request_stop(_signum: int, _frame: object) -> None:
        stop_requested.set()

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)

    while not stop_requested.is_set() and (
        (args.cycles is None and time.time() < deadline)
        or (args.cycles is not None and cycle < args.cycles)
    ):
        cycle += 1
        cycle_started = time.time()
        commands = [("crash-recovery", [sys.executable, str(recovery), "harness", str(binary)])]
        if moonbook is not None:
            commands.append(
                (
                    "automatic-revision",
                    [
                        sys.executable,
                        str(recovery),
                        "revision-harness",
                        str(binary),
                        str(moonbook),
                    ],
                )
            )
        if moonclaw is not None:
            commands.append(
                (
                    "native-helper",
                    [
                        sys.executable,
                        str(recovery),
                        "helper-harness",
                        str(moonclaw),
                    ],
                )
            )
            commands.append(
                (
                    "model-loss",
                    [
                        sys.executable,
                        str(recovery),
                        "model-loss-harness",
                        str(moonclaw),
                    ],
                )
            )
        if moonbook is not None:
            commands.append(
                (
                    "combined-lineage",
                    [
                        sys.executable,
                        str(recovery),
                        "combined-lineage-harness",
                        str(binary),
                        str(moonbook),
                    ],
                )
            )
        commands.append(
            (
                "evidence-mutation",
                [
                    sys.executable,
                    str(recovery),
                    "binding-mutation-harness",
                    str(binary),
                ],
            )
        )
        commands.append(
            (
                "operator-control",
                [
                    sys.executable,
                    str(recovery),
                    "control-harness",
                    str(binary),
                ],
            )
        )
        if moongate is not None:
            commands.append(
                (
                    "budget-exhaustion",
                    [
                        sys.executable,
                        str(recovery),
                        "budget-harness",
                        str(moongate),
                    ],
                )
            )
            commands.append(
                (
                    "product-restart",
                    [
                        sys.executable,
                        str(recovery),
                        "product-restart-harness",
                        str(binary),
                        str(moonbook),
                    ],
                )
            )
        checks = []
        for name, command in commands:
            completed = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=180,
            )
            checks.append(
                {
                    "name": name,
                    "status": completed.returncode,
                    "stdout_tail": completed.stdout[-2000:],
                    "stderr_tail": completed.stderr[-2000:],
                }
            )
            if completed.returncode != 0:
                break
        cycle_status = next(
            (check["status"] for check in checks if check["status"] != 0),
            0,
        )
        record = {
            "contract_id": "moonflow.unattended-soak-cycle.v1",
            "cycle": cycle,
            "started_at_epoch": cycle_started,
            "duration_seconds": time.time() - cycle_started,
            "status": cycle_status,
            "recovery_sequence_verified": cycle_status == 0,
            "checks": checks,
        }
        with log_path.open("a") as stream:
            stream.write(json.dumps(record, separators=(",", ":")) + "\n")
        state = {
            "contract_id": "moonflow.unattended-soak.v1",
            "status": "running" if cycle_status == 0 else "failed",
            "moonflow_binary": str(binary),
            "moonbook_binary": str(moonbook) if moonbook else "",
            "moonclaw_binary": str(moonclaw) if moonclaw else "",
            "moongate_binary": str(moongate) if moongate else "",
            "started_at_epoch": started_wall,
            "last_cycle_at_epoch": time.time(),
            "target_duration_hours": args.duration_hours,
            "completed_cycles": cycle,
            "failed_cycles": 0 if cycle_status == 0 else 1,
            "cycle_log": str(log_path),
        }
        write_json(state_path, state)
        if cycle_status != 0:
            raise SystemExit(f"soak cycle {cycle} failed")
        if args.cycles is not None and cycle >= args.cycles:
            break
        remaining = deadline - time.time()
        if args.cycles is None and remaining <= 0:
            break
        stop_requested.wait(min(args.interval_seconds, max(remaining, 0)))

    final = json.loads(state_path.read_text())
    final["status"] = "interrupted" if stop_requested.is_set() else "passed"
    final["completed_at_epoch"] = time.time()
    final["elapsed_hours"] = (final["completed_at_epoch"] - started_wall) / 3600
    write_json(state_path, final)
    print(json.dumps(final, indent=2))
    if stop_requested.is_set():
        raise SystemExit(130)


if __name__ == "__main__":
    main()
