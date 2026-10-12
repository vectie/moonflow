#!/usr/bin/env python3
"""Inventory shared worksheet inputs and prepare explicit source-bound rebindings."""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import sys

MAX_UNITS = 1_048_576  # Native worksheet bound, in UTF-16 code units.
MAX_BYTES = 4 * MAX_UNITS
HEADERS = ('source_graph_digest', 'work_item_id', 'product_id', 'operation',
           'input_artifacts', 'depends_on', 'acceptance_criteria', 'timeout_ms')
DIGEST = re.compile(r'sha256:[0-9a-f]{64}\Z')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(raw):
    return 'sha256:' + hashlib.sha256(raw).hexdigest()


def read_bounded(path):
    with Path(path).open('rb') as stream:
        raw = stream.read(MAX_BYTES + 1)
    require(len(raw) <= MAX_BYTES, 'input exceeds 4 MiB')
    return raw


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate JSON key: ' + key)
        result[key] = value
    return result


def load_json(text):
    return json.loads(text, object_pairs_hook=unique_object,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('invalid JSON number')))


def artifact_reference(value):
    # Same lexical predicate as boundary.mbt. This is NOT a filesystem check.
    candidate = value.strip().replace('\\', '/')
    return bool(candidate) and not candidate.startswith('/') and all(
        segment not in ('..', '') for segment in candidate.split('/'))


def string_array(cell, field):
    value = load_json(cell)
    require(isinstance(value, list) and all(isinstance(x, str) for x in value),
            field + ' must be a JSON string array')
    require(all(x.strip() for x in value) and len(set(value)) == len(value),
            field + ' contains a blank or duplicate entry')
    require(field == 'depends_on' or value, field + ' must not be empty')
    return value


def parse_worksheet(raw):
    """Read the existing eight-column export; retain exact cell text and ordering."""
    require(len(raw) <= MAX_BYTES, 'worksheet exceeds 4 MiB')
    text = raw.decode('utf-8')
    require(len(text.encode('utf-16-le')) // 2 <= MAX_UNITS,
            'worksheet exceeds 1,048,576 UTF-16 units')
    csv.field_size_limit(MAX_UNITS)
    table = list(csv.reader(io.StringIO(text.removeprefix('\ufeff'), newline=''), strict=True))
    require(2 <= len(table) <= 257, 'worksheet requires 1..256 rows')
    headers = [cell.strip() for cell in table[0]]
    require(len(headers) == len(HEADERS) and set(headers) == set(HEADERS),
            'worksheet requires exactly the eight native worksheet columns')
    rows, inputs, ids, digest = [], [], set(), None
    for index, cells in enumerate(table[1:], 2):
        require(len(cells) == len(headers), f'worksheet row {index} has the wrong cell count')
        row = dict(zip(headers, cells))
        item = row['work_item_id']
        require(item.strip() and item not in ids, 'blank or duplicate work_item_id')
        ids.add(item)
        require(DIGEST.fullmatch(row['source_graph_digest']), 'invalid source_graph_digest')
        digest = digest or row['source_graph_digest']
        require(row['source_graph_digest'] == digest, 'worksheet mixes source graph identities')
        require(row['product_id'].strip() and row['operation'].strip(), 'blank product or operation')
        artifacts = string_array(row['input_artifacts'], 'input_artifacts')
        require(all(artifact_reference(ref) for ref in artifacts),
                'input artifact fails the native workspace-relative lexical predicate')
        string_array(row['depends_on'], 'depends_on')
        string_array(row['acceptance_criteria'], 'acceptance_criteria')
        timeout = row['timeout_ms'].strip()
        require(re.fullmatch(r'[0-9]+', timeout) and 1 <= int(timeout) <= 86_400_000,
                'timeout_ms must be 1..86400000')
        rows.append(row)
        inputs.append(artifacts)
    return {'headers': table[0], 'rows': rows, 'inputs': inputs,
            'worksheet_sha256': sha256(raw), 'source_graph_digest': digest}


def inventory(sheet):
    grouped = {}
    for row, refs in zip(sheet['rows'], sheet['inputs']):
        for ref in refs:
            entry = grouped.setdefault(ref, {'artifact_ref': ref, 'work_item_ids': [], 'product_ids': []})
            entry['work_item_ids'].append(row['work_item_id'])
            if row['product_id'] not in entry['product_ids']:
                entry['product_ids'].append(row['product_id'])
    for entry in grouped.values():
        entry['shared'] = len(entry['work_item_ids']) > 1
    return {'contract_id': 'moonflow.worksheet-input-inventory.v1',
            'worksheet_sha256': sheet['worksheet_sha256'],
            'source_graph_digest': sheet['source_graph_digest'],
            'work_item_count': len(sheet['rows']), 'reference_count': sum(map(len, sheet['inputs'])),
            'unique_input_count': len(grouped),
            'shared_input_count': sum(entry['shared'] for entry in grouped.values()),
            'inputs': list(grouped.values()), 'payloads_read': False, 'dispatched': False}


def plan_rebindings(sheet, mapping_raw):
    require(len(mapping_raw) <= MAX_BYTES, 'mapping exceeds 4 MiB')
    mapping = load_json(mapping_raw.decode('utf-8'))
    require(isinstance(mapping, dict) and set(mapping) == {'contract_id', 'worksheet_sha256', 'replacements'},
            'mapping requires contract_id, worksheet_sha256 and replacements only')
    require(mapping['contract_id'] == 'moonflow.input-rebindings.v1', 'unsupported mapping contract')
    require(mapping['worksheet_sha256'] == sheet['worksheet_sha256'],
            'worksheet bytes changed; inspect a fresh inventory and update the mapping identity')
    replacements = mapping['replacements']
    require(isinstance(replacements, list) and 1 <= len(replacements) <= 256,
            'mapping requires 1..256 replacements')
    known = {ref for refs in sheet['inputs'] for ref in refs}
    selected = {}
    for replacement in replacements:
        require(isinstance(replacement, dict) and set(replacement) == {'from', 'to'},
                'each replacement requires from and to only')
        old, new = replacement['from'], replacement['to']
        require(isinstance(old, str) and isinstance(new, str), 'replacement paths must be strings')
        require(old in known and old not in selected, 'replacement source is absent or repeated')
        require(artifact_reference(new), 'replacement target fails native workspace-relative lexical predicate')
        require(old != new, 'replacement must change the exact reference')
        selected[old] = new
    rows, changes = [], []
    # Bound the emitted CSV while constructing rows, before repeated targets
    # can multiply a large mapping across the entire sheet. All cells are quoted.
    quoted_units = lambda cells: sum(len(cell.encode('utf-16-le')) // 2 + cell.count('"') + 2 for cell in cells) + len(cells)
    output_units = quoted_units(sheet['headers'])
    for row, before in zip(sheet['rows'], sheet['inputs']):
        after = [selected.get(ref, ref) for ref in before]
        require(len(set(after)) == len(after),
                'replacement creates duplicate inputs for ' + row['work_item_id'])
        updated = row.copy()
        if before != after:
            updated['input_artifacts'] = json.dumps(after, ensure_ascii=False, separators=(',', ':'))
            changes.append({'work_item_id': row['work_item_id'], 'product_id': row['product_id'],
                            'before': before, 'after': after})
        output_units += quoted_units([updated[header.strip()] for header in sheet['headers']])
        require(output_units <= MAX_UNITS, 'rebound worksheet exceeds 1,048,576 UTF-16 units')
        rows.append(updated)
    output = io.StringIO(newline='')
    writer = csv.writer(output, lineterminator='\n', quoting=csv.QUOTE_ALL)
    writer.writerow(sheet['headers'])
    writer.writerows([row[header.strip()] for header in sheet['headers']] for row in rows)
    data = output.getvalue().encode('utf-8')
    # Output must remain inside the native worksheet size bound after growth.
    parse_worksheet(data)
    report = {'contract_id': 'moonflow.worksheet-input-rebind-preview.v1',
              'worksheet_sha256': sheet['worksheet_sha256'],
              'mapping_sha256': sha256(mapping_raw),
              'source_graph_digest': sheet['source_graph_digest'],
              'output_sha256': sha256(data), 'output_bytes': len(data),
              'changed_item_ids': [change['work_item_id'] for change in changes],
              'replacement_count': len(selected), 'changes': changes,
              'payloads_read': False, 'dispatched': False}
    return report, data


def render_text(report):
    # JSON-quoted labels retain exact whitespace and keep terminal controls inert.
    quote = lambda value: json.dumps(value, ensure_ascii=True)
    lines = ['Worksheet: ' + report['worksheet_sha256'],
             'Reported source graph: ' + report['source_graph_digest']]
    if 'inputs' in report:
        lines.append(f"{report['unique_input_count']} distinct inputs; {report['shared_input_count']} shared")
        for entry in report['inputs']:
            lines.append(quote(entry['artifact_ref']) + ' -> ' + ', '.join(map(quote, entry['work_item_ids'])))
    else:
        lines.append(f"{len(report['changes'])} changed work items; output {report['output_sha256']}")
        for change in report['changes']:
            lines.append(quote(change['work_item_id']) + ': ' + quote(change['before']) + ' -> ' + quote(change['after']))
        if 'output' in report:
            lines.append('Created worksheet: ' + quote(report['output']))
    lines.append('Planning only. No payload read, file move, plan import, readiness check or dispatch.')
    return '\n'.join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for command in ('inventory', 'preview', 'rebind'):
        sub = commands.add_parser(command)
        sub.add_argument('worksheet', type=Path)
        if command != 'inventory':
            sub.add_argument('mapping', type=Path)
        if command == 'rebind':
            sub.add_argument('output', type=Path, help='new worksheet CSV; existing files are refused')
        sub.add_argument('--text', action='store_true', help='readable exact-path inventory or change list')
    args = parser.parse_args(argv)
    try:
        sheet = parse_worksheet(read_bounded(args.worksheet))
        if args.command == 'inventory':
            report = inventory(sheet)
        else:
            report, output = plan_rebindings(sheet, read_bounded(args.mapping))
            if args.command == 'rebind':
                with args.output.open('xb') as stream:
                    stream.write(output)
                report = {**report, 'output': str(args.output), 'saved_worksheet': True}
        print(render_text(report) if args.text else json.dumps(report, ensure_ascii=True, indent=2))
        return 0
    except (OSError, ValueError, UnicodeError, csv.Error, RecursionError) as error:
        print('input rebindings: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
