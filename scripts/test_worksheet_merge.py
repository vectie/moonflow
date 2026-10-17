#!/usr/bin/env python3
"""Functional tests of the real merge implementation and subprocess CLI."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import worksheet_merge as client
from test_input_rebindings import cells, csv_bytes, EXPORTED

SCRIPT = Path(__file__).with_name('worksheet_merge.py')
BASE = EXPORTED.read_bytes()


def branch(*edits, reverse=False):
    rows = cells(BASE)
    for item, field, val in edits:
        next(row for row in rows if row['work_item_id'] == item)[field] = val
    return csv_bytes(list(reversed(rows)) if reverse else rows)


class MergeTests(unittest.TestCase):
    def conflict(self):
        left = branch(('left', 'timeout_ms', '90000'))
        right = branch(('left', 'timeout_ms', '120000'))
        report, _ = client.merge(BASE, left, right)
        return left, right, report['resolution_template']

    def test_independent_edits_retain_all_native_identity_cells(self):
        left = branch(('left', 'input_artifacts', '["requests/left-v2.json"]'))
        right = branch(('right', 'acceptance_criteria', '["Review revised joints"]'))
        report, output = client.merge(BASE, left, right)
        self.assertTrue(report['ready_to_save'])
        self.assertEqual(len(report['changes']), 2)
        for original, merged in zip(cells(BASE), cells(output)):
            for field in client.READONLY:
                self.assertEqual(original[field], merged[field])
        self.assertEqual(cells(output)[1]['input_artifacts'], '["requests/left-v2.json"]')
        self.assertFalse(report['dispatched'])

    def test_reordered_rows_columns_bom_and_semantically_equal_cells(self):
        rows = cells(BASE)
        for row in rows:
            row['timeout_ms'] = ' 0' + row['timeout_ms'] + ' '
            row['depends_on'] = json.dumps(json.loads(row['depends_on']), indent=2)
        left = csv_bytes(list(reversed(rows)), list(reversed(client.HEADERS)), bom=True)
        report, output = client.merge(BASE, left, BASE)
        self.assertEqual(report['changes'], [])
        self.assertEqual(cells(output), cells(BASE))

    def test_identical_edits_are_not_conflicts(self):
        edit = branch(('root', 'acceptance_criteria', '["材料, \\"quoted\\"\\nreview"]'))
        report, output = client.merge(BASE, edit, edit)
        self.assertEqual(report['conflicts'], [])
        self.assertEqual(cells(output)[0]['acceptance_criteria'], cells(edit)[0]['acceptance_criteria'])

    def test_conflict_requires_explicit_choice_and_supports_all_choices(self):
        left, right, template = self.conflict()
        report, output = client.merge(BASE, left, right)
        self.assertIsNone(output)
        self.assertEqual(len(report['conflicts']), 1)
        for choice, expected in [('base', cells(BASE)[1]['timeout_ms']), ('left', '90000'), ('right', '120000'), ('custom', '150000')]:
            spec = copy.deepcopy(template)
            spec['resolutions'][0]['choice'] = choice
            if choice == 'custom':
                spec['resolutions'][0]['value'] = expected
            resolved, raw = client.merge(BASE, left, right, json.dumps(spec).encode())
            self.assertTrue(resolved['conflicts_resolved'])
            self.assertEqual(cells(raw)[1]['timeout_ms'], expected)

    def test_dependency_delete_versus_edit_conflicts(self):
        left = branch(('left', 'depends_on', '[]'))
        right = branch(('left', 'depends_on', '["root","right"]'))
        report, raw = client.merge(BASE, left, right)
        self.assertIsNone(raw)
        self.assertEqual(report['conflicts'][0]['field'], 'depends_on')
        self.assertEqual(report['conflicts'][0]['left'], '[]')

    def test_deleting_a_row_is_refused_even_when_other_side_edits_it(self):
        with self.assertRaisesRegex(ValueError, 'exactly the base'):
            client.merge(BASE, csv_bytes(cells(BASE)[:-1]), branch(('join', 'timeout_ms', '9')))

    def test_disjoint_valid_branches_that_merge_into_cycle_are_blocked(self):
        left = branch(('left', 'depends_on', '["root","right"]'))
        right = branch(('right', 'depends_on', '["root","left"]'))
        report, raw = client.merge(BASE, left, right)
        self.assertIsNone(raw)
        self.assertIn('cycle', report['blocker'])
        self.assertFalse(report['ready_to_save'])

    def test_dependency_edit_and_other_field_merge(self):
        report, raw = client.merge(BASE, branch(('right', 'depends_on', '["left"]')),
                                  branch(('left', 'timeout_ms', '99')))
        self.assertTrue(report['ready_to_save'])
        self.assertEqual(cells(raw)[2]['depends_on'], '["left"]')

    def test_invalid_branch_cycles_dangling_duplicates_and_identity(self):
        for raw in [branch(('root', 'depends_on', '["join"]')),
                    branch(('root', 'depends_on', '["absent"]')),
                    branch(('root', 'product_id', 'other')),
                    branch(('root', 'source_graph_digest', 'sha256:' + 'a' * 64)),
                    csv_bytes(cells(BASE) + [cells(BASE)[0]])]:
            with self.assertRaises(ValueError):
                client.merge(BASE, raw, BASE)

    def test_stale_resolution_binding_each_input(self):
        left, right, spec = self.conflict()
        spec['resolutions'][0]['choice'] = 'left'
        for index in range(3):
            inputs = [BASE, left, right]
            inputs[index] = b'\xef\xbb\xbf' + inputs[index]
            with self.assertRaisesRegex(ValueError, 'bytes changed'):
                client.merge(*inputs, json.dumps(spec).encode())

    def test_altered_resolution_rejects_unknown_duplicate_missing_and_invalid_custom(self):
        left, right, template = self.conflict()
        mutations = [lambda s: s['resolutions'].clear(),
                     lambda s: s['resolutions'].append(s['resolutions'][0]),
                     lambda s: s['resolutions'][0].update(field='operation', choice='left'),
                     lambda s: s['resolutions'][0].update(choice='implicit'),
                     lambda s: s.update(unexpected=True)]
        for change in mutations:
            spec = copy.deepcopy(template); change(spec)
            with self.assertRaises(ValueError):
                client.merge(BASE, left, right, json.dumps(spec).encode())
        spec = copy.deepcopy(template)
        spec['resolutions'][0].update(choice='custom', value='0')
        report, raw = client.merge(BASE, left, right, json.dumps(spec).encode())
        self.assertIsNone(raw)
        self.assertIn('timeout_ms', report['blocker'])

    def test_custom_resolution_cannot_inject_invalid_paths_or_dependency_cycles(self):
        for field, lval, rval, invalid in [('input_artifacts', '["a"]', '["b"]', '["../escape"]'),
                                           ('depends_on', '[]', '["root","right"]', '["join"]')]:
            left, right = branch(('left', field, lval)), branch(('left', field, rval))
            report, _ = client.merge(BASE, left, right)
            spec = report['resolution_template']
            spec['resolutions'][0].update(choice='custom', value=invalid)
            report, raw = client.merge(BASE, left, right, json.dumps(spec).encode())
            self.assertIsNone(raw)
            self.assertIsNotNone(report['blocker'])

    def test_cli_preview_resolve_save_reopen_exclusive_and_preserve_inputs(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            left, right, spec = self.conflict()
            sources = [root / name for name in ('base.csv','left.csv','right.csv')]
            for path, raw in zip(sources, (BASE,left,right)): path.write_bytes(raw)
            before = {p.name:p.read_bytes() for p in sources}
            invoke = lambda *args: subprocess.run([sys.executable, '-B', str(SCRIPT), *map(str,args)],
                                                  cwd=root, capture_output=True, text=True)
            preview = invoke('preview', *sources)
            self.assertEqual(preview.returncode, 2)
            self.assertEqual(set(p.name for p in root.iterdir()), set(before))
            self.assertEqual(json.loads(preview.stdout)['resolution_template'], spec)
            output = root/'merged.csv'
            self.assertEqual(invoke('save', *sources, output).returncode, 2)
            self.assertFalse(output.exists())
            spec['resolutions'][0]['choice']='right'
            resolution = root/'resolve.json'; resolution.write_text(json.dumps(spec))
            saved=invoke('save', *sources, output, '--resolutions', resolution)
            self.assertEqual(saved.returncode, 0, saved.stderr)
            self.assertEqual(cells(output.read_bytes())[1]['timeout_ms'], '120000')
            self.assertEqual(os.stat(output).st_mode & 0o777, 0o600)
            expected=output.read_bytes()
            self.assertEqual(invoke('save', *sources, output, '--resolutions', resolution).returncode, 2)
            alias=root/'alias.csv'; alias.symlink_to(output)
            self.assertEqual(invoke('save', *sources, alias, '--resolutions', resolution).returncode, 2)
            self.assertEqual(output.read_bytes(),expected)
            self.assertEqual({p.name:p.read_bytes() for p in sources},before)

    def test_combined_output_growth_is_bounded_before_save(self):
        text = json.dumps(['x' * 600000])
        left = branch(('root', 'acceptance_criteria', text))
        right = branch(('right', 'acceptance_criteria', text))
        report, raw = client.merge(BASE, left, right)
        self.assertIsNone(raw)
        self.assertIn('exceeds', report['blocker'])

    def test_resolution_duplicate_json_key_is_refused(self):
        left,right,_=self.conflict()
        with self.assertRaisesRegex(ValueError, 'duplicate JSON key'):
            client.merge(BASE,left,right,b'{"contract_id":1,"contract_id":2}')


if __name__ == '__main__':
    unittest.main(verbosity=2)
