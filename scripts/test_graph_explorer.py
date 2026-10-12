#!/usr/bin/env python3
"""Focused offline renderer tests; no Moon, browser or native CLI required."""
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import graph_explorer as explorer

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "examples/graph-explorer/graph-map.json"


def fixture():
    return json.loads(FIXTURE.read_text())


class Elements(HTMLParser):
    def __init__(self, source):
        super().__init__(convert_charrefs=True)
        self.elements = []
        self.texts = []
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        self.elements.append((tag, dict(attrs)))

    def handle_data(self, text):
        self.texts.append(text)


class GraphExplorerTests(unittest.TestCase):
    def test_existing_graph_map_contract_publication_example(self):
        report, digest = explorer.read_report(FIXTURE)
        self.assertEqual(report, fixture())
        source = json.loads((ROOT / 'examples/graph-route/graph.json').read_text())
        self.assertEqual(report['graph_id'], source['graph_id'])
        for actual, declared in zip(report['nodes'], source['items']):
            for field in ('work_item_id', 'product_id', 'operation', 'depends_on'):
                self.assertEqual(actual[field], declared[field])
        self.assertEqual(report['layers'], [['capture', 'license', 'independent'], ['model', 'texture'], ['publish']])
        self.assertEqual(digest, 'sha256:' + hashlib.sha256(FIXTURE.read_bytes()).hexdigest())

    def test_non_topological_source_order_and_shortcut(self):
        report = fixture()
        report['nodes'].reverse()
        report['nodes'][2]['depends_on'].append('capture')  # publish shortcut
        report['edge_count'] += 1
        report['layers'] = [['independent', 'license', 'capture'], ['texture', 'model'], ['publish']]
        report['root_item_ids'] = ['independent', 'license', 'capture']
        report['leaf_item_ids'] = ['independent', 'publish']
        self.assertEqual(explorer.validate(report), report)
        parsed = Elements(explorer.render(report, 'sha256:' + 'f' * 64))
        ids = {attrs.get('id') for tag, attrs in parsed.elements}
        self.assertTrue(all(f'node-{i}' in ids for i in range(6)))
        self.assertTrue(any(a.get('href') == '#node-5' for _, a in parsed.elements))

    def test_singleton_is_root_and_leaf(self):
        report = fixture()
        report.update(nodes=[report['nodes'][0]], layers=[['capture']],
                      root_item_ids=['capture'], leaf_item_ids=['capture'], edge_count=0)
        self.assertEqual(explorer.validate(report)['edge_count'], 0)

    def test_full_supported_chain(self):
        report = fixture()
        report['nodes'] = [dict(work_item_id=f'n{i}', product_id='p', operation='p/op@1',
                                depends_on=[] if i == 0 else [f'n{i-1}'], layer=i) for i in range(256)]
        report.update(layers=[[f'n{i}'] for i in range(256)], root_item_ids=['n0'],
                      leaf_item_ids=['n255'], edge_count=255)
        self.assertEqual(len(explorer.validate(report)['layers']), 256)
        self.assertLess(len(explorer.render(report, 'sha256:' + '0' * 64)), 350000)

    def test_static_complete_graph_and_offline_assets(self):
        report = fixture()
        document = explorer.render(report, 'sha256:' + 'c' * 64)
        parsed = Elements(document)
        self.assertEqual(len([1 for tag, attrs in parsed.elements if tag == 'article']), 6)
        self.assertEqual(len([1 for tag, attrs in parsed.elements if tag == 'script']), 2)
        self.assertTrue(any(tag == 'noscript' for tag, attrs in parsed.elements))
        for tag, attrs in parsed.elements:
            self.assertNotIn('src', attrs)
            if 'href' in attrs:
                self.assertTrue(attrs['href'].startswith('#node-'))
        self.assertIn('6 work items', document)
        self.assertIn(report['source_graph_digest'], document)
        self.assertIn('Exact imported graph-map file SHA-256', document)

    def test_labels_remain_text_and_json(self):
        report = fixture()
        hostile = '</script><img src="https://invalid/" onerror="alert(1)"> λ & "quote"'
        report['graph_id'] = hostile
        report['nodes'][0]['operation'] = hostile
        document = explorer.render(explorer.validate(report), 'sha256:' + 'd' * 64)
        parsed = Elements(document)
        self.assertFalse(any(tag == 'img' for tag, attrs in parsed.elements))
        self.assertEqual(len([1 for tag, attrs in parsed.elements if tag == 'script']), 2)
        data = document.split('<script id="graph-data" type="application/json">')[1].split('</script>')[0]
        self.assertEqual(json.loads(data)['report']['nodes'][0]['operation'], hostile)
        self.assertIn(hostile, parsed.texts)

    def test_reject_inconsistent_topology(self):
        changes = [lambda r: r.update(edge_count=0), lambda r: r.update(root_item_ids=[]),
                   lambda r: r.update(leaf_item_ids=[]), lambda r: r.update(layers=[]),
                   lambda r: r['nodes'][0].update(layer=1),
                   lambda r: r['nodes'][0].update(depends_on=['publish']),
                   lambda r: r['nodes'][1].update(depends_on=['absent']),
                   lambda r: r['nodes'][1].update(depends_on=['capture', 'capture']),
                   lambda r: r['nodes'][1].update(work_item_id='capture')]
        for change in changes:
            with self.subTest(change=change):
                report = fixture()
                change(report)
                with self.assertRaises(explorer.ExplorerError):
                    explorer.validate(report)

    def test_contract_types_and_limits(self):
        for change in [lambda r: r.update(contract_id='moonsuite.work-model.v1'),
                       lambda r: r.update(source_graph_digest='sha256:unverified'),
                       lambda r: r.update(nodes=[]), lambda r: r.update(nodes=r['nodes'] * 43),
                       lambda r: r.update(edge_count=True), lambda r: r['nodes'][0].update(layer=False),
                       lambda r: r['nodes'][0].update(operation=''),
                       lambda r: r['nodes'][0].update(operation='x' * 16385)]:
            report = fixture(); change(report)
            with self.assertRaises(explorer.ExplorerError): explorer.validate(report)

    def test_read_refuses_incomplete_duplicate_and_oversize_reports(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'input.json'
            for raw in [b'{"contract_id":"x","contract_id":"y"}', b'\xff', b'{',
                        b'null', b'NaN', b' ' * (explorer.MAX_REPORT + 1)]:
                path.write_bytes(raw)
                with self.assertRaises(explorer.ExplorerError): explorer.read_report(path)

    def test_cli_exports_reopenable_deterministic_file_and_receipt(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            source = folder / 'graph-map.json'; source.write_bytes(FIXTURE.read_bytes())
            outputs = [folder / 'first.html', folder / 'second.html']
            for output in outputs:
                process = subprocess.run([sys.executable, '-B', str(ROOT / 'scripts/graph_explorer.py'),
                                          str(source), str(output)], capture_output=True, text=True)
                self.assertEqual(process.returncode, 0, process.stderr)
                receipt = json.loads(process.stdout)
                self.assertEqual(receipt['html_sha256'], 'sha256:' + hashlib.sha256(output.read_bytes()).hexdigest())
                self.assertEqual(receipt['node_count'], 6)
                self.assertFalse(receipt['dispatched'])
            self.assertEqual(outputs[0].read_bytes(), outputs[1].read_bytes())
            self.assertEqual(source.read_bytes(), FIXTURE.read_bytes())
            self.assertEqual({p.name for p in folder.iterdir()}, {'graph-map.json', 'first.html', 'second.html'})

    def test_cli_never_overwrites_existing_or_source_files(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'source.json'; source.write_bytes(FIXTURE.read_bytes())
            output = Path(temp) / 'output.html'; output.write_bytes(b'existing')
            for target in (output, source):
                process = subprocess.run([sys.executable, '-B', str(ROOT / 'scripts/graph_explorer.py'),
                                          str(source), str(target)], capture_output=True, text=True)
                self.assertEqual(process.returncode, 2)
                self.assertEqual(process.stdout, '')
            self.assertEqual(source.read_bytes(), FIXTURE.read_bytes())
            self.assertEqual(output.read_bytes(), b'existing')

    def test_cli_invalid_export_leaves_no_output(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'bad.json'; source.write_text('{"error":"native read failed"}')
            output = Path(temp) / 'output.html'
            process = subprocess.run([sys.executable, '-B', str(ROOT / 'scripts/graph_explorer.py'),
                                      str(source), str(output)], capture_output=True, text=True)
            self.assertEqual(process.returncode, 2)
            self.assertFalse(output.exists())
            self.assertIn('expected moonflow.declared-graph-map.v1', process.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
