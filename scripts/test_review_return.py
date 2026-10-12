"""Offline reviewer -> source-bound native receipt preparation, via real local CLIs.

The native read process serves labeled protocol fixtures, not a MoonFlow runtime.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

from test_review_packet import PROTOCOL_FIXTURE

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/review_return.py'
EXPORTER = ROOT / 'scripts/review_packet.py'
FIXTURES = ROOT / 'fixtures/review-packet'
STAMP = '2026-10-12T01:00:00Z'


class ReviewReturnWorkflow(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='moonflow-return-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.workspace = self.root / 'workspace with spaces'
        shutil.copytree(FIXTURES / 'workspace', self.workspace)
        (self.workspace / 'reviews').mkdir()
        for name in ('projection.json', 'history.json'):
            shutil.copyfile(FIXTURES / name, self.root / name)
        self.cli = self.root / 'native protocol fixture'
        self.cli.write_text(f'#!{sys.executable}\n' + PROTOCOL_FIXTURE)
        self.cli.chmod(0o755)
        self.env = {**os.environ, 'PACKET_FIXTURE_ROOT': str(self.root)}
        self.packet = self.root / 'pending result.zip'
        self.sheet = self.root / 'criterion findings.json'
        self.receipt = self.workspace / 'reviews' / 'finish-review.json'
        result = self.process(EXPORTER, self.workspace, '--cli', self.cli,
                              '--run', 'prototype-r1', '--item', 'inspect-prototype',
                              '--output', self.packet, '--recorded-at', STAMP)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.command('worksheet', self.packet, '--output', self.sheet).returncode, 0)
        (self.root / 'calls.jsonl').unlink()
        (self.root / 'history-read').unlink()

    def process(self, script, *args):
        return subprocess.run([sys.executable, '-B', str(script), *map(str, args)],
                              env=self.env, capture_output=True, text=True, timeout=15)

    def command(self, *args):
        return self.process(SCRIPT, *args)

    def edit(self, path, fn):
        data = json.loads(path.read_text())
        fn(data)
        path.write_text(json.dumps(data, ensure_ascii=False))
        return data

    def findings(self, decision='accepted'):
        def fill(data):
            data.update(review_id='review-finish-1', reviewer_id='operator:alice',
                        review_authority_id='review-scope:prototype', recorded_at=STAMP,
                        decision=decision)
            for finding in data['criteria']:
                finding.update(satisfied=True, evidence_refs=['outputs/metrics.json'],
                               note='Independently inspected dimensions and visible finish. café ✓')
            if decision == 'rejected':
                data['criteria'][1].update(satisfied=False, evidence_refs=[],
                                           note='The finish contains a visible scratch; revise the output.')
        return self.edit(self.sheet, fill)

    def prepare(self, *extra):
        return self.command('prepare', self.packet, self.sheet, self.workspace,
                            '--cli', self.cli, '--receipt', 'reviews/finish-review.json', *extra)

    def snapshot(self):
        return {str(p.relative_to(self.workspace)): p.read_bytes()
                for p in self.workspace.rglob('*') if p.is_file()}

    def blocked(self, text):
        result = self.prepare()
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn(text, result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertFalse(self.receipt.exists())

    def test_blank_worksheet_preserves_criteria_and_offers_no_optimistic_findings(self):
        value = json.loads(self.sheet.read_text())
        with zipfile.ZipFile(self.packet) as packet:
            manifest = json.loads(packet.read('manifest.json'))
        self.assertEqual(value['packet_sha256'], 'sha256:' + hashlib.sha256(self.packet.read_bytes()).hexdigest())
        self.assertEqual(value['item_binding']['acceptance_criteria'], manifest['item']['acceptance_criteria'])
        self.assertEqual(value['available_evidence'], manifest['artifacts'])
        self.assertIsNone(value['decision'])
        self.assertEqual(value['reviewer_id'], '')
        self.assertTrue(all(f['satisfied'] is None and f['note'] == '' and f['evidence_refs'] == []
                            for f in value['criteria']))
        self.assertFalse((self.root / 'calls.jsonl').exists())

    def test_accepted_findings_prepare_exact_native_receipt_without_submitting(self):
        findings = self.findings()
        before = self.snapshot()
        original_packet, original_sheet = self.packet.read_bytes(), self.sheet.read_bytes()
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        report, receipt = json.loads(result.stdout), json.loads(self.receipt.read_text())
        self.assertEqual(receipt, {
            'contract_id': 'moonflow.acceptance-review.v1', 'run_id': 'prototype-r1',
            'work_item_id': 'inspect-prototype', 'declaration_id': 'declaration-inspect',
            'result_id': 'result-1', 'attempt_id': 'attempt-1',
            'output_digest': findings['item_binding']['output_digest'],
            'receipt_artifact': 'reviews/finish-review.json',
            **{key: findings[key] for key in ('review_id', 'reviewer_id', 'review_authority_id',
                                             'recorded_at', 'decision', 'criteria')}})
        after = self.snapshot(); written = after.pop('reviews/finish-review.json')
        self.assertEqual(before, after)
        self.assertEqual(report['sha256'], 'sha256:' + hashlib.sha256(written).hexdigest())
        self.assertEqual(report['worksheet_sha256'], 'sha256:' + hashlib.sha256(original_sheet).hexdigest())
        self.assertEqual(report['submit_argv'], [str(self.cli), 'review-outcome', str(self.workspace),
                                               'prototype-r1', 'reviews/finish-review.json'])
        self.assertFalse(report['submitted'])
        self.assertFalse(report['reviewer_identity_authenticated'])
        self.assertFalse(report['review_authority_verified'])
        self.assertEqual(self.packet.read_bytes(), original_packet)
        self.assertEqual(self.sheet.read_bytes(), original_sheet)
        calls = [json.loads(row) for row in (self.root / 'calls.jsonl').read_text().splitlines()]
        self.assertEqual([row[0] for row in calls], ['status', 'run-history', 'status'])
        self.assertEqual(self.receipt.stat().st_mode & 0o777, 0o600)

    def test_rejected_findings_retain_reason_and_an_explicit_unsatisfied_criterion(self):
        self.findings('rejected')
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = json.loads(self.receipt.read_text())
        self.assertEqual(receipt['decision'], 'rejected')
        self.assertFalse(receipt['criteria'][1]['satisfied'])
        self.assertEqual(receipt['criteria'][1]['evidence_refs'], [])
        self.assertIn('visible scratch', receipt['criteria'][1]['note'])

    def test_unfilled_or_implicit_findings_do_not_become_a_receipt(self):
        self.blocked('review_id must be explicit')
        self.assertFalse((self.root / 'calls.jsonl').exists())
        self.findings()
        self.edit(self.sheet, lambda x: x['criteria'][1].update(satisfied=None))
        self.blocked('explicit true or false')
        self.assertFalse((self.root / 'calls.jsonl').exists())

    def test_acceptance_and_rejection_must_agree_with_findings(self):
        self.findings('rejected')
        self.edit(self.sheet, lambda x: x.update(decision='accepted'))
        self.blocked('decision conflicts')
        self.findings('accepted')
        self.edit(self.sheet, lambda x: x.update(decision='rejected'))
        self.blocked('decision conflicts')

    def test_original_criterion_order_and_evidence_selection_survive_return(self):
        self.findings()
        self.edit(self.sheet, lambda x: x['criteria'].reverse())
        self.blocked('exact criterion order and text')
        self.edit(self.sheet, lambda x: x['criteria'].reverse())
        self.edit(self.sheet, lambda x: x['criteria'][0].update(evidence_refs=['evidence/old-not-current.txt']))
        self.blocked('current-output references')
        self.edit(self.sheet, lambda x: x['criteria'][0].update(evidence_refs=[]))
        self.blocked('needs at least one')

    def test_reexported_same_result_cannot_silently_replace_the_reviewed_packet(self):
        self.findings()
        # Add an innocuous ZIP comment: semantic evidence is equal, exact packet bytes differ.
        with zipfile.ZipFile(self.packet, 'a') as packet:
            packet.comment = b'new transfer'
        self.blocked('packet_sha256 no longer matches')
        self.assertFalse((self.root / 'calls.jsonl').exists())

    def test_replaced_current_result_requires_a_new_review(self):
        self.findings()
        self.edit(self.root / 'projection.json', lambda x: x['items'][0].update(result_id='result-2'))
        self.edit(self.root / 'history.json', lambda x: x['entries'][4]['event'].update(result_id='result-2'))
        self.blocked('result changed since packet export: result_id')

    def test_output_changed_on_disk_cannot_be_approved_from_old_packet(self):
        self.findings()
        (self.workspace / 'outputs/metrics.json').write_text('{"width_mm":121}\n')
        self.blocked('do not match the recorded result digest')

    def test_completed_review_or_changed_observation_does_not_prepare_another_receipt(self):
        self.findings()
        self.edit(self.root / 'projection.json', lambda x: x['items'][0].update(status='accepted'))
        self.blocked('awaiting review')
        self.edit(self.root / 'projection.json', lambda x: x['items'][0].update(status='review'))
        (self.root / 'change-after-history').touch()
        self.blocked('run changed during export')

    def test_later_unrelated_head_can_be_reloaded_if_the_exact_result_remains_current(self):
        self.findings()
        self.edit(self.root / 'projection.json', lambda x: x.update(last_sequence=7))
        self.edit(self.root / 'history.json', lambda x: x['head'].update(
            last_sequence=7, last_event_id='unrelated-note', recorded_at=STAMP))
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['observed_head']['last_sequence'], 7)

    def test_explicit_authority_and_notes_cannot_be_inferred_from_packet(self):
        self.findings()
        self.edit(self.sheet, lambda x: x.update(review_authority_id=''))
        self.blocked('review_authority_id must be explicit')
        self.edit(self.sheet, lambda x: x.update(review_authority_id='review-scope:prototype'))
        self.edit(self.sheet, lambda x: x['criteria'][0].update(note=''))
        self.blocked('criterion note must be explicit')

    def test_prior_receipt_is_preserved_and_canonical_store_cannot_be_the_destination(self):
        self.findings()
        self.receipt.write_bytes(b'previous receipt\n')
        result = self.prepare()
        self.assertEqual(result.returncode, 2)
        self.assertIn('already exists', result.stderr)
        self.assertEqual(self.receipt.read_bytes(), b'previous receipt\n')
        blocked = self.prepare('--receipt', '.moonsuite/review.json')
        self.assertEqual(blocked.returncode, 2)
        self.assertIn('outside the canonical', blocked.stderr)
        self.assertFalse((self.root / 'calls.jsonl').exists())

    def test_packet_integrity_is_rechecked_before_reviewing_or_preparing(self):
        with zipfile.ZipFile(self.packet) as packet:
            members = [(n, packet.read(n)) for n in packet.namelist()]
        with zipfile.ZipFile(self.packet, 'w') as packet:
            for name, data in members:
                packet.writestr(name, b'changed output' if name.startswith('artifacts/output-0001') else data)
        result = self.command('worksheet', self.packet, '--output', self.root / 'new.json')
        self.assertEqual(result.returncode, 2)
        self.assertIn('output bytes differ', result.stderr)
        self.assertFalse((self.root / 'new.json').exists())

    def test_receipt_schema_and_selection_are_anchored_to_existing_native_contract(self):
        source = (ROOT / 'acceptance_review.mbt').read_text()
        main = (ROOT / 'cmd/main/main.mbt').read_text()
        self.assertIn('pub(all) struct AcceptanceReviewReceipt', source)
        self.assertIn('receipt.criteria[index].criterion != item.acceptance_criteria[index]', source)
        self.assertIn('if !item.artifacts.contains(evidence)', source)
        self.assertIn('receipt.receipt_artifact != receipt_artifact', main)
        self.assertIn('["review-outcome", workspace, run_id, receipt_artifact]', main)
        self.assertIn('"moonflow.acceptance-review.v1"', source)


if __name__ == '__main__':
    unittest.main()
