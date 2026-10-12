#!/usr/bin/env python3
"""Export one pending MoonFlow result and its criteria as a portable review ZIP."""
import argparse
from datetime import datetime, timezone
import hashlib
import html
import io
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import zipfile

MAX_RESPONSE = 8 * 1024 * 1024
MAX_FILE = 16 * 1024 * 1024
MAX_TOTAL = 64 * 1024 * 1024
MAX_ARTIFACTS = 128


class PacketError(Exception):
    """The requested result cannot currently be exported for review."""


def digest(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def invoke(cli, arguments, timeout):
    try:
        result = subprocess.run([str(cli), *arguments], stdin=subprocess.DEVNULL,
                                capture_output=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        raise PacketError("native read timed out; no packet was published") from error
    if result.returncode:
        detail = (result.stderr or result.stdout).decode("utf-8", errors="replace")[:2000]
        raise PacketError(f"native read exited {result.returncode}: {detail.strip()}")
    if len(result.stdout) > MAX_RESPONSE:
        raise PacketError("native response exceeds 8 MiB")
    try:
        value = json.loads(result.stdout.decode("utf-8"))
    except (ValueError, UnicodeError) as error:
        raise PacketError("native read did not return one complete UTF-8 JSON object") from error
    if not isinstance(value, dict):
        raise PacketError("native read must return a JSON object")
    return value, result.stdout


def select_item(projection, run_id, item_id):
    if (projection.get("protocol") != "moonflow.run-projection.v3"
            or projection.get("run_id") != run_id
            or type(projection.get("last_sequence")) is not int
            or projection["last_sequence"] < 0
            or not isinstance(projection.get("items"), list)):
        raise PacketError("status is not the selected imported run projection")
    matches = [item for item in projection["items"]
               if isinstance(item, dict) and item.get("work_item_id") == item_id]
    if len(matches) != 1:
        raise PacketError("select exactly one recorded work item")
    item = matches[0]
    if item.get("status") != "review" or item.get("attempt_status") != "succeeded":
        raise PacketError("item must be awaiting review with a succeeded current attempt")
    for name in ("declaration_id", "product_id", "request_id", "active_attempt_id",
                 "idempotency_key", "input_digest", "result_id", "output_digest"):
        if not isinstance(item.get(name), str) or not item[name].strip():
            raise PacketError(f"current result is missing {name}")
    criteria = item.get("acceptance_criteria")
    if not isinstance(criteria, list) or not criteria or any(
            not isinstance(c, str) or not c.strip() for c in criteria):
        raise PacketError("current item has no complete original acceptance criteria")
    return item


def current_result(history, projection, item):
    head = history.get("head")
    if (history.get("contract_id") != "moonflow.run-history.v1"
            or history.get("selected_work_item_id") != item["work_item_id"]
            or not isinstance(head, dict) or not isinstance(history.get("entries"), list)):
        raise PacketError("history is not the selected item's canonical timeline")
    for name in ("run_id", "book_id", "declaration_revision", "source_digest", "last_sequence"):
        if head.get(name) != projection.get(name) or name not in head:
            raise PacketError("status and history have different run revisions or event heads")
    if head.get("run_outcome") != projection.get("outcome"):
        raise PacketError("status and history have different outcomes")
    matches = []
    for entry in history["entries"]:
        event = entry.get("event") if isinstance(entry, dict) else None
        if not isinstance(event, dict) or event.get("work_item_id") != item["work_item_id"]:
            raise PacketError("history includes malformed or unselected item events")
        if (event.get("kind") == "attempt-reconciled"
                and event.get("attempt_status") == "succeeded"
                and event.get("attempt_id") == item["active_attempt_id"]
                and event.get("result_id") == item["result_id"]):
            for name in ("request_id", "idempotency_key", "input_digest", "output_digest",
                         "declaration_id", "product_id", "acceptance_criteria"):
                if event.get(name) != item[name]:
                    raise PacketError(f"current result history differs in {name}")
            for name in ("run_id", "book_id", "declaration_revision", "source_digest"):
                if event.get(name) != head[name]:
                    raise PacketError(f"current result history differs in {name}")
            matches.append(event)
    if len(matches) != 1:
        raise PacketError("one current successful result event is required; reused checkpoints are unsupported")
    event = matches[0]
    refs = event.get("output_artifacts")
    if (not isinstance(refs, list) or not 1 <= len(refs) <= MAX_ARTIFACTS
            or any(not isinstance(ref, str) or not ref for ref in refs)
            or len(set(refs)) != len(refs)):
        raise PacketError("current result must name 1 through 128 distinct output artifacts")
    return event


def read_artifact(workspace, ref):
    # Only exact portable relative references; never archive an arbitrary user path.
    parts = PurePosixPath(ref).parts
    if (ref.startswith("/") or "\\" in ref or not parts or any(p in {".", ".."} for p in ref.split("/"))
            or any(ord(c) < 32 for c in ref)):
        raise PacketError(f"output is not a portable workspace-relative reference: {ref!r}")
    path = workspace.joinpath(*parts).resolve(strict=True)
    if not path.is_relative_to(workspace) or not path.is_file():
        raise PacketError(f"output escapes the workspace or is not a file: {ref!r}")
    with path.open("rb") as source:
        data = source.read(MAX_FILE + 1)
    if len(data) > MAX_FILE:
        raise PacketError(f"output exceeds 16 MiB: {ref!r}")
    return data


def review_index(manifest):
    esc = lambda value: html.escape(str(value), quote=True)
    item, head = manifest["item"], manifest["head"]
    identities = [("Run", head["run_id"]), ("Work item", item["work_item_id"]),
                  ("Book", head["book_id"]), ("Declaration revision", head["declaration_revision"]),
                  ("Event head", f'{head["last_sequence"]}: {head.get("last_event_id", "")}'),
                  ("Attempt", item["active_attempt_id"]), ("Result", item["result_id"]),
                  ("Recorded output digest", item["output_digest"]),
                  ("Packet recorded at", manifest["recorded_at"])]
    details = "".join(f"<dt>{esc(k)}</dt><dd>{esc(v)}</dd>" for k, v in identities)
    criteria = "".join(f"<li>{esc(c)}</li>" for c in item["acceptance_criteria"])
    outputs = "".join(f'<li><a href="{a["packet_path"]}">{esc(a["artifact_ref"])}</a>'
                      f' ({a["size_bytes"]} bytes)<br><small>{esc(a["sha256"])}</small></li>'
                      for a in manifest["artifacts"])
    return ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
            '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'">'
            "<title>MoonFlow pending result review</title><style>body{font:16px system-ui;max-width:850px;"
            "margin:3em auto;padding:0 1em}dd{margin-bottom:.7em;overflow-wrap:anywhere}li{margin:.8em 0}"
            "small{overflow-wrap:anywhere}</style></head><body><h1>Pending result review</h1>"
            "<p>This result is awaiting internal review. Exporting or opening this packet does not accept "
            "the work, grant authority, establish customer approval, or record payment.</p>"
            f"<h2>Identity</h2><dl>{details}</dl><h2>Original acceptance criteria</h2><ol>{criteria}</ol>"
            f"<h2>Current result outputs</h2><ol>{outputs}</ol>"
            "<p>The original bytes above match the recorded ordered output digest. Files are untrusted "
            "adapter outputs; inspect them with an appropriate viewer and do not execute them.</p>"
            '<h2>Evidence and next step</h2><p><a href="manifest.json">Packet manifest</a> · '
            '<a href="history.json">Selected item timeline</a></p>'
            "<p>Keep notes separately. Return to the canonical MoonFlow host and reload this exact run, "
            "attempt and result before using its existing governed review-outcome action. This packet "
            "is an observation and may now be stale. It contains no review decision or importable approval.</p>"
            "</body></html>\n").encode("utf-8")


def prepare_packet(cli, workspace, run_id, item_id, timeout, recorded_at):
    before, _ = invoke(cli, ["status", str(workspace), run_id], timeout)
    item = select_item(before, run_id, item_id)
    history, history_bytes = invoke(cli, ["run-history", str(workspace), run_id, "--json", item_id], timeout)
    event = current_result(history, before, item)
    artifacts, members, total = [], {}, 0
    for ordinal, ref in enumerate(event["output_artifacts"], start=1):
        data = read_artifact(workspace, ref)
        total += len(data)
        if total > MAX_TOTAL:
            raise PacketError("current result outputs exceed 64 MiB in total")
        suffix = PurePosixPath(ref).suffix
        suffix = suffix if re.fullmatch(r"\.[A-Za-z0-9]{1,12}", suffix) else ".bin"
        packet_path = f"artifacts/output-{ordinal:04d}{suffix}"
        members[packet_path] = data
        artifacts.append({"artifact_ref": ref, "packet_path": packet_path,
                          "size_bytes": len(data), "sha256": digest(data)})
    # This is the existing native declared_input_digest algorithm, in declared order.
    observed = digest("\n".join(f'{a["artifact_ref"]}|{a["sha256"]}' for a in artifacts).encode("utf-8"))
    if observed != item["output_digest"]:
        raise PacketError("output bytes do not match the recorded result digest; reload and investigate")
    after, _ = invoke(cli, ["status", str(workspace), run_id], timeout)
    if after != before:
        raise PacketError("run changed during export; reload the current result before exporting")
    manifest = {"contract_id": "moonflow.review-packet.v1", "recorded_at": recorded_at,
                "head": history["head"], "item": item, "result_event_id": event["event_id"],
                "artifact_digest_verified": True, "observed_output_digest": observed,
                "history_sha256": digest(history_bytes), "artifacts": artifacts,
                "review_decision": None,
                "limits": "Local observation only; not a review receipt, backup, authority, customer acceptance or payment."}
    members["history.json"] = history_bytes
    members["manifest.json"] = json_bytes(manifest)
    members["index.html"] = review_index(manifest)
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as packet:
        for name, data in members.items():
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.external_attr = 0o100600 << 16
            packet.writestr(info, data)
    return buffer.getvalue(), manifest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workspace", type=Path)
    parser.add_argument("--cli", type=Path, required=True, help="existing trusted native MoonFlow executable")
    parser.add_argument("--run", required=True)
    parser.add_argument("--item", required=True)
    parser.add_argument("--output", type=Path, required=True, help="new local ZIP; never overwritten")
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--recorded-at", help="UTC YYYY-MM-DDTHH:MM:SSZ; defaults to now")
    args = parser.parse_args(argv)
    try:
        if (not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", args.run) or args.run == "." or ".." in args.run
                or not args.item.strip() or len(args.item) > 256):
            raise PacketError("select a safe run ID and one nonblank item ID of at most 256 characters")
        if not math.isfinite(args.timeout) or not .1 <= args.timeout <= 300:
            raise PacketError("timeout must be 0.1 through 300 seconds")
        workspace, cli = args.workspace.resolve(strict=True), args.cli.resolve(strict=True)
        if not workspace.is_dir() or not cli.is_file() or not os.access(cli, os.X_OK):
            raise PacketError("workspace must be a directory and cli an executable file")
        output = args.output.absolute()
        if output.exists() or output.is_symlink():
            raise PacketError("output already exists; choose a new ZIP path")
        if output.resolve().is_relative_to((workspace / ".moonsuite").resolve()):
            raise PacketError("output must be outside the canonical .moonsuite store")
        if not output.parent.is_dir():
            raise PacketError("output parent directory must already exist")
        stamp = args.recorded_at or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        if not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", stamp):
            raise PacketError("recorded-at must be UTC YYYY-MM-DDTHH:MM:SSZ")
        datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ")
        data, manifest = prepare_packet(cli, workspace, args.run, args.item, args.timeout, stamp)
        # All source validation precedes exclusive publication; preserve any old packet.
        fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as destination:
            destination.write(data)
            destination.flush()
            os.fsync(destination.fileno())
        print(json.dumps({"contract_id": "moonflow.review-packet-export.v1", "output": str(output),
                          "sha256": digest(data), "run_id": args.run, "work_item_id": args.item,
                          "result_id": manifest["item"]["result_id"],
                          "artifact_count": len(manifest["artifacts"]), "review_decision": None}))
        return 0
    except (PacketError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"review-packet: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
