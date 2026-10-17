#!/usr/bin/env python3
"""Verify bounded-wave CLI through saved draft, preparation and conformant import.
No adapters, credentials, providers, or external effects are used.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--cli', required=True, type=Path)
p.add_argument('--workspace-parent', required=True, type=Path)
a = p.parse_args()
a.workspace_parent.mkdir(parents=True, exist_ok=True)
w = Path(tempfile.mkdtemp(prefix='wave-plan-', dir=a.workspace_parent))
example = Path(__file__).resolve().parents[1] / 'examples/plan-worksheet'
for f in example.rglob('*'):
    if f.is_file() and 'outputs' not in f.relative_to(example).parts and f.suffix == '.json':
        out = w / f.relative_to(example)
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(f, out)
logs = w / 'verification-log'
logs.mkdir()
commands = []
def hashes():
    return {str(f.relative_to(w)): hashlib.sha256(f.read_bytes()).hexdigest()
            for f in w.rglob('*') if f.is_file() and logs not in f.parents}
def invoke(*args, fails=False, readonly=False):
    before = hashes()
    result = subprocess.run([str(a.cli.resolve()), *map(str, args)], capture_output=True, text=True, timeout=60)
    n = len(commands)
    (logs / f'{n:02}.stdout').write_text(result.stdout)
    (logs / f'{n:02}.stderr').write_text(result.stderr)
    commands.append({'args': list(map(str, args)), 'exit': result.returncode})
    (logs / 'commands.json').write_text(json.dumps(commands, indent=2))
    assert (result.returncode != 0) == fails, (args, result.stdout, result.stderr)
    if readonly or fails:
        assert before == hashes(), ('unexpected workspace change', args)
    return None if fails else json.loads(result.stdout)

at = '2026-07-31T00:00:00Z'
original = json.loads((w / 'source-graph.json').read_text())
source_hash = hashes()['source-graph.json']
args = (w, 'source-graph.json', 'bounded', at, '1')
preview = invoke('plan', 'preview-waves', *args, readonly=True)
assert preview['waves'] == [['root'], ['left'], ['right'], ['join']]
assert preview['added_edges'] == [{'prerequisite_id': 'left', 'consumer_id': 'right'}]
assert preview['saved'] is False
saved = invoke('plan', 'from-waves', *args)
assert saved['saved'] and saved['form'] == preview['form']
assert invoke('plan', 'from-waves', *args, readonly=True) == saved
assert invoke('plan', 'inspect', w, 'bounded', readonly=True) == saved['form']
for width in ('0', '-1', '257', '1.5', 'true', '999999'):
    invoke('plan', 'from-waves', w, 'source-graph.json', 'invalid', at, width, fails=True)
invoke('plan', 'from-waves', w, 'source-graph.json', 'bounded', at, '2', fails=True)
catalog = invoke('compile-capability-catalog', w / 'capability-source-bundle.json', readonly=True)
(w / 'catalog.json').write_text(json.dumps(catalog))
prepared = invoke('plan', 'prepare', w, 'bounded', 'catalog.json', at)
child = json.loads((w / prepared['graph_ref']).read_text())
assert not prepared['dispatched']
for old, new in zip(original['items'], child['items']):
    assert {k:v for k,v in old.items() if k != 'depends_on'} == {k:v for k,v in new.items() if k != 'depends_on'}
    assert set(old['depends_on']) <= set(new['depends_on'])
assert child['items'][2]['depends_on'] == ['root', 'left']
invoke('import-conformant-graph', w, w / prepared['graph_ref'], w / 'catalog.json', at)
status = invoke('status', w, child['graph_id'], readonly=True)
assert len(status['items']) == 4
assert all(item['attempt_count'] == 0 for item in status['items'])
assert hashes()['source-graph.json'] == source_hash
# Missing input and cycle refusals happen before a draft is created.
changed = json.loads(json.dumps(original))
changed['items'][0]['input_artifacts'] = ['requests/missing.json']
(w / 'missing.json').write_text(json.dumps(changed))
invoke('plan', 'from-waves', w, 'missing.json', 'missing', at, '2', fails=True)
changed['items'][0]['input_artifacts'] = original['items'][0]['input_artifacts']
changed['items'][0]['depends_on'] = ['join']
(w / 'cycle.json').write_text(json.dumps(changed))
invoke('plan', 'from-waves', w, 'cycle.json', 'cycle', at, '2', fails=True)
assert sorted(f.name for f in (w / '.moonsuite/products/moonflow/plan-drafts').glob('*.json')) == ['bounded.json']
report = {'passed': True, 'commands': len(commands), 'workspace': str(w),
          'adapter_dispatches': 0, 'source_unchanged': True,
          'cli_sha256': hashlib.sha256(a.cli.read_bytes()).hexdigest()}
(logs / 'RESULT.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
