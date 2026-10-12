import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import history_explorer as h
ROOT=Path(__file__).resolve().parents[1]
class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.raw=(ROOT/'examples/history-explorer/history.json').read_bytes()
        self.report=json.loads(self.raw)
    def test_complete_evidence_and_sequence(self):
        page=h.render(self.raw)
        self.assertLess(page.index('#0'),page.index('#3'))
        self.assertIn('retained_artifacts',page);self.assertIn('outputs/result.txt',page)
        self.assertIn('duplicate deliveries omitted: 1',page)
        self.assertIn(hashlib.sha256(self.raw).hexdigest(),page)
        self.assertEqual(page,h.render(self.raw))
    def test_selected_export_and_empty(self):
        r=self.report;r['selected_work_item_id']='check';r['entries']=r['entries'][1:]
        h.validate(r)
        r['entries']=[];h.validate(r)
        self.assertIn('No events in this view.',h.render(json.dumps(r).encode()))
    def test_invalid_export(self):
        for mutation in [lambda r:r['entries'].reverse(),lambda r:r['head'].update(last_event_id='wrong'),lambda r:r.update(canonical_event_count=2),lambda r:r['entries'][0]['event'].update(run_id='other')]:
            r=copy.deepcopy(self.report);mutation(r)
            with self.assertRaises(ValueError):h.validate(r)
    def test_text_is_not_markup(self):
        self.report['entries'][1]['after']['blocker']='</script><img src=x> Ω'
        page=h.render(json.dumps(self.report).encode())
        self.assertNotIn('<img src=x>',page);self.assertIn('&lt;img src=x&gt;',page)
    def test_cli_exclusive_output(self):
        with tempfile.TemporaryDirectory() as temp:
            target=Path(temp)/'history.html'
            command=[sys.executable,'-B',str(ROOT/'scripts/history_explorer.py'),str(ROOT/'examples/history-explorer/history.json'),str(target)]
            result=subprocess.run(command,capture_output=True,text=True);self.assertEqual(result.returncode,0,result.stderr)
            receipt=json.loads(result.stdout);self.assertEqual(receipt['output_sha256'],hashlib.sha256(target.read_bytes()).hexdigest())
            old=target.read_bytes();self.assertEqual(subprocess.run(command,capture_output=True).returncode,2);self.assertEqual(target.read_bytes(),old)
    def test_source_schema_matches_fixture(self):
        source=(ROOT/'wire.mbt').read_text().split('pub fn runtime_event_json')[1].split('///|')[0]
        import re
        self.assertEqual(set(re.findall(r'"(\w+)":',source)),set(self.report['entries'][0]['event']))
if __name__=='__main__':unittest.main()
