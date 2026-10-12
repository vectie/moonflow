#!/usr/bin/env python3
"""Retain real CLI outputs and verify them with a Python structural/closure oracle."""
import argparse, copy, hashlib, json, pathlib, subprocess, tempfile
p=argparse.ArgumentParser()
p.add_argument('--cli', type=pathlib.Path, required=True)
p.add_argument('--workspace-parent', type=pathlib.Path, required=True)
a=p.parse_args()
a.workspace_parent.mkdir(parents=True, exist_ok=True)
w=pathlib.Path(tempfile.mkdtemp(prefix='graph-comparison-', dir=a.workspace_parent))
e=w/'evidence'; e.mkdir()
commands=[]

def save(name,value):
    (w/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')

def snapshot():
    return {str(f.relative_to(w)):hashlib.sha256(f.read_bytes()).hexdigest() for f in w.rglob('*') if f.is_file() and e not in f.parents}

def invoke(before,after,fmt='--json',error=None):
    start=snapshot()
    cmd=[str(a.cli.resolve()),'compare-graphs',str(w),before,after,fmt]
    r=subprocess.run(cmd,capture_output=True,text=True)
    n=len(commands)+1
    (e/f'{n:02}.stdout').write_text(r.stdout);(e/f'{n:02}.stderr').write_text(r.stderr)
    commands.append({'argv':cmd,'exit':r.returncode,'expected_error':error})
    (e/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
    assert start==snapshot(),'comparison mutated workspace'
    assert bool(r.returncode)==bool(error),(cmd,r.stdout,r.stderr)
    if error:
        assert error in r.stdout+r.stderr,(error,r.stdout,r.stderr)
        return None
    return json.loads(r.stdout) if fmt=='--json' else r.stdout

def canonical(value):
    # Existing Flow identity sorts keys by MoonBit String shortlex order.
    if isinstance(value,dict):
        keys=sorted(value,key=lambda k:(len(k.encode('utf-16-be')),k.encode('utf-16-be')))
        return '{'+','.join(json.dumps(k,ensure_ascii=False)+':'+canonical(value[k]) for k in keys)+'}'
    if isinstance(value,list):return '['+','.join(canonical(v) for v in value)+']'
    return json.dumps(value,ensure_ascii=False,separators=(',',':'))

def digest(value):
    return 'sha256:'+hashlib.sha256(canonical(value).encode()).hexdigest()

def fields(old,new):
    return [{'field':k,'before_present':k in old,'before':old.get(k),'after_present':k in new,'after':new.get(k)} for k in sorted(old.keys()|new.keys()) if (k in old)!=(k in new) or old.get(k)!=new.get(k)]

def impact(graph,seeds):
    # Walk backward from each consumer to changed ancestors, independently of
    # production's complete-frontier propagation from changed nodes.
    by_id={i['work_item_id']:i for i in graph['items']}
    distance={}
    def paths(node,seen):
        if node in seeds:return [0]
        result=[]
        for dep in by_id[node]['depends_on']:
            if dep not in seen:result += [n+1 for n in paths(dep,seen|{dep})]
        return result
    for node in by_id:
        ds=paths(node,{node})
        if ds:distance[node]=min(ds)
    return {'contract_id':'moonflow.change-impact.v1','source_graph_digest':digest(graph),
            'changed_item_ids':[n for n in by_id if n in seeds],
            'affected_items':[{'work_item_id':n,'dependency_distance':distance[n],
                              'impacted_prerequisite_ids':[d for d in by_id[n]['depends_on'] if d in distance]}
                              for n in by_id if n in distance and n not in seeds],
            'unaffected_item_ids':[n for n in by_id if n not in distance]}

def verify(old,new,label):
    bn=label+'-before.json'; an=label+'-after.json';save(bn,old);save(an,new)
    r=invoke(bn,an)
    b={i['declaration_id']:i for i in old['items']};c={i['declaration_id']:i for i in new['items']}
    ids=list(b)+[k for k in c if k not in b];rows=[];bs=[];cs=[]
    for k in ids:
        diff=fields(b[k],c[k]) if k in b and k in c else []
        status='added' if k not in b else 'removed' if k not in c else 'changed' if diff else 'unchanged'
        rows.append({'declaration_id':k,'change':status,'before':b.get(k),'after':c.get(k),'fields':diff})
        if status!='unchanged':
            if k in b:bs.append(b[k]['work_item_id'])
            if k in c:cs.append(c[k]['work_item_id'])
    expected={'contract_id':'moonflow.declared-graph-comparison.v1','book_id':old['book_id'],
        'before_graph_digest':digest(old),'after_graph_digest':digest(new),
        'graph_fields':fields({k:v for k,v in old.items() if k!='items'},{k:v for k,v in new.items() if k!='items'}),
        'declaration_order_changed':list(b)!=list(c),'items':rows,
        'before_impact':impact(old,bs),'after_impact':impact(new,cs),
        'input_files':{side:{'artifact_ref':name,'bytes':len((w/name).read_bytes()),'sha256':'sha256:'+hashlib.sha256((w/name).read_bytes()).hexdigest()} for side,name in [('before',bn),('after',an)]}}
    assert r==expected,(r,expected)
    (e/(label+'-expected.json')).write_text(json.dumps(expected,ensure_ascii=False,indent=2)+'\n')
    return r,bn,an

old=json.loads((pathlib.Path(__file__).resolve().parents[1]/'examples/graph-comparison/before.json').read_text())
new=json.loads((pathlib.Path(__file__).resolve().parents[1]/'examples/graph-comparison/after.json').read_text())
r,bn,an=verify(old,new,'edit')
assert r['after_impact']['affected_items'][0]['work_item_id']=='publish'
text=invoke(bn,an,'--text');assert 'source-v2.json' in text and 'Potential dependency effects only' in text
assert '\x1b' not in text
assert invoke(bn,an)==r
# Direction is caller selected and every removal/addition reverses.
verify(new,old,'reverse')
rename=copy.deepcopy(old);rename['items'][1]['work_item_id']='renamed';rename['items'][2]['depends_on']=['renamed']
rename['items'][3]['declaration_id']='new-same-name'
verify(old,rename,'rename-replace')
removed=copy.deepcopy(old);removed['items']=[removed['items'][0],removed['items'][2],removed['items'][3]];removed['items'][1]['depends_on']=[]
verify(old,removed,'remove')
metadata=copy.deepcopy(old);metadata['items'][0]['notes']=None;metadata['items'][0]['custom']={'z':[True,None,2],'a':'α\n\"quoted\"\t\u001b'}
verify(old,metadata,'metadata')
reorder=copy.deepcopy(metadata);reorder['items'].reverse();reorder['items']=[dict(reversed(list(i.items()))) for i in reorder['items']]
rr,_,_=verify(metadata,reorder,'reorder');assert all(i['change']=='unchanged' for i in rr['items'])
verify(old,old,'same')
# Both complete inputs must be valid before any report is emitted.
for label,expected,mutate in [
 ('book','same book_id',lambda g:g.update(book_id='unrelated')),
 ('duplicate','unique declaration_id',lambda g:g['items'][1].update(declaration_id=g['items'][0]['declaration_id'])),
 ('cycle','dependency cycle',lambda g:g['items'][0].update(depends_on=['publish'])),
 ('missing','unknown dependency',lambda g:g['items'][1].update(depends_on=['absent'])),
 ('fraction','whole number',lambda g:g['items'][1].update(timeout_ms=1.5)),
 ('many','at most 256',lambda g:g.update(items=[g['items'][0]]*257)),
]:
    bad=copy.deepcopy(old);mutate(bad);save(label+'.json',bad);invoke(bn,label+'.json',error=expected)
invoke(bn,an,'--html',error='Use --json or --text')
invoke('../outside.json',an,error='workspace-relative')
assert not (w/'.moonsuite').exists()
(e/'RESULT.json').write_text(json.dumps({'status':'passed','commands':len(commands),'oracle':'independent structural diff and backward dependency paths','inputs_unchanged':True,'adapter_dispatches':0,'workspace':str(w)},indent=2)+'\n')
print(json.dumps({'status':'passed','commands':len(commands),'workspace':str(w)}))
