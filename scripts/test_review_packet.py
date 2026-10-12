"""Real review-packet process/file tests using labeled native protocol fixtures."""
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / 'scripts/review_packet.py'
FIXTURES = ROOT / 'fixtures/review-packet'
STAMP = '2026-10-11T16:00:00Z'

# It serves retained JSON, does not validate/replay MoonFlow events, and is NOT
# a substitute MoonFlow implementation or dependency route.
PROTOCOL_FIXTURE = r'''
import json, os, pathlib, sys
root = pathlib.Path(os.environ['PACKET_FIXTURE_ROOT'])
command, workspace, run_id, *rest = sys.argv[1:]
with (root/'calls.jsonl').open('a') as out:
    out.write(json.dumps(sys.argv[1:])+'\n')
assert run_id == 'prototype-r1'
if command == 'status':
    assert not rest
    data = json.loads((root/'projection.json').read_text())
    if (root/'change-after-history').exists() and (root/'history-read').exists():
        data['last_sequence'] += 1
elif command == 'run-history':
    assert rest == ['--json', 'inspect-prototype']
    data = json.loads((root/'history.json').read_text())
    (root/'history-read').touch()
else:
    raise AssertionError('Only native read commands are allowed')
print(json.dumps(data,ensure_ascii=False))
'''


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links, self.texts = [], []
    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            self.links.append(dict(attrs)['href'])
    def handle_data(self, data):
        self.texts.append(data)


class ReviewPacketWorkflow(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='moonflow-review-packet-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.workspace = self.root/'workspace with spaces'
        shutil.copytree(FIXTURES/'workspace', self.workspace)
        for name in ['projection.json', 'history.json']:
            shutil.copyfile(FIXTURES/name, self.root/name)
        self.cli = self.root/'native protocol fixture'
        self.cli.write_text(f'#!{sys.executable}\n'+PROTOCOL_FIXTURE)
        self.cli.chmod(0o755)
        self.output = self.root/'review packet.zip'

    def edit(self, name, fn):
        path = self.root/name
        value = json.loads(path.read_text())
        fn(value)
        path.write_text(json.dumps(value))

    def call(self, *extra, output=None):
        return subprocess.run([sys.executable, '-B', str(CLIENT), str(self.workspace),
                               '--cli', str(self.cli), '--run', 'prototype-r1',
                               '--item', 'inspect-prototype', '--recorded-at', STAMP,
                               '--output', str(output or self.output), *extra],
                              env={**os.environ, 'PACKET_FIXTURE_ROOT': str(self.root)},
                              capture_output=True, text=True, timeout=10)

    def snapshot(self):
        return {str(p.relative_to(self.workspace)):p.read_bytes()
                for p in self.workspace.rglob('*') if p.is_file()}

    def assert_blocked(self, detail):
        result = self.call()
        self.assertEqual(result.returncode, 2, result.stdout+result.stderr)
        self.assertIn(detail, result.stderr)
        self.assertFalse(self.output.exists())
        self.assertEqual(result.stdout, '')

    def test_exports_exact_current_bytes_criteria_and_readable_portable_index(self):
        before = self.snapshot()
        result = self.call()
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = json.loads(result.stdout)
        self.assertEqual(receipt['sha256'], 'sha256:'+hashlib.sha256(self.output.read_bytes()).hexdigest())
        self.assertEqual(receipt['artifact_count'], 3)
        self.assertIsNone(receipt['review_decision'])
        with zipfile.ZipFile(self.output) as packet:
            self.assertIsNone(packet.testzip())
            manifest = json.loads(packet.read('manifest.json'))
            self.assertEqual(manifest['item']['acceptance_criteria'],
                             ['Width is 120 mm.', 'Inspect the finish and record any visible defects.'])
            self.assertEqual(manifest['result_event_id'], 'result-recorded')
            self.assertTrue(manifest['artifact_digest_verified'])
            self.assertIsNone(manifest['review_decision'])
            for artifact in manifest['artifacts']:
                self.assertEqual(packet.read(artifact['packet_path']),
                                 (self.workspace/artifact['artifact_ref']).read_bytes())
            self.assertEqual([a['artifact_ref'] for a in manifest['artifacts']],
                             ['outputs/summary.txt','outputs/metrics.json','outputs/thumbnail.png'])
            # Cumulative old/attached evidence is not presented as the current output.
            self.assertEqual(len(packet.namelist()), 6)
            page = packet.read('index.html').decode()
            links = Links(); links.feed(page)
            self.assertTrue(all(link in packet.namelist() for link in links.links))
            self.assertIn('Original acceptance criteria', ''.join(links.texts))
            self.assertIn('awaiting internal review', page)
            self.assertNotIn('unselected-item', packet.read('manifest.json').decode())
            self.assertNotIn('Unselected private criterion', page)
            self.assertEqual(manifest['history_sha256'], 'sha256:'+hashlib.sha256(packet.read('history.json')).hexdigest())
        self.assertEqual(before, self.snapshot())
        calls = [json.loads(line) for line in (self.root/'calls.jsonl').read_text().splitlines()]
        self.assertEqual([c[0] for c in calls], ['status','run-history','status'])
        self.assertEqual(calls[1][-2:], ['--json','inspect-prototype'])

    def test_reopened_export_is_repeatable_and_does_not_overwrite_a_prior_packet(self):
        first = self.call()
        self.assertEqual(first.returncode, 0, first.stderr)
        original = self.output.read_bytes()
        repeated = self.call()
        self.assertEqual(repeated.returncode, 2)
        self.assertIn('already exists', repeated.stderr)
        self.assertEqual(original, self.output.read_bytes())
        second_path = self.root/'review-again.zip'
        second = self.call(output=second_path)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(original, second_path.read_bytes())

    def test_updated_output_requires_investigation_instead_of_exporting_stale_result(self):
        (self.workspace/'outputs/metrics.json').write_text('{"width_mm":121}\n')
        self.assert_blocked('do not match the recorded result digest')

    def test_missing_current_file_is_a_blocker_but_old_unavailable_files_are_not_needed(self):
        (self.workspace/'outputs/metrics.json').unlink()
        self.assert_blocked('metrics.json')

    def test_only_pending_success_can_be_sent_to_this_review_workflow(self):
        self.edit('projection.json', lambda p:p['items'][0].update(status='accepted'))
        self.assert_blocked('awaiting review')

    def test_new_attempt_cannot_borrow_historical_result_outputs(self):
        self.edit('projection.json', lambda p:p['items'][0].update(active_attempt_id='attempt-2',result_id='result-2'))
        self.assert_blocked('one current successful result event')

    def test_result_correlation_and_run_head_must_agree_before_files_are_exported(self):
        self.edit('history.json', lambda h:h['entries'][4]['event'].update(output_digest='sha256:wrong'))
        self.assert_blocked('differs in output_digest')
        shutil.copyfile(FIXTURES/'history.json',self.root/'history.json')
        self.edit('history.json', lambda h:h['head'].update(declaration_revision='revision-2'))
        self.assert_blocked('different run revisions or event heads')

    def test_changed_run_during_collection_produces_no_packet_or_review(self):
        (self.root/'change-after-history').touch()
        self.assert_blocked('run changed during export')

    def test_readable_criteria_remain_literal_and_artifact_links_are_generated(self):
        criterion = 'Inspect <script>alert("x")</script> & café finish.'
        self.edit('projection.json', lambda p:p['items'][0].update(acceptance_criteria=[criterion]))
        self.edit('history.json', lambda h:h['entries'][4]['event'].update(acceptance_criteria=[criterion]))
        result = self.call()
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.output) as packet:
            page = packet.read('index.html').decode()
            self.assertNotIn('<script>',page)
            reader = Links(); reader.feed(page)
            self.assertIn(criterion,reader.texts)
            self.assertTrue(all(link.startswith('artifacts/') or link.endswith('.json') for link in reader.links))

    def test_native_source_contract_and_ordered_digest_are_the_consumed_surface(self):
        main = (ROOT/'cmd/main/main.mbt').read_text()
        wire = (ROOT/'wire.mbt').read_text()
        history = (ROOT/'run_history.mbt').read_text()
        adapter = (ROOT/'adapter.mbt').read_text()
        self.assertIn('["status", workspace, run_id] => show_status(workspace, run_id)', main)
        self.assertIn('["run-history", workspace, run_id, format, item_id]',main)
        self.assertIn('identities.push("\\{artifact_ref}|sha256:\\{sha256_hex(bytes)}")',main)
        self.assertIn('sha256_hex(@utf8.encode(identities.join("\\n")))',main)
        self.assertIn('"protocol": "moonflow.run-projection.v3"',wire)
        self.assertIn('"active_attempt_id": item.active_attempt_id',wire)
        self.assertIn('contract_id: "moonflow.run-history.v1"',history)
        self.assertIn('output_artifacts: result.output_artifacts.copy()',adapter)


if __name__ == '__main__':
    unittest.main()
