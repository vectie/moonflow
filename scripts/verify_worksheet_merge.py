#!/usr/bin/env python3
"""Real native worksheet planning integration; reuses an explicit trusted CLI."""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import worksheet_merge as merge_client
from test_input_rebindings import cells, csv_bytes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', required=True, type=Path)
    parser.add_argument('--workspace-parent', required=True, type=Path)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    args.workspace_parent.mkdir(parents=True, exist_ok=True)
    workspace = Path(tempfile.mkdtemp(prefix='merge-', dir=args.workspace_parent))
    example = source / 'examples/plan-worksheet'
    for path in example.rglob('*'):
        if path.is_file() and 'outputs' not in path.relative_to(example).parts and path.suffix == '.json':
            target = workspace / path.relative_to(example)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
    initial = {str(p.relative_to(workspace)): p.read_bytes() for p in workspace.rglob('*') if p.is_file()}
    logs = workspace / 'verification-log'; logs.mkdir()
    commands = []
    def invoke(*argv, fails=False):
        result = subprocess.run(list(map(str, argv)), capture_output=True, text=True)
        number = len(commands) + 1
        (logs / f'{number:02}.stdout').write_text(result.stdout)
        (logs / f'{number:02}.stderr').write_text(result.stderr)
        commands.append({'argv': list(map(str,argv)), 'exit': result.returncode})
        (logs / 'commands.json').write_text(json.dumps(commands, indent=2))
        assert (result.returncode != 0) == fails, (argv, result.stdout, result.stderr)
        return result.stdout
    cli = args.cli.resolve()
    base = invoke(cli, 'plan', 'export-worksheet', workspace, 'source-graph.json').encode()
    left = cells(base); right = cells(base)
    left[1]['input_artifacts'] = '["requests/left-v2.json"]'
    left[1]['timeout_ms'] = '90000'
    right[1]['timeout_ms'] = '120000'
    right[2]['acceptance_criteria'] = '["Inspect revised material finish"]'
    (workspace/'base.csv').write_bytes(base)
    (workspace/'left.csv').write_bytes(csv_bytes(list(reversed(left))))
    (workspace/'right.csv').write_bytes(csv_bytes(right))
    script = source/'scripts/worksheet_merge.py'
    sources=[workspace/name for name in ('base.csv','left.csv','right.csv')]
    preview=json.loads(invoke(sys.executable,'-B',script,'preview',*sources,fails=True))
    assert len(preview['conflicts'])==1 and not preview['ready_to_save']
    resolution=preview['resolution_template']
    resolution['resolutions'][0]['choice']='right'
    resolution_path=workspace/'resolution.json';resolution_path.write_text(json.dumps(resolution))
    merged=workspace/'merged.csv'
    saved=json.loads(invoke(sys.executable,'-B',script,'save',*sources,merged,'--resolutions',resolution_path))
    assert saved['ready_to_save'] and saved['saved_worksheet']
    expected=cells(merged.read_bytes())
    assert expected[1]['timeout_ms']=='120000'
    stamp='2026-07-31T00:00:00Z' # Fixed synthetic fixture health window, not live readiness.
    native_args=('source-graph.json','merged.csv','merged-study',stamp)
    native=json.loads(invoke(cli,'plan','preview-worksheet',workspace,*native_args))
    assert native['changed_item_ids']==['left','right'] and native['saved'] is False
    for row,item in zip(expected,native['form']['items']):
        for field in merge_client.EDITABLE:
            val=int(row[field]) if field=='timeout_ms' else json.loads(row[field])
            assert item[field]==val
    persisted=json.loads(invoke(cli,'plan','from-worksheet',workspace,*native_args))
    assert persisted['form']==native['form'] and persisted['saved'] is True
    reopened=json.loads(invoke(cli,'plan','inspect',workspace,'merged-study'))
    assert reopened==native['form']
    catalog=invoke(cli,'compile-capability-catalog',workspace/'capability-source-bundle.json')
    (workspace/'catalog.json').write_text(catalog)
    prepared=json.loads(invoke(cli,'plan','prepare',workspace,'merged-study','catalog.json',stamp))
    child=json.loads((workspace/prepared['graph_ref']).read_text())
    assert child['items']==native['form']['items'] and prepared['dispatched'] is False
    assert not (workspace/'.moonsuite/products/moonflow/runs').exists()
    # Native rejects same-shaped worksheet tied to a different source graph.
    altered=json.loads((workspace/'source-graph.json').read_text());altered['source_digest']='sha256:changed'
    (workspace/'other-graph.json').write_text(json.dumps(altered))
    invoke(cli,'plan','preview-worksheet',workspace,'other-graph.json','merged.csv','stale',stamp,fails=True)
    # Native also owns input existence; the merge cannot prove readiness.
    missing=expected.copy();missing=[dict(row) for row in missing]
    missing[1]['input_artifacts']='["requests/missing.json"]'
    (workspace/'missing.csv').write_bytes(csv_bytes(missing))
    invoke(cli,'plan','preview-worksheet',workspace,'source-graph.json','missing.csv','missing',stamp,fails=True)
    for name,original in initial.items():
        assert (workspace/name).read_bytes()==original, name
    report={'passed': True, 'commands':len(commands), 'workspace':str(workspace),
            'cli':str(cli),'cli_sha256':hashlib.sha256(cli.read_bytes()).hexdigest(),
            'merged_sha256':merge_client.sha256(merged.read_bytes()), 'source_inputs_preserved':True,
            'draft_reopened':True,'prepared_child_matches':True,'dispatched':False}
    (logs/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
