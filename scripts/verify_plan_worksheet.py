#!/usr/bin/env python3
"""Exercise the real MoonFlow CLI in a fresh retained synthetic workspace."""
import argparse, copy, csv, hashlib, io, json, pathlib, shutil, subprocess, tempfile

p = argparse.ArgumentParser()
p.add_argument('--cli', required=True, type=pathlib.Path)
p.add_argument('--workspace-parent', required=True, type=pathlib.Path)
p.add_argument('--record', action='store_true', help='Replace reviewed expected fixture outputs')
a = p.parse_args()
source = pathlib.Path(__file__).resolve().parents[1]
example = source / 'examples/plan-worksheet'
a.workspace_parent.mkdir(parents=True, exist_ok=True)
workspace = pathlib.Path(tempfile.mkdtemp(prefix='worksheet-', dir=a.workspace_parent))
for f in example.rglob('*'):
    if f.is_file() and 'outputs' not in f.relative_to(example).parts and f.suffix in ('.json', '.csv'):
        dest = workspace / f.relative_to(example)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(f, dest)
log = workspace / 'verification-log'
log.mkdir()
commands = []

def hashes():
    return {str(f.relative_to(workspace)): hashlib.sha256(f.read_bytes()).hexdigest()
            for f in workspace.rglob('*') if f.is_file() and log not in f.parents}

def invoke(*args, fails=False, read_only=False):
    before = hashes() if read_only or fails else None
    result = subprocess.run([str(a.cli.resolve()), *map(str, args)], capture_output=True, text=True)
    index = len(commands) + 1
    (log / f'{index:02}.stdout').write_text(result.stdout)
    (log / f'{index:02}.stderr').write_text(result.stderr)
    commands.append({'args': list(map(str,args)), 'exit': result.returncode})
    (log / 'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
    assert (result.returncode != 0) == fails, (args, result.returncode, result.stdout, result.stderr)
    if before is not None:
        assert hashes() == before, ('unexpected workspace mutation', args)
    return result.stdout

def checked_output(name, text):
    (log / name).write_text(text)
    expected = example / 'outputs' / name
    if a.record:
        expected.parent.mkdir(exist_ok=True)
        expected.write_text(text)
    else:
        assert expected.read_text() == text, ('changed expected output', name)

def worksheet_text(rows, headers=None, bom=False):
    headers = headers or list(rows[0])
    b = io.StringIO(newline='')
    writer = csv.DictWriter(b, fieldnames=headers, lineterminator='\r\n', quoting=csv.QUOTE_ALL)
    writer.writeheader(); writer.writerows(rows)
    return ('\ufeff' if bom else '') + b.getvalue()

graph = json.loads((workspace / 'source-graph.json').read_text())
initial_files = {f: h for f, h in hashes().items()}
exported = invoke('plan','export-worksheet',workspace,'source-graph.json',read_only=True)
checked_output('exported.csv', exported)
rows = list(csv.DictReader(io.StringIO(exported)))
assert len(rows) == len(graph['items']) == 4
# Compare with the existing plan-identity projection. Moon's existing helper
# is not Python JSON serialization or an RFC 8785 canonicalization promise.
map_report = json.loads(invoke('graph-map',workspace,'source-graph.json','--json',read_only=True))
expected_digest = map_report['source_graph_digest']
for row, item in zip(rows, graph['items']):
    assert row['source_graph_digest'] == expected_digest
    for name in ('work_item_id','product_id','operation'):
        assert row[name] == item[name]
    for name in ('input_artifacts','depends_on','acceptance_criteria'):
        assert json.loads(row[name]) == item[name]
    assert int(row['timeout_ms']) == item['timeout_ms']

# Offline export does not require a request file. This graph references one that
# never exists; only export is expected to succeed.
offline = copy.deepcopy(graph)
offline['items'][0]['input_artifacts']=['requests/not-present.json']
(workspace/'offline-graph.json').write_text(json.dumps(offline))
assert invoke('plan','export-worksheet',workspace,'offline-graph.json',read_only=True)

expected_items = copy.deepcopy(graph['items'])
expected_items[0]['depends_on']=['left']
expected_items[1].update(depends_on=[], input_artifacts=['requests/left-v2.json'],
    acceptance_criteria=['Review café, "revised" shape\nincluding joints', ' Keep outer spaces '], timeout_ms=90000)
for row, item in zip(rows, expected_items):
    for name in ('input_artifacts','depends_on','acceptance_criteria'):
        row[name]=json.dumps(item[name],ensure_ascii=False,separators=(',', ':'))
    row['timeout_ms']=str(item['timeout_ms'])
# A real sheet commonly changes row/column order and line endings.
edited = worksheet_text(list(reversed(rows)), list(reversed(list(rows[0]))), bom=True)
(workspace/'edited.csv').write_text(edited, newline='')
args=('source-graph.json','edited.csv','revised-study','2026-07-31T00:00:00Z')
preview=invoke('plan','preview-worksheet',workspace,*args,read_only=True)
receipt=json.loads(preview)
assert receipt['changed_item_ids']==['root','left']
assert receipt['row_count']==4 and receipt['saved'] is False
assert receipt['form']['items']==expected_items
assert receipt['csv_digest']=='sha256:'+hashlib.sha256(edited.encode()).hexdigest()
checked_output('preview.json',preview)
saved=invoke('plan','from-worksheet',workspace,*args)
assert json.loads(saved)['form']==receipt['form']
assert json.loads(saved)['saved'] is True
assert invoke('plan','from-worksheet',workspace,*args,read_only=True)==saved
inspected=json.loads(invoke('plan','inspect',workspace,'revised-study',read_only=True))
assert inspected==receipt['form']
draft=invoke('plan','export',workspace,'revised-study',read_only=True)
checked_output('draft.json',draft)
compiled=invoke('compile-capability-catalog',workspace/'capability-source-bundle.json',read_only=True)
(workspace/'catalog.json').write_text(compiled)
prepared=invoke('plan','prepare',workspace,'revised-study','catalog.json','2026-07-31T00:00:00Z')
checked_output('preparation.json',prepared)
assert invoke('plan','prepare',workspace,'revised-study','catalog.json','2026-07-31T00:00:00Z',read_only=True)==prepared
prep=json.loads(prepared)
child=json.loads((workspace/prep['graph_ref']).read_text())
assert child['items']==expected_items and prep['dispatched'] is False
assert child['graph_id']!=graph['graph_id']
assert not (workspace/'.moonsuite/products/moonflow/runs').exists()
invoke('import-conformant-graph',workspace,workspace/prep['graph_ref'],workspace/'catalog.json','2026-07-31T00:00:00Z')
status=json.loads(invoke('status',workspace,child['graph_id'],read_only=True))
assert len(status['items'])==4
for item in status['items']:
    assert item['attempt_count']==0
    assert item['declaration_id']==item['work_item_id']

# Each refusal checks every existing workspace file is unchanged.
negative=[]
def bad(label, mutate):
    bad_rows=copy.deepcopy(rows); mutate(bad_rows)
    path=label+'.csv'; (workspace/path).write_text(worksheet_text(bad_rows))
    negative.append((label,'source-graph.json',path,'invalid-'+label))
bad('missing',lambda r:r.pop())
bad('duplicate',lambda r:r.__setitem__(3,copy.deepcopy(r[0])))
bad('unknown',lambda r:r[0].__setitem__('work_item_id','absent'))
bad('digest',lambda r:r[0].__setitem__('source_graph_digest','sha256:wrong'))
bad('product',lambda r:r[0].__setitem__('product_id','other'))
bad('operation',lambda r:r[0].__setitem__('operation','moonmold/other@0.2.0'))
bad('cycle',lambda r:r[1].__setitem__('depends_on','["root"]'))
bad('dangling',lambda r:r[1].__setitem__('depends_on','["absent"]'))
bad('path',lambda r:r[1].__setitem__('input_artifacts','["../outside.json"]'))
bad('missing-file',lambda r:r[1].__setitem__('input_artifacts','["requests/absent.json"]'))
bad('typed-array',lambda r:r[1].__setitem__('acceptance_criteria','[42]'))
bad('timeout',lambda r:r[1].__setitem__('timeout_ms','1.5'))
# Reuse the same draft ID with different valid edits.
(workspace/'original.csv').write_text(exported)
negative.append(('conflict','source-graph.json','original.csv','revised-study'))
changed=copy.deepcopy(graph); changed['source_digest']='sha256:changed'
(workspace/'changed-graph.json').write_text(json.dumps(changed))
negative.append(('stale','changed-graph.json','edited.csv','stale-draft'))
for label,source_ref,csv_ref,draft_id in negative:
    output=invoke('plan','from-worksheet',workspace,source_ref,csv_ref,draft_id,'2026-07-31T00:00:00Z',fails=True)
    assert output.strip(), label
assert {f:hashes()[f] for f in initial_files}==initial_files
assert sorted(p.name for p in (workspace/'.moonsuite/products/moonflow/plan-drafts').glob('*.json'))==['revised-study.json']
report={'passed':True,'commands':len(commands),'negative_cases':len(negative),
        'workspace':str(workspace),'expected_items':expected_items,
        'cli_sha256':hashlib.sha256(a.cli.read_bytes()).hexdigest(),
        'source_unchanged':True,'adapter_dispatches':0}
(log/'RESULT.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
