#!/usr/bin/env python3
"""Dependency-free functional checks for the actual worksheet editing boundary."""
import csv
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import input_rebindings as client

ROOT = Path(__file__).resolve().parents[1]
EXPORTED = ROOT / 'examples/plan-worksheet/outputs/exported.csv'
SCRIPT = ROOT / 'scripts/input_rebindings.py'


def mapping(raw, pairs):
    return json.dumps({'contract_id': 'moonflow.input-rebindings.v1',
                       'worksheet_sha256': client.sha256(raw),
                       'replacements': [{'from': old, 'to': new} for old, new in pairs]},
                      ensure_ascii=False).encode('utf-8')


def csv_bytes(rows, headers=None, bom=False):
    buffer = io.StringIO(newline='')
    writer = csv.DictWriter(buffer, fieldnames=headers or list(rows[0]), lineterminator='\r\n')
    writer.writeheader()
    writer.writerows(rows)
    return (('\ufeff' if bom else '') + buffer.getvalue()).encode('utf-8')


def cells(raw):
    return list(csv.DictReader(io.StringIO(raw.decode('utf-8-sig'), newline='')))


def shared_fixture():
    rows = cells(EXPORTED.read_bytes())
    for row in rows[1:3]:
        row['input_artifacts'] = json.dumps(json.loads(row['input_artifacts']) + ['references/finish-v1.json'])
    return csv_bytes(rows)


class InputRebindingsTests(unittest.TestCase):
    def test_captured_native_export_and_existing_native_import_fixture(self):
        raw = EXPORTED.read_bytes()
        sheet = client.parse_worksheet(raw)
        graph = json.loads((EXPORTED.parents[1] / 'source-graph.json').read_text())
        recorded = json.loads((EXPORTED.parent / 'preview.json').read_text())
        self.assertEqual(sheet['source_graph_digest'], recorded['form']['source_graph_digest'])
        for row, item in zip(sheet['rows'], graph['items']):
            self.assertEqual(row['work_item_id'], item['work_item_id'])
            for key in ('input_artifacts', 'depends_on', 'acceptance_criteria'):
                self.assertEqual(json.loads(row[key]), item[key])
        report, output = client.plan_rebindings(sheet, mapping(raw, [('requests/left.json', 'requests/left-v2.json')]))
        self.assertEqual(report['changed_item_ids'], ['left'])
        # Independent stdlib CSV consumption: retained cells match the actual
        # native export; the changed input matches the recorded native import.
        for before, after in zip(cells(raw), cells(output)):
            for key in client.HEADERS:
                if before['work_item_id'] == 'left' and key == 'input_artifacts':
                    expected = next(item for item in recorded['form']['items'] if item['work_item_id'] == 'left')
                    self.assertEqual(json.loads(after[key]), expected[key])
                else:
                    self.assertEqual(after[key], before[key])
        self.assertEqual(report['output_sha256'], client.sha256(output))
        self.assertEqual(client.parse_worksheet(output)['inputs'][1], ['requests/left-v2.json'])

    def test_shared_input_inventory_includes_parallel_consumers_in_sheet_order(self):
        report = client.inventory(client.parse_worksheet(shared_fixture()))
        self.assertEqual((report['work_item_count'], report['reference_count'], report['unique_input_count']), (4, 6, 5))
        shared = [entry for entry in report['inputs'] if entry['shared']]
        self.assertEqual(shared, [{'artifact_ref': 'references/finish-v1.json', 'work_item_ids': ['left', 'right'],
                                  'product_ids': ['moonmold'], 'shared': True}])
        self.assertFalse(report['payloads_read'])
        self.assertFalse(report['dispatched'])

    def test_one_explicit_rebind_updates_all_shared_uses_and_no_other_cells(self):
        raw = shared_fixture()
        report, output = client.plan_rebindings(client.parse_worksheet(raw),
            mapping(raw, [('references/finish-v1.json', 'references/finish-v2.json')]))
        self.assertEqual(report['changed_item_ids'], ['left', 'right'])
        for before, after in zip(cells(raw), cells(output)):
            for key in client.HEADERS:
                if key != 'input_artifacts':
                    self.assertEqual(after[key], before[key])
            expected = ['references/finish-v2.json' if value == 'references/finish-v1.json' else value
                        for value in json.loads(before['input_artifacts'])]
            self.assertEqual(json.loads(after['input_artifacts']), expected)

    def test_simultaneous_swap_and_non_cascading_chain(self):
        raw = EXPORTED.read_bytes()
        sheet = client.parse_worksheet(raw)
        _, swapped = client.plan_rebindings(sheet, mapping(raw, [('requests/root.json', 'requests/left.json'),
                                                                ('requests/left.json', 'requests/root.json')]))
        self.assertEqual(client.parse_worksheet(swapped)['inputs'][:2], [['requests/left.json'], ['requests/root.json']])
        _, chained = client.plan_rebindings(sheet, mapping(raw, [('requests/root.json', 'requests/left.json'),
                                                                ('requests/left.json', 'requests/right.json')]))
        self.assertEqual(client.parse_worksheet(chained)['inputs'][:3],
                         [['requests/left.json'], ['requests/right.json'], ['requests/right.json']])

    def test_reordered_bom_sheet_preserves_exact_cells_and_path_spelling(self):
        rows = list(reversed(cells(EXPORTED.read_bytes())))
        odd = ' inputs\\café, "quoted"\nreference.json '
        rows[0]['input_artifacts'] = json.dumps([odd])
        rows[0]['acceptance_criteria'] = '["Keep spaces, commas and \\"quotes\\"", "CR\\r\\nLF"]'
        rows[0]['timeout_ms'] = ' 60000 '
        raw = csv_bytes(rows, list(reversed(client.HEADERS)), bom=True)
        target = ' other\\材料, "new"\nref.json '
        _, output = client.plan_rebindings(client.parse_worksheet(raw), mapping(raw, [(odd, target)]))
        before, after = cells(raw), cells(output)
        self.assertEqual(list(before[0]), list(after[0]))
        self.assertEqual(json.loads(after[0]['input_artifacts']), [target])
        for old, new in zip(before, after):
            self.assertEqual({k: v for k, v in old.items() if k != 'input_artifacts'},
                             {k: v for k, v in new.items() if k != 'input_artifacts'})
        text = client.render_text(client.inventory(client.parse_worksheet(output)))
        self.assertIn('\\nref.json', text)
        self.assertNotIn('"new"\nref.json', text)

    def test_native_path_predicate_is_lexical_and_never_rewrites_values(self):
        # Boundary.mbt deliberately accepts dot segments and backslashes; it
        # does not establish real path containment, existence or portability.
        for ref in ['requests/./file.json', 'a\\b.json', ' spaced/file.json ', 'C:relative.json']:
            self.assertTrue(client.artifact_reference(ref))
        for ref in ['/outside', 'a/../outside', 'a//b', '\\outside', 'a/']:
            self.assertFalse(client.artifact_reference(ref))

    def test_duplicate_inputs_after_rebinding_are_not_silently_deduplicated(self):
        raw = shared_fixture()
        with self.assertRaisesRegex(ValueError, 'duplicate inputs for left'):
            client.plan_rebindings(client.parse_worksheet(raw),
                mapping(raw, [('references/finish-v1.json', 'requests/left.json')]))

    def test_unused_and_stale_rebinds_require_new_explicit_intent(self):
        raw = EXPORTED.read_bytes()
        spec = mapping(raw, [('requests/left.json', 'requests/left-v2.json')])
        with self.assertRaisesRegex(ValueError, 'worksheet bytes changed'):
            client.plan_rebindings(client.parse_worksheet(b'\xef\xbb\xbf' + raw), spec)
        with self.assertRaisesRegex(ValueError, 'source is absent'):
            client.plan_rebindings(client.parse_worksheet(raw), mapping(raw, [('absent.json', 'new.json')]))

    def test_actual_cli_inventory_preview_save_and_reopen_without_payloads(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = shared_fixture()
            source = root / 'source.csv'; source.write_bytes(raw)
            spec = root / 'mapping.json'; spec.write_bytes(mapping(raw, [('references/finish-v1.json', 'references/finish-v2.json')]))
            target = root / 'changed.csv'
            invoke = lambda *args: subprocess.run([sys.executable, '-B', str(SCRIPT), *map(str, args)],
                                                  cwd=root, capture_output=True, text=True)
            inv = invoke('inventory', source)
            self.assertEqual(inv.returncode, 0, inv.stderr)
            self.assertEqual(json.loads(inv.stdout)['shared_input_count'], 1)
            preview = invoke('preview', source, spec)
            self.assertEqual(preview.returncode, 0, preview.stderr)
            self.assertEqual(set(path.name for path in root.iterdir()), {'source.csv', 'mapping.json'})
            saved = invoke('rebind', source, spec, target)
            self.assertEqual(saved.returncode, 0, saved.stderr)
            receipt = json.loads(saved.stdout)
            self.assertEqual(receipt['output_sha256'], json.loads(preview.stdout)['output_sha256'])
            self.assertEqual(receipt['output_sha256'], client.sha256(target.read_bytes()))
            self.assertEqual(invoke('inventory', target, '--text').returncode, 0)
            self.assertEqual(client.parse_worksheet(target.read_bytes())['inputs'][1][-1], 'references/finish-v2.json')
            self.assertEqual(source.read_bytes(), raw)
            self.assertEqual(set(path.name for path in root.iterdir()), {'source.csv', 'mapping.json', 'changed.csv'})
            again = invoke('rebind', source, spec, target)
            self.assertEqual(again.returncode, 2)
            self.assertEqual(again.stdout, '')
            self.assertEqual(client.sha256(target.read_bytes()), receipt['output_sha256'])
            self.assertEqual(invoke('rebind', source, spec, source).returncode, 2)
            self.assertEqual(source.read_bytes(), raw)

    def test_failed_cli_preview_creates_no_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source.csv'; source.write_bytes(shared_fixture())
            spec = root / 'mapping.json'
            spec.write_bytes(mapping(source.read_bytes(), [('references/finish-v1.json', 'requests/left.json')]))
            target = root / 'never.csv'
            result = subprocess.run([sys.executable, '-B', str(SCRIPT), 'rebind', str(source), str(spec), str(target)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertFalse(target.exists())
            self.assertIn('duplicate inputs', result.stderr)

    def test_repeated_targets_cannot_grow_beyond_native_worksheet_bound(self):
        raw = shared_fixture()
        large_target = 'references/' + 'x' * 530_000
        with self.assertRaisesRegex(ValueError, 'rebound worksheet exceeds'):
            client.plan_rebindings(client.parse_worksheet(raw),
                mapping(raw, [('references/finish-v1.json', large_target)]))

    def test_checked_in_example_is_reproducible(self):
        example = ROOT / 'examples/input-rebindings'
        report, output = client.plan_rebindings(client.parse_worksheet((example / 'worksheet.csv').read_bytes()),
                                                (example / 'rebindings.json').read_bytes())
        self.assertEqual(output, (example / 'rebound.csv').read_bytes())
        self.assertEqual(report, json.loads((example / 'preview.json').read_text()))
        self.assertEqual(report['changed_item_ids'], ['left', 'right'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
