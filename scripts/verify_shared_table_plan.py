#!/usr/bin/env python3
"""Exercise selected repetition through the retained native MoonFlow engine."""
import argparse
import copy
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import shared_table_plan as author

PINNED_CLI_SHA256 = 'e85e60dc3109a8fb5d498dcf995d866d4a55610adae2544ab64e2af8991e28c2'
STAMP = '2026-07-31T00:00:00Z'  # Synthetic example catalog's health window, not current health.


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', required=True, type=Path)
    parser.add_argument('--workspace-parent', required=True, type=Path)
    args = parser.parse_args()
    cli = args.cli.resolve()
    assert digest(cli) == PINNED_CLI_SHA256, 'native executable differs from reviewed retained receipt'
    source = Path(__file__).resolve().parents[1]
    args.workspace_parent.mkdir(parents=True, exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix='shared-table-', dir=args.workspace_parent))
    for path in (source / 'examples/shared-table-plan').rglob('*'):
        if path.is_file():
            target = workspace / path.relative_to(source / 'examples/shared-table-plan')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
    shutil.copyfile(source/'examples/table-plan/capability-source-bundle.json',workspace/'capability-source-bundle.json')
    originals = {str(p.relative_to(workspace)): p.read_bytes() for p in workspace.rglob('*') if p.is_file()}
    logs=workspace/'verification-log';logs.mkdir()
    commands=[]
    def invoke(*argv, fails=False):
        is_native=Path(argv[0]) == cli
        if is_native:
            with open(os.environ['MOON_NATIVE_LOCK'],'a') as lock:
                fcntl.flock(lock,fcntl.LOCK_EX)
                result=subprocess.run(list(map(str,argv)),capture_output=True,text=True,timeout=60)
        else:
            result=subprocess.run(list(map(str,argv)),capture_output=True,text=True,timeout=60)
        number=len(commands)+1
        (logs/f'{number:02}.stdout').write_text(result.stdout)
        (logs/f'{number:02}.stderr').write_text(result.stderr)
        commands.append({'argv':list(map(str,argv)),'exit':result.returncode,'expected_failure':fails})
        (logs/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
        assert (result.returncode != 0)==fails,(argv,result.stdout,result.stderr)
        return result.stdout
    def save_form(name, form):
        (workspace/name).write_bytes(author.encode(form))
    def from_form(name, draft, fails=False):
        text=invoke(cli,'plan','from-form',workspace,name,draft,STAMP,fails=fails)
        return None if fails else json.loads(text)
    def prepare(draft, catalog='catalog.json', fails=False, stamp=STAMP):
        text=invoke(cli,'plan','prepare',workspace,draft,catalog,stamp,fails=fails)
        return None if fails else json.loads(text)
    script=source/'scripts/shared_table_plan.py'
    preview=json.loads(invoke(sys.executable,'-B',script,'preview',workspace/'source-graph.json',workspace/'template.json',workspace/'variants.csv'))
    assert not (workspace/'.moonsuite').exists()
    saved=json.loads(invoke(sys.executable,'-B',script,'save',workspace/'source-graph.json',workspace/'template.json',workspace/'variants.csv',workspace/'form.json'))
    assert saved['work_item_count']==9 and saved['shared_item_count']==3 and saved['native_validation_pending']
    assert json.loads((workspace/'form.json').read_text())==preview
    native=from_form('form.json','shared-study')
    assert native['preparation_dispatches'] is False
    reopened=json.loads(invoke(cli,'plan','inspect',workspace,'shared-study'))
    assert reopened==native
    draft_path=workspace/'.moonsuite/products/moonflow/plan-drafts/shared-study.json'
    draft_bytes=draft_path.read_bytes()
    assert from_form('form.json','shared-study')==native
    assert draft_path.read_bytes()==draft_bytes
    exported=json.loads(invoke(cli,'plan','export',workspace,'shared-study'))
    source_graph=json.loads((workspace/'source-graph.json').read_text())
    assert json.loads(exported['source_graph_json'])==source_graph
    assert exported['added_templates']==preview['added_templates']
    assert exported['contract_id']=='moonflow.declared-plan-draft.v2'
    native_items={item['work_item_id']:item for item in native['items']}
    original_items={item['work_item_id']:item for item in source_graph['items']}
    expected_dependencies={'final':['compact--rowjoin','wide--rowjoin','setup'],
                           'setup':[],'audit':['setup']}
    for key in ('compact','wide'):
        expected_dependencies.update({key+'--left':['setup'],key+'--right':['setup'],
                                      key+'--rowjoin':[key+'--left',key+'--right']})
    assert set(native_items)==set(expected_dependencies)
    declarations=set()
    for item_id,item in native_items.items():
        assert item['depends_on']==expected_dependencies[item_id]
        template_id=preview['added_templates'].get(item_id,item_id)
        original=original_items[template_id]
        if item_id in preview['added_templates']:
            key=item_id.split('--',1)[0]
            assert item['input_artifacts']==['requests/'+key+'-'+template_id+'.json']
            criteria=['Review '+key.capitalize()+' study left result'] if template_id=='left' else original['acceptance_criteria']
            assert item['acceptance_criteria']==criteria
            assert item['declaration_id'].startswith('added-')
            assert item['declaration_id'] not in {x['declaration_id'] for x in original_items.values()}
        else:
            assert item['declaration_id']==original['declaration_id']
            assert item['input_artifacts']==original['input_artifacts']
            assert item['acceptance_criteria']==original['acceptance_criteria']
        frozen=set(original)-{'work_item_id','declaration_id','input_artifacts','acceptance_criteria','depends_on'}
        assert {f:item[f] for f in frozen}=={f:original[f] for f in frozen}
        assert item['declaration_id'] not in declarations
        declarations.add(item['declaration_id'])
    (workspace/'catalog.json').write_text(invoke(cli,'compile-capability-catalog',workspace/'capability-source-bundle.json'))
    prepared=prepare('shared-study')
    child=json.loads((workspace/prepared['graph_ref']).read_text())
    proposal=json.loads((workspace/prepared['proposal_ref']).read_text())
    assert child['items']==native['items']
    assert prepared['dispatched'] is False and proposal['dispatch_requested'] is False
    assert proposal['parent_graph_id']==source_graph['graph_id'] and proposal['parent_revision']==source_graph['declaration_revision']
    assert proposal['parent_graph_digest']==native['source_graph_digest']
    assert child['graph_id']!=source_graph['graph_id']
    assert prepare('shared-study')==prepared
    # Row reordering keeps native declaration identity; the sequence/child hash may change.
    template=json.loads((workspace/'template.json').read_text())
    reverse=author.expand(source_graph,template,b'key,label\nwide,Wide study\ncompact,Compact study\n')
    save_form('reverse.json',reverse)
    reordered=from_form('reverse.json','reordered')
    assert {x['work_item_id']:x['declaration_id'] for x in reordered['items']}=={x['work_item_id']:x['declaration_id'] for x in native['items']}
    # A changed input makes a distinct prepared child while leaving parent and old draft intact.
    changed=copy.deepcopy(preview)
    changed['edits'][next(i for i,x in enumerate(changed['edits']) if x['work_item_id']=='compact--left')]['input_artifacts']=['requests/wide-left.json']
    save_form('changed.json',changed)
    from_form('changed.json','shared-study',fails=True)
    assert draft_path.read_bytes()==draft_bytes
    from_form('changed.json','changed-input')
    changed_prepared=prepare('changed-input')
    assert changed_prepared['prepared']['preparation_id']!=prepared['prepared']['preparation_id']
    assert json.loads((workspace/prepared['graph_ref']).read_text())==child
    # Exact engine refusal boundaries: source cycle, unknown operation, missing input, expired health.
    bad=copy.deepcopy(preview)
    next(x for x in bad['source_graph']['items'] if x['work_item_id']=='setup')['depends_on']=['final']
    save_form('cycle.json',bad);from_form('cycle.json','bad-cycle',fails=True)
    assert not (draft_path.parent/'bad-cycle.json').exists()
    bad=copy.deepcopy(preview)
    bad['source_graph']['items'][0]['operation']='moonmold/missing.operation@0.2.0'
    save_form('unknown-operation.json',bad);from_form('unknown-operation.json','unknown-operation')
    prepared_root=workspace/'.moonsuite/products/moonflow/prepared-plans'
    before_prepared={str(p.relative_to(prepared_root)):p.read_bytes() for p in prepared_root.rglob('*') if p.is_file()}
    prepare('unknown-operation',fails=True)
    bad=copy.deepcopy(preview);bad['edits'][0]['input_artifacts']=['requests/missing.json']
    save_form('missing.json',bad);from_form('missing.json','missing-input')
    prepare('missing-input',fails=True)
    prepare('shared-study',stamp='2026-08-02T00:00:00Z',fails=True)
    assert before_prepared=={str(p.relative_to(prepared_root)):p.read_bytes() for p in prepared_root.rglob('*') if p.is_file()}
    # The native v2 boundary, not the authoring code alone, accepts the 256-item edge.
    single=copy.deepcopy(template);single['repeated_work_item_ids']=['left'];single['item_bindings']=single['item_bindings'][:1]
    boundary=author.expand(source_graph,single,('key,label\n'+''.join(f'row{i},Item\n' for i in range(251))).encode())
    save_form('boundary.json',boundary)
    edge=from_form('boundary.json','boundary-256')
    assert len(edge['items'])==256
    # No run registration or effectful command was invoked, even on refused preparations.
    assert not (workspace/'.moonsuite/products/moonflow/runs').exists()
    assert not list(workspace.rglob('events.json'))
    for name,raw in originals.items():assert (workspace/name).read_bytes()==raw,name
    assert draft_path.read_bytes()==draft_bytes
    report={'passed':True,'commands':len(commands),'native_commands':sum(Path(c['argv'][0])==cli for c in commands),
            'workspace':str(workspace),'cli':str(cli),'cli_sha256':digest(cli),
            'graph_items':9,'exact_dependencies_and_declarations':True,'native_256_boundary':True,
            'stable_lineage_after_row_reorder':True,'prepared_child_matches':True,'source_inputs_preserved':True,
            'idempotent_native_import':True,'native_refusal_cases':4,'dispatched':False,
            'scope_limit':'Planning and synthetic catalog validation only; no adapter execution or live checkpoint/recovery claim.'}
    (logs/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
