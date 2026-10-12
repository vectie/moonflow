#!/usr/bin/env python3
"""Read an exported MoonFlow timeline; never replay or operate a run."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import sys

MAX_BYTES = 8 * 1024 * 1024


def require(ok, message):
    if not ok:
        raise ValueError(message)


def pairs(values):
    result = {}
    for key, value in values:
        require(key not in result, 'duplicate JSON key')
        result[key] = value
    return result


def validate(value):
    require(isinstance(value, dict) and value.get('contract_id') == 'moonflow.run-history.v1', 'expected run-history.v1 export')
    head = value.get('head')
    require(isinstance(head, dict), 'missing head')
    for field in ('run_id', 'book_id', 'declaration_revision', 'source_digest', 'last_event_id', 'recorded_at', 'run_outcome'):
        require(isinstance(head.get(field), str), 'invalid head ' + field)
    require(bool(head['run_id'].strip()), 'blank run ID')
    require(type(head.get('last_sequence')) is int, 'invalid head sequence')
    selected = value.get('selected_work_item_id')
    require(selected is None or isinstance(selected, str) and bool(selected.strip()), 'invalid selection')
    for key in ('input_event_count', 'canonical_event_count', 'duplicate_event_count'):
        require(type(value.get(key)) is int and 0 <= value[key] <= 4096, 'invalid event counts')
    require(value['input_event_count'] == value['canonical_event_count'] + value['duplicate_event_count'], 'inconsistent event counts')
    entries = value.get('entries')
    require(isinstance(entries, list) and len(entries) <= value['canonical_event_count'], 'invalid entries')
    if selected is None:
        require(len(entries) == value['canonical_event_count'], 'unfiltered export is incomplete')
    sequence, ids = -1, set()
    for entry in entries:
        require(isinstance(entry, dict), 'invalid entry')
        event = entry.get('event')
        require(isinstance(event, dict), 'missing event')
        for key in ('event_id', 'run_id', 'work_item_id', 'kind', 'recorded_at'):
            require(isinstance(event.get(key), str), 'invalid event ' + key)
        require(event['run_id'] == head['run_id'], 'event belongs to another run')
        require(event['event_id'] and event['event_id'] not in ids, 'duplicate or empty event ID')
        ids.add(event['event_id'])
        require(type(event.get('sequence')) is int and sequence < event['sequence'] <= head['last_sequence'], 'events must be in canonical sequence')
        sequence = event['sequence']
        require(selected is None or event['work_item_id'] == selected, 'entry outside selected item')
        for side in ('before', 'after'):
            state = entry.get(side)
            require(side in entry and (state is None or isinstance(state, dict) and isinstance(state.get('status'), str)), 'invalid item snapshot')
        for key in ('run_outcome_before', 'run_outcome_after'):
            require(isinstance(entry.get(key), str), 'invalid run outcome')
    if entries and selected is None:
        require(entries[-1]['event']['event_id'] == head['last_event_id'] and sequence == head['last_sequence'], 'head differs from final event')
    return value


def load(raw):
    require(len(raw) <= MAX_BYTES, 'report exceeds 8 MiB')
    return validate(json.loads(raw.decode('utf-8'), object_pairs_hook=pairs,
                               parse_constant=lambda _: (_ for _ in ()).throw(ValueError('invalid JSON number'))))


def render(raw):
    report = load(raw)
    esc = html.escape
    pretty = lambda value: esc(json.dumps(value, ensure_ascii=True, indent=2))
    entries = report['entries']
    items = list(dict.fromkeys(e['event']['work_item_id'] for e in entries))
    kinds = list(dict.fromkeys(e['event']['kind'] for e in entries))
    options = lambda values: ''.join(f'<option value="{i}">{esc(v or "Run-level")}</option>' for i, v in enumerate(values))
    cards = []
    for index, entry in enumerate(entries):
        event = entry['event']
        before, after = entry['before'], entry['after']
        changes = [key for key in dict.fromkeys([*(before or {}), *(after or {})]) if (before or {}).get(key) != (after or {}).get(key) or (key in (before or {})) != (key in (after or {}))]
        cells = ''.join(f'<tr><th>{esc(key)}</th><td><pre>{pretty((before or {}).get(key))}</pre></td><td><pre>{pretty((after or {}).get(key))}</pre></td></tr>' for key in changes)
        cards.append(f'''<article id="event-{index}" data-index="{index}"><h2><a href="#event-{index}">#{event['sequence']}</a> {esc(event['kind'])} · {esc(event['work_item_id'] or 'Run-level')}</h2>
<p>Event {esc(event['event_id'])} · Recorded {esc(event['recorded_at'])}</p>
<p>Item: {esc(before['status'] if before else 'No item snapshot')} → {esc(after['status'] if after else 'No item snapshot')}; run: {esc(entry['run_outcome_before'])} → {esc(entry['run_outcome_after'])}</p>
<table><caption>Changed snapshot fields (JSON null also represents an absent field here; complete snapshots below)</caption><thead><tr><th>Field</th><th>Before</th><th>After</th></tr></thead><tbody>{cells}</tbody></table>
{''.join(f'<details><summary>{label}</summary><pre>{pretty(value)}</pre></details>' for label, value in [('This event only', event), ('Complete before snapshot', before), ('Complete after snapshot', after)])}</article>''')
    data = json.dumps([{'item': items.index(e['event']['work_item_id']), 'kind': kinds.index(e['event']['kind']), 'text': json.dumps(e, ensure_ascii=False)} for e in entries], ensure_ascii=True).replace('<', '\\u003c')
    script = Path(__file__).with_name('history_explorer.js').read_text()
    return f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>MoonFlow recorded timeline</title><style>body{{font:16px system-ui;max-width:1100px;margin:2rem auto;padding:1rem}}article{{border-top:2px solid #888;margin-top:2rem}}pre{{white-space:pre-wrap;overflow-wrap:anywhere}}td,th{{border:1px solid #aaa;padding:.4rem;vertical-align:top}}table{{border-collapse:collapse;width:100%}}label{{display:inline-block;margin:.5rem}}[hidden]{{display:none}}@media print{{article[hidden]{{display:block}}nav{{display:none}}}}</style>
<h1>{esc(report['head']['run_id'])}: recorded timeline</h1><p>Read-only exported evidence. No replay, execution, current-state verification or acceptance is performed. Order is canonical sequence, never elapsed time.</p>
<p>Exact report SHA-256: {hashlib.sha256(raw).hexdigest()}</p><p>Selected export scope: {esc(report['selected_work_item_id'] or 'All items')}. Supplied events: {report['input_event_count']}; canonical: {report['canonical_event_count']}; duplicate deliveries omitted: {report['duplicate_event_count']}.</p>
<details><summary>Complete recorded run head</summary><pre>{pretty(report['head'])}</pre></details>
<p>Retained artifacts and approvals in snapshots are cumulative. They are not newly produced by this event. References are displayed as text and never opened.</p>
<nav hidden><label>Item <select id="item"><option value="">All items</option>{options(items)}</select></label><label>Event kind <select id="kind"><option value="">All kinds</option>{options(kinds)}</select></label><label>Search event and snapshots <input id="search" type="search"></label><button id="reset">Reset</button></nav>
<p id="count" aria-live="polite">{len(entries)} events</p><p id="empty" {'hidden' if entries else ''}>No events in this view.</p>{''.join(cards)}
<script id="timeline-data" type="application/json">{data}</script><script>{script}</script></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report'); parser.add_argument('output')
    args = parser.parse_args()
    try:
        with Path(args.report).open('rb') as stream:
            raw = stream.read(MAX_BYTES + 1)
        output = render(raw).encode('utf-8')
        with Path(args.output).open('xb') as stream:
            stream.write(output)
        print(json.dumps({'report_sha256': hashlib.sha256(raw).hexdigest(), 'output_sha256': hashlib.sha256(output).hexdigest(), 'dispatched': False}))
    except (OSError, ValueError, UnicodeError, RecursionError) as error:
        print(str(error), file=sys.stderr); return 2
    return 0

if __name__ == '__main__':
    sys.exit(main())
