#!/usr/bin/env python3
"""Focused graph authoring contract tests; native integration is separate."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import shared_table_plan as plan

SOURCE = Path(__file__).resolve().parents[1]
EXAMPLE = SOURCE / 'examples/shared-table-plan'


class SharedTableTests(unittest.TestCase):
    def setUp(self):
        self.source = json.loads((EXAMPLE / 'source-graph.json').read_text())
        self.template = json.loads((EXAMPLE / 'template.json').read_text())
        self.csv = (EXAMPLE / 'variants.csv').read_bytes()

    def expand(self, raw=None):
        return plan.expand(self.source, self.template, self.csv if raw is None else raw)

    def test_shared_prelude_diamond_and_final_fanin(self):
        form = self.expand()
        by_id = {item['work_item_id']: item for item in form['edits']}
        self.assertEqual(set(by_id), {'setup', 'final', 'audit', *[key+'--'+step for key in ('compact','wide') for step in ('left','right','rowjoin')]})
        self.assertEqual(by_id['final']['depends_on'], ['compact--rowjoin','wide--rowjoin','setup'])
        for key in ('compact','wide'):
            self.assertEqual(by_id[key+'--rowjoin']['depends_on'], [key+'--left',key+'--right'])
            self.assertEqual(by_id[key+'--left']['depends_on'], ['setup'])
            self.assertEqual(by_id[key+'--right']['depends_on'], ['setup'])
        self.assertEqual(by_id['audit']['depends_on'], ['setup'])
        self.assertEqual(form['contract_id'], 'moonflow.declared-plan-form-input.v2')
        self.assertEqual(len(form['added_templates']),6)

    def test_preserves_source_and_shared_edits_exactly(self):
        before = copy.deepcopy((self.source, self.template))
        form = self.expand()
        self.assertEqual((self.source,self.template),before)
        self.assertEqual(form['source_graph'],self.source)
        by_id = {item['work_item_id']: item for item in form['edits']}
        for item in self.source['items']:
            if item['work_item_id'] in ('audit','setup'):
                self.assertEqual(by_id[item['work_item_id']], {field:item[field] for field in plan.EDIT_FIELDS})
        form['source_graph']['items'][0]['acceptance_criteria'].append('detached')
        self.assertEqual(self.source,before[0])

    def test_stable_ids_after_row_and_selection_reorder(self):
        first = self.expand()
        self.template['repeated_work_item_ids'].reverse()
        self.template['item_bindings'].reverse()
        second = self.expand(b'key,label\nwide,Wide study\ncompact,Compact study\n')
        self.assertEqual(first['added_templates'],second['added_templates'])
        for form in (first,second):
            for item in form['edits']:
                item['depends_on'].sort()
        self.assertEqual(sorted(first['edits'],key=lambda x:x['work_item_id']),sorted(second['edits'],key=lambda x:x['work_item_id']))

    def test_nontopological_order(self):
        self.assertEqual(self.source['items'][0]['work_item_id'],'final')
        form=self.expand()
        self.assertEqual(form['edits'][0]['work_item_id'],'final')
        plan.validate_dag(form['edits'])

    def test_all_selected_is_independent_complete_workflow(self):
        self.template['repeated_work_item_ids']=[x['work_item_id'] for x in self.source['items']]
        self.template['item_bindings']=[{'template_work_item_id':x['work_item_id'],'input_artifacts':x['input_artifacts']} for x in self.source['items']]
        form=self.expand()
        self.assertEqual(len(form['edits']),12)
        self.assertEqual(len(form['added_templates']),12)
        for item in form['edits']:
            key=item['work_item_id'].split('--',1)[0]
            self.assertTrue(all(dep.startswith(key+'--') for dep in item['depends_on']))

    def test_shared_barrier_between_repeated_steps(self):
        self.template['repeated_work_item_ids']=['left','final']
        self.template['item_bindings']=[{'template_work_item_id':key,'input_artifacts':['requests/'+key+'.json']} for key in ('left','final')]
        items={item['work_item_id']:item for item in self.expand()['edits']}
        self.assertEqual(items['rowjoin']['depends_on'],['compact--left','wide--left','right'])
        self.assertEqual(items['compact--final']['depends_on'],['rowjoin','setup'])
        self.assertEqual(items['wide--final']['depends_on'],['rowjoin','setup'])
        plan.validate_dag(list(items.values()))

    def test_criteria_default_and_explicit_binding(self):
        items={item['work_item_id']:item for item in self.expand()['edits']}
        self.assertEqual(items['compact--left']['acceptance_criteria'],['Review Compact study left result'])
        self.assertEqual(items['compact--rowjoin']['acceptance_criteria'],['Review exact rowjoin result'])
        self.assertEqual(items['compact--left']['input_artifacts'],['requests/compact-left.json'])

    def test_cell_placeholder_values_are_literal(self):
        form=self.expand(b'key,label\na,{{missing}}\n')
        self.assertEqual(next(item for item in form['edits'] if item['work_item_id']=='a--left')['acceptance_criteria'],['Review {{missing}} left result'])

    def test_utf8_bom_crlf_quoted_multiline_and_comma(self):
        rows=plan.parse_rows('\ufeffkey,label\r\na,"  alpha, ""quoted""\r\nnext  "\r\n'.encode())
        self.assertEqual(rows,[{'key':'a','label':'alpha, "quoted"\nnext'}])

    def test_exact_256_cap_includes_shared_items(self):
        self.template['repeated_work_item_ids']=['left']
        self.template['item_bindings']=self.template['item_bindings'][:1]
        rows=('key,label\n'+''.join(f'row{i},Item\n' for i in range(251))).encode()
        self.assertEqual(len(self.expand(rows)['edits']),256)
        with self.assertRaisesRegex(ValueError,'256 total'):
            self.expand(rows+b'row251,Item\n')

    def test_unknown_and_duplicate_selection(self):
        for selected in (['absent'],['left','left'],[],[None]):
            with self.subTest(selected=selected),self.assertRaises(ValueError):
                self.template['repeated_work_item_ids']=selected
                self.expand()

    def test_binding_must_match_selection_exactly(self):
        original=copy.deepcopy(self.template)
        for bindings in ([],original['item_bindings']*2,[{'template_work_item_id':'setup','input_artifacts':['x']}], [{'template_work_item_id':'left','input_artifacts':['x'],'operation':'invented'}]):
            with self.subTest(bindings=bindings),self.assertRaises(ValueError):
                self.template={**original,'item_bindings':bindings}
                self.expand()

    def test_source_id_collision(self):
        self.source['items'].append({**self.source['items'][-1],'work_item_id':'compact--left','declaration_id':'collision'})
        with self.assertRaisesRegex(ValueError,'collides'):
            self.expand()

    def test_expanded_id_length_and_ambiguous_key(self):
        for key in ('x'*128,'a--b','..','../bad','a b','a/b','.'):
            with self.subTest(key=key),self.assertRaises(ValueError):
                self.expand(f'key,label\n{key},text\n'.encode())

    def test_csv_rejects_malformed_and_duplicate_keys(self):
        for raw in (b'key,label\na,x\na,y\n',b'key,label\na\n',b'key,key\na,b\n',b'key,label\na,b"x\n',b'key,label\na,"b"x\n',b'key,label\na,"unterminated',b'key,label\ra,b',b'key,label\n',b'other,label\na,b',b'key,label\n\na,b'):
            with self.subTest(raw=raw),self.assertRaises(ValueError):
                self.expand(raw)

    def test_csv_row_and_size_bounds(self):
        for raw in (b'key,label\n'+b'a,b\n'*257,b' '*(plan.MAX_CSV_UNITS+1),b'\xff'):
            with self.subTest(size=len(raw)),self.assertRaises((ValueError,UnicodeError)):
                self.expand(raw)

    def test_placeholder_errors_and_blank_values(self):
        for value in ('{{missing}}','{{label','bad}}','{{bad column}}'):
            with self.subTest(value=value),self.assertRaises(ValueError):
                self.template['item_bindings'][0]['acceptance_criteria']=[value]
                self.expand()
        self.template['item_bindings'][0]['acceptance_criteria']=['{{label}}']
        with self.assertRaisesRegex(ValueError,'blank table column'):
            self.expand(b'key,label\na,\n')

    def test_binding_paths_and_duplicate_expansion(self):
        for refs in (['../{{key}}'],['/{{key}}'],['a//b'],['{{label}}','fixed']):
            with self.subTest(refs=refs),self.assertRaises(ValueError):
                self.template['item_bindings'][0]['input_artifacts']=refs
                self.expand(b'key,label\na,fixed\n')

    def test_cycle_and_unknown_dependency(self):
        for deps in (['final'],['missing']):
            with self.subTest(deps=deps),self.assertRaises(ValueError):
                self.source['items'][3]['depends_on']=deps
                self.expand()

    def test_invalid_source_timeout_and_duplicates(self):
        for timeout in (True,1.5,0,86_400_001,'1'):
            with self.subTest(timeout=timeout),self.assertRaises(ValueError):
                self.source['items'][0]['timeout_ms']=timeout
                self.expand()
        self.setUp()
        self.source['items'].append(copy.deepcopy(self.source['items'][0]))
        with self.assertRaises(ValueError):self.expand()

    def test_strict_json(self):
        for raw in (b'{"a":1,"a":2}',b'{"a":NaN}',b'{"a":Infinity}'):
            with self.subTest(raw=raw),self.assertRaises(ValueError):plan.load_json(raw)

    def test_form_size_bound_before_save(self):
        with mock.patch.object(plan,'MAX_BYTES',500):
            with self.assertRaisesRegex(ValueError,'output bound'):self.expand()

    def test_cli_refuses_overwrite_and_preserves_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            output=Path(temp)/'form.json'
            args=[sys.executable,'-B',str(SOURCE/'scripts/shared_table_plan.py'),'save',str(EXAMPLE/'source-graph.json'),str(EXAMPLE/'template.json'),str(EXAMPLE/'variants.csv'),str(output)]
            before={p:p.read_bytes() for p in EXAMPLE.rglob('*') if p.is_file()}
            saved=subprocess.run(args,capture_output=True,text=True)
            self.assertEqual(saved.returncode,0,saved.stderr)
            self.assertEqual(json.loads(saved.stdout)['work_item_count'],9)
            original=output.read_bytes()
            second=subprocess.run(args,capture_output=True,text=True)
            self.assertEqual(second.returncode,2)
            self.assertEqual(output.read_bytes(),original)
            self.assertEqual(before,{p:p.read_bytes() for p in before})

    def test_invalid_save_leaves_no_output(self):
        with tempfile.TemporaryDirectory() as temp:
            csv=Path(temp)/'bad.csv';csv.write_text('key,label\na,x\na,y\n')
            output=Path(temp)/'form.json'
            result=subprocess.run([sys.executable,'-B',str(SOURCE/'scripts/shared_table_plan.py'),'save',str(EXAMPLE/'source-graph.json'),str(EXAMPLE/'template.json'),str(csv),str(output)],capture_output=True,text=True)
            self.assertEqual(result.returncode,2)
            self.assertFalse(output.exists())


if __name__=='__main__':unittest.main(verbosity=2)
