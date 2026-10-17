#!/usr/bin/env python3
"""Render a MoonFlow graph-map JSON export as one offline HTML explorer."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import sys
import subprocess

MAX_REPORT = 2 * 1024 * 1024
CONTRACT = "moonflow.declared-graph-map.v1"
ASSETS = Path(__file__).with_name("graph_explorer")


class ExplorerError(ValueError):
    """The selected report cannot be rendered faithfully."""


def require(condition, message):
    if not condition:
        raise ExplorerError(message)


def label(value, name):
    require(isinstance(value, str) and bool(value.strip()) and len(value) <= 16384,
            f"{name} must be a nonblank string of at most 16384 characters")
    # Lone surrogates cannot round-trip through UTF-8 HTML.
    require(not any(0xD800 <= ord(char) <= 0xDFFF for char in value),
            f"{name} must contain Unicode scalar values")
    return value


def validate(report):
    """Validate the exported topology; do not infer work-model/runtime validity."""
    require(isinstance(report, dict) and report.get("contract_id") == CONTRACT,
            f"expected {CONTRACT}")
    label(report.get("graph_id"), "graph_id")
    digest = report.get("source_graph_digest")
    require(isinstance(digest, str) and re.fullmatch(r"sha256:[0-9a-f]{64}", digest),
            "source_graph_digest must be a lowercase SHA-256 identity")
    nodes = report.get("nodes")
    require(isinstance(nodes, list) and 1 <= len(nodes) <= 256,
            "graph map must contain 1..256 nodes")
    by_id = {}
    for node in nodes:
        require(isinstance(node, dict), "each node must be an object")
        identity = label(node.get("work_item_id"), "work_item_id")
        require(identity not in by_id, f"duplicate work item: {identity}")
        label(node.get("product_id"), "product_id")
        label(node.get("operation"), "operation")
        require(type(node.get("layer")) is int and 0 <= node["layer"] < len(nodes),
                "node layer must be an integer in range")
        deps = node.get("depends_on")
        require(isinstance(deps, list) and len(deps) <= len(nodes),
                "depends_on must be a bounded array")
        for dep in deps:
            label(dep, "prerequisite")
        require(len(set(deps)) == len(deps), "exported prerequisites must be unique")
        by_id[identity] = node
    for node in nodes:
        require(all(dep in by_id for dep in node["depends_on"]),
                f"unknown prerequisite of {node['work_item_id']}")
    depths, layers = {}, []
    while len(depths) < len(nodes):
        frontier = [n for n in nodes if n["work_item_id"] not in depths
                    and all(d in depths for d in n["depends_on"])]
        require(bool(frontier), "graph map contains a dependency cycle")
        layer = [n["work_item_id"] for n in frontier]
        layers.append(layer)
        for identity in layer:
            depths[identity] = len(layers) - 1
    require(all(n["layer"] == depths[n["work_item_id"]] for n in nodes),
            "node layers disagree with declared prerequisites")
    require(report.get("layers") == layers, "layers disagree with source-ordered topology")
    consumers = {dep for node in nodes for dep in node["depends_on"]}
    require(report.get("root_item_ids") == [n["work_item_id"] for n in nodes
                                             if not n["depends_on"]],
            "root_item_ids disagree with topology")
    require(report.get("leaf_item_ids") == [n["work_item_id"] for n in nodes
                                             if n["work_item_id"] not in consumers],
            "leaf_item_ids disagree with topology")
    require(type(report.get("edge_count")) is int
            and report["edge_count"] == sum(len(n["depends_on"]) for n in nodes),
            "edge_count disagrees with topology")
    # Carry only this contract's fields. Future annotation keys are not executable data.
    return {"contract_id": CONTRACT, "graph_id": report["graph_id"],
            "source_graph_digest": digest, "nodes": [
                {key: node[key] for key in ("work_item_id", "product_id", "operation", "depends_on", "layer")}
                for node in nodes], "layers": layers, "root_item_ids": report["root_item_ids"],
            "leaf_item_ids": report["leaf_item_ids"], "edge_count": report["edge_count"]}


def reject_duplicates(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read_report(path):
    with Path(path).open("rb") as stream:
        raw = stream.read(MAX_REPORT + 1)
    require(len(raw) <= MAX_REPORT, "graph-map export exceeds 2 MiB")
    try:
        report = json.loads(raw.decode("utf-8"), object_pairs_hook=reject_duplicates,
                            parse_constant=lambda value: (_ for _ in ()).throw(
                                ExplorerError(f"invalid JSON number: {value}")))
    except (UnicodeError, json.JSONDecodeError, RecursionError) as error:
        raise ExplorerError("graph-map export must be complete UTF-8 JSON") from error
    return validate(report), "sha256:" + hashlib.sha256(raw).hexdigest()


def author_source(path, cli):
    """Bind full source bytes to a fresh report from the retained trusted engine."""
    source_path = path.resolve(strict=True)
    cli = cli.resolve(strict=True)
    # This is an executable/source pin, not a replacement native identity algorithm.
    verified = subprocess.run([sys.executable, "-I", "-B", str(Path(__file__).with_name(
        "verify_shared_table_native.py")), "--source", str(Path(__file__).resolve().parents[1]),
        "--cli", str(cli)], capture_output=True, timeout=60)
    require(verified.returncode == 0, "trusted native/source pin verification failed")
    raw = read_source_bytes(source_path)
    try:
        source = json.loads(raw.decode("utf-8"), object_pairs_hook=reject_duplicates,
                            parse_constant=lambda value: (_ for _ in ()).throw(
                                ExplorerError(f"invalid JSON number: {value}")))
    except (UnicodeError, json.JSONDecodeError, RecursionError) as error:
        raise ExplorerError("source graph must be complete UTF-8 JSON") from error
    require(isinstance(source, dict) and source.get("contract_id") == "moonsuite.work-model.v1",
            "authoring requires the original full moonsuite.work-model.v1 graph")
    result = subprocess.run([str(cli), "graph-map", str(source_path.parent), source_path.name,
                             "--json"], capture_output=True, timeout=60)
    require(read_source_bytes(source_path) == raw, "source graph bytes changed during graph-map; export refused")
    require(result.returncode == 0, "native graph-map refused this source graph")
    require(len(result.stdout) <= MAX_REPORT, "native graph-map export exceeds 2 MiB")
    try:
        report = validate(json.loads(result.stdout.decode("utf-8"), object_pairs_hook=reject_duplicates))
    except (UnicodeError, json.JSONDecodeError, RecursionError) as error:
        raise ExplorerError("native graph-map returned invalid JSON") from error
    items = source.get("items")
    require(source.get("graph_id") == report["graph_id"] and isinstance(items, list)
            and len(items) == len(report["nodes"]), "native report differs from full source")
    for item, node in zip(items, report["nodes"]):
        require(isinstance(item, dict) and all(item.get(key) == node[key] for key in
                ("work_item_id", "product_id", "operation", "depends_on")),
                "native report differs from full source declarations")
        for key in ("input_artifacts", "acceptance_criteria"):
            values = item.get(key)
            require(isinstance(values, list) and bool(values)
                    and all(isinstance(v, str) and v.strip() for v in values),
                    f"full source requires {key} string arrays")
        require(type(item.get("timeout_ms")) is int and 1 <= item["timeout_ms"] <= 86400000,
                "full source requires a bounded integer timeout_ms")
    return report, "sha256:" + hashlib.sha256(result.stdout).hexdigest(), {
        # Retain this text verbatim inside the downloaded JSON, including unknown
        # declaration fields and numbers that JavaScript cannot represent exactly.
        "source_text": raw.decode("utf-8"),
        "source_bytes_sha256": "sha256:" + hashlib.sha256(raw).hexdigest(),
        "native_cli_sha256": json.loads(verified.stdout)["cli_sha256"]}, raw


def read_source_bytes(path):
    with path.open("rb") as stream:
        raw = stream.read(4 * 1024 * 1024 + 1)
    require(len(raw) <= 4 * 1024 * 1024, "full source graph exceeds 4 MiB")
    return raw


def read_resume_form(path, source_text, report):
    """Read a detached v1/v2 draft without mutating the graph or a native store."""
    raw = read_source_bytes(path)
    def decode(text, exact=False):
        options = {"object_pairs_hook": reject_duplicates,
                   "parse_constant": lambda value: (_ for _ in ()).throw(
                       ExplorerError(f"invalid JSON number: {value}"))}
        if exact:
            # Preserve number tokens, types and unknown annotations when comparing
            # source graphs. A tuple cannot collide with any decoded JSON value.
            options.update(parse_int=lambda value: ("number", value),
                           parse_float=lambda value: ("number", value))
        try:
            if isinstance(text, bytes):
                text = text.decode("utf-8")
            return json.loads(text, **options)
        except ExplorerError:
            raise
        except (ValueError, RecursionError) as error:
            raise ExplorerError("resume form must be complete UTF-8 JSON") from error
    exact = decode(raw, exact=True)
    require(isinstance(exact, dict), "resume requires a plan form object")
    v2 = exact.get("contract_id") == "moonflow.declared-plan-form-input.v2"
    require(set(exact) == ({"contract_id", "source_kind", "source_graph", "edits"}
                           | ({"added_templates"} if v2 else set())),
            "resume form contains missing or unsupported fields")
    require(exact["contract_id"] in ("moonflow.declared-plan-form-input.v1", "moonflow.declared-plan-form-input.v2")
            and exact["source_kind"] == "existing-graph",
            "resume supports existing-graph v1/v2 plan forms only")
    require(exact["source_graph"] == decode(source_text, exact=True),
            "saved plan source differs from the selected full graph; choose its original source")
    form = decode(raw)
    edits = form["edits"]
    source_ids = [node["work_item_id"] for node in report["nodes"]]
    templates = form.get("added_templates", {})
    require(isinstance(templates, dict), "added_templates must be an object")
    require(isinstance(edits, list) and 1 <= len(edits) <= 256,
            "saved plan must contain 1..256 items")
    for identity, template in templates.items():
        require(re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", identity) and identity != "."
                and ".." not in identity and identity not in source_ids,
                "added item must have a safe new ID without overwriting a source item")
        require(isinstance(template, str) and template in source_ids,
                "added template must name an original source item")
    by_id = {}
    for edit in edits:
        require(isinstance(edit, dict) and set(edit) == {
            "work_item_id", "input_artifacts", "depends_on", "acceptance_criteria", "timeout_ms"},
            "saved item contains missing or unsupported edit fields")
        identity = label(edit["work_item_id"], "saved work item")
        require((identity in source_ids or identity in templates) and identity not in by_id,
                "saved plan contains an unknown or duplicate work item")
        for name in ("input_artifacts", "depends_on", "acceptance_criteria"):
            values = edit[name]
            require(isinstance(values, list) and (bool(values) or name == "depends_on"),
                    f"saved {name} must be a string array")
            for value in values:
                label(value, f"saved {name}")
            require(len(set(values)) == len(values), f"saved {name} contains duplicates")
        require(type(edit["timeout_ms"]) is int and 1 <= edit["timeout_ms"] <= 86400000,
                "saved timeout_ms must be an integer in 1..86400000")
        for path_text in edit["input_artifacts"]:
            normalized = path_text.strip().replace("\\", "/")
            require(not normalized.startswith("/")
                    and all(part not in ("..", "") for part in normalized.split("/")),
                    "saved input artifacts must be workspace-relative without empty or parent segments")
        by_id[identity] = edit
    require(all(identity in by_id for identity in templates), "added template has no edited item")
    if not v2:
        require(set(by_id) == set(source_ids), "saved v1 plan must retain every source item exactly once")
    ids = list(by_id) if v2 else source_ids
    for identity, edit in by_id.items():
        require(all(dep in by_id and dep != identity for dep in edit["depends_on"]),
                "saved plan contains an unknown, removed or self prerequisite")
    visited = set()
    while len(visited) < len(ids):
        ready = [identity for identity in ids if identity not in visited
                 and all(dep in visited for dep in by_id[identity]["depends_on"])]
        require(bool(ready), "saved plan contains a dependency cycle")
        visited.update(ready)
    return {"edits": [by_id[identity] for identity in ids], "added_templates": templates,
            "form_sha256": "sha256:" + hashlib.sha256(raw).hexdigest()}, raw


def render(report, report_digest, authoring=None):
    escape = html.escape
    nodes = report["nodes"]
    indexes = {node["work_item_id"]: index for index, node in enumerate(nodes)}
    consumers = {identity: [] for identity in indexes}
    for node in nodes:
        for dep in node["depends_on"]:
            consumers[dep].append(node["work_item_id"])

    def links(identities):
        return ", ".join(f'<a href="#node-{indexes[identity]}" data-link="{indexes[identity]}">{escape(identity)}</a>'
                         for identity in identities) or "None"

    sections = []
    for layer_index, identities in enumerate(report["layers"]):
        cards = []
        for identity in identities:
            index = indexes[identity]
            node = nodes[index]
            cards.append(f'''<article class="node" id="node-{index}" data-index="{index}">
<h3>{escape(identity)}</h3><p class="product">{escape(node['product_id'])}</p>
<p class="operation">{escape(node['operation'])}</p>
<p><strong>Prerequisites:</strong> {links(node['depends_on'])}</p>
<p><strong>Direct consumers:</strong> {links(consumers[identity])}</p>
<button type="button" data-select="{index}" hidden>Explore this item</button></article>''')
        sections.append(f'<section class="layer" data-layer="{layer_index}">'
                        f'<h2>Dependency depth {layer_index}</h2><div class="cards">'
                        + "\n".join(cards) + '</div></section>')
    options = ''.join(f'<option value="{index}">{escape(node["work_item_id"])}</option>'
                      for index, node in enumerate(nodes))
    products = list(dict.fromkeys(n["product_id"] for n in nodes))
    product_options = ''.join(f'<option value="{index}">{escape(product)}</option>'
                              for index, product in enumerate(products))
    data = json.dumps({"report": report, "products": products, "authoring": authoring}, ensure_ascii=True,
                      separators=(",", ":")).replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
    css = (ASSETS / "style.css").read_text(encoding="utf-8")
    js = (ASSETS / "explorer.js").read_text(encoding="utf-8")
    identity_help = ("The renderer checks topology consistency. It cannot authenticate the export, recompute the source graph identity without the source, or check a capability catalog or run state. No files, network services or adapters are opened by this page.")
    footer = "This page changes no work graph, draft, run, approval or result."
    editor = ""
    if authoring is not None:
        resume_note = ("<p><strong>Resumed saved plan.</strong> All applied changes below include the saved plan. "
                       "Undo reverses edits made in this session; Reset all edits returns to the original source graph. "
                       "Saved declarations remain editable.</p><p>Saved form SHA-256: <code>"
                       + escape(authoring["resume"]["form_sha256"]) + "</code></p>"
                       if authoring.get("resume") else "")
        identity_help = ("This authoring snapshot was generated by invoking the pinned native graph-map against the full source graph. Source bytes were compared before and after that invocation and before HTML output. This verifies the source/report binding at export time, not catalog health, authority, execution or future source freshness. The browser opens no workspace files, services or adapters; it can download a local plan form.")
        footer = "This page edits a local dependency and timeout proposal, including input artifact edits. No source file, native draft, run, approval or result is changed."
        editor = f'''<section id="authoring" class="selection" hidden aria-label="Edit declared dependencies and timeout">
<h2>Edit prerequisite links and timeouts</h2>
<p>Changes are local to this page until you download a plan form. Dependencies and selected-item timeouts are editable. Input artifact lists and acceptance criteria are also editable. Added or removed steps download as v2; unchanged item sets keep v1 compatibility. The full original source graph travels in the form; no source file, draft, run or approval is changed here.</p>
<p>Source bytes SHA-256: <code>{escape(authoring['source_bytes_sha256'])}</code></p>
<p>Verified native CLI SHA-256: <code>{escape(authoring['native_cli_sha256'])}</code></p>
{resume_note}
<p id="edit-node">Choose a work item above.</p>
<h3>Add or remove a declared step</h3>
<p>Duplicate an existing declared operation using a new ID. Its owner, operation, schemas, authority and claim stay source-owned; no acceptance is copied. Before removal, explicitly edit any dependent items to remove or replace their prerequisite links. Removal never cascades.</p>
<label>New work item ID<input id="edit-new-id" type="text" maxlength="128"></label>
<button id="edit-duplicate" type="button">Preview duplicate declared operation</button>
<button id="edit-remove-step" type="button">Preview removal of this step</button>
<p id="edit-step-preview" role="status"></p>
<label>Acceptance criteria as a JSON array of distinct nonblank strings<textarea id="edit-criteria-json" rows="6"></textarea></label>
<p>Use JSON escapes for newlines inside a criterion. Exact text and order are preserved. Preview, then Apply to retain the edit; Cancel discards the preview.</p>
<button id="edit-criteria-preview" type="button">Preview acceptance criteria</button>
<p>Pending acceptance criteria:</p><ul id="edit-criteria"></ul>
<label>Prerequisite work item<select id="edit-target"><option value="">Choose a prerequisite</option>{options}</select></label>
<button id="edit-add" type="button">Add prerequisite</button>
<button id="edit-remove" type="button">Remove prerequisite</button>
<label>Timeout in milliseconds (1–86400000)<input id="edit-timeout" type="number" min="1" max="86400000" step="1"></label>
<button id="edit-timeout-preview" type="button">Preview timeout</button>
<p id="edit-timeout-pending"></p>
<label>Input artifacts, one workspace-relative path per line<textarea id="edit-inputs" rows="4"></textarea></label>
<button id="edit-inputs-preview" type="button">Preview input artifacts</button>
<p id="edit-inputs-pending"></p>
<p>Pending prerequisites:</p><ul id="edit-pending"></ul>
<button id="edit-apply" type="button">Apply pending changes</button>
<button id="edit-cancel" type="button">Cancel pending changes</button>
<p id="edit-message" role="status" aria-live="polite"></p>
<button id="edit-undo" type="button">Undo last edit</button>
<button id="edit-reset" type="button">Reset all edits</button>
<h3>Changes from the source graph</h3><ul id="edit-changes"></ul>
<button id="edit-download" type="button">Download dependency and timeout plan form</button>
<p>Run the downloaded form through native plan from-form, inspect and prepare with current catalog health. This page validates topology and bounded timeout declarations only; it grants no execution authority. Pending changes must be applied or canceled before download. Closing the page loses unsaved edits.</p>
</section>'''
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>{escape(report['graph_id'])} · MoonFlow dependency explorer</title><style>{css}</style></head>
<body><header><p class="eyebrow">MoonFlow · declared dependencies</p><h1>{escape(report['graph_id'])}</h1>
<p>Original source snapshot: {len(nodes)} work items · {report['edge_count']} prerequisite links · {len(report['layers'])} dependency depths</p>
<p class="boundary">This is an offline declaration snapshot. Depths and links do not indicate readiness, execution, timing, authority or acceptance.</p>
<details><summary>Snapshot identity and limits</summary><p>Contract: {CONTRACT}</p>
<p>Source graph identity (reported): <code>{escape(report['source_graph_digest'])}</code></p>
<p>Exact imported graph-map file SHA-256: <code>{escape(report_digest)}</code></p>
<p>{identity_help}</p></details></header>
<main><section id="controls" class="controls" hidden aria-label="Explore graph">
<label>Search IDs, products and operations<input id="search" type="search" placeholder="Search declared work"></label>
<label>Product<select id="product"><option value="">All products</option>{product_options}</select></label>
<label>Selected item<select id="focus"><option value="">Choose an item</option>{options}</select></label>
<label>Show<select id="scope" disabled><option value="all">All work</option><option value="prerequisites">Selected + all prerequisites</option><option value="consumers">Selected + all downstream consumers</option></select></label>
<button id="reset" type="button">Reset view</button></section>
<p id="summary" role="status" aria-live="polite">Showing all {len(nodes)} work items.</p>
<p id="empty" hidden>No work items match these filters. Reset the view or change your search.</p>
<section id="selection" class="selection" aria-label="Selected item details" hidden></section>
{editor}
<noscript><p>JavaScript is disabled. The cards below show the original source graph, without saved edits. Search, closure selection and resumed plan changes need JavaScript.</p></noscript>
<p class="print-note">Print view: the complete declared graph, regardless of screen filters.</p>
<div id="graph">{''.join(sections)}</div></main>
<footer>MoonFlow topology inspection · {footer}</footer>
<script id="graph-data" type="application/json">{data}</script><script>{js}</script></body></html>\n'''


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="graph-map JSON export, or original full graph with --author")
    parser.add_argument("--author", action="store_true", help="enable dependency and timeout editing of the original full source graph")
    parser.add_argument("--cli", type=Path, help="trusted pinned MoonFlow native executable; required with --author")
    parser.add_argument("--resume", type=Path, help="resume a saved v1/v2 plan form bound to this original full source graph; requires --author")
    parser.add_argument("output", type=Path, help="new local HTML file; existing files are never replaced")
    args = parser.parse_args(argv)
    try:
        require(args.author == (args.cli is not None), "--author and --cli must be supplied together")
        require(args.resume is None or args.author, "--resume requires --author and --cli")
        authoring = None
        if args.author:
            report, digest, authoring, original = author_source(args.report, args.cli)
            if args.resume is not None:
                authoring["resume"], resume_raw = read_resume_form(args.resume, authoring["source_text"], report)
        else:
            report, digest = read_report(args.report)
        document = render(report, digest, authoring).encode("utf-8")
        if args.author:
            require(read_source_bytes(args.report.resolve()) == original,
                    "source graph bytes changed before output; export refused")
            if args.resume is not None:
                require(read_source_bytes(args.resume) == resume_raw,
                        "saved plan bytes changed before output; export refused")
        # Exclusive creation also refuses aliases of the source or existing symlinks.
        with args.output.open("xb") as output:
            output.write(document)
        print(json.dumps({"contract_id": "moonflow.graph-explorer-export.v1",
                          "output": str(args.output), "graph_id": report["graph_id"],
                          "report_sha256": digest, "html_sha256": "sha256:" + hashlib.sha256(document).hexdigest(),
                          "node_count": len(report["nodes"]), "authoring": args.author,
                          "resumed_form_sha256": authoring["resume"]["form_sha256"] if args.resume is not None else None,
                          "dispatched": False}))
        return 0
    except (OSError, ExplorerError, UnicodeError, subprocess.TimeoutExpired) as error:
        print(f"graph explorer: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
