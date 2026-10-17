#!/usr/bin/env python3
"""Repeat explicitly selected workflow steps per CSV row, keeping shared steps."""
import argparse
import copy
import json
from pathlib import Path
import re
import sys

MAX_BYTES = 4 * 1024 * 1024
MAX_CSV_UNITS = 1_048_576
MAX_ITEMS = 256
ID = re.compile(r'[A-Za-z0-9_.-]{1,128}\Z')
COLUMN = re.compile(r'[A-Za-z0-9_]+\Z')
EDIT_FIELDS = ('work_item_id', 'input_artifacts', 'depends_on', 'acceptance_criteria', 'timeout_ms')


def require(condition, message):
    if not condition:
        raise ValueError(message)


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


def load_json(raw):
    require(len(raw) <= MAX_BYTES, 'JSON input exceeds 4 MiB')
    return json.loads(raw.decode('utf-8'), object_pairs_hook=unique_object,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('invalid JSON number')))


def encode(value):
    return (json.dumps(value, ensure_ascii=True, separators=(',', ':'), allow_nan=False) + '\n').encode()


def safe_id(value):
    return isinstance(value, str) and ID.fullmatch(value) and value != '.' and '..' not in value


def strings(value, label, nonempty=True):
    require(isinstance(value, list) and all(isinstance(x, str) for x in value),
            label + ' must be a string array')
    require((value or not nonempty) and all(x.strip() for x in value)
            and len(set(value)) == len(value), label + ' contains empty, blank or duplicate entries')
    return value


def artifact_ref(value):
    # The native lexical predicate; actual existence and containment remain CLI-owned.
    value = value.strip().replace('\\', '/')
    return bool(value) and not value.startswith('/') and all(part not in ('..', '') for part in value.split('/'))


def parse_rows(raw):
    """The table CSV grammar: commas, doubled quotes, LF/CRLF, no loose quotes."""
    require(len(raw) <= MAX_BYTES, 'CSV input exceeds 4 MiB')
    text = raw.decode('utf-8')
    require(len(text.encode('utf-16-le')) // 2 <= MAX_CSV_UNITS,
            'CSV exceeds 1,048,576 UTF-16 units')
    text = text.removeprefix('\ufeff')
    records, row, cell = [], [], []
    quoted = closed = started = False
    i = 0
    while i < len(text):
        char = text[i]
        if quoted:
            if char == '"':
                if text[i + 1:i + 2] == '"':
                    cell.append('"'); i += 1
                else:
                    quoted, closed = False, True
            elif char == '\r':
                require(text[i + 1:i + 2] == '\n', 'CSV uses an unpaired carriage return')
                cell.append('\n'); i += 1
            else:
                cell.append(char)
        elif char in ',\n\r':
            row.append(''.join(cell)); cell = []
            closed = started = False
            if char != ',':
                if char == '\r':
                    require(text[i + 1:i + 2] == '\n', 'CSV uses an unpaired carriage return')
                    i += 1
                records.append(row); row = []
                require(len(records) <= 257, 'CSV requires 1..256 rows')
        else:
            require(not closed, 'CSV has text after a closing quote')
            if char == '"':
                require(not started, 'CSV has a quote inside an unquoted cell')
                quoted = True
            else:
                cell.append(char)
            started = True
        i += 1
    require(not quoted, 'CSV has an unterminated quoted cell')
    if started or closed or row:
        row.append(''.join(cell)); records.append(row)
    require(2 <= len(records) <= 257, 'CSV requires 1..256 rows')
    headers = [value.strip() for value in records[0]]
    strings(headers, 'CSV headers')
    require('key' in headers and all(COLUMN.fullmatch(h) for h in headers),
            'CSV requires key and ASCII alphanumeric/underscore column names')
    rows, keys = [], set()
    for record in records[1:]:
        require(len(record) == len(headers), 'CSV row has the wrong cell count')
        cells = dict(zip(headers, (value.strip() for value in record)))
        key = cells['key']
        require(safe_id(key) and '--' not in key and key not in keys,
                'CSV key must be unique, safe and contain neither .. nor --')
        keys.add(key); rows.append(cells)
    return rows


def expand_text(template, cells):
    """Insert cell values once; braces in the inserted value are literal."""
    output, i, size = [], 0, 0
    while i < len(template):
        if template[i:i + 2] == '{{':
            end = template.find('}}', i + 2)
            require(end != -1, 'unclosed table placeholder')
            name = template[i + 2:end]
            require(COLUMN.fullmatch(name) and name in cells, 'unknown table column: ' + name)
            value = cells[name]
            require(value.strip(), 'blank table column: ' + name)
            i = end + 2
        else:
            require(template[i:i + 2] != '}}', 'unmatched table placeholder close')
            value = template[i]; i += 1
        size += len(value)
        require(size <= MAX_BYTES, 'expanded text exceeds output bound')
        output.append(value)
    return ''.join(output)


def validate_dag(items):
    dependencies = {item['work_item_id']: set(item['depends_on']) for item in items}
    known = set(dependencies)
    require(all(deps <= known for deps in dependencies.values()), 'source dependency names an unknown step')
    # Iterative so the full allowed graph does not depend on Python recursion limits.
    remaining = dict(dependencies)
    while remaining:
        ready = {key for key, deps in remaining.items() if not deps}
        require(ready, 'source dependency graph contains a cycle')
        remaining = {key: deps - ready for key, deps in remaining.items() if key not in ready}


def expand(source, template, csv_raw):
    """Produce the real v2 form. Native MoonFlow validates all product semantics."""
    require(isinstance(source, dict) and source.get('contract_id') == 'moonsuite.work-model.v1',
            'source must be a moonsuite.work-model.v1 graph')
    items = source.get('items')
    require(isinstance(items, list) and 1 <= len(items) <= MAX_ITEMS, 'source requires 1..256 steps')
    ids = set()
    for item in items:
        require(isinstance(item, dict) and all(field in item for field in EDIT_FIELDS),
                'source step lacks editable fields')
        key = item['work_item_id']
        require(safe_id(key) and key not in ids, 'source step ID must be unique and safe')
        ids.add(key)
        for field in ('input_artifacts', 'depends_on', 'acceptance_criteria'):
            strings(item[field], field, nonempty=field != 'depends_on')
        require(all(artifact_ref(ref) for ref in item['input_artifacts']), 'invalid source input artifact path')
        require(type(item['timeout_ms']) is int and 1 <= item['timeout_ms'] <= 86_400_000,
                'timeout_ms must be a whole number in 1..86400000')
    validate_dag(items)
    require(isinstance(template, dict) and set(template) == {
        'contract_id', 'repeated_work_item_ids', 'item_bindings'}, 'invalid shared table template fields')
    require(template['contract_id'] == 'moonflow.shared-table-template.v1', 'unsupported shared table template')
    selected = strings(template['repeated_work_item_ids'], 'repeated_work_item_ids')
    require(set(selected) <= ids, 'repeated selection names an unknown source step')
    repeated = set(selected)
    bindings = template['item_bindings']
    require(isinstance(bindings, list), 'item_bindings must be an array')
    binding_map = {}
    for binding in bindings:
        require(isinstance(binding, dict) and {'template_work_item_id', 'input_artifacts'} <= set(binding)
                <= {'template_work_item_id', 'input_artifacts', 'acceptance_criteria'}, 'invalid item binding fields')
        key = binding['template_work_item_id']
        require(isinstance(key, str) and key in repeated and key not in binding_map,
                'binding must name one distinct repeated step')
        strings(binding['input_artifacts'], 'artifact templates')
        if 'acceptance_criteria' in binding:
            strings(binding['acceptance_criteria'], 'criteria templates')
        binding_map[key] = binding
    require(set(binding_map) == repeated, 'provide exactly one binding per repeated step')
    rows = parse_rows(csv_raw)
    require(len(items) - len(repeated) + len(rows) * len(repeated) <= MAX_ITEMS,
            'expanded plan exceeds 256 total work items')
    added = {}
    for item in items:
        if item['work_item_id'] in repeated:
            for row in rows:
                key = row['key'] + '--' + item['work_item_id']
                require(safe_id(key), 'expanded work item ID exceeds safe identifier bound')
                require(key not in ids and key not in added, 'expanded ID collides with a source or added step')
                added[key] = item['work_item_id']
    form = {'contract_id': 'moonflow.declared-plan-form-input.v2', 'source_kind': 'existing-graph',
            'source_graph': copy.deepcopy(source), 'edits': [], 'added_templates': added}
    size = len(encode(form))
    require(size <= MAX_BYTES, 'form exceeds 4 MiB output bound')
    for item in items:
        original_id = item['work_item_id']
        for row in rows if original_id in repeated else [None]:
            edit = {field: copy.deepcopy(item[field]) for field in EDIT_FIELDS}
            if row is not None:
                edit['work_item_id'] = row['key'] + '--' + original_id
                binding = binding_map[original_id]
                edit['input_artifacts'] = [expand_text(value, row) for value in binding['input_artifacts']]
                if 'acceptance_criteria' in binding:
                    edit['acceptance_criteria'] = [expand_text(value, row) for value in binding['acceptance_criteria']]
            edit['depends_on'] = []
            for dependency in item['depends_on']:
                if dependency not in repeated:
                    edit['depends_on'].append(dependency)
                else:
                    edit['depends_on'].extend(cells['key'] + '--' + dependency
                                              for cells in ([row] if row is not None else rows))
            strings(edit['input_artifacts'], 'expanded input_artifacts')
            strings(edit['acceptance_criteria'], 'expanded acceptance_criteria')
            require(all(artifact_ref(ref) for ref in edit['input_artifacts']), 'expanded input artifact is not workspace-relative')
            size += len(encode(edit)) + 1
            require(size <= MAX_BYTES, 'form exceeds 4 MiB output bound')
            form['edits'].append(edit)
    return form


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('preview', 'save'):
        sub = commands.add_parser(name)
        sub.add_argument('source_graph', type=Path)
        sub.add_argument('template', type=Path)
        sub.add_argument('rows', type=Path)
        if name == 'save':
            sub.add_argument('output', type=Path, help='new native v2 form; existing files are refused')
    args = parser.parse_args(argv)
    try:
        form = expand(load_json(read_bounded(args.source_graph)), load_json(read_bounded(args.template)),
                      read_bounded(args.rows))
        data = encode(form)
        require(len(data) <= MAX_BYTES, 'form exceeds 4 MiB output bound')
        if args.command == 'save':
            with args.output.open('xb') as stream:
                stream.write(data)
            print(json.dumps({'form_ref': str(args.output), 'work_item_count': len(form['edits']),
                              'shared_item_count': len(form['edits']) - len(form['added_templates']),
                              'dispatched': False, 'native_validation_pending': True}))
        else:
            sys.stdout.buffer.write(data)
        return 0
    except (OSError, ValueError, UnicodeError, RecursionError) as error:
        print('shared table plan: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
