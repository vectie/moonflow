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
import time


def read(path: Path) -> dict:
    return json.loads(path.read_text())


def write(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")


def qualification_root(name: str) -> Path:
    return Path.home() / "moonsuite/qualification/harness-work" / name


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


def fake_flaky_adapter(argv: list[str]) -> None:
    root = Path(option(argv, "--workspace"))
    request = read(root / option(argv, "--request"))
    marker = root / ".faults" / "product-adapter-failed-once"
    if "auto-recovery" not in request["run_id"] and not marker.exists():
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text("seeded product process crash\n")
        raise SystemExit(17)
    fake_adapter(argv)


def fake_lineage_adapter(argv: list[str]) -> None:
    root = Path(option(argv, "--workspace"))
    request = read(root / option(argv, "--request"))
    if "auto-recovery" in request["run_id"]:
        marker = root / ".faults" / "delayed-child-result"
        if not marker.exists():
            marker.parent.mkdir(parents=True, exist_ok=True)
            marker.write_text("child adapter deliberately delayed before result\n")
            time.sleep(0.25)
    fake_adapter(argv)


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


def fake_revision_reviewer(argv: list[str]) -> None:
    root = Path(option(argv, "--workspace"))
    packet = read(root / option(argv, "--review-packet"))
    accepted = "auto-recovery" in packet["run_id"]
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
            "decision": "accepted" if accepted else "rejected",
            "criteria": [
                {
                    "criterion": criterion,
                    "satisfied": accepted,
                    "evidence_refs": packet["evidence_refs"],
                    "note": (
                        "bounded recovery evidence accepted"
                        if accepted
                        else "seeded review rejection requires diagnostic revision"
                    ),
                }
                for criterion in packet["acceptance_criteria"]
            ],
            "reviewer_id": packet["reviewer_id"],
            "review_authority_id": packet["review_authority_id"],
            "receipt_artifact": receipt_ref,
            "recorded_at": packet["recorded_at"],
        },
    )


def fake_combined_reviewer(argv: list[str]) -> None:
    fake_revision_reviewer(argv)
    root = Path(option(argv, "--workspace"))
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
    root = qualification_root("moonflow-unattended-recovery-smoke")
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


def run_revision_harness(binary: Path, moonbook: Path, product_restart: bool = False) -> None:
    fixture_name = (
        "moonflow-unattended-product-restart-smoke"
        if product_restart
        else "moonflow-unattended-revision-smoke"
    )
    root = qualification_root(fixture_name)
    shutil.rmtree(root, ignore_errors=True)
    root.mkdir(parents=True)
    root = root.resolve()
    refs = fixture_files(root, Path(__file__).resolve())
    for stage in ("after-result", "after-attestation", "after-review"):
        marker = root / ".faults" / stage
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text("revision harness disables crash injection\n")
    manifest = read(root / refs[2])
    if product_restart:
        manifest["drivers"][0]["arguments"] = [
            str(Path(__file__).resolve()),
            "flaky-adapter",
            "--workspace",
            "{workspace}",
            "--request",
            "{request}",
            "--result",
            "{result}",
            "--artifact",
            "books/recovery/drafts/output.json",
        ]
    manifest["drivers"][0]["reviewer_arguments"] = [
        str(Path(__file__).resolve()),
        "revision-reviewer",
        "--workspace",
        "{workspace}",
        "--review-packet",
        "{review}",
    ]
    manifest["observer_executable"] = str(moonbook.resolve())
    manifest["observer_arguments"] = [
        "bookkeeper",
        "reconcile-run",
        "{workspace}/books/{book_id}",
        "{projection}",
        "{recorded_at}",
    ]
    write(root / refs[2], manifest)
    command = [str(binary.resolve()), "run-unattended", str(root), *refs, "2026-07-12T10:02:00Z"]
    completed = subprocess.run(command, capture_output=True, text=True)
    if completed.returncode != 0:
        raise SystemExit(completed.stdout + completed.stderr)
    parent_dir = root / ".moonsuite/products/moonflow/runs/recovery-smoke-r1"
    continuation = read(parent_dir / "continuation.json")
    child_dir = root / ".moonsuite/products/moonflow/runs" / continuation["child_run_id"]
    parent = read(parent_dir / "projection.json")
    child = read(child_dir / "projection.json")
    migration = read(child_dir / "migration.json")
    usage = read(root / refs[4])
    if parent["outcome"] != "blocked" or child["outcome"] != "accepted":
        raise SystemExit("automatic revision did not progress blocked parent to accepted child")
    if product_restart and "adapter process failed" not in parent["items"][0]["blocker"]:
        raise SystemExit("product restart harness did not seed an adapter process failure")
    if migration["invalidated_count"] != 1 or usage["attempts"] != 2:
        raise SystemExit("automatic revision did not preserve bounded migration and usage")
    child_evidence = child["items"][0]["artifacts"][0]
    if product_restart:
        if not (root / child_evidence).exists():
            raise SystemExit("product restart lost child evidence snapshot")
    else:
        parent_evidence = parent["items"][0]["artifacts"][0]
        if parent_evidence == child_evidence:
            raise SystemExit("revision overwrote rejected evidence identity")
        if not (root / parent_evidence).exists() or not (root / child_evidence).exists():
            raise SystemExit("revision lost immutable evidence snapshots")
    print(
        json.dumps(
            {
                "parent": parent,
                "continuation": continuation,
                "child": child,
                "migration": migration,
                "usage": usage,
            },
            indent=2,
        )
    )


def run_helper_harness(moonclaw: Path) -> None:
    root = qualification_root("moonclaw-native-helper-soak")
    shutil.rmtree(root, ignore_errors=True)
    root.mkdir(parents=True)
    write(
        root / "runtime/request.json",
        {
            "request_id": "soak-helper-request",
            "product_id": "moonclaw",
            "operation": "implement-helper-tools",
            "output_contracts": ["moonclaw.software-result.v1"],
        },
    )
    write(
        root / "runtime/result.json",
        {
            "result_id": "soak-helper-result",
            "product_id": "moonclaw",
            "output_digest": "sha256:soak-draft",
            "output_artifacts": ["drafts/reserve.json"],
        },
    )
    write(
        root / "drafts/reserve.json",
        {
            "contract_id": "moonclaw.software-result.v1",
            "product_id": "moonclaw",
            "change_summary": "Provide a bounded reserve margin helper.",
            "implementation": {
                "language": "moonsuite-helper-dsl.v1",
                "functions": [
                    {
                        "name": "reserve_margin",
                        "operation": "subtract",
                        "inputs": ["available", "required"],
                    }
                ],
            },
            "test_vectors": [
                {
                    "case_id": "nominal",
                    "function": "reserve_margin",
                    "inputs": {"available": 100, "required": 30},
                    "expected": 70,
                }
            ],
            "negative_cases": [
                {
                    "case_id": "deficit",
                    "function": "reserve_margin",
                    "inputs": {"available": 20, "required": 30},
                    "expected": -10,
                }
            ],
            "criteria_preserved": True,
            "physical_readiness": False,
        },
    )
    command = [
        str(moonclaw.resolve()),
        "flow-adapter",
        "attest",
        "--workspace",
        str(root),
        "--request",
        "runtime/request.json",
        "--result",
        "runtime/result.json",
        "--attestation",
        "runtime/attestation.json",
        "--attestor-id",
        "moonclaw-native-helper-soak-v1",
        "--draft",
        "drafts/reserve.json",
        "--final",
        "outputs/reserve.json",
    ]
    completed = subprocess.run(command, capture_output=True, text=True)
    if completed.returncode != 0:
        raise SystemExit(completed.stdout + completed.stderr)
    output = read(root / "outputs/reserve.json")
    attestation = read(root / "runtime/attestation.json")
    if not attestation["accepted"] or not output["criteria_preserved"]:
        raise SystemExit("MoonClaw native helper attestation was not accepted")
    if len(output["test_results"]) != 2 or output["physical_readiness"]:
        raise SystemExit("MoonClaw helper evidence was incomplete or overclaimed")
    if any(not result["passed"] for result in output["test_results"]):
        raise SystemExit("MoonClaw native helper vector failed")
    print(json.dumps({"attestation": attestation, "output": output}, indent=2))


def run_combined_lineage_harness(binary: Path, moonbook: Path) -> None:
    root = qualification_root("moonflow-unattended-combined-lineage")
    shutil.rmtree(root, ignore_errors=True)
    root.mkdir(parents=True)
    root = root.resolve()
    refs = fixture_files(root, Path(__file__).resolve())
    manifest = read(root / refs[2])
    manifest["drivers"][0]["arguments"] = [
        str(Path(__file__).resolve()),
        "lineage-adapter",
        "--workspace",
        "{workspace}",
        "--request",
        "{request}",
        "--result",
        "{result}",
        "--artifact",
        "books/recovery/drafts/output.json",
    ]
    manifest["drivers"][0]["reviewer_arguments"] = [
        str(Path(__file__).resolve()),
        "combined-reviewer",
        "--workspace",
        "{workspace}",
        "--review-packet",
        "{review}",
    ]
    manifest["observer_executable"] = str(moonbook.resolve())
    manifest["observer_arguments"] = [
        "bookkeeper",
        "reconcile-run",
        "{workspace}/books/{book_id}",
        "{projection}",
        "{recorded_at}",
    ]
    write(root / refs[2], manifest)
    command = [
        str(binary.resolve()),
        "run-unattended",
        str(root),
        *refs,
        "2026-07-12T10:02:00Z",
    ]
    return_codes = [subprocess.run(command).returncode for _ in range(5)]
    if return_codes[:3] != [-signal.SIGKILL] * 3 or return_codes[3:] != [0, 0]:
        raise SystemExit(f"unexpected combined-lineage sequence: {return_codes}")
    parent_dir = root / ".moonsuite/products/moonflow/runs/recovery-smoke-r1"
    continuation = read(parent_dir / "continuation.json")
    child_dir = root / ".moonsuite/products/moonflow/runs" / continuation["child_run_id"]
    parent = read(parent_dir / "projection.json")
    child = read(child_dir / "projection.json")
    migration = read(child_dir / "migration.json")
    usage = read(root / refs[4])
    delayed_marker = root / ".faults" / "delayed-child-result"
    if parent["outcome"] != "blocked" or child["outcome"] != "accepted":
        raise SystemExit("combined lineage did not revise rejected parent to accepted child")
    if migration["invalidated_count"] != 1 or usage["attempts"] != 2:
        raise SystemExit("combined lineage duplicated or incorrectly reused an attempt")
    if not delayed_marker.exists():
        raise SystemExit("combined lineage did not exercise delayed child result")
    parent_evidence = parent["items"][0]["artifacts"][0]
    child_evidence = child["items"][0]["artifacts"][0]
    if parent_evidence == child_evidence:
        raise SystemExit("combined lineage overwrote rejected evidence identity")
    if not (root / parent_evidence).exists() or not (root / child_evidence).exists():
        raise SystemExit("combined lineage lost immutable evidence")
    print(
        json.dumps(
            {
                "return_codes": return_codes,
                "delayed_result": True,
                "duplicate_terminal_delivery": True,
                "parent": parent,
                "continuation": continuation,
                "child": child,
                "migration": migration,
                "usage": usage,
            },
            indent=2,
        )
    )


def run_model_loss_harness(moonclaw: Path) -> None:
    root = qualification_root("moonclaw-model-loss-soak")
    shutil.rmtree(root, ignore_errors=True)
    root.mkdir(parents=True)
    write(root / "books/model-loss/goal.txt", {"goal": "prove safe model loss"})
    write(
        root / "runtime/request.json",
        {
            "contract_id": "moonflow.adapter-request.v1",
            "request_id": "request-model-loss",
            "attempt_id": "attempt-model-loss-1",
            "idempotency_key": "model-loss/attempt-1",
            "run_id": "model-loss",
            "work_item_id": "work-model-loss",
            "declaration_id": "model-loss",
            "product_id": "moonwiki",
            "requested_authority": "observe",
            "acceptance_criteria": ["model loss cannot fabricate evidence"],
            "operation": "research-goal",
            "input_contracts": ["moonsuite.goal.v1"],
            "output_contracts": ["moonwiki.evidence-bundle.v1"],
            "required_claim": "research-evidence",
            "input_artifacts": ["books/model-loss/goal.txt"],
            "created_at": "2026-07-12T10:02:00Z",
        },
    )
    command = [
        str(moonclaw.resolve()),
        "flow-adapter",
        "execute",
        "--workspace",
        str(root),
        "--request",
        "runtime/request.json",
        "--result",
        "runtime/result.json",
        "--model",
        "qualification/model-deliberately-unavailable",
        "--artifact",
        "books/model-loss/draft.json",
        "--max-trials",
        "1",
    ]
    completed = subprocess.run(command, capture_output=True, text=True)
    if completed.returncode == 0:
        raise SystemExit("missing model unexpectedly produced a successful result")
    result = read(root / "runtime/result.json")
    if result["status"] != "failed" or result["output_artifacts"]:
        raise SystemExit("model loss did not fail closed without evidence")
    if (root / "books/model-loss/draft.json").exists():
        raise SystemExit("model loss fabricated a draft artifact")
    print(json.dumps({"return_code": completed.returncode, "result": result}, indent=2))


def run_binding_mutation_harness(binary: Path) -> None:
    root = qualification_root("moonflow-binding-mutation-soak")
    shutil.rmtree(root, ignore_errors=True)
    root.mkdir(parents=True)
    refs = fixture_files(root, Path(__file__).resolve())
    graph = read(root / refs[0])
    graph["source_digest"] = "sha256:" + "b" * 64
    write(root / refs[0], graph)
    command = [
        str(binary.resolve()),
        "run-unattended",
        str(root),
        *refs,
        "2026-07-12T10:02:00Z",
    ]
    completed = subprocess.run(command, capture_output=True, text=True)
    if completed.returncode == 0:
        raise SystemExit("mutated graph unexpectedly passed envelope binding")
    receipt = read(
        root
        / ".moonsuite/products/moonflow/runs/recovery-smoke-r1/autonomy-binding-rejection.json"
    )
    if receipt["field"] != "source_digest" or receipt["actual"] == receipt["expected"]:
        raise SystemExit("source mutation did not leave a precise durable refusal")
    print(json.dumps({"return_code": completed.returncode, "receipt": receipt}, indent=2))


def run_control_harness(binary: Path) -> None:
    root = qualification_root("moonflow-control-soak")
    shutil.rmtree(root, ignore_errors=True)
    root.mkdir(parents=True)
    refs = fixture_files(root, Path(__file__).resolve())
    imported = subprocess.run(
        [str(binary.resolve()), "import-graph", str(root), str(root / refs[0])],
        capture_output=True,
        text=True,
    )
    if imported.returncode != 0:
        raise SystemExit(imported.stdout + imported.stderr)
    for action, at, detail in [
        ("pause", "2026-07-12T10:03:00Z", "qualification inspection"),
        ("resume", "2026-07-12T10:04:00Z", ""),
    ]:
        command = [
            str(binary.resolve()),
            "control",
            str(root),
            "recovery-smoke-r1",
            action,
            at,
        ]
        if detail:
            command.append(detail)
        completed = subprocess.run(command, capture_output=True, text=True)
        if completed.returncode != 0:
            raise SystemExit(completed.stdout + completed.stderr)
    control = read(
        root / ".moonsuite/products/moonflow/runs/recovery-smoke-r1/control.json"
    )
    if control["state"] != "running":
        raise SystemExit("pause/resume did not return the run to running")
    print(json.dumps({"control": control}, indent=2))


def run_budget_harness(moongate: Path) -> None:
    root = qualification_root("moongate-budget-soak")
    shutil.rmtree(root, ignore_errors=True)
    root.mkdir(parents=True)
    refs = fixture_files(root, Path(__file__).resolve())
    usage = read(root / refs[4])
    usage["attempts"] = 10
    write(root / refs[4], usage)
    write(
        root / "runtime/event.json",
        {
            "contract_id": "moongate.autonomy-event-request.v1",
            "event_id": "budget-exhaustion-event",
            "run_id": "recovery-smoke-r1",
            "product_id": "moonwiki",
            "operation": "recovery-smoke",
            "requested_authority": "observe",
            "claim": "research-evidence",
            "artifact_paths": ["books/recovery/output.json"],
            "external_destination": "",
            "budget_request": {
                "model_tokens": 1,
                "tool_calls": 1,
                "storage_bytes": 4096,
                "attempts": 1,
                "concurrency": 1,
            },
            "recorded_at": "2026-07-12T10:02:00Z",
        },
    )
    command = [
        str(moongate.resolve()),
        "suite",
        "autonomy-check",
        "--root",
        str(root),
        "--envelope",
        str(root / refs[3]),
        "--event",
        str(root / "runtime/event.json"),
        "--usage",
        str(root / refs[4]),
        "--decision",
        "budget-exhaustion-decision",
        "--checked-at",
        "2026-07-12T10:02:00Z",
    ]
    completed = subprocess.run(command, capture_output=True, text=True)
    if completed.returncode == 0:
        raise SystemExit("exhausted attempt budget unexpectedly passed MoonGate")
    decision = read(
        root
        / ".moonsuite/products/moongate/autonomy/recovery-envelope/decisions/budget-exhaustion-decision.json"
    )
    if decision["accepted"] or not any(
        "attempt" in finding.lower() and "budget" in finding.lower()
        for finding in decision["findings"]
    ):
        raise SystemExit("budget refusal did not persist an explicit finding")
    print(json.dumps({"return_code": completed.returncode, "decision": decision}, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "mode",
        choices=[
            "harness",
            "revision-harness",
            "product-restart-harness",
            "helper-harness",
            "combined-lineage-harness",
            "model-loss-harness",
            "binding-mutation-harness",
            "control-harness",
            "budget-harness",
            "gate",
            "adapter",
            "flaky-adapter",
            "lineage-adapter",
            "attestor",
            "reviewer",
            "revision-reviewer",
            "combined-reviewer",
            "observer",
        ],
    )
    parser.add_argument("rest", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.mode == "harness":
        if not args.rest:
            raise SystemExit("harness requires the MoonFlow binary path")
        run_harness(Path(args.rest[0]).resolve())
    elif args.mode == "revision-harness":
        if len(args.rest) != 2:
            raise SystemExit("revision-harness requires MoonFlow and MoonBook binaries")
        run_revision_harness(Path(args.rest[0]), Path(args.rest[1]))
    elif args.mode == "product-restart-harness":
        if len(args.rest) != 2:
            raise SystemExit("product-restart-harness requires MoonFlow and MoonBook binaries")
        run_revision_harness(
            Path(args.rest[0]),
            Path(args.rest[1]),
            product_restart=True,
        )
    elif args.mode == "helper-harness":
        if len(args.rest) != 1:
            raise SystemExit("helper-harness requires the MoonClaw binary path")
        run_helper_harness(Path(args.rest[0]))
    elif args.mode == "combined-lineage-harness":
        if len(args.rest) != 2:
            raise SystemExit(
                "combined-lineage-harness requires MoonFlow and MoonBook binaries"
            )
        run_combined_lineage_harness(Path(args.rest[0]), Path(args.rest[1]))
    elif args.mode == "model-loss-harness":
        if len(args.rest) != 1:
            raise SystemExit("model-loss-harness requires the MoonClaw binary path")
        run_model_loss_harness(Path(args.rest[0]))
    elif args.mode == "binding-mutation-harness":
        if len(args.rest) != 1:
            raise SystemExit("binding-mutation-harness requires the MoonFlow binary path")
        run_binding_mutation_harness(Path(args.rest[0]))
    elif args.mode == "control-harness":
        if len(args.rest) != 1:
            raise SystemExit("control-harness requires the MoonFlow binary path")
        run_control_harness(Path(args.rest[0]))
    elif args.mode == "budget-harness":
        if len(args.rest) != 1:
            raise SystemExit("budget-harness requires the MoonGate binary path")
        run_budget_harness(Path(args.rest[0]))
    elif args.mode == "adapter":
        fake_adapter(args.rest)
    elif args.mode == "flaky-adapter":
        fake_flaky_adapter(args.rest)
    elif args.mode == "lineage-adapter":
        fake_lineage_adapter(args.rest)
    elif args.mode == "attestor":
        fake_attestor(args.rest)
    elif args.mode == "reviewer":
        fake_reviewer(args.rest)
    elif args.mode == "revision-reviewer":
        fake_revision_reviewer(args.rest)
    elif args.mode == "combined-reviewer":
        fake_combined_reviewer(args.rest)
    elif args.mode in {"gate", "observer"}:
        return


if __name__ == "__main__":
    main()
