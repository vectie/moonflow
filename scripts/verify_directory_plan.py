#!/usr/bin/env python3
"""Exercise native folder discovery, editable plans, preparation and refusals.

Every generated workspace and log is retained. No adapter is dispatched.
"""
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import stat
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--cli', required=True, type=pathlib.Path)
parser.add_argument('--workspace-parent', required=True, type=pathlib.Path)
args = parser.parse_args()
source = pathlib.Path(__file__).resolve().parents[1]
args.workspace_parent.mkdir(parents=True, exist_ok=True)
workspace = pathlib.Path(tempfile.mkdtemp(prefix='directory-', dir=args.workspace_parent))
shutil.copytree(source / 'examples/directory-plan', workspace, dirs_exist_ok=True)
logs = workspace / 'verification-log'
logs.mkdir()
commands = []
stamp = '2026-07-31T00:00:00Z'
cli = args.cli.resolve()


def snapshot():
    result = {}
    for path in workspace.rglob('*'):
        if logs == path or logs in path.parents:
            continue
        name = str(path.relative_to(workspace))
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            result[name] = ('symlink', os.readlink(path))
        elif stat.S_ISREG(mode):
            result[name] = ('file', hashlib.sha256(path.read_bytes()).hexdigest())
        else:
            result[name] = ('kind', stat.S_IFMT(mode))
    return result


def invoke(*command, error=None, readonly=False):
    before = snapshot() if error is not None or readonly else None
    result = subprocess.run([str(cli), *map(str, command)], capture_output=True, text=True)
    number = len(commands) + 1
    (logs / f'{number:02}.stdout').write_text(result.stdout)
    (logs / f'{number:02}.stderr').write_text(result.stderr)
    commands.append({'args': list(map(str, command)), 'exit': result.returncode,
                     'expected_error': error, 'readonly': readonly})
    (logs / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    assert (result.returncode != 0) == (error is not None), (command, result.stdout, result.stderr)
    if error is not None:
        assert error in result.stdout + result.stderr, (error, result.stdout, result.stderr)
    if before is not None:
        assert snapshot() == before, ('unexpected workspace mutation', command)
    return result.stdout if error is not None else json.loads(result.stdout)


def store(name, value):
    (workspace / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def selection(name, **changes):
    value = json.loads((workspace / 'selection.json').read_text())
    value.update(changes)
    store(name, value)
    return name


def folder(mode, selection_ref='selection.json', draft='folder-study', **kwargs):
    return invoke('plan', mode, workspace, 'source-graph.json', selection_ref, draft, stamp, **kwargs)


# Unicode and punctuation are real path bytes; sort is UTF-16 lexical, not locale order.
for name in ['café, final.json', '😀.json', '\ue000.json']:
    shutil.copyfile(workspace / 'requests/compact.json', workspace / 'requests' / name)
(workspace / 'requests/notes.txt').write_text('This file is not a request.\n')
(workspace / 'requests/UPPER.JSON').write_text('{}\n')
(workspace / 'requests/.hidden.json').write_text('{}\n')
(workspace / 'requests/.ignored').mkdir()
(workspace / 'requests/.ignored/secret.json').write_text('{}\n')
(workspace / 'requests/empty.json').mkdir()  # A matching directory is never an input.
(workspace / 'requests/link').symlink_to('nested', target_is_directory=True)
expected_paths = sorted([
    'requests/compact.json', 'requests/wide.json', 'requests/nested/display.json',
    'requests/café, final.json', 'requests/😀.json', 'requests/\ue000.json',
], key=lambda text: text.encode('utf-16-be'))
preview = folder('preview-directory', readonly=True)
assert preview['saved'] is False
assert not (workspace / '.moonsuite').exists()
assert [entry['artifact_ref'] for entry in preview['entries']] == expected_paths
assert preview['skipped_symlink_refs'] == ['requests/link']
assert preview['scanned_entry_count'] == 13
for entry, item in zip(preview['entries'], preview['form']['items']):
    assert entry['work_item_id'] == 'model-' + hashlib.sha256(entry['artifact_ref'].encode()).hexdigest()
    assert item['work_item_id'] == entry['work_item_id']
    assert item['input_artifacts'] == [entry['artifact_ref']]
    assert item['depends_on'] == []
assert preview['inventory_digest'] == 'sha256:' + hashlib.sha256(
    json.dumps(expected_paths, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
selection('direct.json', recursive=False, suffixes=['.json', '.request.json'])
direct = folder('preview-directory', 'direct.json', readonly=True)
assert [entry['artifact_ref'] for entry in direct['entries']] == [p for p in expected_paths if '/nested/' not in p]
saved = folder('from-directory')
assert saved['form'] == preview['form'] and saved['saved'] is True
assert folder('from-directory', readonly=True) == saved
assert invoke('plan', 'inspect', workspace, 'folder-study', readonly=True) == saved['form']

# A saved draft is a path snapshot: byte edits do not falsely change path identity.
(workspace / 'requests/compact.json').write_text('{"changed":true}\n')
assert folder('from-directory', readonly=True) == saved
old_ids = {e['artifact_ref']: e['work_item_id'] for e in saved['entries']}
(workspace / 'requests/000.json').write_text('{}\n')
expanded = folder('preview-directory', readonly=True)
assert len(expanded['entries']) == len(expected_paths) + 1
assert all(e['work_item_id'] == old_ids[e['artifact_ref']] for e in expanded['entries'] if e['artifact_ref'] in old_ids)
assert expanded['inventory_digest'] != saved['inventory_digest']
folder('from-directory', error='draft identity already exists')
assert invoke('plan', 'inspect', workspace, 'folder-study', readonly=True) == saved['form']

# The normal editor adds explicit ordering and the regular prepare/import path stays usable.
draft = invoke('plan', 'export', workspace, 'folder-study', readonly=True)
edit = dict(draft['edits'][1])
edit['depends_on'] = [draft['edits'][0]['work_item_id']]
edit['acceptance_criteria'] = ['Review the selected request output']
store('edit.json', {'expected_draft': draft, 'item_edit': edit})
edited = invoke('plan', 'edit', workspace, 'folder-study', 'edit.json')
assert edited['items'][1]['depends_on'] == edit['depends_on']
catalog = invoke('compile-capability-catalog', workspace / 'capability-source-bundle.json', readonly=True)
store('catalog.json', catalog)
prepared = invoke('plan', 'prepare', workspace, 'folder-study', 'catalog.json', stamp)
assert prepared['dispatched'] is False
assert invoke('plan', 'prepare', workspace, 'folder-study', 'catalog.json', stamp, readonly=True) == prepared
child = json.loads((workspace / prepared['graph_ref']).read_text())
assert len(child['items']) == len(expected_paths)
original = json.loads((workspace / 'source-graph.json').read_text())['items'][0]
for item in child['items']:
    for key in ('product_id', 'operation', 'requested_authority', 'required_claim', 'input_contracts', 'output_contracts', 'timeout_ms'):
        assert item[key] == original[key]
assert not (workspace / '.moonsuite/products/moonflow/runs').exists()
invoke('import-conformant-graph', workspace, workspace / prepared['graph_ref'], workspace / 'catalog.json', stamp)
status = invoke('status', workspace, child['graph_id'], readonly=True)
assert len(status['items']) == len(expected_paths)
assert all(item['attempt_count'] == 0 for item in status['items'])

# Invalid selections, no matches, invalid source template and symlinked root fail before saving.
for name, changes, error in [
    ('empty', {'suffixes': ['.absent']}, '1..256 matching regular files'),
    ('unknown', {'operation': 'other/run@1'}, 'unknown directory plan selection field'),
    ('glob', {'suffixes': ['*.json']}, 'literal extension'),
    ('parent', {'directory_ref': 'requests/../requests'}, 'canonical non-hidden'),
    ('missing', {'directory_ref': 'missing'}, 'No such file'),
    ('template', {'template_work_item_id': 'unknown'}, 'not an original source item'),
    ('symlink-root', {'directory_ref': 'requests/link'}, 'symlinked or not a directory'),
]:
    ref = selection(name + '.json', **changes)
    folder('from-directory', ref, 'bad-' + name, error=error)
folder('from-directory', draft='../unsafe', error='safe identifier')

# Matching symlinks, dangling symlinks and named pipes are never accepted/read.
for name, kind in [('linked', 'symlink'), ('dangling', 'dangling'), ('special', 'fifo')]:
    directory = workspace / name
    directory.mkdir()
    (directory / 'good.json').write_text('{}\n')
    if kind == 'symlink':
        (directory / 'bad.json').symlink_to('../requests/compact.json')
    elif kind == 'dangling':
        (directory / 'bad.json').symlink_to('../absent.json')
    else:
        os.mkfifo(directory / 'bad.json')
    ref = selection(name + '-selection.json', directory_ref=name)
    folder('from-directory', ref, 'bad-' + name, error='regular file')

# Bounded discovery exercises actual traversal, not just an injected inventory.
large = workspace / 'large'
large.mkdir()
for index in range(257):
    (large / f'{index}.json').touch()
folder('from-directory', selection('large.json', directory_ref='large'), 'bad-large', error='256 matching files')
deep = workspace / 'deep'
deep.mkdir()
for index in range(17):
    deep = deep / str(index)
    deep.mkdir()
folder('from-directory', selection('deep.json', directory_ref='deep'), 'bad-deep', error='16 nested levels')
wide = workspace / 'wide'
wide.mkdir()
for index in range(8193):
    (wide / str(index)).touch()
folder('from-directory', selection('wide.json', directory_ref='wide'), 'bad-wide', error='8192 visited entries')

# Later missing inputs are caught during ordinary preparation, not called complete.
(workspace / 'requests/wide.json').rename(workspace / 'retained-wide.json')
invoke('plan', 'prepare', workspace, 'folder-study', 'catalog.json', stamp, error='does not exist')
assert sorted(p.name for p in (workspace / '.moonsuite/products/moonflow/plan-drafts').glob('*.json')) == ['folder-study.json']
result = {
    'passed': True, 'commands': len(commands),
    'negative_cases': sum(c['expected_error'] is not None for c in commands),
    'workspace': str(workspace), 'selected_requests': len(expected_paths),
    'adapter_dispatches': 0, 'preview_and_failure_snapshots_unchanged': True,
    'cli_sha256': hashlib.sha256(cli.read_bytes()).hexdigest(),
}
(logs / 'RESULT.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
