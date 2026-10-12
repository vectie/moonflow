#!/usr/bin/env python3
"""Exercise the compiled result-data CLI against retained synthetic event histories."""
import argparse
import copy
import csv
import hashlib
import io
import json
import pathlib
import shutil
import subprocess
import tempfile

p = argparse.ArgumentParser()
p.add_argument('--cli', required=True, type=pathlib.Path)
p.add_argument('--workspace-parent', required=True, type=pathlib.Path)
a = p.parse_args()
source = pathlib.Path(__file__).resolve().parents[1]
example = source / 'examples/result-data'
a.workspace_parent.mkdir(parents=True, exist_ok=True)
w = pathlib.Path(tempfile.mkdtemp(prefix='result-data-', dir=a.workspace_parent))
logs = w / 'verification-log'
logs.mkdir()
(w / 'outputs').mkdir()
for name in ('a', 'b'):
    shutil.copyfile(example / f'{name}.json', w / 'outputs' / f'{name}.json')
    run = w / '.moonsuite/products/moonflow/runs' / f'study-{name}'
    run.mkdir(parents=True)
    shutil.copyfile(example / f'study-{name}.events.json', run / 'events.json')
    (run / 'projection.json').write_text('deliberately invalid cached projection\n')
shutil.copyfile(example / 'mapping.json', w / 'mapping.json')
commands = []

def hashes():
    return {str(f.relative_to(w)): hashlib.sha256(f.read_bytes()).hexdigest()
            for f in w.rglob('*') if f.is_file() and logs not in f.parents}

def invoke(*args, error=None, json_output=True):
    before = hashes()
    r = subprocess.run([str(a.cli.resolve()), *map(str, args)], capture_output=True, text=True)
    n = len(commands) + 1
    (logs / f'{n:02}.stdout').write_text(r.stdout)
    (logs / f'{n:02}.stderr').write_text(r.stderr)
    commands.append({'args': list(map(str, args)), 'exit': r.returncode})
    (logs / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    assert hashes() == before, ('unexpected file mutation', args)
    assert (r.returncode != 0) == (error is not None), (args, r.returncode, r.stdout, r.stderr)
    if error is not None:
        assert error in r.stdout + r.stderr, (error, r.stdout, r.stderr)
        assert '"contract_id": "moonflow.result-data-table.v1"' not in r.stdout
        return r.stdout
    return json.loads(r.stdout) if json_output else r.stdout

def store(name, value):
    (w / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

original = hashes()
args = ('result-data', w, 'mapping.json')
table = invoke(*args, '--json', 'study-a', 'study-b')
assert table['contract_id'] == 'moonflow.result-data-table.v1'
assert [r['run_id'] for r in table['runs']] == ['study-a', 'study-b']
rows = table['rows']
assert [r['source']['work_item_id'] for r in rows] == ['variant-a', 'pending', 'variant-b', 'uncertain']
assert [r['data_status'] for r in rows] == ['extracted', 'no-successful-attempt', 'extracted', 'no-successful-attempt']
for index, name, expected_status in [(0, 'a', 'accepted'), (2, 'b', 'review')]:
    row = rows[index]
    assert row['source']['status'] == expected_status
    assert row['artifact_ref'] == f'outputs/{name}.json'
    data = (w / row['artifact_ref']).read_bytes()
    assert row['observed_sha256'] == 'sha256:' + hashlib.sha256(data).hexdigest()
    assert row['observed_size_bytes'] == len(data)
    assert row['observed_sha256'] != row['source']['output_digest']
    expected = json.loads(data)
    assert row['values'] == dict(score=expected['metrics']['score'], label=expected['label'], passed=expected['passed'], metadata=expected['metadata'], note=expected['note'], tags=expected['tags'], escaped=expected['a/b']['~'][0])
assert rows[0]['source']['review_id'] == 'review-a'
assert rows[2]['source']['review_id'] == ''
assert all(v is None for v in rows[3]['values'].values())
assert rows[3]['source']['attempt_status'] == 'unknown'
assert invoke(*args, '--json', 'study-a', 'study-b') == table
reversed_table = invoke(*args, '--json', 'study-b', 'study-a')
assert [r['source']['work_item_id'] for r in reversed_table['rows']] == ['variant-b', 'uncertain', 'variant-a', 'pending']
text = invoke(*args, '--csv', 'study-a', 'study-b', json_output=False)
csv_rows = list(csv.DictReader(io.StringIO(text)))
for csv_row, row in zip(csv_rows, rows):
    assert csv_row['work_item_id'] == row['source']['work_item_id']
    assert {k.removeprefix('value:'): json.loads(v) for k, v in csv_row.items() if k.startswith('value:')} == row['values']
assert len(csv_rows) == 4
mapping = json.loads((w / 'mapping.json').read_text())
filtered = copy.deepcopy(mapping)
filtered['operation'] = 'unmatched@1'
store('filter.json', filtered)
empty = invoke('result-data', w, 'filter.json', '--json', 'study-a')
assert empty['rows'] == [] and len(empty['runs']) == 1
assert len(list(csv.reader(io.StringIO(invoke('result-data', w, 'filter.json', '--csv', 'study-a', json_output=False))))) == 1
# Changed file bytes are explicitly a different observation; recorded attempt identity is unchanged.
old = (w / 'outputs/a.json').read_bytes()
changed = json.loads(old)
changed['metrics']['score'] = 1.25
store('outputs/a.json', changed)
observed = invoke(*args, '--json', 'study-a')
assert observed['rows'][0]['values']['score'] == 1.25
assert observed['rows'][0]['observed_sha256'] != rows[0]['observed_sha256']
assert observed['rows'][0]['source']['output_digest'] == rows[0]['source']['output_digest']
(w / 'outputs/a.json').write_bytes(old)
# Failure paths never print a partial worksheet and never change any workspace bytes.
for label, mutate, error in [
    ('missing-pointer', lambda m: m['columns'][0].update(pointer='/missing'), 'JSON Pointer does not resolve'),
    ('index', lambda m: m.update(output_artifact_index=2), 'result has no output at index'),
    ('duplicate', lambda m: m['columns'].append(m['columns'][0].copy()), 'column names must be unique'),
    ('unknown-field', lambda m: m.update(fallback=True), 'unknown result data mapping field'),
]:
    bad = copy.deepcopy(mapping)
    mutate(bad)
    store(label + '.json', bad)
    invoke('result-data', w, label + '.json', '--json', 'study-a', error=error)
invoke(*args, '--json', 'study-a', 'study-a', error='Duplicate results run')
invoke(*args, '--json', 'missing-run', error='')
invoke(*args, '--bad', 'study-a', error='Use --csv or --json')
invoke(*args, '--json', error='Select 1..64 runs')
for content, error in [(b'{bad', 'invalid result output JSON'), (b' ' * 1048577, 'exceeds 1048576 bytes')]:
    (w / 'outputs/a.json').write_bytes(content)
    invoke(*args, '--json', 'study-a', error=error)
(w / 'outputs/a.json').write_bytes(old)
# A canonical result whose selected output is missing must fail even though its retained list has other files.
event_path = w / '.moonsuite/products/moonflow/runs/study-a/events.json'
event_bytes = event_path.read_bytes()
events = json.loads(event_bytes)
for event in events:
    if event['event_id'] == 'study-a-5':
        event['output_artifacts'][1] = 'missing.json'
store(str(event_path.relative_to(w)), events)
invoke(*args, '--json', 'study-a', error='artifact does not exist')
event_path.write_bytes(event_bytes)
# Invalid canonical history cannot be bypassed by the cached projection.
event_path.write_text('{invalid')
invoke(*args, '--json', 'study-a', error='')
event_path.write_bytes(event_bytes)
assert invoke(*args, '--json', 'study-a', 'study-b') == table
assert all(hashes()[name] == digest for name, digest in original.items())
result = {'passed': True, 'commands': len(commands), 'rows': len(rows), 'typed_columns': len(mapping['columns']), 'negative_cases': sum(c['exit'] != 0 for c in commands), 'workspace': str(w), 'canonical_events_unchanged': True, 'adapter_dispatches': 0, 'cli_sha256': hashlib.sha256(a.cli.read_bytes()).hexdigest()}
(logs / 'RESULT.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
