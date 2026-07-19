#!/usr/bin/env python3
"""Deterministic FLOW-2 production-boundary and compatibility scanner."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "conformance/boundary-rules.json"
SKIP_DIRS = {
    ".git",
    ".mooncakes",
    ".moonagent",
    ".moonsuite",
    "_build",
    "target",
    "__pycache__",
}
SERIALIZED_SUFFIXES = {".json", ".yaml", ".yml", ".toml"}
DURABLE_NAME = re.compile(
    r"(?:Event|Projection|Request|Result|Receipt|Record|Store|Checkpoint|"
    r"Outbox|Schedule|Authority|Review|Effect|Artifact|Evidence|Envelope)$"
)
STRUCT = re.compile(
    r"(?m)^(?:pub(?:\(all\))?\s+)?struct\s+(\w+)\s*\{(?P<body>.*?)^\}",
    re.DOTALL,
)
FORBIDDEN_ID = re.compile(
    r"(?i)\b(?:moonbook|bookkeeper|mooncast|moonfish|moonpack)\b"
)
PACK_VOCABULARY = re.compile(
    r"(?i)\b(?:pack|pack_id|pack_version|pack_manifest|gate|gate_id|policy|"
    r"policy_id)\b"
)
DOMAIN_VOCABULARY = re.compile(
    r"(?<![A-Za-z0-9])"
    r"(?i:finance|financial|a[_-]?share|stock|equity_research|aigc|campaign|"
    r"scene|shot|storyboard|animatic|video_generation|video_production)"
    r"(?![A-Za-z0-9])|"
    r"(?:Finance|Financial|AShare|Ashare|Stock|EquityResearch|AIGC|"
    r"Aigc|Campaign|Scene|Shot|Storyboard|Animatic|VideoGeneration|"
    r"VideoProduction)(?=[^a-z]|$)"
)
PRODUCT_BRANCH = re.compile(
    r"(?is)(?:(?:if|guard|match)\b.{0,240}\b(?:product_id|pack_id)\b"
    r".{0,120}(?:==|!=|=>)\s*\"|\b(?:product_id|pack_id)\b\s*"
    r"(?:==|!=)\s*\")"
)
SECRET_FIELD = re.compile(
    r"(?i)\b(?:password|passwd|api_key|access_key|access_token|secret|token|"
    r"private_key)\b\s*:"
)
SAFE_SECRET_REF = re.compile(
    r"(?i)\b(?:secret_ref|credential_ref|token_ref|key_ref)\b"
)
CREDENTIAL_VALUE = re.compile(
    r"(?i)(?:-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|"
    r"\bAKIA[0-9A-Z]{16}\b|\bgh[pousr]_[A-Za-z0-9_]{20,}\b|"
    r"\bsk-[A-Za-z0-9_-]{20,}\b|\bBearer\s+[A-Za-z0-9._~-]{20,}|"
    r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b)"
)
FLOW3_PUBLIC_DECLARATION = re.compile(
    r"(?m)^pub(?:\((?:all|open)\))?\s+"
    r"(?:struct|enum|suberror|trait|type)\s+(\w+)\b"
)
FLOW3_PUBLIC_VALUE = re.compile(r"(?m)^pub\s+fn\s+([a-z]\w*)\(")
FLOW4A_PUBLIC_METHOD = re.compile(
    r"(?m)^pub\s+fn\s+([A-Z]\w*::[a-z]\w*)\("
)
LATER_RUNTIME = re.compile(
    r"\b(?:EffectIntent|OutboxStore|CheckpointStore|ScheduleStore|"
    r"AuthorityAttestation)\b"
)
FLOW4_PLUS_PUBLIC = re.compile(
    r"\b(?:EventStore|RunHeadStore|CheckpointStore|ConflictQuarantine|"
    r"EffectIntent|OutboxStore|ScheduleStore|AuthorityAttestation)\b"
)
PUBLIC_SIDE_EFFECT_METHOD = re.compile(
    r"(?m)^(?:pub\s+)?fn\s+(?:\w+::)?"
    r"(?:apply|execute|dispatch|persist|schedule|grant|publish|deploy|install|"
    r"activate|mutate|submit|cancel|reconcile)(?:\b|_)"
)
FLOW3_SCOPE_REASON = re.compile(r"FLOW-3 public symbol '([^']+)' is outside")
FLOW4A_SCOPE_REASON = re.compile(r"FLOW-4A public symbol '([^']+)' is outside")
FLOW5A_SCOPE_REASON = re.compile(r"FLOW-5A public symbol '([^']+)' is outside")
FLOW6A_SCOPE_REASON = re.compile(r"FLOW-6A public symbol '([^']+)' is outside")
FLOW6C_V2_SCOPE_REASON = re.compile(
    r"FLOW-6C V2 public symbol '([^']+)' is outside"
)
FLOW7A_SCOPE_REASON = re.compile(r"FLOW-7A public symbol '([^']+)' is outside")
DECLARED_IDENTIFIER = re.compile(
    r"(?m)^(?:pub(?:\((?:all|open)\))?\s+)?(?:async\s+)?(?:"
    r"fn\s+(?P<function>(?:\w+::)?\w+)|"
    r"(?:struct|enum|suberror|trait|type)\s+(?P<type>\w+))\b"
)
FLOW4B_PLUS_IDENTIFIER = re.compile(
    r"(?i)(?:dispatch|execut(?:e|ion)|provider_?(?:submi(?:t|ssion)|call)|"
    r"delivery_?(?:receipt|status)|schedul(?:e|ing|er)|retry_?policy|"
    r"lease|fenc(?:e|ing)|authority_?grant|publish|publication|"
    r"deploy(?:ment)?|install(?:ation)?|activat(?:e|ion)|"
    r"capability_?(?:apply|application)|(?:^|_)ui|(?:^|_)dom|browser)"
)
FLOW4B_PLUS_CALL = re.compile(
    r"(?i)\b(?:provider|client|adapter)\s*\.\s*"
    r"(?:submit|call|execute|dispatch)\s*\("
)
FLOW5A_LATER_IDENTIFIER = re.compile(
    r"(?i)(?:effect|dispatch|execut(?:e|ion)|provider|schedul(?:e|ing|er)|"
    r"worker|queue|retry|lease|broker|publish|publication|deliver|acknowledge|"
    r"adapter|network|timer|orchestrat)"
)
FLOW5A_BYPASS_IDENTIFIER = re.compile(
    r"(?i)^(?:accept|set_state|force|force_approve|skip_review|review_bypass|"
    r"skip_authority|authority_bypass)$"
)
FLOW5A_DUPLICATION_IDENTIFIER = re.compile(
    r"(?i)^(?:encode_wire_envelope|decode_wire_envelope|EnvelopeCodec|"
    r"MemoryStore|FileSystemStore|StoredBatch|CheckpointRecord|ReplayResult|"
    r"CommitRequest|OutboxIntent|StoragePort)$"
)
FLOW5A_FORBIDDEN_VOCABULARY = re.compile(
    r"(?i)\b(?:mooncode|moonflow|bookkeeper|moonwiki|three-gap|pack|finance|"
    r"stock|target|video|shot|campaign)\b"
)
FLOW6A_FORBIDDEN_IDENTIFIER = re.compile(
    r"(?i)^(?:execute|apply|accept|force|send_now|retry_anyway|deliver|"
    r"acknowledge|publish|ConcreteDispatcher|ProviderClient|NetworkClient)$"
)
FLOW6A_DUPLICATION_IDENTIFIER = re.compile(
    r"(?i)^(?:encode_wire_envelope|decode_wire_envelope|EnvelopeCodec|"
    r"MemoryStore|FileSystemStore|CheckpointRecord|ReplayResult|CommitRequest|"
    r"OutboxIntent|StoragePort|GovernanceProjection|ReviewReceipt)$"
)
FLOW6A_LATER_IDENTIFIER = re.compile(
    r"(?i)(?:schedule|scheduler|worker|cron|lease_service|user_interface|"
    r"command_line|v2_bridge|flow7)"
)
FLOW6A_EFFECT_CALL = re.compile(
    r"(?i)\b(?:dispatcher|provider|client|adapter)\s*\.\s*"
    r"(?:execute|apply|dispatch|send|publish|retry|deliver|acknowledge)\s*\("
)
FLOW7A_FORBIDDEN_IDENTIFIER = re.compile(
    r"(?i)^(?:run|execute|apply|force|send|dispatch|retry_anyway|claim_anyway|"
    r"now|sleep|tick|ConcreteTimer|ConcreteWorker|SchedulerDaemon|LeaseService|"
    r"LockManager|WorkerLoop|HeartbeatProcess)$"
)
FLOW7A_DUPLICATION_IDENTIFIER = re.compile(
    r"(?i)^(?:encode_wire_envelope|decode_wire_envelope|EnvelopeCodec|MemoryStore|"
    r"FileSystemStore|CheckpointRecord|ReplayResult|CommitRequest|OutboxIntent|"
    r"StoragePort|GovernanceProjection|ReviewReceipt|EffectIntent)$"
)
FLOW7A_AMBIENT_CALL = re.compile(
    r"(?i)\b(?:Date\s*::\s*now|Time\s*::\s*now|Math\s*\.\s*random|"
    r"random\s*\(|uuid\s*\(|getenv\s*\(|sleep\s*\()"
)
FLOW7A_EFFECT_CALL = re.compile(
    r"(?i)\b(?:dispatcher|outbox|provider|client|adapter)\s*\.\s*"
    r"(?:execute|apply|dispatch|send|publish|deliver|acknowledge|consume)\s*\("
)
FLOW7A_FORBIDDEN_VOCABULARY = re.compile(
    r"(?i)(?<![A-Za-z0-9])(?:mooncode|bookkeeper|user_interface|command_line|v2_bridge|"
    r"finance|stock|aigc|campaign|storyboard|publisher|broker|destination|"
    r"credential|secret_value)(?![A-Za-z0-9])"
)


@dataclass(frozen=True, order=True)
class Finding:
    path: str
    line: int
    rule: str
    reason: str

    def render(self) -> str:
        return f"{self.path}:{self.line}: {self.rule} {self.reason}"


def load_config() -> dict[str, Any]:
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def project_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT)
        if any(part in SKIP_DIRS for part in relative.parts):
            continue
        files.append(relative)
    return sorted(files, key=lambda item: item.as_posix())


def is_test_source(path: str) -> bool:
    return path.endswith("_test.mbt") or path.endswith("_wbtest.mbt")


def is_production_source(path: str, allowlist: set[str]) -> bool:
    return path.endswith(".mbt") and not is_test_source(path) and path not in allowlist


def flow3_config(config: dict[str, Any]) -> dict[str, Any]:
    return config.get("flow3_contract", {})


def flow3_production_paths(config: dict[str, Any]) -> set[str]:
    return set(flow3_config(config).get("production_files", {}))


def flow3_interface_paths(config: dict[str, Any]) -> set[str]:
    return set(flow3_config(config).get("interface_files", {}))


def flow3_public_symbols(config: dict[str, Any]) -> frozenset[str]:
    symbols: set[str] = set()
    for path in sorted(flow3_interface_paths(config)):
        interface = (ROOT / path).read_text(encoding="utf-8")
        symbols.update(FLOW3_PUBLIC_DECLARATION.findall(interface))
        symbols.update(FLOW3_PUBLIC_VALUE.findall(interface))
    return frozenset(symbols)


def flow3_public_symbol_pattern(config: dict[str, Any]) -> re.Pattern[str]:
    symbols = sorted(flow3_public_symbols(config), key=lambda value: (-len(value), value))
    if not symbols:
        return re.compile(r"(?!x)x")
    return re.compile(r"\b(" + "|".join(re.escape(symbol) for symbol in symbols) + r")\b")


def flow6c_v2_config(config: dict[str, Any]) -> dict[str, Any]:
    """Return the exact registered FLOW-6C V2 authorization boundary."""
    return config["flow6c_v2_authorization"]


def flow6c_v2_paths(config: dict[str, Any], category: str) -> set[str]:
    """Return registered paths for one exact V2 boundary category."""
    return set(flow6c_v2_config(config).get(category, {}))


def flow6c_v2_production_files(config: dict[str, Any]) -> set[str]:
    return flow6c_v2_paths(config, "production_files")


def flow6c_v2_test_files(config: dict[str, Any]) -> set[str]:
    return flow6c_v2_paths(config, "test_files")


def flow6c_v2_manifest_files(config: dict[str, Any]) -> set[str]:
    return flow6c_v2_paths(config, "manifest_files")


def flow6c_v2_interface_files(config: dict[str, Any]) -> set[str]:
    return flow6c_v2_paths(config, "interface_files")


def flow6c_v2_all_registered_paths(config: dict[str, Any]) -> set[str]:
    return set().union(*(
        flow6c_v2_paths(config, category)
        for category in (
            "production_files", "test_files", "manifest_files", "interface_files"
        )
    ))


def flow4a_config(config: dict[str, Any]) -> dict[str, Any]:
    return config.get("flow4a_storage", {})


def flow4a_production_paths(config: dict[str, Any]) -> set[str]:
    return set(flow4a_config(config).get("production_files", {}))


def flow4a_test_paths(config: dict[str, Any]) -> set[str]:
    return set(flow4a_config(config).get("test_files", {}))


def flow4a_manifest_paths(config: dict[str, Any]) -> set[str]:
    return set(flow4a_config(config).get("manifest_files", {}))


def flow4a_interface_paths(config: dict[str, Any]) -> set[str]:
    return set(flow4a_config(config).get("interface_files", {}))


def flow4a_public_symbols(config: dict[str, Any]) -> frozenset[str]:
    symbols: set[str] = set()
    for path in sorted(flow4a_interface_paths(config)):
        interface = (ROOT / path).read_text(encoding="utf-8")
        symbols.update(FLOW3_PUBLIC_DECLARATION.findall(interface))
        symbols.update(FLOW3_PUBLIC_VALUE.findall(interface))
        symbols.update(FLOW4A_PUBLIC_METHOD.findall(interface))
    return frozenset(symbols)


def public_symbol_pattern(symbols: frozenset[str]) -> re.Pattern[str]:
    ordered = sorted(symbols, key=lambda value: (-len(value), value))
    if not ordered:
        return re.compile(r"(?!x)x")
    return re.compile(
        r"(?<![A-Za-z0-9_])(" + "|".join(re.escape(symbol) for symbol in ordered)
        + r")(?![A-Za-z0-9_])"
    )


def flow4a_public_symbol_pattern(config: dict[str, Any]) -> re.Pattern[str]:
    return public_symbol_pattern(flow4a_public_symbols(config))


def flow4a_trusted_registry_identifiers(config: dict[str, Any]) -> set[str]:
    """Exact storage-kernel activation identifiers admitted after Phase1C."""
    return set(flow4a_config(config).get("trusted_registry_identifiers", []))


def flow5a_config(config: dict[str, Any]) -> dict[str, Any]:
    return config.get("flow5a_governance", {})


def flow5a_production_paths(config: dict[str, Any]) -> set[str]:
    return set(flow5a_config(config).get("production_files", {}))


def flow5a_test_paths(config: dict[str, Any]) -> set[str]:
    return set(flow5a_config(config).get("test_files", {}))


def flow5a_manifest_paths(config: dict[str, Any]) -> set[str]:
    return set(flow5a_config(config).get("manifest_files", {}))


def flow5a_interface_paths(config: dict[str, Any]) -> set[str]:
    return set(flow5a_config(config).get("interface_files", {}))


def flow5a_public_symbols(config: dict[str, Any]) -> frozenset[str]:
    symbols: set[str] = set()
    for path in sorted(flow5a_interface_paths(config)):
        interface = (ROOT / path).read_text(encoding="utf-8")
        symbols.update(FLOW3_PUBLIC_DECLARATION.findall(interface))
        symbols.update(FLOW3_PUBLIC_VALUE.findall(interface))
        symbols.update(FLOW4A_PUBLIC_METHOD.findall(interface))
    return frozenset(symbols)


def flow5a_public_symbol_pattern(config: dict[str, Any]) -> re.Pattern[str]:
    return public_symbol_pattern(flow5a_public_symbols(config))


def flow6a_config(config: dict[str, Any]) -> dict[str, Any]:
    return config.get("flow6a_effects", {})


def flow6a_production_paths(config: dict[str, Any]) -> set[str]:
    return set(flow6a_config(config).get("production_files", {}))


def flow6a_test_paths(config: dict[str, Any]) -> set[str]:
    return set(flow6a_config(config).get("test_files", {}))


def flow6a_manifest_paths(config: dict[str, Any]) -> set[str]:
    return set(flow6a_config(config).get("manifest_files", {}))


def flow6a_interface_paths(config: dict[str, Any]) -> set[str]:
    return set(flow6a_config(config).get("interface_files", {}))


def flow6a_public_symbols(config: dict[str, Any]) -> frozenset[str]:
    symbols: set[str] = set()
    for path in sorted(flow6a_interface_paths(config)):
        interface = (ROOT / path).read_text(encoding="utf-8")
        symbols.update(FLOW3_PUBLIC_DECLARATION.findall(interface))
        symbols.update(FLOW3_PUBLIC_VALUE.findall(interface))
        symbols.update(FLOW4A_PUBLIC_METHOD.findall(interface))
    return frozenset(symbols)


def flow6a_public_symbol_pattern(config: dict[str, Any]) -> re.Pattern[str]:
    return public_symbol_pattern(flow6a_public_symbols(config))


def flow6c_v2_public_symbols(config: dict[str, Any]) -> frozenset[str]:
    symbols: set[str] = set()
    for path in sorted(flow6c_v2_interface_files(config)):
        interface = (ROOT / path).read_text(encoding="utf-8")
        symbols.update(FLOW3_PUBLIC_DECLARATION.findall(interface))
        symbols.update(FLOW3_PUBLIC_VALUE.findall(interface))
        symbols.update(FLOW4A_PUBLIC_METHOD.findall(interface))
    inherited = (
        set(flow3_public_symbols(config))
        | set(flow4a_public_symbols(config))
        | set(flow5a_public_symbols(config))
        | set(flow6a_public_symbols(config))
    )
    return frozenset(symbols - inherited)


def flow6c_v2_public_symbol_pattern(config: dict[str, Any]) -> re.Pattern[str]:
    return public_symbol_pattern(flow6c_v2_public_symbols(config))


def flow7a_config(config: dict[str, Any]) -> dict[str, Any]:
    return config.get("flow7a_orchestration", {})


def flow7a_production_paths(config: dict[str, Any]) -> set[str]:
    return set(flow7a_config(config).get("production_files", {}))


def flow7a_interface_paths(config: dict[str, Any]) -> set[str]:
    return set(flow7a_config(config).get("interface_files", {}))


def flow7a_public_symbols(config: dict[str, Any]) -> frozenset[str]:
    symbols: set[str] = set()
    for path in sorted(flow7a_interface_paths(config)):
        interface = (ROOT / path).read_text(encoding="utf-8")
        symbols.update(FLOW3_PUBLIC_DECLARATION.findall(interface))
        symbols.update(FLOW3_PUBLIC_VALUE.findall(interface))
        symbols.update(FLOW4A_PUBLIC_METHOD.findall(interface))
    return frozenset(symbols)


def flow7a_public_symbol_pattern(config: dict[str, Any]) -> re.Pattern[str]:
    return public_symbol_pattern(flow7a_public_symbols(config))


def is_flow3_contract_surface(path: str, config: dict[str, Any]) -> bool:
    return path in flow3_production_paths(config) | flow3_interface_paths(config)


def is_flow6c_v2_authorization_surface(path: str, config: dict[str, Any]) -> bool:
    """Recognize only the exact approved V2 production/interface surface."""
    return path in flow6c_v2_production_files(config) | flow6c_v2_interface_files(config)


def is_flow4a_storage_surface(path: str, config: dict[str, Any]) -> bool:
    return path in flow4a_production_paths(config) | flow4a_interface_paths(config)


def is_flow5a_governance_surface(path: str, config: dict[str, Any]) -> bool:
    return path in flow5a_production_paths(config) | flow5a_interface_paths(config)


def is_flow6a_effects_surface(path: str, config: dict[str, Any]) -> bool:
    return path in flow6a_production_paths(config) | flow6a_interface_paths(config)


def is_flow7a_orchestration_surface(path: str, config: dict[str, Any]) -> bool:
    return path in flow7a_production_paths(config) | flow7a_interface_paths(config)


def add_matches(
    findings: list[Finding],
    path: str,
    text: str,
    pattern: re.Pattern[str],
    rule: str,
    reason: str,
) -> None:
    for match in pattern.finditer(text):
        findings.append(Finding(path, line_of(text, match.start()), rule, reason))


def scan_manifest(path: str, text: str) -> list[Finding]:
    findings: list[Finding] = []
    for match in re.finditer(r'"([^"\n]+)"', text):
        value = match.group(1)
        if FORBIDDEN_ID.search(value) or re.search(
            r"(?i)(?:^|/)(?:packs?|pack-source)(?:/|$)", value
        ):
            findings.append(
                Finding(
                    path,
                    line_of(text, match.start()),
                    "DEP001",
                    f"forbidden production dependency/import {value!r}",
                )
            )
    return findings


def scan_source_or_interface(
    path: str,
    text: str,
    config: dict[str, Any],
    *,
    production: bool,
    flow3_surface: bool = False,
    flow4a_surface: bool = False,
    flow5a_surface: bool = False,
    flow6a_surface: bool = False,
    flow6c_v2_surface: bool = False,
    flow7a_surface: bool = False,
) -> list[Finding]:
    findings: list[Finding] = []
    if not production:
        return findings
    add_matches(
        findings,
        path,
        text,
        FORBIDDEN_ID,
        "DOM001",
        "external product/domain identifier in production source or interface",
    )
    if not flow5a_surface and not flow6a_surface and not flow7a_surface and not flow6c_v2_surface:
        add_matches(
            findings,
            path,
            text,
            PACK_VOCABULARY,
            "DOM002",
            "pack-owned contract vocabulary in production source or interface",
        )
    add_matches(
        findings,
        path,
        text,
        PRODUCT_BRANCH,
        "DOM003",
        "conditional branch on product/pack identity",
    )
    for match in DOMAIN_VOCABULARY.finditer(text):
        findings.append(
            Finding(
                path,
                line_of(text, match.start()),
                "DOM004",
                "forbidden finance or AIGC/media-production vocabulary token "
                f"{match.group(0)!r} in production source or interface",
            )
        )
    for match in SECRET_FIELD.finditer(text):
        line = text[text.rfind("\n", 0, match.start()) + 1 : text.find("\n", match.end())]
        if (flow6a_surface or flow7a_surface) and re.search(r"\bfencing_token\b", line):
            continue
        if not SAFE_SECRET_REF.search(line):
            findings.append(
                Finding(
                    path,
                    line_of(text, match.start()),
                    "SEC001",
                    "credential/secret-like field in production source",
                )
            )
    add_matches(
        findings,
        path,
        text,
        CREDENTIAL_VALUE,
        "SEC002",
        "credential-shaped material in production source",
    )
    legacy = set(config.get("legacy_unversioned_records", {}).get(path, []))
    if path.endswith(".mbti"):
        for names in config.get("legacy_unversioned_records", {}).values():
            legacy.update(names)
    non_durable = set(
        config.get("non_durable_records", {}).get(path, [])
    )
    if path.endswith(".mbti"):
        for names in config.get("non_durable_records", {}).values():
            non_durable.update(names)
    v2_non_durable = set(
        flow6c_v2_config(config)
        .get("non_durable_records", {})
        .get(path, [])
    )
    for match in STRUCT.finditer(text):
        name = match.group(1)
        if not DURABLE_NAME.search(name) or name in legacy or name in non_durable or (flow6c_v2_surface and name in v2_non_durable):
            continue
        body = match.group("body")
        if not re.search(
            r"(?m)^\s*(?:record|schema|contract|registry|projection|envelope)_version\s*:",
            body,
        ):
            findings.append(
                Finding(
                    path,
                    line_of(text, match.start()),
                    "DUR001",
                    f"durable-looking declaration {name} lacks an explicit version field",
                )
            )
    bypass = re.compile(
        r'(?is)"succeeded"\s*=>.{0,900}(?:status\s*=\s*Accepted|ItemAccepted)'
    )
    add_matches(
        findings,
        path,
        text,
        bypass,
        "REV001",
        "adapter success can reach acceptance instead of Review",
    )
    for match in re.finditer(r"\bstatus\s*=\s*Accepted\b", text):
        before = text[max(0, match.start() - 4000) : match.start()]
        if before.rfind("ItemAccepted =>") <= max(
            before.rfind('"succeeded" =>'), before.rfind("Succeeded =>")
        ):
            findings.append(
                Finding(
                    path,
                    line_of(text, match.start()),
                    "REV002",
                    "terminal acceptance assignment is not guarded by ItemAccepted review handling",
                )
            )
    if Path(path).name == "acceptance_review.mbt" and re.search(
        r"\bfn\s+acceptance_review_event\b", text
    ):
        anchors = [
            'require_review_identity("result_id"',
            'require_review_identity(\n    "attempt_id"',
            'require_review_identity(\n    "output_digest"',
            "receipt.criteria[index].criterion != item.acceptance_criteria[index]",
            "item.artifacts.contains(evidence)",
            "item.status != Review",
        ]
        if any(anchor not in text for anchor in anchors):
            findings.append(
                Finding(
                    path,
                    line_of(text, text.find("acceptance_review_event")),
                    "REV003",
                    "acceptance review lacks exact identity/criteria/evidence/status guards",
                )
            )
    attestation = re.search(
        r"(?i)\b(?:struct|enum|type)\s+\w*Attestation\b|\bnamed[_-]human\b",
        text,
    )
    if attestation and not flow5a_surface:
        findings.append(
            Finding(
                path,
                line_of(text, attestation.start()),
                "AUTH001",
                "FLOW-2 must not upgrade a bare authority string into an attestation",
            )
        )
    for match in flow3_public_symbol_pattern(config).finditer(text):
        if flow3_surface or flow4a_surface or flow5a_surface or flow6a_surface or flow7a_surface or flow6c_v2_surface:
            continue
        symbol = match.group(1)
        findings.append(
            Finding(
                path,
                line_of(text, match.start()),
                "SCOPE001",
                f"FLOW-3 public symbol {symbol!r} is outside the exact approved "
                "package surface",
            )
        )
    if not flow6a_surface and not flow7a_surface and not flow6c_v2_surface:
        for match in LATER_RUNTIME.finditer(text):
            findings.append(
                Finding(
                    path,
                    line_of(text, match.start()),
                    "SCOPE001",
                    "closed-loop contract symbol belongs to a later work order",
                )
            )
    for match in flow4a_public_symbol_pattern(config).finditer(text):
        if flow4a_surface or flow5a_surface or flow6a_surface or flow7a_surface or flow6c_v2_surface:
            continue
        symbol = match.group(1)
        findings.append(
            Finding(
                path,
                line_of(text, match.start()),
                "SCOPE003",
                f"FLOW-4A public symbol {symbol!r} is outside the exact approved "
                "storage package surface",
            )
        )
    for match in flow5a_public_symbol_pattern(config).finditer(text):
        if flow5a_surface or flow6a_surface or flow7a_surface or flow6c_v2_surface:
            continue
        symbol = match.group(1)
        findings.append(
            Finding(
                path,
                line_of(text, match.start()),
                "SCOPE005",
                f"FLOW-5A public symbol {symbol!r} is outside the exact approved "
                "governance package surface",
            )
        )
    for match in DECLARED_IDENTIFIER.finditer(text):
        identifier = match.group("function") or match.group("type") or ""
        trusted_registry_identifier = (
            flow4a_surface
            and identifier in flow4a_trusted_registry_identifiers(config)
        )
        if not flow5a_surface and not flow6a_surface and not flow7a_surface and not flow6c_v2_surface and not trusted_registry_identifier and FLOW4B_PLUS_IDENTIFIER.search(identifier):
            findings.append(
                Finding(
                    path,
                    line_of(text, match.start()),
                    "FLOW4B001",
                    f"later-work-order capability identifier {identifier!r} is "
                    "forbidden in production",
                )
            )
        if flow5a_surface and FLOW5A_LATER_IDENTIFIER.search(identifier):
            findings.append(
                Finding(
                    path,
                    line_of(text, match.start()),
                    "FLOW5A001",
                    f"effect, coordination, or later-phase identifier {identifier!r} "
                    "is forbidden in FLOW-5A",
                )
            )
        if flow5a_surface and FLOW5A_BYPASS_IDENTIFIER.search(identifier):
            findings.append(
                Finding(
                    path,
                    line_of(text, match.start()),
                    "FLOW5A002",
                    f"review or authority bypass identifier {identifier!r} is forbidden",
                )
            )
        if flow5a_surface and FLOW5A_DUPLICATION_IDENTIFIER.search(identifier):
            findings.append(
                Finding(
                    path,
                    line_of(text, match.start()),
                    "FLOW5A003",
                    f"contract or storage duplication identifier {identifier!r} is forbidden",
                )
            )
        if flow6a_surface and FLOW6A_FORBIDDEN_IDENTIFIER.search(identifier):
            findings.append(Finding(
                path, line_of(text, match.start()), "FLOW6A001",
                f"concrete effect or bypass identifier {identifier!r} is forbidden",
            ))
        if flow6a_surface and FLOW6A_DUPLICATION_IDENTIFIER.search(identifier):
            findings.append(Finding(
                path, line_of(text, match.start()), "FLOW6A003",
                f"accepted contract/storage/governance duplication {identifier!r} is forbidden",
            ))
        if flow6a_surface and FLOW6A_LATER_IDENTIFIER.search(identifier):
            findings.append(Finding(
                path, line_of(text, match.start()), "FLOW6A004",
                f"later-phase identifier {identifier!r} is forbidden in FLOW-6A",
            ))
        if flow7a_surface and FLOW7A_FORBIDDEN_IDENTIFIER.search(identifier):
            findings.append(Finding(
                path, line_of(text, match.start()), "FLOW7A001",
                f"active shortcut or concrete runtime identifier {identifier!r} is forbidden",
            ))
        if flow7a_surface and FLOW7A_DUPLICATION_IDENTIFIER.search(identifier):
            findings.append(Finding(
                path, line_of(text, match.start()), "FLOW7A002",
                f"accepted contract/storage/governance/effect duplication {identifier!r} is forbidden",
            ))
    if not flow5a_surface and not flow6a_surface and not flow7a_surface and not flow6c_v2_surface:
        add_matches(
            findings,
            path,
            text,
            FLOW4B_PLUS_CALL,
            "FLOW4B001",
            "later-work-order provider/effect call is forbidden in production",
        )
    if flow5a_surface:
        vocabulary_text = "\n".join(
            ""
            if line.lstrip().startswith("package ")
            or '"vectie/moonflow/' in line
            else line
            for line in text.splitlines()
        )
        add_matches(
            findings,
            path,
            vocabulary_text,
            FLOW5A_FORBIDDEN_VOCABULARY,
            "FLOW5A004",
            "forbidden product, domain, or pack vocabulary in FLOW-5A",
        )
    if flow6a_surface:
        add_matches(
            findings, path, text, FLOW6A_EFFECT_CALL, "FLOW6A001",
            "production FLOW-6A must not invoke an effect port",
        )
    if flow7a_surface:
        add_matches(findings, path, text, FLOW7A_AMBIENT_CALL, "FLOW7A003", "ambient time, randomness, environment, or sleep is forbidden in FLOW-7A")
        add_matches(findings, path, text, FLOW7A_EFFECT_CALL, "FLOW7A004", "production FLOW-7A must not invoke dispatcher, outbox, provider, client, or adapter operations")
        add_matches(findings, path, text, FLOW7A_FORBIDDEN_VOCABULARY, "FLOW7A005", "forbidden product, domain, secret, destination, UI/CLI/v2, or later-phase vocabulary in FLOW-7A")
    for match in flow6a_public_symbol_pattern(config).finditer(text):
        if flow6a_surface or flow7a_surface or flow6c_v2_surface:
            continue
        symbol = match.group(1)
        findings.append(Finding(
            path, line_of(text, match.start()), "SCOPE007",
            f"FLOW-6A public symbol {symbol!r} is outside the exact approved effects package surface",
        ))
    for match in flow6c_v2_public_symbol_pattern(config).finditer(text):
        # FLOW-7 orchestration may bind the approved neutral authorization
        # records by reference; every other package remains outside this exact
        # authorization surface.
        if flow6c_v2_surface or flow7a_surface:
            continue
        symbol = match.group(1)
        findings.append(Finding(
            path, line_of(text, match.start()), "SCOPE011",
            f"FLOW-6C V2 public symbol {symbol!r} is outside the exact approved authorization package surface",
        ))
    for match in flow7a_public_symbol_pattern(config).finditer(text):
        if flow7a_surface:
            continue
        symbol = match.group(1)
        # FLOW-6 effects own the retry proposal/result evidence that FLOW-7
        # consumes. Permit only the three neutral symbols that are deliberately
        # shared by those exact registered surfaces; all other FLOW-7 symbols
        # remain forbidden outside orchestration.
        if flow6a_surface and symbol in {
            "RetryPlanProposalV2",
            "RetryPlanProposalV2::decode",
            "retry_child_attempt_request_ref_v2",
        }:
            continue
        findings.append(Finding(
            path, line_of(text, match.start()), "SCOPE009",
            f"FLOW-7A public symbol {symbol!r} is outside the exact approved orchestration package surface",
        ))
    if flow3_surface and path.endswith(".mbti"):
        add_matches(
            findings,
            path,
            text,
            FLOW4_PLUS_PUBLIC,
            "SCOPE002",
            "FLOW-4+ public contract is forbidden in the FLOW-3 interface",
        )
        add_matches(
            findings,
            path,
            text,
            PUBLIC_SIDE_EFFECT_METHOD,
            "API002",
            "FLOW-3 public interface exposes a state-changing operation",
        )
    push = text.find("applied_events.push(event)")
    if push >= 0:
        prefix = text[:push]
        if "previous.event_id == event.event_id" not in prefix or "previous == event" not in prefix:
            findings.append(
                Finding(
                    path,
                    line_of(text, push),
                    "IDEM001",
                    "event application appends without exact-duplicate/content-conflict guard",
                )
            )
    if Path(path).name == "boundary.mbt":
        anchors = [
            'workspace_root.has_prefix("/")',
            'candidate.has_prefix("/")',
            'path.has_prefix(root + "/")',
            'value.has_prefix("/")',
            'segment == ".."',
            'segment == ""',
        ]
        if any(anchor not in text for anchor in anchors):
            findings.append(
                Finding(
                    path,
                    1,
                    "PATH001",
                    "workspace/artifact lexical containment guards are incomplete",
                )
            )
    if path == "cmd/main/main.mbt" and "validate_artifact_ref" in text:
        anchors = [
            "@fs.exists(artifact_path)",
            "@fs.realpath(@moonflow.normalize_workspace_path(workspace))",
            "@fs.realpath(artifact_path)",
            "@moonflow.path_is_within_workspace(root, canonical_artifact)",
        ]
        if any(anchor not in text for anchor in anchors):
            findings.append(
                Finding(
                    path,
                    line_of(text, text.find("validate_artifact_ref")),
                    "PATH002",
                    "native CLI existence/realpath containment guards are incomplete",
                )
            )
    return findings


def serialized_pairs(value: Any, prefix: str = "$") -> Iterable[tuple[str, str, Any]]:
    if isinstance(value, dict):
        for key in sorted(value):
            child = f"{prefix}.{key}"
            yield child, str(key), value[key]
            yield from serialized_pairs(value[key], child)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from serialized_pairs(item, f"{prefix}[{index}]")


def scan_serialized(path: str, text: str) -> list[Finding]:
    findings: list[Finding] = []
    try:
        value = json.loads(text) if path.endswith(".json") else None
    except json.JSONDecodeError:
        value = None
    if value is not None:
        for location, key, item in serialized_pairs(value):
            lowered = key.lower()
            if lowered in {
                "password",
                "passwd",
                "api_key",
                "access_key",
                "access_token",
                "secret",
                "token",
                "private_key",
            }:
                findings.append(
                    Finding(
                        path,
                        1,
                        "SEC001",
                        f"credential/secret-like serialized field at {location}",
                    )
                )
            if isinstance(item, str) and CREDENTIAL_VALUE.search(item):
                findings.append(
                    Finding(
                        path,
                        1,
                        "SEC002",
                        f"credential-shaped serialized value at {location}",
                    )
                )
    else:
        add_matches(
            findings,
            path,
            text,
            CREDENTIAL_VALUE,
            "SEC002",
            "credential-shaped material in serialized fixture",
        )
    return findings


def hash_findings(config: dict[str, Any]) -> list[Finding]:
    findings: list[Finding] = []
    for section, rule, reason in [
        ("runtime_files", "SRC001", "frozen production runtime source drift"),
        ("manifest_files", "SRC001", "frozen module/package manifest drift"),
        ("interface_files", "API001", "generated public-interface drift"),
        ("fixture_files", "GOLD001", "frozen v2 fixture/golden drift"),
    ]:
        for path, expected in sorted(config[section].items()):
            absolute = ROOT / path
            actual = sha256(absolute) if absolute.is_file() else "missing"
            if actual != expected:
                findings.append(
                    Finding(path, 1, rule, f"{reason}: expected {expected}, got {actual}")
                )
    authorization_v2 = flow6c_v2_config(config)
    for section, rule, reason in [
        ("production_files", "SRC010", "approved FLOW-6C V2 production source drift"),
        ("test_files", "TEST005", "approved FLOW-6C V2 test source drift"),
        ("manifest_files", "SRC010", "approved FLOW-6C V2 package manifest drift"),
        ("interface_files", "API010", "approved FLOW-6C V2 public-interface drift"),
    ]:
        for path, expected in sorted(authorization_v2.get(section, {}).items()):
            absolute = ROOT / path
            actual = sha256(absolute) if absolute.is_file() else "missing"
            if actual != expected:
                findings.append(
                    Finding(path, 1, rule, f"{reason}: expected {expected}, got {actual}")
                )

    contract = flow3_config(config)
    for section, rule, reason in [
        ("production_files", "SRC003", "approved FLOW-3 production source drift"),
        ("test_files", "TEST001", "approved FLOW-3 test source drift"),
        ("manifest_files", "SRC003", "approved FLOW-3 package manifest drift"),
        ("interface_files", "API003", "approved FLOW-3 public-interface drift"),
    ]:
        for path, expected in sorted(contract.get(section, {}).items()):
            absolute = ROOT / path
            actual = sha256(absolute) if absolute.is_file() else "missing"
            if actual != expected:
                findings.append(
                    Finding(path, 1, rule, f"{reason}: expected {expected}, got {actual}")
                )
    storage = flow4a_config(config)
    for section, rule, reason in [
        ("production_files", "SRC004", "approved FLOW-4A production source drift"),
        ("test_files", "TEST002", "approved FLOW-4A test source drift"),
        ("manifest_files", "SRC004", "approved FLOW-4A package manifest drift"),
        ("interface_files", "API004", "approved FLOW-4A public-interface drift"),
    ]:
        for path, expected in sorted(storage.get(section, {}).items()):
            absolute = ROOT / path
            actual = sha256(absolute) if absolute.is_file() else "missing"
            if actual != expected:
                findings.append(
                    Finding(path, 1, rule, f"{reason}: expected {expected}, got {actual}")
                )
    governance = flow5a_config(config)
    for section, rule, reason in [
        ("production_files", "SRC006", "approved FLOW-5A production source drift"),
        ("test_files", "TEST003", "approved FLOW-5A test/conformance drift"),
        ("manifest_files", "SRC006", "approved FLOW-5A package manifest drift"),
        ("interface_files", "API005", "approved FLOW-5A public-interface drift"),
    ]:
        for path, expected in sorted(governance.get(section, {}).items()):
            absolute = ROOT / path
            actual = sha256(absolute) if absolute.is_file() else "missing"
            if actual != expected:
                findings.append(
                    Finding(path, 1, rule, f"{reason}: expected {expected}, got {actual}")
                )
    effects = flow6a_config(config)
    for section, rule, reason in [
        ("production_files", "SRC007", "approved FLOW-6A production source drift"),
        ("test_files", "TEST004", "approved FLOW-6A test/conformance drift"),
        ("manifest_files", "SRC007", "approved FLOW-6A package manifest drift"),
        ("interface_files", "API007", "approved FLOW-6A public-interface drift"),
    ]:
        for path, expected in sorted(effects.get(section, {}).items()):
            absolute = ROOT / path
            actual = sha256(absolute) if absolute.is_file() else "missing"
            if actual != expected:
                findings.append(
                    Finding(path, 1, rule, f"{reason}: expected {expected}, got {actual}")
                )
    orchestration = flow7a_config(config)
    for section, rule, reason in [
        ("production_files", "SRC009", "approved FLOW-7A production source drift"),
        ("test_files", "TEST005", "approved FLOW-7A test/conformance drift"),
        ("manifest_files", "SRC009", "approved FLOW-7A package manifest drift"),
        ("interface_files", "API009", "approved FLOW-7A public-interface drift"),
    ]:
        for path, expected in sorted(orchestration.get(section, {}).items()):
            absolute = ROOT / path
            actual = sha256(absolute) if absolute.is_file() else "missing"
            if actual != expected:
                findings.append(
                    Finding(path, 1, rule, f"{reason}: expected {expected}, got {actual}")
                )
    inventory_items: list[tuple[str, str]] = []
    for section in ("production_files", "test_files", "manifest_files", "interface_files"):
        inventory_items.extend(sorted(orchestration.get(section, {}).items()))
    inventory_bytes = b"".join(
        path.encode("utf-8") + b"\0" + digest.encode("ascii") + b"\n"
        for path, digest in inventory_items
    )
    actual_inventory_digest = hashlib.sha256(inventory_bytes).hexdigest()
    expected_inventory_digest = orchestration.get("inventory_digest", "missing")
    if actual_inventory_digest != expected_inventory_digest:
        findings.append(Finding(
            "conformance/boundary-rules.json", 1, "API009",
            "FLOW-7A inventory digest mismatch: expected "
            f"{expected_inventory_digest}, got {actual_inventory_digest}",
        ))
    return findings


def repository_anchor_findings() -> list[Finding]:
    path = "cmd/main/main.mbt"
    text = (ROOT / path).read_text(encoding="utf-8")
    anchors = [
        "@fs.exists(artifact_path)",
        "@fs.realpath(@moonflow.normalize_workspace_path(workspace))",
        "@fs.realpath(artifact_path)",
        "@moonflow.path_is_within_workspace(root, canonical_artifact)",
    ]
    if any(anchor not in text for anchor in anchors):
        return [
            Finding(
                path,
                68,
                "PATH002",
                "native CLI existence/realpath containment guards are incomplete",
            )
        ]
    return []


def scan_repository(config: dict[str, Any]) -> list[Finding]:
    findings = hash_findings(config) + repository_anchor_findings()
    term_allowlist = set(config["term_path_allowlist"])
    negative_fixtures = {
        case["fixture"] for case in config["self_tests"]
        if case.get("exclude_from_repository", True)
    }
    files = project_files()
    production_sources = {
        path.as_posix()
        for path in files
        if is_production_source(path.as_posix(), negative_fixtures)
    }
    expected_sources = (
        set(config["runtime_files"])
        | flow3_production_paths(config)
        | flow4a_production_paths(config)
        | flow5a_production_paths(config)
        | flow6a_production_paths(config)
        | flow7a_production_paths(config)
        | flow6c_v2_production_files(config)
    )
    for path in sorted(production_sources - expected_sources):
        findings.append(
            Finding(
                path,
                1,
                "SRC002",
                "new production MoonBit source is outside the FLOW-2 frozen baseline",
            )
        )
    native_sources = {
        path.as_posix()
        for path in files
        if path.suffix in {".c", ".h"}
    }
    expected_native_sources = {
        path
        for path in flow4a_production_paths(config)
        if Path(path).suffix in {".c", ".h"}
    }
    for path in sorted(native_sources - expected_native_sources):
        findings.append(
            Finding(
                path,
                1,
                "SRC005",
                "new production C source is outside the exact FLOW-4A storage surface",
            )
        )
    for relative in files:
        path = relative.as_posix()
        if path in negative_fixtures or path in term_allowlist:
            continue
        suffix = relative.suffix
        if relative.name in {"moon.mod", "moon.pkg"}:
            text = (ROOT / relative).read_text(encoding="utf-8")
            findings.extend(scan_manifest(path, text))
        if suffix in {".mbt", ".mbti"}:
            text = (ROOT / relative).read_text(encoding="utf-8")
            production = path.endswith(".mbti") or path in production_sources
            findings.extend(
                scan_source_or_interface(
                    path,
                    text,
                    config,
                    production=production,
                    flow3_surface=is_flow3_contract_surface(path, config),
                    flow4a_surface=is_flow4a_storage_surface(path, config),
                    flow5a_surface=is_flow5a_governance_surface(path, config),
                    flow6a_surface=is_flow6a_effects_surface(path, config),
                    flow6c_v2_surface=is_flow6c_v2_authorization_surface(path, config),
                    flow7a_surface=is_flow7a_orchestration_surface(path, config),
                )
            )
        if suffix in SERIALIZED_SUFFIXES:
            text = (ROOT / relative).read_text(encoding="utf-8")
            findings.extend(scan_serialized(path, text))
    return sorted(set(findings))


def scan_virtual(path: str, text: str, config: dict[str, Any]) -> list[Finding]:
    findings: list[Finding] = []
    name = Path(path).name
    if name in {"moon.mod", "moon.pkg"}:
        findings.extend(scan_manifest(path, text))
    if path.endswith((".mbt", ".mbti")):
        findings.extend(
            scan_source_or_interface(
                path,
                text,
                config,
                production=True,
                flow3_surface=is_flow3_contract_surface(path, config),
                flow4a_surface=is_flow4a_storage_surface(path, config),
                flow5a_surface=is_flow5a_governance_surface(path, config),
                flow6a_surface=is_flow6a_effects_surface(path, config),
                flow6c_v2_surface=is_flow6c_v2_authorization_surface(path, config),
                flow7a_surface=is_flow7a_orchestration_surface(path, config),
            )
        )
    if Path(path).suffix in SERIALIZED_SUFFIXES:
        findings.extend(scan_serialized(path, text))
    return sorted(set(findings))


def scope_symbols_from_findings(
    findings: Iterable[Finding],
    rule: str,
    reason_pattern: re.Pattern[str],
) -> list[str]:
    symbols: list[str] = []
    for finding in findings:
        if finding.rule != rule:
            continue
        match = reason_pattern.search(finding.reason)
        if match:
            symbols.append(match.group(1))
    return symbols


def assert_scope_coverage(
    label: str,
    findings: list[Finding],
    expected: frozenset[str],
    rule: str,
    reason_pattern: re.Pattern[str],
) -> list[str]:
    observed = scope_symbols_from_findings(findings, rule, reason_pattern)
    if len(observed) == len(expected) and set(observed) == expected:
        return []
    missing = sorted(expected - set(observed))
    extra = sorted(set(observed) - expected)
    return [
        f"{label}: expected exactly {len(expected)} {rule} public-symbol "
        f"matches, observed {len(observed)}; missing {missing}; extra {extra}"
    ]


def self_test(config: dict[str, Any]) -> int:
    failures: list[str] = []
    covered: set[str] = set()
    expected_flow3_symbols = flow3_public_symbols(config)
    expected_flow4a_symbols = flow4a_public_symbols(config)
    expected_flow5a_symbols = flow5a_public_symbols(config)
    expected_flow6a_symbols = flow6a_public_symbols(config)
    expected_flow6c_v2_symbols = flow6c_v2_public_symbols(config)
    expected_flow7a_symbols = flow7a_public_symbols(config)
    individually_covered_flow3_symbols: set[str] = set()
    individually_covered_flow4a_symbols: set[str] = set()
    individually_covered_flow5a_symbols: set[str] = set()
    individually_covered_flow6a_symbols: set[str] = set()
    individually_covered_flow6c_v2_symbols: set[str] = set()
    individually_covered_flow7a_symbols: set[str] = set()
    approved_flow3_clean_surfaces = 0
    approved_flow4a_clean_surfaces = 0
    approved_flow5a_clean_surfaces = 0
    approved_flow6a_clean_surfaces = 0
    approved_flow6c_v2_clean_surfaces = 0
    approved_flow7a_clean_surfaces = 0
    for case in config["self_tests"]:
        fixture = ROOT / case["fixture"]
        expected = case["rule"]
        case_findings: list[Finding] = []
        if expected == "SRC001":
            actual = sha256(fixture)
            baseline = config["runtime_files"][case["virtual_path"]]
            rules = {"SRC001"} if actual != baseline else set()
        elif expected == "API001":
            actual = sha256(fixture)
            baseline = config["interface_files"][case["virtual_path"]]
            rules = {"API001"} if actual != baseline else set()
        elif expected == "SRC002":
            allowed_sources = (
                set(config["runtime_files"])
                | flow3_production_paths(config)
                | flow4a_production_paths(config)
                | flow5a_production_paths(config)
                | flow6a_production_paths(config)
                | flow6c_v2_production_files(config)
                | flow7a_production_paths(config)
            )
            rules = (
                {"SRC002"}
                if case["virtual_path"] not in allowed_sources
                else set()
            )
        elif expected == "GOLD001":
            actual = sha256(fixture)
            baseline = config["fixture_files"][case["virtual_path"]]
            rules = {"GOLD001"} if actual != baseline else set()
        else:
            text = fixture.read_text(encoding="utf-8")
            if case.get("mechanical_symbols") == "flow6a":
                text = "\n".join(sorted(expected_flow6a_symbols))
            if case.get("mechanical_symbols") == "flow4a":
                text = "\n".join(sorted(expected_flow4a_symbols))
            if case.get("mechanical_symbols") == "flow6c_v2":
                text = "\n".join(sorted(expected_flow6c_v2_symbols))
            if case.get("mechanical_symbols") == "flow7a":
                text = "\n".join(sorted(expected_flow7a_symbols))
            case_findings = scan_virtual(case["virtual_path"], text, config)
            rules = {finding.rule for finding in case_findings}
        if expected not in rules:
            failures.append(
                f"{case['fixture']}: expected {expected}, observed {sorted(rules)}"
            )
        else:
            covered.add(expected)
        if case.get("scope_symbols") == "all_flow3_public":
            failures.extend(
                assert_scope_coverage(
                    case["fixture"],
                    case_findings,
                    expected_flow3_symbols,
                    "SCOPE001",
                    FLOW3_SCOPE_REASON,
                )
            )
            for symbol in sorted(expected_flow3_symbols):
                individual_findings = scan_virtual(
                    case["virtual_path"], symbol, config
                )
                observed = scope_symbols_from_findings(
                    individual_findings, "SCOPE001", FLOW3_SCOPE_REASON
                )
                if observed != [symbol]:
                    failures.append(
                        f"{case['fixture']}: individual SCOPE001 proof for "
                        f"{symbol!r} observed {observed}"
                    )
                else:
                    individually_covered_flow3_symbols.add(symbol)
        if case.get("scope_symbols") == "all_flow4a_public":
            failures.extend(
                assert_scope_coverage(
                    case["fixture"],
                    case_findings,
                    expected_flow4a_symbols,
                    "SCOPE003",
                    FLOW4A_SCOPE_REASON,
                )
            )
            for symbol in sorted(expected_flow4a_symbols):
                individual_findings = scan_virtual(
                    case["virtual_path"], symbol, config
                )
                observed = scope_symbols_from_findings(
                    individual_findings, "SCOPE003", FLOW4A_SCOPE_REASON
                )
                if observed != [symbol]:
                    failures.append(
                        f"{case['fixture']}: individual SCOPE003 proof for "
                        f"{symbol!r} observed {observed}"
                    )
                else:
                    individually_covered_flow4a_symbols.add(symbol)
        if case.get("scope_symbols") == "all_flow5a_public":
            failures.extend(
                assert_scope_coverage(
                    case["fixture"],
                    case_findings,
                    expected_flow5a_symbols,
                    "SCOPE005",
                    FLOW5A_SCOPE_REASON,
                )
            )
            for symbol in sorted(expected_flow5a_symbols):
                individual_findings = scan_virtual(
                    case["virtual_path"], symbol, config
                )
                observed = scope_symbols_from_findings(
                    individual_findings, "SCOPE005", FLOW5A_SCOPE_REASON
                )
                if observed != [symbol]:
                    failures.append(
                        f"{case['fixture']}: individual SCOPE005 proof for "
                        f"{symbol!r} observed {observed}"
                    )
                else:
                    individually_covered_flow5a_symbols.add(symbol)
        if case.get("scope_symbols") == "all_flow6a_public":
            failures.extend(
                assert_scope_coverage(
                    case["fixture"], case_findings, expected_flow6a_symbols,
                    "SCOPE007", FLOW6A_SCOPE_REASON,
                )
            )
            for symbol in sorted(expected_flow6a_symbols):
                individual_findings = scan_virtual(
                    case["virtual_path"], symbol, config
                )
                observed = scope_symbols_from_findings(
                    individual_findings, "SCOPE007", FLOW6A_SCOPE_REASON
                )
                if observed != [symbol]:
                    failures.append(
                        f"{case['fixture']}: individual SCOPE007 proof for "
                        f"{symbol!r} observed {observed}"
                    )
                else:
                    individually_covered_flow6a_symbols.add(symbol)
        if case.get("scope_symbols") == "all_flow6c_v2_public":
            failures.extend(
                assert_scope_coverage(
                    case["fixture"], case_findings, expected_flow6c_v2_symbols,
                    "SCOPE011", FLOW6C_V2_SCOPE_REASON,
                )
            )
            for symbol in sorted(expected_flow6c_v2_symbols):
                individual_findings = scan_virtual(
                    case["virtual_path"], symbol, config
                )
                observed = scope_symbols_from_findings(
                    individual_findings, "SCOPE011", FLOW6C_V2_SCOPE_REASON
                )
                if observed != [symbol]:
                    failures.append(
                        f"{case['fixture']}: individual SCOPE011 proof for "
                        f"{symbol!r} observed {observed}"
                    )
                else:
                    individually_covered_flow6c_v2_symbols.add(symbol)
        if case.get("scope_symbols") == "all_flow7a_public":
            failures.extend(
                assert_scope_coverage(
                    case["fixture"], case_findings, expected_flow7a_symbols,
                    "SCOPE009", FLOW7A_SCOPE_REASON,
                )
            )
            for symbol in sorted(expected_flow7a_symbols):
                individual_findings = scan_virtual(case["virtual_path"], symbol, config)
                observed = scope_symbols_from_findings(
                    individual_findings, "SCOPE009", FLOW7A_SCOPE_REASON
                )
                if observed != [symbol]:
                    failures.append(
                        f"{case['fixture']}: individual SCOPE009 proof for "
                        f"{symbol!r} observed {observed}"
                    )
                else:
                    individually_covered_flow7a_symbols.add(symbol)
    for case in config.get("clean_self_tests", []):
        fixture = ROOT / case["fixture"]
        text = fixture.read_text(encoding="utf-8")
        findings = scan_virtual(case["virtual_path"], text, config)
        if findings:
            failures.append(
                f"{case['fixture']}: expected no findings, observed "
                + "; ".join(finding.render() for finding in findings)
            )
        outside_path = case.get("outside_virtual_path")
        if outside_path:
            outside_text = text
            if case.get("mechanical_symbols") == "flow6a":
                outside_text = "\n".join(sorted(expected_flow6a_symbols))
            if case.get("mechanical_symbols") == "flow4a":
                outside_text = "\n".join(sorted(expected_flow4a_symbols))
            if case.get("mechanical_symbols") == "flow6c_v2":
                outside_text = "\n".join(sorted(expected_flow6c_v2_symbols))
            if case.get("mechanical_symbols") == "flow7a":
                outside_text = "\n".join(sorted(expected_flow7a_symbols))
            outside_findings = scan_virtual(outside_path, outside_text, config)
            scope_contract = case.get("scope_contract", "flow3")
            if scope_contract == "flow4a":
                approved_flow4a_clean_surfaces += 1
                expected_symbols = expected_flow4a_symbols
                scope_rule = "SCOPE003"
                reason_pattern = FLOW4A_SCOPE_REASON
            elif scope_contract == "flow5a":
                approved_flow5a_clean_surfaces += 1
                expected_symbols = expected_flow5a_symbols
                scope_rule = "SCOPE005"
                reason_pattern = FLOW5A_SCOPE_REASON
            elif scope_contract == "flow6a":
                approved_flow6a_clean_surfaces += 1
                expected_symbols = expected_flow6a_symbols
                scope_rule = "SCOPE007"
                reason_pattern = FLOW6A_SCOPE_REASON
            elif scope_contract == "flow6c_v2":
                approved_flow6c_v2_clean_surfaces += 1
                expected_symbols = expected_flow6c_v2_symbols
                scope_rule = "SCOPE011"
                reason_pattern = FLOW6C_V2_SCOPE_REASON
            elif scope_contract == "flow7a":
                approved_flow7a_clean_surfaces += 1
                expected_symbols = expected_flow7a_symbols
                scope_rule = "SCOPE009"
                reason_pattern = FLOW7A_SCOPE_REASON
            else:
                approved_flow3_clean_surfaces += 1
                expected_symbols = expected_flow3_symbols
                scope_rule = "SCOPE001"
                reason_pattern = FLOW3_SCOPE_REASON
            failures.extend(
                assert_scope_coverage(
                    f"{case['fixture']} outside exact approved path",
                    outside_findings,
                    expected_symbols,
                    scope_rule,
                    reason_pattern,
                )
            )
    real_findings = scan_repository(config)
    if real_findings:
        failures.append("real repository scan produced findings during self-test")
        failures.extend(finding.render() for finding in real_findings)
    if failures:
        for failure in failures:
            print(f"SELFTEST: {failure}", file=sys.stderr)
        return 1
    print(
        "FLOW-7A scanner self-test: PASS "
        f"({len(config['self_tests'])} negative fixtures; rules "
        f"{', '.join(sorted(covered))}; "
        f"{len(config.get('clean_self_tests', []))} clean fixtures; "
        f"{approved_flow3_clean_surfaces} approved FLOW-3 clean surface with "
        f"{len(expected_flow3_symbols)} symbols; "
        f"{approved_flow4a_clean_surfaces} approved FLOW-4A clean surface with "
        f"{len(expected_flow4a_symbols)} symbols; "
        f"{approved_flow5a_clean_surfaces} approved FLOW-5A clean surface with "
        f"{len(expected_flow5a_symbols)} symbols; "
        f"{approved_flow6a_clean_surfaces} approved FLOW-6A clean surface with "
        f"{len(expected_flow6a_symbols)} symbols; "
        f"{approved_flow6c_v2_clean_surfaces} approved FLOW-6C V2 clean surface with "
        f"{len(expected_flow6c_v2_symbols)} symbols; "
        f"{approved_flow7a_clean_surfaces} approved FLOW-7A clean surface with "
        f"{len(expected_flow7a_symbols)} symbols; "
        f"{len(individually_covered_flow3_symbols)}/{len(expected_flow3_symbols)} "
        "FLOW-3 public symbols individually covered; "
        f"{len(individually_covered_flow4a_symbols)}/{len(expected_flow4a_symbols)} "
        "FLOW-4A public symbols individually covered; "
        f"{len(individually_covered_flow5a_symbols)}/{len(expected_flow5a_symbols)} "
        "FLOW-5A public symbols individually covered; "
        f"{len(individually_covered_flow6a_symbols)}/{len(expected_flow6a_symbols)} "
        "FLOW-6A public symbols individually covered; "
        f"{len(individually_covered_flow6c_v2_symbols)}/{len(expected_flow6c_v2_symbols)} "
        "FLOW-6C V2 public symbols individually covered; "
        f"{len(individually_covered_flow7a_symbols)}/{len(expected_flow7a_symbols)} "
        "FLOW-7A public symbols individually covered; "
        "real allowlisted data clean)"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["scan", "self-test"], nargs="?", default="scan")
    args = parser.parse_args()
    config = load_config()
    if args.command == "self-test":
        return self_test(config)
    findings = scan_repository(config)
    if findings:
        for finding in findings:
            print(finding.render(), file=sys.stderr)
        print(f"FLOW-7A boundary scan: FAIL ({len(findings)} findings)", file=sys.stderr)
        return 1
    files = project_files()
    production_count = sum(
        1
        for path in files
        if is_production_source(
            path.as_posix(), {case["fixture"] for case in config["self_tests"]}
        )
    )
    fixture_count = sum(1 for path in files if path.suffix in SERIALIZED_SUFFIXES)
    print(
        "FLOW-7A boundary scan: PASS "
        f"({len(config['runtime_files'])} frozen production sources; "
        f"{len(flow3_production_paths(config))} approved FLOW-3 sources; "
        f"{len(flow4a_production_paths(config))} approved FLOW-4A sources; "
        f"{len(flow5a_production_paths(config))} approved FLOW-5A sources; "
        f"{len(flow6a_production_paths(config))} approved FLOW-6A sources; "
        f"{len(flow7a_production_paths(config))} approved FLOW-7A sources; "
        f"{production_count} total production sources; {fixture_count} serialized files)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
