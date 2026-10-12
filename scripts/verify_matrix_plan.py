#!/usr/bin/env python3
"""Exercise matrix preview, materialization, ordinary editing and preparation."""
import argparse, copy, hashlib, itertools, json, pathlib, shutil, subprocess, tempfile
p = argparse.ArgumentParser()
p.add_argument('--cli', required=True, type=pathlib.Path)
p.add_argument('--workspace-parent', required=True, type=pathlib.Path)
a = p.parse_args()
source = pathlib.Path(__file__).resolve().parents[1]
a.workspace_parent.mkdir(parents=True, exist_ok=True)
w = pathlib.Path(tempfile.mkdtemp(prefix='matrix-', dir=a.workspace_parent))
for f in (source/'examples/matrix-plan').glob('*.json'):
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
def select(value, pointer):
    for token in pointer.split('/')[1:]:
        token=token.replace('~1','/').replace('~0','~')
        value=value[int(token)] if isinstance(value,list) else value[token]
    return value
def replace(value, pointer, replacement):
    tokens=[t.replace('~1','/').replace('~0','~') for t in pointer.split('/')[1:]]
    for token in tokens[:-1]: value=value[int(token)] if isinstance(value,list) else value[token]
    value[int(tokens[-1]) if isinstance(value,list) else tokens[-1]]=replacement
stamp = '2026-07-31T00:00:00Z'
args=('source-graph.json','matrix.json','request-template.json','study',stamp)
original=hashes()
preview=invoke('plan','preview-matrix',w,*args,readonly=True)
assert preview['saved'] is False and not (w/'.moonsuite').exists()
matrix=json.loads((w/'matrix.json').read_text())
template=json.loads((w/'request-template.json').read_text())
expected=[]
for choices in itertools.product(*(axis['values'] for axis in matrix['axes'])):
    expected.append({'id':'--'.join([matrix['item_prefix']]+[c['key'] for c in choices]),
                     'keys':{axis['name']:c['key'] for axis,c in zip(matrix['axes'],choices)},
                     'parameters':{axis['name']:c['value'] for axis,c in zip(matrix['axes'],choices)}})
assert preview['combinations']==expected and len(expected)==8
for record,artifact,item in zip(expected,preview['artifacts'],preview['form']['items']):
    request=copy.deepcopy(template)
    for binding in matrix['bindings']: replace(request,binding['target_pointer'],select(record,binding['value_pointer']))
    assert json.loads(artifact['json_text'])==request
    h=hashlib.sha256(artifact['json_text'].encode()).hexdigest()
    assert artifact['sha256']=='sha256:'+h
    assert artifact['artifact_ref']=='.moonsuite/products/moonflow/plan-inputs/'+h+'/artifact'
    assert artifact['work_item_id']==record['id']==item['work_item_id']
    assert item['input_artifacts']==[artifact['artifact_ref']] and item['depends_on']==[]
saved=invoke('plan','from-matrix',w,*args)
assert saved['saved'] is True and saved['form']==preview['form']
for artifact in saved['artifacts']:
    assert (w/artifact['artifact_ref']).read_bytes()==artifact['json_text'].encode()
assert invoke('plan','from-matrix',w,*args,readonly=True)==saved
assert invoke('plan','inspect',w,'study',readonly=True)==saved['form']
# Existing editable plan operations work with generated matrix items.
exported=invoke('plan','export',w,'study',readonly=True)
first=copy.deepcopy(exported['edits'][0])
first['acceptance_criteria']=['Review this explicitly revised matrix variant']
# Follow the existing single-item edit envelope, preserving expected draft identity.
store('edit.json', {'expected_draft':exported,'item_edit':{k:first[k] for k in ['work_item_id','input_artifacts','depends_on','acceptance_criteria','timeout_ms']}})
edited=invoke('plan','edit',w,'study','edit.json')
assert edited['items'][0]['acceptance_criteria']==first['acceptance_criteria']
# Reimport never replaces an edited saved plan.
invoke('plan','from-matrix',w,*args,fail=True)
catalog=invoke('compile-capability-catalog',w/'capability-source-bundle.json',readonly=True)
store('catalog.json',catalog)
prepared=invoke('plan','prepare',w,'study','catalog.json',stamp)
assert prepared['dispatched'] is False
assert invoke('plan','prepare',w,'study','catalog.json',stamp,readonly=True)==prepared
child=json.loads((w/prepared['graph_ref']).read_text())
assert len(child['items'])==8
for item,original_item in zip(child['items'],preview['form']['items']):
    for key in ('product_id','operation','requested_authority','required_claim','input_contracts','output_contracts','depends_on'):
        assert item[key]==original_item[key]
    assert json.loads((w/item['input_artifacts'][0]).read_text())['model_id']==item['work_item_id']
assert not (w/'.moonsuite/products/moonflow/runs').exists()
# Reordered choices keep each key's stable identity and typed payload.
reordered=copy.deepcopy(matrix);reordered['axes'][0]['values'].reverse()
store('reordered.json',reordered)
other=invoke('plan','preview-matrix',w,'source-graph.json','reordered.json','request-template.json','reordered',stamp,readonly=True)
assert {v['work_item_id']:v['json_text'] for v in other['artifacts']}=={v['work_item_id']:v['json_text'] for v in preview['artifacts']}
# Typed axis objects, arrays, booleans and nulls are transported unchanged.
typed=copy.deepcopy(matrix)
typed['axes']=[{'name':'typed','values':[{'key':'null','value':None},{'key':'array','value':[True,False,3.5]},{'key':'object','value':{'a/b~c':'雪\n"quote"'}}]}]
typed['bindings']=[{'target_pointer':'/request_id','value_pointer':'/id'},{'target_pointer':'/operation/params/name','value_pointer':'/parameters/typed'}]
store('typed.json',typed)
result=invoke('plan','preview-matrix',w,'source-graph.json','typed.json','request-template.json','typed',stamp,readonly=True)
assert [json.loads(x['json_text'])['operation']['params']['name'] for x in result['artifacts']]==[x['value'] for x in typed['axes'][0]['values']]
negative=[]
for label, mutate in [
    ('ambiguous',lambda m:m['axes'][0]['values'][0].update(key='a--b')),
    ('edge-hyphen',lambda m:m['axes'][0]['values'][0].update(key='a-')),
    ('duplicate-key',lambda m:m['axes'][0]['values'].append(m['axes'][0]['values'][0])),
    ('duplicate-axis',lambda m:m['axes'][1].update(name='label')),
    ('missing-value',lambda m:m['axes'][0]['values'][0].pop('value')),
    ('empty-axis',lambda m:m['axes'][0].update(values=[])),
    ('missing-pointer',lambda m:m['bindings'][0].update(value_pointer='/parameters/nope')),
    ('overlap',lambda m:m['bindings'].append({'target_pointer':'/operation','value_pointer':'/parameters/label'})),
    ('contract-change',lambda m:m.update(operation='other/run@9')),
    ('overflow',lambda m:m['axes'].append({'name':'overflow','values':[{'key':'v'+str(i),'value':i} for i in range(33)]})),
    ('long-id',lambda m:m.update(item_prefix='p'*64,axes=[{'name':'label','values':[{'key':'k'*64,'value':1}]}])),
]:
    bad=copy.deepcopy(matrix);mutate(bad);store(label+'.json',bad);negative.append(label+'.json')
for spec in negative:
    invoke('plan','from-matrix',w,'source-graph.json',spec,'request-template.json','bad',stamp,fail=True)
# Existing addressed bytes remain protected by the shared payload save path.
original_args=('source-graph.json','matrix.json','request-template.json','unchanged',stamp)
intact=invoke('plan','from-matrix',w,*original_args)
artifact_path=w/intact['artifacts'][0]['artifact_ref']
artifact_path.write_text('verifier injected corruption\n')
invoke('plan','from-matrix',w,*original_args,fail=True)
assert artifact_path.read_text()=='verifier injected corruption\n'
artifact_path.write_text(intact['artifacts'][0]['json_text'])
assert invoke('plan','from-matrix',w,*original_args,readonly=True)==intact
assert {f:hashes()[f] for f in original}==original
assert not (w/'.moonsuite/products/moonflow/runs').exists()
result={'passed':True,'commands':len(commands),'negative_cases':len(negative)+2,'workspace':str(w),
        'matrix_shape':[2,2,2],'materialized_requests':len(saved['artifacts']),'adapter_dispatches':0,
        'source_files_unchanged':True,'cli_sha256':hashlib.sha256(a.cli.read_bytes()).hexdigest()}
(log/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
