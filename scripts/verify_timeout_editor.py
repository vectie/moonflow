#!/usr/bin/env python3
"""Run actual emitted timeout-editor handlers through the retained native planner."""
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

PIN = '269fee483db73a215c799845a21ddbbcee4986c269bba3743e41b59ba49b564e'
STAMP = '2026-07-31T00:00:00Z'  # Synthetic catalog health, never current readiness.
MIN_FREE = 4 * 1024**3 + 20 * 1024**2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, required=True)
    parser.add_argument('--workspace-parent', type=Path, required=True)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    cli = args.cli.resolve()
    with cli.open('rb') as stream:
        assert hashlib.file_digest(stream, 'sha256').hexdigest() == PIN
    assert shutil.disk_usage(args.workspace_parent).free >= MIN_FREE, 'free-space guard: 4 GiB + 20 MiB required'
    workspace = Path(tempfile.mkdtemp(prefix='timeout-editor-', dir=args.workspace_parent))
    # Only small synthetic input fixtures, never a repository/source-tree copy.
    example = source/'examples/plan-worksheet'
    for path in example.rglob('*.json'):
        if 'outputs' not in path.relative_to(example).parts:
            destination = workspace/path.relative_to(example)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(path.read_bytes())
    source_path = workspace/'source-graph.json'
    graph = json.loads(source_path.read_bytes())
    graph['operator_annotation'] = {'text': 'Literal </script> λ & quote', 'exact_integer': 9007199254740993}
    source_path.write_text(json.dumps(graph, ensure_ascii=False, indent=2)+'\n')
    originals = {str(path.relative_to(workspace)): path.read_bytes() for path in workspace.rglob('*') if path.is_file()}
    logs = workspace/'verification-log'; logs.mkdir()
    commands = []
    def invoke(*argv, fails=False):
        assert shutil.disk_usage(workspace).free >= MIN_FREE, 'free-space guard'
        with open(os.environ.get('MOON_NATIVE_LOCK', str(args.workspace_parent/'native.lock')), 'a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            result = subprocess.run(list(map(str, argv)), capture_output=True, text=True, timeout=90)
        number = len(commands)+1
        (logs/f'{number:02}.stdout').write_text(result.stdout)
        (logs/f'{number:02}.stderr').write_text(result.stderr)
        commands.append({'argv': list(map(str, argv)), 'exit': result.returncode})
        (logs/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
        assert (result.returncode != 0) == fails, (argv, result.stdout, result.stderr)
        return result.stdout
    page = workspace/'dependency-editor.html'
    exported = json.loads(invoke(sys.executable, '-B', source/'scripts/graph_explorer.py', source_path, page,
                                 '--author', '--cli', cli))
    assert exported['authoring'] and not exported['dispatched']
    # The JS test clicks emitted timeout Preview/Apply/Undo/Download controls and saves
    # bytes from its actual Blob into this form. Python does not synthesize it.
    form_path = workspace/'downloaded-form.json'
    invoke('node', source/'scripts/test_timeout_editor.mjs', page, form_path)
    form = json.loads(form_path.read_bytes())
    assert form['source_graph'] == graph
    assert form['source_graph']['operator_annotation']['exact_integer'] == 9007199254740993
    assert form['contract_id'] == 'moonflow.declared-plan-form-input.v1'
    draft = json.loads(invoke(cli, 'plan', 'from-form', workspace, form_path.name, 'dependency-study', STAMP))
    reopened = json.loads(invoke(cli, 'plan', 'inspect', workspace, 'dependency-study'))
    assert reopened == draft
    draft_path = workspace/'.moonsuite/products/moonflow/plan-drafts/dependency-study.json'
    draft_bytes = draft_path.read_bytes()
    assert json.loads(invoke(cli, 'plan', 'from-form', workspace, form_path.name, 'dependency-study', STAMP)) == draft
    assert draft_path.read_bytes() == draft_bytes
    frozen = lambda row: {key: value for key, value in row.items() if key != 'timeout_ms'}
    for original, actual, edit in zip(graph['items'], draft['items'], form['edits']):
        assert frozen(actual) == frozen(original)
        assert actual['timeout_ms'] == edit['timeout_ms']
    (workspace/'catalog.json').write_text(invoke(cli, 'compile-capability-catalog', workspace/'capability-source-bundle.json'))
    prepared = json.loads(invoke(cli, 'plan', 'prepare', workspace, 'dependency-study', 'catalog.json', STAMP))
    child = json.loads((workspace/prepared['graph_ref']).read_bytes())
    proposal = json.loads((workspace/prepared['proposal_ref']).read_bytes())
    assert child['items'] == draft['items']
    assert not prepared['dispatched'] and not proposal['dispatch_requested']
    assert proposal['parent_graph_id'] == graph['graph_id']
    assert child['graph_id'] != graph['graph_id']
    prepared_bytes = {str(path.relative_to(workspace)): path.read_bytes() for path in
                      (workspace/'.moonsuite/products/moonflow/prepared-plans').rglob('*') if path.is_file()}
    assert json.loads(invoke(cli, 'plan', 'prepare', workspace, 'dependency-study', 'catalog.json', STAMP)) == prepared
    # Even if a downloaded form is manually tampered, the native consumer owns
    # rejection and creates no partial draft for cycle/self/unknown edges.
    for kind, deps in [('cycle', ['join']), ('self', ['right']), ('unknown', ['absent'])]:
        bad = copy.deepcopy(form)
        next(row for row in bad['edits'] if row['work_item_id'] == 'right')['depends_on'] = deps
        path = workspace/(kind+'.json'); path.write_text(json.dumps(bad))
        invoke(cli, 'plan', 'from-form', workspace, path.name, 'bad-'+kind, STAMP, fails=True)
        assert not (draft_path.parent/('bad-'+kind+'.json')).exists()
    for value in [0, -1, 86400001, 1.5, '1000']:
        bad = copy.deepcopy(form); bad['edits'][0]['timeout_ms'] = value
        (workspace/'bad-timeout.json').write_text(json.dumps(bad))
        invoke(cli, 'plan', 'from-form', workspace, 'bad-timeout.json', 'bad-timeout', STAMP, fails=True)
        assert not (draft_path.parent/'bad-timeout.json').exists()
    # Frozen operation/authority are still catalog-validated at preparation.
    bad = copy.deepcopy(form); bad['source_graph']['items'][0]['operation'] = 'moonmold/unknown@0.2.0'
    (workspace/'bad-operation.json').write_text(json.dumps(bad))
    invoke(cli, 'plan', 'from-form', workspace, 'bad-operation.json', 'bad-operation', STAMP)
    invoke(cli, 'plan', 'prepare', workspace, 'bad-operation', 'catalog.json', STAMP, fails=True)
    invoke(cli, 'plan', 'prepare', workspace, 'dependency-study', 'catalog.json', '2026-08-02T00:00:00Z', fails=True)
    assert all((workspace/name).read_bytes() == raw for name, raw in prepared_bytes.items())
    assert not (workspace/'.moonsuite/products/moonflow/runs').exists()
    assert not list(workspace.rglob('events.json'))
    assert all((workspace/name).read_bytes() == raw for name, raw in originals.items())
    assert draft_path.read_bytes() == draft_bytes
    result = {'passed': True, 'workspace': str(workspace), 'commands': len(commands),
              'cli_sha256': PIN, 'native_rebuilt': False, 'emitted_script_tests': 3, 'dom_adapter': True,
              'blob_form_consumed_by_native': True, 'source_bytes_preserved': True,
              'full_source_annotation_preserved': True, 'frozen_declarations_preserved': True,
              'native_refusal_cases': 10, 'draft_reopened': True, 'child_prepared': True,
              'dispatched': False, 'direct_prd_evidence': ['MF-W01', 'MF-W05'],
              'limitations': 'DOM adapter, synthetic catalog planning only. No real browser, dispatch, accepted checkpoint reuse or full suite.'}
    (logs/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__': main()
