#!/usr/bin/env python3
"""Render a MoonFlow graph-map JSON export as one offline HTML explorer."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import sys

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


def render(report, report_digest):
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
    data = json.dumps({"report": report, "products": products}, ensure_ascii=True,
                      separators=(",", ":")).replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
    css = (ASSETS / "style.css").read_text(encoding="utf-8")
    js = (ASSETS / "explorer.js").read_text(encoding="utf-8")
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>{escape(report['graph_id'])} · MoonFlow dependency explorer</title><style>{css}</style></head>
<body><header><p class="eyebrow">MoonFlow · declared dependencies</p><h1>{escape(report['graph_id'])}</h1>
<p>{len(nodes)} work items · {report['edge_count']} prerequisite links · {len(report['layers'])} dependency depths</p>
<p class="boundary">This is an offline declaration snapshot. Depths and links do not indicate readiness, execution, timing, authority or acceptance.</p>
<details><summary>Snapshot identity and limits</summary><p>Contract: {CONTRACT}</p>
<p>Source graph identity (reported): <code>{escape(report['source_graph_digest'])}</code></p>
<p>Exact imported graph-map file SHA-256: <code>{escape(report_digest)}</code></p>
<p>The renderer checks topology consistency. It cannot authenticate the export, recompute the source graph identity without the source, or check a capability catalog or run state. No files, network services or adapters are opened by this page.</p></details></header>
<main><section id="controls" class="controls" hidden aria-label="Explore graph">
<label>Search IDs, products and operations<input id="search" type="search" placeholder="Search declared work"></label>
<label>Product<select id="product"><option value="">All products</option>{product_options}</select></label>
<label>Selected item<select id="focus"><option value="">Choose an item</option>{options}</select></label>
<label>Show<select id="scope" disabled><option value="all">All work</option><option value="prerequisites">Selected + all prerequisites</option><option value="consumers">Selected + all downstream consumers</option></select></label>
<button id="reset" type="button">Reset view</button></section>
<p id="summary" role="status" aria-live="polite">Showing all {len(nodes)} work items.</p>
<p id="empty" hidden>No work items match these filters. Reset the view or change your search.</p>
<section id="selection" class="selection" aria-label="Selected item details" hidden></section>
<noscript><p>JavaScript is disabled. All declarations and direct prerequisite/consumer links remain readable below. Search and closure selection need JavaScript.</p></noscript>
<p class="print-note">Print view: the complete declared graph, regardless of screen filters.</p>
<div id="graph">{''.join(sections)}</div></main>
<footer>MoonFlow topology inspection · This page changes no work graph, draft, run, approval or result.</footer>
<script id="graph-data" type="application/json">{data}</script><script>{js}</script></body></html>\n'''


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="existing moonflow graph-map --json export")
    parser.add_argument("output", type=Path, help="new local HTML file; existing files are never replaced")
    args = parser.parse_args(argv)
    try:
        report, digest = read_report(args.report)
        document = render(report, digest).encode("utf-8")
        # Exclusive creation also refuses aliases of the source or existing symlinks.
        with args.output.open("xb") as output:
            output.write(document)
        print(json.dumps({"contract_id": "moonflow.graph-explorer-export.v1",
                          "output": str(args.output), "graph_id": report["graph_id"],
                          "report_sha256": digest, "html_sha256": "sha256:" + hashlib.sha256(document).hexdigest(),
                          "node_count": len(report["nodes"]), "dispatched": False}))
        return 0
    except (OSError, ExplorerError, UnicodeError) as error:
        print(f"graph explorer: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
