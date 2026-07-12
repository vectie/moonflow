#!/usr/bin/env python3
"""Fault-inject a MoonFlow run at every durable receipt boundary."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile


def read(path: Path) -> dict:
    return json.loads(path.read_text())


def write(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")


def option(argv: list[str], name: str) -> str:
    return argv[argv.index(name) + 1]


def aggregate_digest(root: Path, refs: list[str]) -> str:
    identities = []
    for ref in refs:
        digest = hashlib.sha256((root / ref).read_bytes()).hexdigest()
        identities.append(f"{ref}|sha256:{digest}")
    return "sha256:" + hashlib.sha256("\n".join(identities).encode()).hexdigest()


def kill_parent_once(root: Path, stage: str) -> None:
    marker = root / ".faults" / stage
    if marker.exists():
        return
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text("fault injected after durable receipt\n")
    os.kill(os.getppid(), signal.SIGKILL)


def fake_adapter(argv: list[str]) -> None:
    root = Path(option(argv, "--workspace"))
    request = read(root / option(argv, "--request"))
    result_ref = option(argv, "--result")
    artifact_ref = option(argv, "--artifact")
    artifact = {
        "contract_id": request["output_contracts"][0],
        "product_id": request["product_id"],
        "evidence": [{"fact": "durable recovery", "source": "fixture"}],
        "limitations": ["fault-injection fixture; not domain evidence"],
    }
    write(root / artifact_ref, artifact)
    digest = aggregate_digest(root, [artifact_ref])
    write(
        root / result_ref,
        {
            "result_id": f"result-{request['attempt_id']}-succeeded",
            "request_id": request["request_id"],
            "attempt_id": request["attempt_id"],
            "idempotency_key": request["idempotency_key"],
            "product_id": request["product_id"],
            "external_job_id": f"fixture-{request['attempt_id']}",
            "status": "succeeded",
            "output_digest": digest,
            "output_artifacts": [artifact_ref],
            "error_kind": "",
            "compensable": True,
            "recorded_at": request["created_at"],
        },
    )
    kill_parent_once(root, "after-result")


def fake_attestor(argv: list[str]) -> None:
    root = Path(option(argv, "--workspace"))
    request = read(root / option(argv, "--request"))
    result = read(root / option(argv, "--result"))
    draft_ref = option(argv, "--draft")
    final_ref = option(argv, "--final")
    write(root / final_ref, read(root / draft_ref))
    write(
        root / option(argv, "--attestation"),
        {
            "contract_id": "moonflow.product-attestation.v1",
            "attestor_id": option(argv, "--attestor-id"),
            "product_id": request["product_id"],
            "request_id": request["request_id"],
            "result_id": result["result_id"],
            "output_digest": result["output_digest"],
            "accepted": True,
        },
    )
    kill_parent_once(root, "after-attestation")


def fake_reviewer(argv: list[str]) -> None:
    root = Path(option(argv, "--workspace"))
    packet = read(root / option(argv, "--review-packet"))
    receipt_ref = packet["receipt_artifact"]
    write(
        root / receipt_ref,
        {
            "contract_id": "moonflow.acceptance-review.v1",
            "review_id": f"review-{packet['attempt_id']}",
            "run_id": packet["run_id"],
            "work_item_id": packet["work_item_id"],
            "declaration_id": packet["declaration_id"],
            "result_id": packet["result_id"],
            "attempt_id": packet["attempt_id"],
            "output_digest": packet["output_digest"],
            "decision": "accepted",
            "criteria": [
                {
                    "criterion": criterion,
                    "satisfied": True,
                    "evidence_refs": packet["evidence_refs"],
                    "note": "fixture evidence is identity-bound",
                }
                for criterion in packet["acceptance_criteria"]
            ],
            "reviewer_id": packet["reviewer_id"],
            "review_authority_id": packet["review_authority_id"],
            "receipt_artifact": receipt_ref,
            "recorded_at": packet["recorded_at"],
        },
    )
    kill_parent_once(root, "after-review")


def fixture_files(root: Path, script: Path) -> tuple[str, ...]:
    goal_ref = "books/recovery/goal.txt"
    graph_ref = "runtime/graph.json"
    capabilities_ref = "runtime/capabilities.json"
    manifest_ref = "runtime/manifest.json"
    envelope_ref = "runtime/envelope.json"
    usage_ref = "runtime/usage.json"
    draft_ref = "books/recovery/drafts/output.json"
    artifact_ref = "books/recovery/output.json"
    (root / goal_ref).parent.mkdir(parents=True, exist_ok=True)
    (root / goal_ref).write_text("Prove restart recovery without domain work.\n")
    source_digest = "sha256:" + "a" * 64
    write(
        root / graph_ref,
        {
            "contract_id": "moonsuite.work-model.v1",
            "graph_id": "recovery-smoke-r1",
            "book_id": "recovery",
            "declaration_revision": "r1",
            "source_digest": source_digest,
            "items": [
                {
                    "work_item_id": "work-recovery",
                    "declaration_id": "recovery",
                    "product_id": "moonwiki",
                    "status": "ready",
                    "depends_on": [],
                    "acceptance_criteria": ["durable output identity is preserved"],
                    "requested_authority": "observe",
                    "operation": "recovery-smoke",
                    "input_contracts": ["moonsuite.goal.v1"],
                    "output_contracts": ["moonwiki.evidence-bundle.v1"],
                    "required_claim": "research-evidence",
                    "input_artifacts": [goal_ref],
                    "timeout_ms": 30000,
                    "attempt_count": 0,
                    "blocker": "",
                }
            ],
            "recorded_at": "2026-07-12T10:00:00Z",
        },
    )
    adapter_id = "moonwiki-recovery-smoke-v1"
    write(
        root / capabilities_ref,
        [
            {
                "adapter_id": adapter_id,
                "product_id": "moonwiki",
                "protocol": "moonflow.adapter.v1",
                "operations": ["recovery-smoke"],
                "authority_classes": ["observe"],
                "input_contracts": ["moonsuite.goal.v1"],
                "output_contracts": ["moonwiki.evidence-bundle.v1"],
                "claim_ceiling": "research-evidence",
                "healthy": True,
                "supports_cancel": True,
                "supports_reconcile": True,
            }
        ],
    )
    python = sys.executable
    common = [str(script)]
    write(
        root / manifest_ref,
        {
            "contract_id": "moonflow.unattended-manifest.v3",
            "gate_executable": python,
            "gate_arguments": common + ["gate"],
            "max_cycles": 10,
            "drivers": [
                {
                    "adapter_id": adapter_id,
                    "executable": python,
                    "arguments": common
                    + [
                        "adapter",
                        "--workspace",
                        "{workspace}",
                        "--request",
                        "{request}",
                        "--result",
                        "{result}",
                        "--artifact",
                        draft_ref,
                    ],
                    "draft_output_artifacts": [draft_ref],
                    "expected_output_artifacts": [artifact_ref],
                    "attestor_id": "moonwiki-recovery-attestor-v1",
                    "attestor_executable": python,
                    "attestor_arguments": common
                    + [
                        "attestor",
                        "--workspace",
                        "{workspace}",
                        "--request",
                        "{request}",
                        "--result",
                        "{result}",
                        "--attestation",
                        "{attestation}",
                        "--attestor-id",
                        "moonwiki-recovery-attestor-v1",
                        "--draft",
                        "{draft}",
                        "--final",
                        "{final}",
                    ],
                    "reviewer_id": "independent-recovery-reviewer",
                    "reviewer_executable": python,
                    "reviewer_arguments": common
                    + [
                        "reviewer",
                        "--workspace",
                        "{workspace}",
                        "--review-packet",
                        "{review}",
                    ],
                    "review_authority_id": "recovery-review-policy-v1",
                    "budget_request": {
                        "model_tokens": 1,
                        "tool_calls": 1,
                        "storage_bytes": 4096,
                        "attempts": 1,
                        "concurrency": 1,
                    },
                }
            ],
            "observer_executable": python,
            "observer_arguments": common + ["observer"],
        },
    )
    write(
        root / envelope_ref,
        {
            "contract_id": "moongate.autonomy-envelope.v1",
            "envelope_id": "recovery-envelope",
            "mode": "unattended-digital",
            "goal_ref": goal_ref,
            "workspace_root": str(root),
            "grants": [
                {
                    "product_id": "moonwiki",
                    "operations": ["recovery-smoke"],
                    "authority_ceiling": "observe",
                    "claim_ceiling": "research-evidence",
                    "artifact_prefixes": ["books/recovery"],
                }
            ],
            "budget": {
                "model_tokens": 10,
                "tool_calls": 10,
                "storage_bytes": 100000,
                "attempts": 10,
                "concurrency": 1,
            },
            "external_effects_allowed": False,
            "physical_effects_allowed": False,
            "granted_by": "fixture-owner",
            "source_digest": source_digest,
            "recorded_at": "2026-07-12T10:00:00Z",
            "expires_at": "2026-07-13T10:00:00Z",
            "revoked": False,
        },
    )
    write(
        root / usage_ref,
        {
            "model_tokens": 0,
            "tool_calls": 0,
            "storage_bytes": 0,
            "attempts": 0,
            "concurrency": 0,
        },
    )
    return graph_ref, capabilities_ref, manifest_ref, envelope_ref, usage_ref


def run_harness(binary: Path) -> None:
    root = Path(tempfile.gettempdir()) / "moonflow-unattended-recovery-smoke"
    shutil.rmtree(root, ignore_errors=True)
    root.mkdir(parents=True)
    root = root.resolve()
    refs = fixture_files(root, Path(__file__).resolve())
    command = [str(binary), "run-unattended", str(root), *refs, "2026-07-12T10:02:00Z"]
    # The fifth launch is a duplicate terminal delivery and must be a no-op.
    return_codes = [subprocess.run(command).returncode for _ in range(5)]
    if return_codes[:3] != [-signal.SIGKILL] * 3 or return_codes[3:] != [0, 0]:
        raise SystemExit(f"unexpected restart sequence: {return_codes}")
    projection = read(
        root
        / ".moonsuite/products/moonflow/runs/recovery-smoke-r1/projection.json"
    )
    scorecard = read(
        root
        / ".moonsuite/products/moonflow/runs/recovery-smoke-r1/intervention-scorecard.json"
    )
    if projection["outcome"] != "accepted" or not scorecard["unattended_qualified"]:
        raise SystemExit("recovered run did not finish as unattended-qualified")
    if projection["items"][0]["attempt_count"] != 1:
        raise SystemExit("recovery created a duplicate attempt")
    attempt_id = projection["items"][0]["active_attempt_id"]
    lease = read(
        root
        / ".moonsuite/products/moonflow/runs/recovery-smoke-r1/dispatch"
        / f"lease-{attempt_id}.json"
    )
    if lease["stage"] != "reviewed":
        raise SystemExit("recovery did not close the durable adapter lease")
    print(json.dumps({"return_codes": return_codes, "projection": projection, "scorecard": scorecard}, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["harness", "gate", "adapter", "attestor", "reviewer", "observer"])
    parser.add_argument("rest", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.mode == "harness":
        if not args.rest:
            raise SystemExit("harness requires the MoonFlow binary path")
        run_harness(Path(args.rest[0]).resolve())
    elif args.mode == "adapter":
        fake_adapter(args.rest)
    elif args.mode == "attestor":
        fake_attestor(args.rest)
    elif args.mode == "reviewer":
        fake_reviewer(args.rest)
    elif args.mode in {"gate", "observer"}:
        return


if __name__ == "__main__":
    main()
