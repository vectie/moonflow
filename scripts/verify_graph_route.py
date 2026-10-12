#!/usr/bin/env python3
"""Retained CLI fixtures and independent dependency-path oracle. No teardown."""
import argparse, collections, copy, hashlib, json, pathlib, subprocess, tempfile
p = argparse.ArgumentParser()
p.add_argument('--cli', required=True)
p.add_argument('--workspace-parent', required=True)
a = p.parse_args()
parent = pathlib.Path(a.workspace_parent); parent.mkdir(parents=True, exist_ok=True)
w = pathlib.Path(tempfile.mkdtemp(prefix='graph-route-', dir=parent))
source = pathlib.Path(__file__).resolve().parents[1]
graph = json.loads((source/'examples/graph-route/graph.json').read_text())
def save(name, value):
    (w/name).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
save('graph.json', graph)
commands=[]
def snapshot():
    return {str(f.relative_to(w)):hashlib.sha256(f.read_bytes()).hexdigest() for f in w.rglob("*") if f.is_file()}
def run(ref, start, end, fmt='--json', success=True):
    cmd=[a.cli,'graph-route',str(w),ref,start,end,fmt]
    before_call=snapshot()
    r=subprocess.run(cmd, text=True, capture_output=True)
    assert snapshot()==before_call, "Route command mutated the workspace"
    i=len(commands); commands.append(dict(command=cmd,returncode=r.returncode))
    (w/f'{i:02d}.stdout').write_text(r.stdout); (w/f'{i:02d}.stderr').write_text(r.stderr)
    (w/'commands.json').write_text(json.dumps(commands,indent=2))
    assert (r.returncode==0)==success,(cmd,r.returncode,r.stderr)
    return json.loads(r.stdout) if success and fmt=='--json' else r.stdout

def oracle(g,start,end):
    ids=[i['work_item_id'] for i in g['items']]
    deps={i['work_item_id']:list(dict.fromkeys(i['depends_on'])) for i in g['items']}
    paths={start:[start]}; q=collections.deque([start])
    while q:
        cur=q.popleft()
        for node in ids:
            if cur in deps[node] and node not in paths:
                paths[node]=paths[cur]+[node]; q.append(node)
    ancestors={end}; todo=[end]
    while todo:
        for dep in deps[todo.pop()]:
            if dep not in ancestors: ancestors.add(dep); todo.append(dep)
    corridor=[i for i in ids if i in paths and i in ancestors]
    inside=[];outside=[]
    for consumer in corridor:
        for dep in deps[consumer]:
            edge={'prerequisite_id':dep,'consumer_id':consumer}
            (inside if dep in corridor else outside).append(edge)
    return dict(reachable=end in paths, shortest_distance=len(paths[end])-1 if end in paths else None,
                shortest_path=paths.get(end,[]),corridor_item_ids=corridor,
                corridor_edges=inside,outside_prerequisite_edges=outside)

def verify(g,ref,start,end):
    result=run(ref,start,end)
    assert result['contract_id']=='moonflow.declared-graph-route.v1'
    assert result['graph_id']==g['graph_id']
    assert result['from_item_id']==start and result['to_item_id']==end
    for key,val in oracle(g,start,end).items(): assert result[key]==val,(key,result[key],val)
    data=(w/ref).read_bytes()
    assert result['input_file']==dict(artifact_ref=ref,sha256='sha256:'+hashlib.sha256(data).hexdigest(),bytes=len(data))
    assert result['source_graph_digest'].startswith('sha256:')
    return result
before=(w/'graph.json').read_bytes()
for start,end in [('capture','publish'),('model','publish'),('publish','capture'),('model','texture'),('model','model')]:
    verify(graph,'graph.json',start,end)
first=verify(graph,'graph.json','capture','publish')
assert verify(graph,'graph.json','capture','publish')==first
text=run('graph.json','model','publish','--text')
assert 'Other prerequisites:' in text and 'not execution readiness' in text
reverse=copy.deepcopy(graph); reverse['items'].reverse(); save('reverse.json',reverse)
verify(reverse,'reverse.json','capture','publish')
shortcut=copy.deepcopy(graph)
next(i for i in shortcut['items'] if i['work_item_id']=='publish')['depends_on']=['capture','model','model']
save('shortcut.json',shortcut); verify(shortcut,'shortcut.json','capture','publish')
unicode_graph=copy.deepcopy(graph)
special='capture \"λ\\n\"'
for item in unicode_graph['items']:
    if item['work_item_id']=='capture': item['work_item_id']=special
    item['depends_on']=[special if d=='capture' else d for d in item['depends_on']]
save('unicode.json',unicode_graph)
verify(unicode_graph,'unicode.json',special,'publish')
assert json.dumps(special,ensure_ascii=False,separators=(',',':')) in run('unicode.json',special,'publish','--text')
run('graph.json','unknown','publish',success=False)
run('graph.json','capture','publish','--csv',success=False)
run('../graph.json','capture','publish',success=False)
bad=copy.deepcopy(graph);bad['items'][-1]['depends_on']=[bad['items'][-1]['work_item_id']]
save('cycle.json',bad);run('cycle.json','capture','publish',success=False)
bounded=copy.deepcopy(graph); template=bounded['items'][0]; bounded['items']=[]
for i in range(257):
    item=copy.deepcopy(template);item.update(work_item_id=f'step-{i}',declaration_id=f'step-{i}',depends_on=[] if i==0 else [f'step-{i-1}']);bounded['items'].append(item)
save('over-bound.json',bounded);run('over-bound.json','step-0','step-1',success=False)
bounded['items']=bounded['items'][:256];save('bound.json',bounded)
verify(bounded,'bound.json','step-0','step-255')
assert (w/'graph.json').read_bytes()==before
assert not (w/'.moonflow').exists()
summary=dict(passed=True,commands=len(commands),workspace=str(w),scope='declared routes only; no dispatch or runtime qualification')
(w/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary))
