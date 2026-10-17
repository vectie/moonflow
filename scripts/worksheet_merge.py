#!/usr/bin/env python3
"""Merge independently edited native plan worksheets without losing conflicting intent."""
import argparse
import csv
import io
import json
import os
from pathlib import Path
import sys

from input_rebindings import (HEADERS, MAX_UNITS, load_json, parse_worksheet,
                              read_bounded, require, sha256)

EDITABLE = ('input_artifacts', 'depends_on', 'acceptance_criteria', 'timeout_ms')
READONLY = tuple(key for key in HEADERS if key not in EDITABLE)


def value(row, field):
    return int(row[field].strip()) if field == 'timeout_ms' else load_json(row[field])


def validate_graph(rows):
    dependencies = {row['work_item_id']: load_json(row['depends_on']) for row in rows}
    for item, parents in dependencies.items():
        require(all(parent in dependencies for parent in parents),
                'unknown dependency for ' + repr(item))
    completed = set()
    while len(completed) < len(rows):
        ready = {item for item, parents in dependencies.items()
                 if item not in completed and all(parent in completed for parent in parents)}
        require(ready, 'dependency cycle; revise branch worksheets before merging')
        completed.update(ready)


def serialize(rows, headers):
    units = 0
    buffer = io.StringIO(newline='')
    writer = csv.writer(buffer, lineterminator='\n', quoting=csv.QUOTE_ALL)
    for cells in [headers] + [[row[key.strip()] for key in headers] for row in rows]:
        units += sum(len(cell.encode('utf-16-le')) // 2 + cell.count('"') + 2 for cell in cells) + len(cells)
        require(units <= MAX_UNITS, 'merged worksheet exceeds 1,048,576 UTF-16 units')
        writer.writerow(cells)
    raw = buffer.getvalue().encode('utf-8')
    parse_worksheet(raw)
    return raw


def merge(base_raw, left_raw, right_raw, resolution_raw=None):
    sheets = [parse_worksheet(raw) for raw in (base_raw, left_raw, right_raw)]
    base, left, right = sheets
    indexed = [{row['work_item_id']: row for row in sheet['rows']} for sheet in sheets]
    for sheet, index in zip(sheets, indexed):
        require(set(index) == set(indexed[0]), 'branches must retain exactly the base work item IDs')
        for original in base['rows']:
            require(all(index[original['work_item_id']][key] == original[key] for key in READONLY),
                    'read-only identity changed for ' + repr(original['work_item_id']))
        validate_graph(sheet['rows'])
    hashes = {name + '_sha256': sheet['worksheet_sha256']
              for name, sheet in zip(('base', 'left', 'right'), sheets)}
    rows, conflicts, changes = [], [], []
    for original in base['rows']:
        item = original['work_item_id']
        updated = original.copy()
        for field in EDITABLE:
            before, lvalue, rvalue = [value(index[item], field) for index in indexed]
            if lvalue == rvalue:
                if lvalue != before:
                    updated[field] = indexed[1][item][field]
            elif lvalue == before:
                updated[field] = indexed[2][item][field]
            elif rvalue == before:
                updated[field] = indexed[1][item][field]
            else:
                conflicts.append({'work_item_id': item, 'field': field,
                                  'base': original[field], 'left': indexed[1][item][field],
                                  'right': indexed[2][item][field]})
        rows.append(updated)
    resolution_template = {'contract_id': 'moonflow.worksheet-merge-resolution.v1', **hashes,
                           'resolutions': [{'work_item_id': c['work_item_id'], 'field': c['field'],
                                            'choice': None} for c in conflicts]}
    resolved = resolution_raw is not None
    if resolved:
        spec = load_json(resolution_raw.decode('utf-8'))
        require(isinstance(spec, dict) and set(spec) == set(resolution_template), 'invalid resolution fields')
        require(spec['contract_id'] == resolution_template['contract_id'], 'unsupported resolution contract')
        require(all(spec[key] == expected for key, expected in hashes.items()),
                'worksheet bytes changed; preview again and resolve the current conflicts')
        selections = spec['resolutions']
        require(isinstance(selections, list) and len(selections) == len(conflicts),
                'resolve every conflict exactly once')
        known = {(c['work_item_id'], c['field']): c for c in conflicts}
        chosen = {}
        for selection in selections:
            require(isinstance(selection, dict), 'resolution must be an object')
            choice = selection.get('choice')
            require(isinstance(choice, str) and choice in ('base', 'left', 'right', 'custom'),
                    'choice must be base, left, right or custom')
            expected = {'work_item_id', 'field', 'choice'} | ({'value'} if choice == 'custom' else set())
            require(set(selection) == expected, 'invalid conflict resolution fields')
            item, field = selection['work_item_id'], selection['field']
            require(isinstance(item, str) and isinstance(field, str), 'resolution identities must be strings')
            key = (item, field)
            require(key in known and key not in chosen, 'unknown or repeated conflict resolution')
            cell = selection['value'] if choice == 'custom' else known[key][choice]
            require(isinstance(cell, str), 'custom value must be an exact worksheet cell string')
            chosen[key] = cell
        for row in rows:
            for field in EDITABLE:
                if (row['work_item_id'], field) in chosen:
                    row[field] = chosen[(row['work_item_id'], field)]
    ready = not conflicts or resolved
    output, blocker = None, None
    if ready:
        try:
            output = serialize(rows, base['headers'])
            validate_graph(rows)
        except ValueError as error:
            output, blocker = None, str(error)
    if output is not None:
        for before, after in zip(base['rows'], rows):
            for field in EDITABLE:
                if value(before, field) != value(after, field):
                    changes.append({'work_item_id': before['work_item_id'], 'field': field,
                                    'before': before[field], 'after': after[field]})
    report = {'contract_id': 'moonflow.worksheet-merge-preview.v1', **hashes,
              'source_graph_digest': base['source_graph_digest'],
              'conflicts': conflicts, 'conflicts_resolved': resolved, 'resolution_template': resolution_template,
              'ready_to_save': output is not None, 'blocker': blocker, 'changes': changes,
              'output_sha256': sha256(output) if output is not None else None,
              'output_bytes': len(output) if output is not None else 0,
              'native_validated': False, 'dispatched': False}
    if resolution_raw is not None:
        report['resolution_sha256'] = sha256(resolution_raw)
    return report, output


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    for name in ('preview', 'save'):
        command = sub.add_parser(name)
        for source in ('base', 'left', 'right'):
            command.add_argument(source, type=Path)
        command.add_argument('--resolutions', type=Path)
        if name == 'save':
            command.add_argument('output', type=Path)
    args = parser.parse_args(argv)
    try:
        report, data = merge(*[read_bounded(getattr(args, name)) for name in ('base', 'left', 'right')],
                             read_bounded(args.resolutions) if args.resolutions else None)
        if args.command == 'save':
            require(data is not None, report['blocker'] or 'unresolved conflicts; preview and supply resolutions')
            # Exclusive creation refuses aliases, symlinks and existing files.
            with os.fdopen(os.open(args.output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), 'wb') as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            report['output'] = str(args.output)
            report['saved_worksheet'] = True
        print(json.dumps(report, ensure_ascii=True, indent=2))
        return 0 if report['ready_to_save'] else 2
    except (OSError, ValueError, UnicodeError, csv.Error, RecursionError) as error:
        print('worksheet merge: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
