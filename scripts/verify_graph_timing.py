#!/usr/bin/env python3
"""Retained native CLI evidence with independent exhaustive-path timing oracle."""
import argparse, copy, csv, hashlib, io, json, pathlib, random, subprocess, tempfile
p = argparse.ArgumentParser()
p.add_argument('--cli', required=True, type=pathlib.Path)
p.add_argument('--workspace-parent', required=True, type=pathlib.Path)
a = p.parse_args()
a.workspace_parent.mkdir(parents=True, exist_ok=True)
w = pathlib.Path(tempfile.mkdtemp(prefix='timing-', dir=a.workspace_parent))
logs = w / 'evidence'; logs.mkdir()
commands = []

def store(name, data):
    (w/name).write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')

def snapshot():
    return {str(x.relative_to(w)): hashlib.sha256(x.read_bytes()).hexdigest() for x in w.rglob('*') if x.is_file() and logs not in x.parents}

def invoke(graph='graph.json', estimates='estimates.json', fmt='--json', error=None):
    before = snapshot()
    command = [str(a.cli.resolve()), 'graph-timing', str(w), graph, estimates, fmt]
    r = subprocess.run(command, text=True, capture_output=True)
    i = len(commands)+1
    (logs/f'{i:02}.stdout').write_text(r.stdout); (logs/f'{i:02}.stderr').write_text(r.stderr)
    commands.append({'command': command, 'exit':r.returncode, 'expected_error':error})
    (logs/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
    assert snapshot() == before, 'CLI changed workspace'
    assert bool(r.returncode) == bool(error), (command, r.stdout, r.stderr)
    if error:
        assert error in r.stdout+r.stderr, (error, r.stdout, r.stderr)
        return
    return json.loads(r.stdout) if fmt == '--json' else list(csv.DictReader(io.StringIO(r.stdout)))

def graph_for(deps, graph_id='timing-α, "release"\nworksheet'):
    return {'contract_id':'moonsuite.work-model.v1', 'graph_id':graph_id, 'book_id':'timing-fixture', 'declaration_revision':'r1', 'source_digest':'sha256:fixture', 'recorded_at':'2026-10-10T00:00:00Z', 'items':[{
        'work_item_id':name, 'declaration_id':name, 'product_id':'moonmold', 'requested_authority':'workspace-mutation', 'acceptance_criteria':['Review exact artifact'], 'operation':'moonmold/spatial.operation.execute@0.2.0', 'input_contracts':['moonmold/spatial-operation-request@1.0.0'], 'output_contracts':['moonmold/spatial-operation-receipt@1.0.0'], 'required_claim':'digital-artifact', 'input_artifacts':['missing/'+name+'.json'], 'timeout_ms':60000, 'depends_on':prereqs
    } for name,prereqs in deps.items()]}

def estimates_for(g,durations):
    return {'contract_id':'moonflow.duration-estimates.v1', 'graph_id':g['graph_id'], 'durations_seconds':durations}

def oracle(deps, durations):
    # Enumerate every root-to-terminal path, independent of the implementation's
    # forward/backward dynamic programming and layer ordering.
    successors = {n:[] for n in deps}
    for n,ds in deps.items():
        for d in set(ds): successors[d].append(n)
    paths=[]
    def walk(path):
        if not successors[path[-1]]: paths.append(path); return
        for n in successors[path[-1]]: walk(path+[n])
    for n in deps:
        if not deps[n]: walk([n])
    totals=[sum(durations[n] for n in path) for path in paths]
    horizon=max(totals)
    result={}
    for n in deps:
        containing=[path for path in paths if n in path]
        start=max(sum(durations[k] for k in path[:path.index(n)]) for path in containing)
        remaining=max(sum(durations[k] for k in path[path.index(n):]) for path in containing)
        latest=horizon-remaining
        result[n]=(start,start+durations[n],latest,latest+durations[n],latest-start)
    edges={(p[i],p[i+1]) for p,total in zip(paths,totals) if total==horizon for i in range(len(p)-1)}
    return horizon,result,edges

def verify(deps,durations):
    graph=graph_for(deps); graph['items'].reverse()
    estimates=estimates_for(graph,durations)
    store('graph.json',graph);store('estimates.json',estimates)
    r=invoke(); horizon,expected,edges=oracle(deps,durations)
    assert r['minimum_duration_seconds']==horizon
    assert [x['work_item_id'] for x in r['items']]==[x['work_item_id'] for x in graph['items']]
    for item in r['items']:
        n=item['work_item_id']
        assert tuple(item[k] for k in ['earliest_start_seconds','earliest_finish_seconds','latest_start_seconds','latest_finish_seconds','slack_seconds'])==expected[n], (item,expected[n])
        assert item['critical']==(expected[n][-1]==0)
    assert set(r['critical_item_ids'])=={n for n,t in expected.items() if t[-1]==0}
    assert {(e['prerequisite_item_id'],e['consumer_item_id']) for e in r['critical_edges']}==edges
    return graph,estimates,r

# A reviewable named example, with a shortcut and a disconnected branch.
deps={'root':[], 'left':['root'], 'right':['root'], 'join':['root','left','left','right'], 'isolated':[]}
durations={'root':10,'left':20,'right':5,'join':3,'isolated':8}
g,e,r=verify(deps,durations)
store('example-graph.json',g);store('example-estimates.json',e);store('example-report.json',r)
rows=invoke(fmt='--csv')
assert len(rows)==5 and all(row['graph_id']==g['graph_id'] for row in rows)
assert {row['work_item_id']:int(row['slack_seconds']) for row in rows}=={'root':0,'left':0,'right':15,'join':0,'isolated':25}
assert invoke()==r
# New estimates give a different actionable bottleneck and preserve graph identity.
e2=copy.deepcopy(e);e2['durations_seconds']['right']=40;store('changed-estimates.json',e2)
r2=invoke(estimates='changed-estimates.json')
assert r2['minimum_duration_seconds']==53 and set(r2['critical_item_ids'])=={'root','right','join'}
assert r2['source_graph_digest']==r['source_graph_digest'] and r2['estimates_digest']!=r['estimates_digest']
# Fixed-seed small DAGs include ties, zero milestones and parallel/disconnected branches.
for seed in range(8):
    rng=random.Random(seed);names=[f'n{i}' for i in range(9)]
    ds={n:[prior for prior in names[:i] if rng.random()<0.27] for i,n in enumerate(names)}
    verify(ds,{n:rng.randrange(0,6) for n in names})
store('graph.json',g);store('estimates.json',e)
for value in [-1,0.25,604801,'10',None,True]:
    bad=copy.deepcopy(e);bad['durations_seconds']['root']=value;store('bad.json',bad)
    invoke(estimates='bad.json',error='must be an integer')
for kind in ['missing','unknown','wrong-graph','wrong-contract']:
    bad=copy.deepcopy(e)
    if kind=='missing': del bad['durations_seconds']['root']
    elif kind=='unknown': bad['durations_seconds']['typo']=1
    elif kind=='wrong-graph': bad['graph_id']='wrong'
    else: bad['contract_id']='wrong'
    store('bad.json',bad);invoke(estimates='bad.json',error={'missing':'must be an integer','unknown':'unknown duration item','wrong-graph':'does not match','wrong-contract':'expected moonflow.duration-estimates.v1'}[kind])
for kind in ['cycle','missing','empty','duplicate']:
    bad=copy.deepcopy(g)
    if kind=='cycle': next(x for x in bad['items'] if x['work_item_id']=='root')['depends_on']=['join']
    elif kind=='missing':bad['items'][0]['depends_on']=['missing']
    elif kind=='empty':bad['items']=[]
    else:bad['items'].append(bad['items'][0])
    store('bad-graph.json',bad)
    before=snapshot();cmd=[str(a.cli.resolve()),'graph-timing',str(w),'bad-graph.json','estimates.json','--json']
    result=subprocess.run(cmd,capture_output=True,text=True)
    (logs/f'{kind}-invalid-graph.txt').write_text(result.stdout+result.stderr)
    assert result.returncode!=0 and snapshot()==before
invoke(fmt='--xml',error='Use --json or --csv')
invoke(graph='../outside.json',error='artifact')
assert not (w/'.moonsuite').exists()
summary={'status':'pass','recorded_commands':len(commands),'independent_oracle_dags':9,'invalid_graph_cases':4,'workspace':str(w),'cli_sha256':hashlib.sha256(a.cli.read_bytes()).hexdigest(),'no_workspace_mutations':True}
(logs/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2))
