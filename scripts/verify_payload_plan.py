#!/usr/bin/env python3
"""Verify actual template materialization, draft reuse and preparation via CLI."""
import argparse, copy, hashlib, json, pathlib, shutil, subprocess, tempfile
p = argparse.ArgumentParser()
p.add_argument('--cli', required=True, type=pathlib.Path)
p.add_argument('--workspace-parent', required=True, type=pathlib.Path)
a = p.parse_args()
source = pathlib.Path(__file__).resolve().parents[1]
a.workspace_parent.mkdir(parents=True, exist_ok=True)
w = pathlib.Path(tempfile.mkdtemp(prefix='payloads-', dir=a.workspace_parent))
for f in (source/'examples/payload-plan').glob('*.json'):
    shutil.copyfile(f, w/f.name)
log = w/'verification-log'; log.mkdir()
commands = []
def hashes():
    return {str(f.relative_to(w)): hashlib.sha256(f.read_bytes()).hexdigest()
            for f in w.rglob('*') if f.is_file() and log not in f.parents}
def invoke(*args, fail=False, readonly=False):
    before = hashes() if fail or readonly else None
    r = subprocess.run([str(a.cli.resolve()), *map(str,args)], capture_output=True, text=True)
    n = len(commands)+1
    (log/f'{n:02}.stdout').write_text(r.stdout)
    (log/f'{n:02}.stderr').write_text(r.stderr)
    commands.append({'args':list(map(str,args)), 'exit':r.returncode})
    (log/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
    assert (r.returncode != 0) == fail, (args,r.returncode,r.stdout,r.stderr)
    if before is not None: assert hashes()==before, ('unexpected mutation',args)
    return r.stdout if fail else json.loads(r.stdout)
def store(name, value): (w/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
stamp = '2026-07-31T00:00:00Z'
args = ('source-graph.json','mapping.json','request-template.json','records.json','study',stamp)
original = hashes()
preview = invoke('plan','preview-payloads',w,*args,readonly=True)
assert preview['saved'] is False
assert not (w/'.moonsuite').exists()
records = json.loads((w/'records.json').read_text())['jobs']
template = json.loads((w/'request-template.json').read_text())
assert len(preview['artifacts'])==3
for record,artifact,item in zip(records,preview['artifacts'],preview['form']['items']):
    expected = copy.deepcopy(template)
    expected.update(request_id=record['request_id'],idempotency_key=record['request_id'],model_id=record['id'])
    expected['operation']['params']['name']=record['name']
    assert json.loads(artifact['json_text'])==expected
    h=hashlib.sha256(artifact['json_text'].encode()).hexdigest()
    assert artifact['sha256']=='sha256:'+h
    assert artifact['artifact_ref']=='.moonsuite/products/moonflow/plan-inputs/'+h+'/artifact'
    assert item['input_artifacts']==[artifact['artifact_ref']]
    assert item['depends_on']==record['after']
    assert item['acceptance_criteria']==record['review']
saved = invoke('plan','from-payloads',w,*args)
assert saved['saved'] is True and saved['form']==preview['form']
for artifact in saved['artifacts']:
    assert (w/artifact['artifact_ref']).read_bytes()==artifact['json_text'].encode()
assert invoke('plan','from-payloads',w,*args,readonly=True)==saved
assert invoke('plan','inspect',w,'study',readonly=True)==saved['form']
catalog = invoke('compile-capability-catalog',w/'capability-source-bundle.json',readonly=True)
store('catalog.json',catalog)
prepared = invoke('plan','prepare',w,'study','catalog.json',stamp)
assert prepared['dispatched'] is False
assert invoke('plan','prepare',w,'study','catalog.json',stamp,readonly=True)==prepared
child = json.loads((w/prepared['graph_ref']).read_text())
for item,original_item in zip(child['items'],preview['form']['items']):
    for key in ('product_id','operation','requested_authority','required_claim','input_contracts','output_contracts','depends_on'):
        assert item[key]==original_item[key]
    assert json.loads((w/item['input_artifacts'][0]).read_text())['model_id']==item['work_item_id']
assert not (w/'.moonsuite/products/moonflow/runs').exists()
invoke('import-conformant-graph',w,w/prepared['graph_ref'],w/'catalog.json',stamp)
status = invoke('status',w,child['graph_id'],readonly=True)
assert len(status['items'])==3 and all(i['attempt_count']==0 for i in status['items'])
# Ancillary inputs remain explicit, existing files after the generated primary.
extra_mapping = json.loads((w/'mapping.json').read_text())
extra_mapping['additional_input_artifacts_pointer']='/files'
extra_records = {'jobs':copy.deepcopy(records)}
for row in extra_records['jobs']: row['files']=[]
extra_records['jobs'][0]['files']=['evidence.json']
store('evidence.json',{'note':'Synthetic room reference'})
store('extra-mapping.json',extra_mapping);store('extra-records.json',extra_records)
extra = invoke('plan','from-payloads',w,'source-graph.json','extra-mapping.json','request-template.json','extra-records.json','with-evidence',stamp)
assert extra['form']['items'][0]['input_artifacts'][1]=='evidence.json'
assert len(extra['form']['items'][0]['input_artifacts'])==2
extra_records['jobs'][0]['files']=['absent-evidence.json']
store('missing-evidence.json',extra_records)
invoke('plan','from-payloads',w,'source-graph.json','extra-mapping.json','request-template.json','missing-evidence.json','bad-evidence',stamp,fail=True)
# Malformed mappings/records are refused before any files or saved drafts change.
mapping = json.loads((w/'mapping.json').read_text())
negative = []
for label, mutate in [
    ('missing',lambda m:m['bindings'][0].update(value_pointer='/missing')),
    ('root',lambda m:m['bindings'][0].update(target_pointer='')),
    ('overlap',lambda m:m['bindings'].append({'target_pointer':'/operation','value_pointer':'/name'})),
    ('operation',lambda m:m.update(operation='other/run@9')),
    ('missing-extra',lambda m:m.update(additional_input_artifacts_pointer='/files')),
]:
    bad=copy.deepcopy(mapping);mutate(bad);store(label+'.json',bad)
    negative.append((label+'.json','records.json','study'))
changed = {'jobs':copy.deepcopy(records)}; changed['jobs'][0]['name']='different'
store('changed.json',changed);negative.append(('mapping.json','changed.json','study'))
cycle={'jobs':copy.deepcopy(records)};cycle['jobs'][0]['after']=['display']
store('cycle.json',cycle);negative.append(('mapping.json','cycle.json','invalid'))
for mapping_ref,records_ref,draft_id in negative:
    invoke('plan','from-payloads',w,'source-graph.json',mapping_ref,'request-template.json',records_ref,draft_id,stamp,fail=True)
# Existing corrupt addressed objects cannot be overwritten by a repeated save.
artifact_path=w/saved['artifacts'][0]['artifact_ref']
artifact_path.write_text('changed externally\n')
invoke('plan','from-payloads',w,*args,fail=True)
assert artifact_path.read_text()=='changed externally\n'
# Restore only this verifier-owned injected corruption and verify the successful repeat.
artifact_path.write_text(saved['artifacts'][0]['json_text'])
assert invoke('plan','from-payloads',w,*args,readonly=True)==saved
assert {f:hashes()[f] for f in original}==original
assert sorted(p.name for p in (w/'.moonsuite/products/moonflow/plan-drafts').glob('*.json'))==['study.json','with-evidence.json']
result={'passed':True,'commands':len(commands),'negative_cases':len(negative)+2,'workspace':str(w),
        'materialized_requests':len(saved['artifacts']),'adapter_dispatches':0,'source_files_unchanged':True,
        'cli_sha256':hashlib.sha256(a.cli.read_bytes()).hexdigest()}
(log/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
