#!/usr/bin/env node
// Runs the actual emitted page and captures Blob bytes with a bounded DOM adapter.
// This does not qualify browser rendering, file dialogs or assistive technology.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const [mode, pagePath, formPath, nativeEvidence] = process.argv.slice(2);
assert.ok(['seed', 'resume', 'readback', 'steps', 'steps-resume', 'steps-native'].includes(mode) && pagePath && formPath);
const html = readFileSync(pagePath, 'utf8');
const dataText = html.match(/<script id="graph-data" type="application\/json">([\s\S]*?)<\/script>/)[1];
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const data = JSON.parse(dataText), original = JSON.parse(data.authoring.source_text);
const ids = original.items.map(item => item.work_item_id);
const plain = value => JSON.parse(JSON.stringify(value));

class Element {
  constructor(tag = 'div', attributes = {}) {
    this.tagName = tag.toUpperCase(); this.attributes = attributes; this.dataset = {};
    for (const [name, value] of Object.entries(attributes)) if (name.startsWith('data-')) this.dataset[name.slice(5)] = value;
    this.hidden = 'hidden' in attributes; this.disabled = 'disabled' in attributes;
    this.value = ''; this.children = []; this.handlers = {}; this._text = '';
    const classes = new Set();
    this.classList = {toggle(name, enabled) {enabled ? classes.add(name) : classes.delete(name);}, contains(name) {return classes.has(name);}};
  }
  get textContent() {return this._text + this.children.map(child => child.textContent).join('');}
  set textContent(text) {this._text = String(text); this.children = [];}
  appendChild(child) {this.children.push(child); child.parent = this; return child;}
  replaceChildren(...children) {this._text = ''; this.children = children;}
  setAttribute(name, value) {this.attributes[name] = value;}
  addEventListener(type, handler) {(this.handlers[type] ??= []).push(handler);}
  dispatch(type) {if (!this.disabled) for (const handler of this.handlers[type] ?? []) handler({target: this});}
  click() {this.clicked = true; this.dispatch('click');}
  remove() {if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this);}
}

function adapter(override = null) {
  const elements = [], byId = new Map(), blobs = [], anchors = [], revoked = [], timers = [];
  for (const match of html.matchAll(/<([a-z][a-z0-9-]*)\b([^>]*)>/gi)) {
    const attrs = {};
    for (const attr of match[2].matchAll(/([a-z][a-z0-9-]*)(?:="([^"]*)")?/gi)) attrs[attr[1]] = attr[2] ?? '';
    const element = new Element(match[1], attrs); elements.push(element);
    if (attrs.id) byId.set(attrs.id, element);
  }
  byId.get('graph-data').textContent = override ? JSON.stringify(override) : dataText;
  byId.get('scope').value = 'all';
  const document = {body: new Element('body'),
    getElementById(id) {assert.ok(byId.has(id), 'Missing emitted element ' + id); return byId.get(id);},
    querySelectorAll(selector) {const key = selector.match(/^\[([^\]]+)\]$/)[1]; return elements.filter(e => key in e.attributes);},
    createElement(tag) {const e = new Element(tag); if (tag === 'a') anchors.push(e); return e;}
  };
  const context = vm.createContext({document, Blob, TextEncoder,
    URL: {createObjectURL(blob) {blobs.push(blob); return 'blob:fixture-' + blobs.length;}, revokeObjectURL(url) {revoked.push(url);}},
    setTimeout(fn) {timers.push(fn);}
  });
  vm.runInContext(script, context);
  const get = id => document.getElementById(id);
  const input = (id, value, event = 'change') => {get(id).value = String(value); get(id).dispatch(event);};
  const click = id => get(id).dispatch('click');
  const currentIndex = id => get('focus').children.length ? get('focus').children.find(e => e.textContent === id)?.value : ids.indexOf(id);
  const focus = id => input('focus', id === null ? '' : currentIndex(id));
  const edge = (id, adding) => {input('edit-target', currentIndex(id)); click(adding ? 'edit-add' : 'edit-remove');};
  return {get, input, click, focus, edge, blobs, anchors, revoked, timers, document, context};
}

async function download(a) {
  a.click('edit-download');
  const text = await a.blobs.at(-1).text();
  assert.ok(text.includes('"source_graph":' + data.authoring.source_text + ',"edits":'));
  return text;
}

if (mode === 'steps-native') {
  test('native v2 import fresh inspect and prepared child exactly retain downloaded declarations', () => {
    assert.ok(nativeEvidence);
    const form = JSON.parse(readFileSync(formPath, 'utf8'));
    const draftBytes = readFileSync(nativeEvidence + '/native-draft.json', 'utf8');
    assert.equal(readFileSync(nativeEvidence + '/native-reopened.json', 'utf8'), draftBytes);
    const draft = JSON.parse(draftBytes);
    assert.equal(draft.contract_id, 'moonflow.declared-plan-form.v2');
    assert.equal(draft.preparation_dispatches, false);
    assert.deepEqual(draft.items.map(x => x.work_item_id), form.edits.map(x => x.work_item_id));
    for (const [i, item] of draft.items.entries()) {
      for (const key of ['work_item_id', 'input_artifacts', 'depends_on', 'acceptance_criteria', 'timeout_ms']) assert.deepEqual(item[key], form.edits[i][key]);
      const template = original.items.find(x => x.work_item_id === (form.added_templates[item.work_item_id] ?? item.work_item_id));
      for (const key of ['operation', 'product_id', 'requested_authority', 'input_contracts', 'output_contracts', 'required_claim']) assert.deepEqual(item[key], template[key]);
      if (form.added_templates[item.work_item_id]) assert.ok(!original.items.some(x => x.declaration_id === item.declaration_id));
      else assert.equal(item.declaration_id, template.declaration_id);
    }
    const prepared = JSON.parse(readFileSync(nativeEvidence + '/native-prepared-fixture-time.json', 'utf8'));
    assert.equal(prepared.dispatched, false);
    assert.equal(prepared.prepared.proposal.dispatch_requested, false);
    assert.equal(prepared.evaluated_at, '2026-07-31T00:00:00Z');
    assert.deepEqual(prepared.prepared.graph.items, draft.items);
    const stored = JSON.parse(readFileSync(nativeEvidence + '/workspace/' + prepared.graph_ref, 'utf8'));
    assert.deepEqual(stored, prepared.prepared.graph);
    assert.match(readFileSync(nativeEvidence + '/native-prepared-current.json', 'utf8'), /operation-health-window-invalid/);
    assert.deepEqual(JSON.parse(readFileSync(nativeEvidence + '/workspace/source-graph.json', 'utf8')), original);
  });
} else if (mode === 'steps') {
  test('duplicate preview, cancel, apply, undo and undoable reset use real controls', async () => {
    const a = adapter(); a.focus('left');
    a.input('edit-new-id', 'second-left'); a.click('edit-duplicate');
    assert.match(a.get('edit-step-preview').textContent, /Pending addition: second-left/);
    assert.equal(a.get('edit-download').disabled, true);
    a.click('edit-cancel'); assert.equal(a.get('edit-apply').disabled, true);
    a.click('edit-duplicate'); a.click('edit-apply');
    assert.match(a.get('summary').textContent, /5 work items.*second-left/);
    assert.match(a.get('edit-changes').textContent, /added declared step from source template left/);
    a.click('edit-undo'); assert.match(a.get('summary').textContent, /4 work items/);
    a.click('edit-duplicate'); a.click('edit-apply');
    a.click('edit-reset'); assert.match(a.get('summary').textContent, /4 work items/);
    a.click('edit-undo'); assert.match(a.get('summary').textContent, /5 work items/);
    assert.equal(JSON.parse(await download(a)).added_templates['second-left'], 'left');
  });
  test('unsafe and reused IDs refuse; navigation discards a structural preview', () => {
    const a = adapter(); a.focus('left');
    for (const id of ['', '.', '..', 'a..b', '../x', 'two words', 'λ', 'x'.repeat(129), 'root']) {
      a.input('edit-new-id', id); a.click('edit-duplicate');
      assert.equal(a.get('edit-apply').disabled, true);
    }
    a.input('edit-new-id', 'copy'); a.click('edit-duplicate'); a.focus('right');
    assert.equal(a.get('edit-apply').disabled, true);
    assert.match(a.get('edit-message').textContent, /canceled/);
  });
  test('removal requires explicit prerequisite repair and never cascades', async () => {
    const a = adapter(); a.focus('right'); a.click('edit-remove-step');
    assert.match(a.get('edit-message').textContent, /Repair prerequisites.*join/);
    assert.equal(a.get('edit-apply').disabled, true);
    a.focus('join'); a.edge('right', false); a.click('edit-apply');
    a.focus('right'); a.click('edit-remove-step');
    assert.match(a.get('edit-step-preview').textContent, /Pending removal: right/);
    a.click('edit-cancel'); a.click('edit-remove-step'); a.click('edit-apply');
    assert.match(a.get('summary').textContent, /3 work items/);
    const form = JSON.parse(await download(a));
    assert.equal(form.contract_id, 'moonflow.declared-plan-form-input.v2');
    assert.deepEqual(form.added_templates, {});
    assert.deepEqual(form.edits.map(x => x.work_item_id), ['root', 'left', 'join']);
    assert.deepEqual(form.edits.find(x => x.work_item_id === 'join').depends_on, ['left']);
    a.click('edit-undo'); assert.match(a.get('summary').textContent, /4 work items/);
  });
  test('added step edits, explicit replacement and actual v2 download retain exact source', async () => {
    const a = adapter(); a.focus('left');
    a.input('edit-new-id', 'second-left'); a.click('edit-duplicate'); a.click('edit-apply');
    a.input('edit-inputs', 'requests/right.json'); a.click('edit-inputs-preview');
    a.input('edit-criteria-json', '["Review copied result\\n確認"]'); a.click('edit-criteria-preview');
    a.input('edit-timeout', '45000'); a.click('edit-timeout-preview'); a.click('edit-apply');
    a.focus('join'); a.edge('right', false); a.edge('second-left', true); a.click('edit-apply');
    a.focus('right'); a.click('edit-remove-step'); a.click('edit-apply');
    assert.equal(a.get('focus').children.some(e => e.textContent === 'right'), false);
    a.focus('second-left'); assert.equal(a.get('edit-inputs').value, 'requests/right.json');
    const text = await download(a), form = JSON.parse(text);
    assert.equal(form.contract_id, 'moonflow.declared-plan-form-input.v2');
    assert.deepEqual(form.added_templates, {'second-left': 'left'});
    assert.deepEqual(form.edits.map(x => x.work_item_id), ['root', 'left', 'join', 'second-left']);
    assert.deepEqual(form.edits.find(x => x.work_item_id === 'join').depends_on, ['left', 'second-left']);
    assert.deepEqual(form.edits.at(-1), {work_item_id: 'second-left', input_artifacts: ['requests/right.json'], depends_on: ['root'], acceptance_criteria: ['Review copied result\n確認'], timeout_ms: 45000});
    writeFileSync(formPath, text, {flag: 'wx'});
  });
  test('copy of copy resolves the original template and last-item removal is refused', () => {
    const a = adapter(), e = a.context.MoonFlowGraphExplorer.editor(data.authoring.source_text, data.report);
    e.select(1); e.stageDuplicate('copy'); e.apply(); e.stageDuplicate('copy-again'); e.apply();
    assert.deepEqual(JSON.parse(e.downloadText()).added_templates, {copy: 'left', 'copy-again': 'left'});
    e.reset();
    for (const id of ['join', 'right', 'left']) {e.select(e.snapshot().nodes.findIndex(n => n.work_item_id === id)); e.stageRemoval(); e.apply();}
    e.select(0); assert.throws(() => e.stageRemoval(), /at least one/);
  });
} else if (mode === 'steps-resume') {
  test('actual v2 resumed page restores additions removals edited fields and exact redownload', async () => {
    const a = adapter();
    assert.match(a.get('edit-message').textContent, /Saved plan restored/);
    assert.match(a.get('edit-changes').textContent, /right: removed declared step/);
    assert.match(a.get('edit-changes').textContent, /second-left: added declared step/);
    assert.equal(a.get('focus').children.some(e => e.textContent === 'right'), false);
    a.focus('second-left');
    assert.equal(a.get('edit-timeout').value, '45000');
    assert.equal(a.get('edit-inputs').value, 'requests/right.json');
    assert.deepEqual(JSON.parse(a.get('edit-criteria-json').value), ['Review copied result\n確認']);
    a.input('edit-timeout', '70000'); a.click('edit-timeout-preview'); a.click('edit-apply');
    a.click('edit-undo'); a.click('edit-reset');
    assert.equal(a.get('edit-download').disabled, true);
    a.click('edit-undo');
    const text = await download(a), form = JSON.parse(text);
    assert.deepEqual(form.edits, data.authoring.resume.edits);
    assert.deepEqual(form.added_templates, data.authoring.resume.added_templates);
    writeFileSync(formPath, text, {flag: 'wx'});
  });
} else if (mode === 'seed') {
  test('save actual combined dependency input and timeout edits for a later session', async () => {
    const a = adapter(); assert.equal(a.get('edit-download').disabled, true);
    a.focus('left'); a.edge('root', false); a.edge('right', true);
    a.input('edit-inputs', 'requests/right.json'); a.click('edit-inputs-preview');
    a.input('edit-timeout', '45000'); a.click('edit-timeout-preview');
    assert.equal(a.get('edit-download').disabled, true);
    a.click('edit-apply');
    const text = await download(a), form = JSON.parse(text), left = form.edits.find(x => x.work_item_id === 'left');
    assert.deepEqual(left.depends_on, ['right']); assert.equal(left.timeout_ms, 45000);
    assert.deepEqual(left.input_artifacts, ['requests/right.json']);
    writeFileSync(formPath, text, {flag: 'wx'});
  });
} else {
  assert.match(html, /Resumed saved plan/);
  const saved = data.authoring.resume.edits;
  test('saved topology and all item fields restore before the first user action', () => {
    const a = adapter();
    assert.equal(a.get('edit-undo').disabled, true);
    assert.equal(a.get('edit-download').disabled, false);
    assert.match(a.get('edit-message').textContent, /Saved plan restored/);
    assert.match(a.get('edit-changes').textContent, /left: timeout 60000 → 45000/);
    assert.match(a.get('edit-changes').textContent, /left: added \[right\]; removed \[root\]/);
    assert.match(a.get('graph').textContent, /edited declaration/);
    a.focus('left');
    assert.equal(a.get('edit-timeout').value, '45000');
    assert.equal(a.get('edit-inputs').value, 'requests/right.json');
    assert.match(a.get('selection').textContent, /All prerequisites \(2\)/);
    assert.equal(a.get('edit-criteria').textContent, saved.find(x => x.work_item_id === 'left').acceptance_criteria.join(''));
  });
  test('download without further edits retains every saved declaration and exact source text', async () => {
    const a = adapter(), text = await download(a), form = JSON.parse(text);
    assert.deepEqual(form.edits, saved);
    assert.equal(form.source_kind, 'existing-graph');
    const anchor = a.anchors.find(x => x.download); assert.ok(anchor.clicked);
    assert.equal(a.document.body.children.length, 0);
    a.timers.forEach(fn => fn()); assert.deepEqual(a.revoked, ['blob:fixture-1']);
  });
  test('pending cancel and navigation preserve saved changes; repeated apply is harmless', async () => {
    const a = adapter(); a.focus('left');
    a.input('edit-timeout', '123'); a.click('edit-timeout-preview');
    assert.equal(a.get('edit-download').disabled, true);
    a.focus('right'); a.focus('left');
    assert.equal(a.get('edit-timeout').value, '45000');
    a.input('edit-timeout', '456'); a.click('edit-timeout-preview'); a.click('edit-cancel');
    assert.equal(a.get('edit-timeout').value, '45000');
    a.click('edit-apply'); a.click('edit-undo');
    assert.deepEqual(JSON.parse(await download(a)).edits, saved);
  });
  test('source reset is undoable; view reset does not erase the resumed plan', async () => {
    const a = adapter(); a.focus('left'); a.click('edit-reset');
    assert.equal(a.get('edit-timeout').value, '60000');
    assert.equal(a.get('edit-download').disabled, true);
    a.click('edit-undo'); assert.equal(a.get('edit-timeout').value, '45000');
    a.click('reset'); assert.equal(a.get('focus').value, '');
    assert.deepEqual(JSON.parse(await download(a)).edits, saved);
  });
  test('changed saved criteria remain visible and survive edits undo reset and redownload', async () => {
    const variant = structuredClone(data);
    variant.authoring.resume.edits[1].acceptance_criteria = ['New criterion </script> λ', 'Keep original objections'];
    const a = adapter(variant); a.focus('left');
    assert.match(a.get('edit-criteria').textContent, /New criterion <\/script> λ/);
    assert.match(a.get('edit-changes').textContent, /acceptance criteria/);
    a.input('edit-timeout', '678'); a.click('edit-timeout-preview'); a.click('edit-apply'); a.click('edit-undo');
    a.click('edit-reset'); a.click('edit-undo');
    assert.deepEqual(JSON.parse(await download(a)).edits, variant.authoring.resume.edits);
  });
  test('resume continue save and reopen keeps earlier and new edits together', async () => {
    const a = adapter(); a.focus('right');
    const initial = saved.find(x => x.work_item_id === 'right').timeout_ms;
    a.input('edit-timeout', '90000'); a.click('edit-timeout-preview'); a.click('edit-apply');
    if (initial !== 90000) {
      a.click('edit-undo'); assert.equal(a.get('edit-timeout').value, String(initial));
      a.input('edit-timeout', '90000'); a.click('edit-timeout-preview'); a.click('edit-apply');
    }
    const text = await download(a), form = JSON.parse(text);
    const expected = structuredClone(saved); expected.find(x => x.work_item_id === 'right').timeout_ms = 90000;
    assert.deepEqual(form.edits, expected);
    const reopened = adapter(); reopened.focus('right');
    assert.equal(reopened.get('edit-timeout').value, String(initial));
    assert.equal(reopened.get('edit-undo').disabled, true);
    writeFileSync(formPath, text, {flag: 'wx'});
  });
}
