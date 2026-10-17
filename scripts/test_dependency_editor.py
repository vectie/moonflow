#!/usr/bin/env python3
"""Source binding/refusal tests; native/DOM integration lives in verify_dependency_editor."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

import graph_explorer as explorer

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'examples/graph-route/graph.json'
REPORT = ROOT / 'examples/graph-explorer/graph-map.json'


class SourceBindingTests(unittest.TestCase):
    def invoke(self, path, mutate=None, report=None, fail=False):
        calls = []
        def run(argv, **kwargs):
            calls.append(argv)
            if len(calls) == 1:
                return subprocess.CompletedProcess(argv, 0, json.dumps({'cli_sha256': 'pinned'}).encode(), b'')
            if mutate: mutate(path)
            return subprocess.CompletedProcess(argv, 1 if fail else 0,
                REPORT.read_bytes() if report is None else json.dumps(report).encode(), b'')
        with mock.patch.object(explorer.subprocess, 'run', side_effect=run):
            result = explorer.author_source(path, Path('/bin/true'))
        return result, calls

    def test_full_source_verbatim_and_exact_native_argv(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'source.json'
            source = json.loads(SOURCE.read_bytes())
            source['retained_annotation'] = {'large': 9007199254740993, 'literal': '</script> λ'}
            raw = (' \n' + json.dumps(source, ensure_ascii=False, indent=2) + '\n').encode()
            path.write_bytes(raw)
            (report, digest, authoring, original), calls = self.invoke(path)
            self.assertEqual(authoring['source_text'].encode(), raw)
            self.assertEqual(original, raw)
            self.assertEqual(path.read_bytes(), raw)
            self.assertEqual(calls[1], [str(Path('/bin/true').resolve()), 'graph-map', str(path.parent), path.name, '--json'])
            self.assertTrue(any('verify_shared_table_native.py' in arg for arg in calls[0]))
            self.assertIn('-I', calls[0])
            self.assertEqual(authoring['source_bytes_sha256'], 'sha256:' + hashlib.sha256(raw).hexdigest())
            html = explorer.render(report, digest, authoring)
            self.assertIn('Edit prerequisite links', html)
            data = html.split('<script id="graph-data" type="application/json">')[1].split('</script>')[0]
            self.assertEqual(json.loads(data)['authoring']['source_text'].encode(), raw)
            self.assertEqual(html.count('<script'), 2)

    def test_source_changed_during_native_read_is_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'source.json'; path.write_bytes(SOURCE.read_bytes())
            with self.assertRaisesRegex(explorer.ExplorerError, 'bytes changed during'):
                self.invoke(path, mutate=lambda p: p.write_bytes(p.read_bytes() + b' '))

    def test_native_failure_and_mismatched_source_report(self):
        with self.assertRaisesRegex(explorer.ExplorerError, 'native graph-map refused'):
            self.invoke(SOURCE, fail=True)
        report = json.loads(REPORT.read_bytes()); report['graph_id'] = 'different'
        with self.assertRaisesRegex(explorer.ExplorerError, 'differs from full source'):
            self.invoke(SOURCE, report=report)
        report = json.loads(REPORT.read_bytes()); report['nodes'][0]['operation'] = 'other'
        with self.assertRaisesRegex(explorer.ExplorerError, 'differs from full source declarations'):
            self.invoke(SOURCE, report=report)

    def test_supplied_report_cannot_enable_authoring(self):
        with self.assertRaisesRegex(explorer.ExplorerError, 'original full'):
            self.invoke(REPORT)

    def test_source_invalid_json_and_input_bound(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'source.json'
            for raw in (b'{"a":0,"a":1}', b'NaN', b'\xff', b'{'):
                path.write_bytes(raw)
                with self.subTest(raw=raw), self.assertRaises(explorer.ExplorerError): self.invoke(path)
            with mock.patch.object(Path, 'open') as opened:
                opened.return_value.__enter__.return_value.read.return_value = b' ' * (4*1024*1024+1)
                with self.assertRaisesRegex(explorer.ExplorerError, '4 MiB'): explorer.read_source_bytes(path)

    def test_invalid_timeout_cannot_roundtrip_as_a_different_js_number(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'source.json'; source = json.loads(SOURCE.read_bytes())
            for timeout in (True, 1.1, 9007199254740993):
                source['items'][0]['timeout_ms'] = timeout; path.write_text(json.dumps(source))
                with self.subTest(timeout=timeout), self.assertRaisesRegex(explorer.ExplorerError, 'integer timeout'):
                    self.invoke(path)

    def test_native_pin_is_required(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)/'page.html'
            command = ['python3', '-B', str(ROOT/'scripts/graph_explorer.py'), str(SOURCE), str(output)]
            for flags in (['--author'], ['--cli', '/bin/true'], ['--author', '--cli', '/bin/true']):
                result = subprocess.run(command+flags, capture_output=True, text=True)
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertFalse(output.exists())

    def test_output_time_source_drift_leaves_no_file(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'source.json'; path.write_bytes(SOURCE.read_bytes())
            output=Path(temp)/'page.html'
            report=json.loads(REPORT.read_bytes())
            before=path.read_bytes()
            def render(*args): path.write_bytes(before+b' '); return '<html></html>'
            with mock.patch.object(explorer, 'author_source', return_value=(report, 'sha256:test', {}, before)), \
                 mock.patch.object(explorer, 'render', side_effect=render):
                self.assertEqual(explorer.main([str(path),str(output),'--author','--cli','/bin/true']),2)
            self.assertFalse(output.exists())


class ResumePlanTests(unittest.TestCase):
    def setUp(self):
        self.source = json.loads(SOURCE.read_bytes())
        self.report = json.loads(REPORT.read_bytes())
        self.source['annotation'] = {'integer': 9007199254740993,
                                     'literal': '</script> λ &', 'string': '1'}
        self.source_text = json.dumps(self.source, ensure_ascii=False, indent=2)
        self.form = {'contract_id': 'moonflow.declared-plan-form-input.v1',
                     'source_kind': 'existing-graph', 'source_graph': copy.deepcopy(self.source),
                     'edits': [{key: copy.deepcopy(item[key]) for key in
                               ('work_item_id', 'input_artifacts', 'depends_on', 'acceptance_criteria', 'timeout_ms')}
                              for item in self.source['items']]}

    def read(self, form=None, raw=None):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/'resume.json'
            data = raw if raw is not None else json.dumps(self.form if form is None else form).encode()
            path.write_bytes(data)
            result, retained = explorer.read_resume_form(path, self.source_text, self.report)
            self.assertEqual(retained, data)
            self.assertEqual(path.read_bytes(), data)
            return result

    def test_restore_all_edit_fields_and_normalize_source_order_without_mutating_input(self):
        self.form['edits'][0]['timeout_ms'] = 1234
        self.form['edits'][0]['input_artifacts'] = ['requests/revised.json']
        self.form['edits'][0]['acceptance_criteria'] = ['Inspect new criteria literally: </script> λ']
        self.form['edits'].reverse()
        before = copy.deepcopy(self.form)
        resumed = self.read()
        self.assertEqual(self.form, before)
        self.assertEqual([x['work_item_id'] for x in resumed['edits']],
                         [x['work_item_id'] for x in self.source['items']])
        self.assertEqual(resumed['edits'][0]['timeout_ms'], 1234)
        self.assertEqual(resumed['edits'][0]['acceptance_criteria'], self.form['edits'][-1]['acceptance_criteria'])
        self.assertRegex(resumed['form_sha256'], r'^sha256:[0-9a-f]{64}$')

    def test_exact_source_comparison_detects_unknown_fields_types_and_precise_numbers(self):
        for key, value in [('integer', 9007199254740992), ('integer', '9007199254740993'),
                           ('integer', True), ('string', 1), ('literal', 'changed')]:
            form = copy.deepcopy(self.form); form['source_graph']['annotation'][key] = value
            with self.subTest(key=key, value=value), self.assertRaisesRegex(explorer.ExplorerError, 'source differs'):
                self.read(form)
        # Numeric token identity is stricter than floating-point equality.
        self.source_text = self.source_text.replace('9007199254740993', '1.00000000000000000001')
        raw = json.dumps(self.form).replace('9007199254740993', '1.00000000000000000002').encode()
        with self.assertRaisesRegex(explorer.ExplorerError, 'source differs'): self.read(raw=raw)
        self.read(raw=raw.replace(b'1.00000000000000000002', b'1.00000000000000000001'))

    def test_unsupported_forms_missing_duplicate_unknown_members_and_edit_fields_refused(self):
        bad = []
        for key, value in [('contract_id', 'moonflow.declared-plan-form-input.v2'), ('source_kind', 'company-task')]:
            form = copy.deepcopy(self.form); form[key] = value; bad.append(form)
        form = copy.deepcopy(self.form); form['extra'] = True; bad.append(form)
        form = copy.deepcopy(self.form); form['edits'].pop(); bad.append(form)
        form = copy.deepcopy(self.form); form['edits'][1] = form['edits'][0]; bad.append(form)
        form = copy.deepcopy(self.form); form['edits'][0]['work_item_id'] = 'unknown'; bad.append(form)
        form = copy.deepcopy(self.form); form['edits'][0]['owner'] = 'changed'; bad.append(form)
        for form in bad:
            with self.subTest(form=form), self.assertRaises(explorer.ExplorerError): self.read(form)

    def test_invalid_declarations_are_refused_before_rendering(self):
        ids = [item['work_item_id'] for item in self.form['edits']]
        for field, values in [('timeout_ms', [True, 0, 86400001, 1.5, '1000']),
                              ('input_artifacts', [[], ['../secret'], ['/absolute'], ['a//b'], ['a', 'a'], [None]]),
                              ('acceptance_criteria', [[], [''], ['x', 'x']]),
                              ('depends_on', [[ids[0]], ['missing'], [ids[1], ids[1]]])]:
            for value in values:
                form = copy.deepcopy(self.form); form['edits'][0][field] = value
                with self.subTest(field=field, value=value), self.assertRaises(explorer.ExplorerError): self.read(form)
        form = copy.deepcopy(self.form)
        form['edits'][0]['depends_on'] = [ids[-1]]
        form['edits'][-1]['depends_on'] = [ids[0]]
        with self.assertRaisesRegex(explorer.ExplorerError, 'cycle'): self.read(form)

    def expanded(self):
        form = copy.deepcopy(self.form)
        form['contract_id'] = 'moonflow.declared-plan-form-input.v2'
        copied = copy.deepcopy(form['edits'][0]); copied['work_item_id'] = 'second-capture'
        form['edits'].append(copied)
        form['added_templates'] = {'second-capture': form['edits'][0]['work_item_id']}
        return form

    def test_v2_addition_and_removal_preserve_order_templates_and_exact_source(self):
        form = self.expanded()
        form['edits'] = [e for e in form['edits'] if e['work_item_id'] != 'independent']
        resumed = self.read(form)
        self.assertEqual(resumed['edits'], form['edits'])
        self.assertEqual(resumed['added_templates'], form['added_templates'])
        form['edits'].pop(); form['added_templates'] = {}
        self.assertEqual(self.read(form)['added_templates'], {})

    def test_v2_invalid_template_bindings_ids_and_removed_dependencies_refused(self):
        variants = []
        for name, template in [('capture', 'capture'), ('a..b', 'capture'), ('copy', 'missing'), ('copy', 'second-capture')]:
            form = self.expanded(); form['edits'][-1]['work_item_id'] = name
            form['added_templates'] = {name: template}; variants.append(form)
        form = self.expanded(); form['added_templates']['absent'] = 'capture'; variants.append(form)
        form = self.expanded(); form['added_templates'] = {}; variants.append(form)
        form = self.expanded(); form['edits'] = [e for e in form['edits'] if e['work_item_id'] != 'capture']; variants.append(form)
        form = self.expanded(); form['edits'] = []; variants.append(form)
        form = self.expanded(); form['edits'] *= 43; variants.append(form)
        for form in variants:
            with self.subTest(form=form), self.assertRaises(explorer.ExplorerError): self.read(form)

    def test_malformed_duplicate_non_utf8_oversize_and_deep_json_refused(self):
        for raw in (b'{', b'{"x":1,"x":2}', b'NaN', b'\xff', b'['*2000+b']'*2000,
                    b' '*(4*1024*1024+1), json.dumps(self.form).encode('utf-16'),
                    json.dumps(self.form).encode().replace(b'"timeout_ms": 60000', b'"timeout_ms": '+b'9'*5000)):
            with self.subTest(length=len(raw)), self.assertRaises(explorer.ExplorerError): self.read(raw=raw)

    def test_resume_requires_author_and_output_time_drift_refuses_all_output(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp)/'source.json'; source.write_text(self.source_text)
            saved = Path(temp)/'form.json'; saved.write_text(json.dumps(self.form))
            output = Path(temp)/'page.html'
            self.assertEqual(explorer.main([str(source), str(output), '--resume', str(saved)]), 2)
            authoring = {'source_text': self.source_text}
            def render(*args): saved.write_bytes(saved.read_bytes()+b' '); return '<html></html>'
            with mock.patch.object(explorer, 'author_source', return_value=(self.report, 'sha256:test', authoring, source.read_bytes())), \
                 mock.patch.object(explorer, 'render', side_effect=render):
                self.assertEqual(explorer.main([str(source), str(output), '--author', '--cli', '/bin/true', '--resume', str(saved)]), 2)
            self.assertFalse(output.exists())


if __name__ == '__main__': unittest.main(verbosity=2)
