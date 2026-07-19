#!/usr/bin/env python3
"""Discover and verify the provisional Phase 1C-A orchestration graph."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GRAPH = ROOT / "conformance/phase1c-a-package-graph.json"
RULES = ROOT / "conformance/boundary-rules.json"
PREFIX = "vectie/moonflow/"
INTERNAL_PREFIX = PREFIX + "closed_loop/orchestration/internal/"


def imports(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    blocks = re.findall(r"\bimport\s*\{(.*?)\}(?:\s*for\s*\"[^\"]+\")?", text, re.S)
    return {item for block in blocks for item in re.findall(r'\"([^\"]+)\"', block)}


def cycle(edges: dict[str, set[str]]) -> list[str] | None:
    active: set[str] = set()
    done: set[str] = set()
    stack: list[str] = []

    def visit(node: str) -> list[str] | None:
        if node in active:
            return stack[stack.index(node):] + [node]
        if node in done:
            return None
        active.add(node)
        stack.append(node)
        for target in sorted(edges[node]):
            found = visit(target)
            if found:
                return found
        stack.pop()
        active.remove(node)
        done.add(node)
        return None

    for node in sorted(edges):
        found = visit(node)
        if found:
            return found
    return None


def check_additive_facade_interface(graph: dict, errors: list[str]) -> None:
    """Preserve every Phase1B3 interface line and admit only reviewed additions."""
    config = graph["facade_interface_additive_gate"]
    text = (ROOT / config["path"]).read_text(encoding="utf-8")
    new_types = set(config["allowed_types"])
    new_functions = set(config["allowed_functions"])
    new_methods = {tuple(item.split("::", 1)) for item in config["allowed_methods"]}
    base: list[str] = []
    additions: list[str] = []
    found_types: set[str] = set()
    found_functions: set[str] = set()
    found_methods: set[tuple[str, str]] = set()
    for block in text.split("\n\n"):
        lines = block.splitlines()
        type_match = next(
            (
                re.match(r"pub(?:\(all\))? (?:struct|enum) (\w+)", line)
                for line in lines
                if re.match(r"pub(?:\(all\))? (?:struct|enum) (\w+)", line)
            ),
            None,
        )
        if type_match and type_match.group(1) in new_types:
            found_types.add(type_match.group(1))
            additions.extend(line.rstrip() for line in lines if line.strip())
            continue
        for line in lines:
            stripped = line.rstrip()
            function_match = re.match(r"pub fn(?:\[[^]]+\])? (\w+)\(", stripped)
            method_match = re.match(r"pub fn (\w+)::(\w+)\(", stripped)
            is_addition = False
            if function_match and function_match.group(1) in new_functions:
                found_functions.add(function_match.group(1))
                is_addition = True
            if method_match and (method_match.group(1), method_match.group(2)) in new_methods:
                found_methods.add((method_match.group(1), method_match.group(2)))
                is_addition = True
            (additions if is_addition else base).append(stripped)
    base = [line for line in base if line.strip()]
    additions = [line for line in additions if line.strip()]
    base_hash = hashlib.sha256(("\n".join(base) + "\n").encode()).hexdigest()
    additions_hash = hashlib.sha256(("\n".join(additions) + "\n").encode()).hexdigest()
    if base_hash != config["phase1b3_semantic_lines_sha256"]:
        errors.append(
            "facade Phase1B3 interface mutation/removal: "
            f"expected {config['phase1b3_semantic_lines_sha256']}, got {base_hash}"
        )
    if additions_hash != config["allowed_additions_sha256"]:
        errors.append(
            "facade Phase1C-B additions differ from allowlist: "
            f"expected {config['allowed_additions_sha256']}, got {additions_hash}"
        )
    if found_types != new_types or found_functions != new_functions or found_methods != new_methods:
        errors.append("facade Phase1C-B additive symbol set differs from allowlist")


def check_semantic_corpus(errors: list[str]) -> None:
    """Recompute provisional source anchors and ensure their assertions remain."""
    corpus = json.loads(
        (ROOT / "conformance/phase1b3-semantic-compatibility.json").read_text(
            encoding="utf-8"
        )
    )
    if corpus.get("status") != "source_anchor_only_provisional":
        errors.append("Phase1B3 semantic evidence must remain explicitly provisional")
    if corpus.get("audit_disposition", {}).get("p2_1") != "pending_materialized_runtime_outputs":
        errors.append("Phase1B3 semantic evidence must keep P2-1 pending")
    combined = ""
    for path, expected in corpus["semantic_anchors"].items():
        source = ROOT / path
        actual = hashlib.sha256(source.read_bytes()).hexdigest() if source.is_file() else "missing"
        if actual != expected:
            errors.append(f"Phase1B3 semantic anchor drift {path}: expected {expected}, got {actual}")
        if source.is_file():
            combined += source.read_text(encoding="utf-8")
    for assertion in corpus["required_runtime_assertions"]:
        if f'test "{assertion}"' not in combined:
            errors.append(f"Phase1B3 runtime assertion missing: {assertion}")
    for token in corpus["required_semantic_tokens"]:
        if token not in combined:
            errors.append(f"Phase1B3 semantic token missing: {token}")
    if set(corpus["terminal_outcomes"]) != {
        "CancelledBeforeEffectIntentV2",
        "SucceededV2",
        "CancelledAfterReconciledNotAppliedV2",
        "FailedNonRetryableV2",
        "FailedRetryExhaustedV2",
        "FailedCancellationStoppedRetryV2",
    }:
        errors.append("Phase1B3 six-outcome corpus is incomplete")


def private_import_violations(
    manifest: Path,
    importer: str,
    allowed_internal_importers: set[str],
) -> list[str]:
    return [
        f"first-party package {importer} imports private {dependency}"
        for dependency in sorted(imports(manifest))
        if dependency.startswith(INTERNAL_PREFIX)
        and importer not in allowed_internal_importers
    ]


def moonbit_loc(paths: list[Path]) -> int:
    return sum(len(path.read_text(encoding="utf-8").splitlines()) for path in paths)


def main() -> None:
    graph = json.loads(GRAPH.read_text(encoding="utf-8"))
    allowed_internal_importers = set(graph["allowed_internal_importers"])
    if len(sys.argv) == 3 and sys.argv[1] == "--probe-private-import-manifest":
        probe = Path(sys.argv[2]).resolve()
        errors = private_import_violations(
            probe,
            PREFIX + "conformance/compile_fail_probe",
            allowed_internal_importers,
        )
        if errors:
            for error in errors:
                print(f"PHASE1C_GRAPH: FAIL: {error}", file=sys.stderr)
            raise SystemExit(1)
        print("PHASE1C_GRAPH: PASS: private import probe contained")
        return
    if len(sys.argv) != 1:
        print("usage: check_phase1c_package_graph.py [--probe-private-import-manifest PATH]", file=sys.stderr)
        raise SystemExit(2)
    rules = json.loads(RULES.read_text(encoding="utf-8"))["flow7a_orchestration"]
    configured = graph["packages"]
    manifests = sorted((ROOT / "closed_loop/orchestration").glob("**/moon.pkg"))
    discovered = {PREFIX + item.parent.relative_to(ROOT).as_posix(): item for item in manifests}
    errors: list[str] = []

    missing = sorted(set(configured) - set(discovered))
    extra = sorted(set(discovered) - set(configured))
    if missing:
        errors.append("configured packages missing manifests: " + ", ".join(missing))
    if extra:
        errors.append("unregistered discovered packages: " + ", ".join(extra))

    actual: dict[str, set[str]] = {}
    forbidden = [item.lower() for item in graph["forbidden_import_fragments"]]
    for name, manifest in discovered.items():
        found = imports(manifest)
        actual[name] = found
        expected = set(configured.get(name, {}).get("imports", []))
        if found != expected:
            errors.append(f"{name} imports differ: expected {sorted(expected)}, got {sorted(found)}")
        for dependency in found:
            if any(fragment in dependency.lower() for fragment in forbidden):
                errors.append(f"{name} has forbidden import {dependency}")
        if name != graph["facade"] and graph["facade"] in found:
            errors.append(f"implementation package {name} imports the facade")

    # Repository-wide ownership gate: no first-party package may reach through
    # the facade into orchestration internals. This is deliberately broader
    # than boundary_scan.py, which owns product/domain vocabulary containment.
    ignored_parts = {"_build", "vendor", "node_modules", ".mooncakes", ".git"}
    for manifest in sorted(ROOT.rglob("moon.pkg")):
        if ignored_parts.intersection(manifest.relative_to(ROOT).parts):
            continue
        importer = PREFIX + manifest.parent.relative_to(ROOT).as_posix()
        errors.extend(
            private_import_violations(
                manifest,
                importer,
                allowed_internal_importers,
            )
        )

    local = {
        name: {dependency for dependency in found if dependency in configured}
        for name, found in actual.items()
    }
    found_cycle = cycle(local)
    if found_cycle:
        errors.append("package cycle: " + " -> ".join(found_cycle))

    result = graph["result"]
    facade_dir = ROOT / configured[graph["facade"]]["path"]
    facade_production = sorted(
        path
        for path in facade_dir.glob("*.mbt")
        if not path.name.endswith(("_test.mbt", "_wbtest.mbt"))
    )
    internal_root = facade_dir / "internal"
    internal_production = sorted(
        path
        for path in internal_root.glob("**/*.mbt")
        if not path.name.endswith(("_test.mbt", "_wbtest.mbt"))
    )
    internal_tests = sorted(
        path
        for path in internal_root.glob("**/*.mbt")
        if path.name.endswith(("_test.mbt", "_wbtest.mbt"))
    )
    measured = {
        "facade_production_files": len(facade_production),
        "facade_production_loc": moonbit_loc(facade_production),
        "internal_production_files": len(internal_production),
        "internal_production_loc": moonbit_loc(internal_production),
        "internal_test_files": len(internal_tests),
        "internal_test_loc": moonbit_loc(internal_tests),
        "internal_package_edges": sum(len(items) for items in local.values()),
    }
    for field, actual_value in measured.items():
        if result.get(field) != actual_value:
            errors.append(
                f"Phase1C material-extraction metric {field} differs: "
                f"expected {result.get(field)}, got {actual_value}"
            )
    lifecycle_internal = [
        ROOT / path for path in result["lifecycle_race_internal_production_files"]
    ]
    lifecycle_loc = moonbit_loc(lifecycle_internal)
    if lifecycle_loc != result["lifecycle_race_internal_production_loc"]:
        errors.append(
            "Phase1C lifecycle-race extraction LOC differs: "
            f"expected {result['lifecycle_race_internal_production_loc']}, "
            f"got {lifecycle_loc}"
        )
    if "not established" not in result.get("compile_time_reduction_claim", ""):
        errors.append("Phase1C graph must not overclaim compile-time reduction")

    registered = {
        "production": set(rules["production_files"]),
        "test": set(rules["test_files"]),
        "manifest": set(rules["manifest_files"]),
        "interface": set(rules["interface_files"]),
    }
    for name, manifest in discovered.items():
        for source in sorted(manifest.parent.glob("*.mbt")):
            relative = source.relative_to(ROOT).as_posix()
            section = "test" if source.name.endswith(("_test.mbt", "_wbtest.mbt")) else "production"
            if relative not in registered[section]:
                errors.append(f"unregistered {section} source in {name}: {relative}")
        relative = manifest.relative_to(ROOT).as_posix()
        if relative not in registered["manifest"]:
            errors.append(f"unregistered manifest in {name}: {relative}")
        interface = manifest.parent / "pkg.generated.mbti"
        relative = interface.relative_to(ROOT).as_posix()
        if not interface.is_file() or relative not in registered["interface"]:
            errors.append(f"unregistered or missing interface in {name}: {relative}")

    for path, expected in graph["compatibility_artifacts"].items():
        artifact = ROOT / path
        actual_hash = hashlib.sha256(artifact.read_bytes()).hexdigest() if artifact.is_file() else "missing"
        if actual_hash != expected:
            errors.append(f"compatibility drift {path}: expected {expected}, got {actual_hash}")

    check_additive_facade_interface(graph, errors)
    check_semantic_corpus(errors)

    if errors:
        for error in errors:
            print(f"PHASE1C_GRAPH: FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
    edges = sum(len(items) for items in local.values())
    print(f"PHASE1C_GRAPH: PASS ({len(discovered)} registered packages; {edges} internal edges; {len(graph['compatibility_artifacts'])} compatibility artifacts)")


if __name__ == "__main__":
    main()
