#!/usr/bin/env node
// Actual emitted page events and Blob bytes, using a DOM adapter, not a live browser.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const [pagePath, formPath] = process.argv.slice(2);
assert.ok(pagePath && formPath, 'usage: node test_dependency_editor.mjs emitted.html new-form.json');
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
function adapter() {
  const elements = [], byId = new Map(), blobs = [], anchors = [], revoked = [], timers = [];
  for (const match of html.matchAll(/<([a-z][a-z0-9-]*)\b([^>]*)>/gi)) {
    const attrs = {};
    for (const attr of match[2].matchAll(/([a-z][a-z0-9-]*)(?:="([^"]*)")?/gi)) attrs[attr[1]] = attr[2] ?? '';
    const element = new Element(match[1], attrs); elements.push(element);
    if (attrs.id) byId.set(attrs.id, element);
  }
  byId.get('graph-data').textContent = dataText; byId.get('scope').value = 'all';
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
  const focus = id => input('focus', id === null ? '' : ids.indexOf(id));
  const edge = (id, adding) => {input('edit-target', ids.indexOf(id)); click(adding ? 'edit-add' : 'edit-remove');};
  const apply = () => click('edit-apply');
  return {get, input, click, focus, edge, apply, blobs, anchors, timers, revoked, document, context};
}
function changes(a) {
  a.focus('left'); a.edge('root', false); a.edge('right', true); a.apply();
  a.focus('join'); a.edge('right', false); a.apply();
  a.focus('right'); a.edge('root', false); a.apply();
}

test('authoring is opt-in, no initial download and every source node stays selectable', () => {
  const a = adapter();
  assert.equal(a.get('authoring').hidden, false);
  assert.equal(a.get('edit-download').disabled, true);
  assert.equal(a.get('edit-add').disabled, true);
  assert.match(a.get('edit-changes').textContent, /No applied changes/);
  for (const id of ids) {a.focus(id); assert.ok(a.get('edit-node').textContent.includes(id));}
  assert.equal(a.blobs.length, 0);
});

test('self, duplicate and unknown prerequisites refuse changes in real event handlers', () => {
  const a = adapter(); a.focus('left');
  a.edge('left', true); assert.match(a.get('edit-message').textContent, /itself/);
  a.edge('root', true); assert.match(a.get('edit-message').textContent, /already present/);
  a.input('edit-target', '999'); a.click('edit-add'); assert.match(a.get('edit-message').textContent, /known prerequisite/);
  a.edge('join', false); assert.match(a.get('edit-message').textContent, /not present/);
  assert.equal(a.get('edit-apply').disabled, true);
  assert.equal(a.get('edit-download').disabled, true);
});

test('cycles cannot apply or export, cancellation retains the complete diamond', () => {
  const a = adapter(); a.focus('root'); a.edge('join', true); a.apply();
  assert.match(a.get('edit-message').textContent, /cycle/);
  assert.equal(a.get('edit-download').disabled, true);
  a.click('edit-cancel');
  assert.equal(a.get('edit-apply').disabled, true);
  a.focus('join');
  assert.match(a.get('selection').textContent, /Direct prerequisites \(2\)/);
  assert.match(a.get('selection').textContent, /All prerequisites \(3\)/);
  assert.match(a.get('edit-changes').textContent, /No applied changes/);
});

test('multiple applied edits refresh links, depth, closure and changed-edge review', () => {
  const a = adapter(); changes(a);
  assert.match(a.get('edit-changes').textContent, /left: added \[right\]; removed \[root\]/);
  assert.match(a.get('edit-changes').textContent, /join: added \[\]; removed \[right\]/);
  assert.match(a.get('edit-changes').textContent, /join transitive prerequisites: \[root, left, right\] → \[left, right\]/);
  a.focus('join'); assert.match(a.get('selection').textContent, /Direct prerequisites \(1\)/);
  assert.match(a.get('selection').textContent, /All prerequisites \(2\)/);
  assert.match(a.get('graph').textContent, /edited declaration/);
  a.input('scope', 'prerequisites');
  const cards = a.get('graph').children.flatMap(layer => layer.children).filter(e => e.className === 'cards').flatMap(e => e.children);
  assert.deepEqual(cards.filter(e => !e.hidden).map(e => ids[Number(e.dataset.index)]).sort(), ['join','left','right']);
  assert.equal(a.get('edit-download').disabled, false);
});

test('undo and undoable reset preserve pending/cancel boundaries', () => {
  const a = adapter(); changes(a);
  a.click('edit-undo'); assert.match(a.get('edit-changes').textContent, /left: added \[right\]/);
  assert.ok(!a.get('edit-changes').textContent.includes('right: added'));
  a.click('edit-reset'); assert.match(a.get('edit-changes').textContent, /No applied changes/);
  assert.equal(a.get('edit-download').disabled, true);
  a.click('edit-undo'); assert.match(a.get('edit-changes').textContent, /left: added \[right\]/);
  a.focus('root'); a.edge('join', true); assert.equal(a.get('edit-download').disabled, true);
  a.focus('join'); assert.match(a.get('edit-message').textContent, /Pending changes canceled/);
  assert.equal(a.get('edit-download').disabled, false);
  a.click('reset'); assert.equal(a.get('focus').value, '');
  assert.match(a.get('edit-changes').textContent, /left: added \[right\]/);
});

test('cancel restores exactly; repeated add/remove does not create duplicate or order-only changes', () => {
  const a = adapter(); a.focus('join'); a.edge('left', false); a.edge('left', true);
  assert.equal(a.get('edit-apply').disabled, true);
  a.edge('root', true); a.click('edit-cancel');
  assert.equal(a.get('edit-apply').disabled, true);
  assert.equal(a.get('edit-download').disabled, true);
  a.click('edit-cancel'); assert.equal(a.blobs.length, 0);
});

test('real Blob download retains full original source and only depends_on edits', async () => {
  const a = adapter(); changes(a); a.click('edit-download');
  assert.equal(a.blobs.length, 1); assert.equal(a.blobs[0].type, 'application/json');
  const text = await a.blobs[0].text(), form = JSON.parse(text);
  assert.ok(text.includes('"source_graph":' + data.authoring.source_text + ',"edits":'));
  assert.deepEqual(form.source_graph, original);
  assert.equal(form.contract_id, 'moonflow.declared-plan-form-input.v1');
  assert.deepEqual(form.edits.map(item => item.work_item_id), ids);
  const expected = {root: [], left: ['right'], right: [], join: ['left']};
  for (const item of form.edits) {
    assert.deepEqual(item.depends_on, expected[item.work_item_id]);
    const source = original.items.find(row => row.work_item_id === item.work_item_id);
    for (const key of ['input_artifacts','acceptance_criteria','timeout_ms']) assert.deepEqual(item[key], source[key]);
    assert.deepEqual(Object.keys(item).sort(), ['acceptance_criteria','depends_on','input_artifacts','timeout_ms','work_item_id']);
  }
  const anchor = a.anchors.find(e => e.download);
  assert.equal(anchor.download, 'moonflow-dependency-plan.json'); assert.equal(anchor.clicked, true);
  assert.equal(a.document.body.children.length, 0); a.timers.forEach(fn => fn());
  assert.deepEqual(a.revoked, ['blob:fixture-1']);
  writeFileSync(formPath, text, {flag: 'wx'});
});

test('unknown annotations and non-JavaScript integers remain verbatim in form source', () => {
  const raw = data.authoring.source_text.replace(/}\s*$/, ',"annotation":{"n":9007199254740993,"text":"</script> λ"}}');
  const a = adapter(), editor = a.context.MoonFlowGraphExplorer.editor(raw, data.report);
  editor.select(ids.indexOf('left')); editor.stage('root', false); editor.apply();
  const result = editor.downloadText();
  assert.ok(result.includes('"source_graph":' + raw + ',"edits":'));
  assert.ok(result.includes('9007199254740993'));
  assert.throws(() => editor.stage('unknown', true), /known prerequisite/);
});

test('reopening emitted page restores original graph and no prior unsaved author state', () => {
  const first = adapter(); changes(first);
  const next = adapter(); assert.equal(next.get('edit-download').disabled, true);
  assert.match(next.get('edit-changes').textContent, /No applied changes/);
});

test('non-topological full-source order stays exact through editing and export', () => {
  const a = adapter(), graph = structuredClone(original), report = structuredClone(data.report);
  graph.items.reverse(); report.nodes.reverse();
  const editor = a.context.MoonFlowGraphExplorer.editor(JSON.stringify(graph), report);
  editor.select(graph.items.findIndex(item => item.work_item_id === 'left'));
  editor.stage('root', false); editor.stage('right', true); editor.apply();
  const form = JSON.parse(editor.downloadText());
  assert.deepEqual(form.edits.map(item => item.work_item_id), graph.items.map(item => item.work_item_id));
  assert.deepEqual(form.source_graph, graph);
  assert.deepEqual(form.edits.find(item => item.work_item_id === 'left').depends_on, ['right']);
});

test('full 256-node chain rejects closing cycle and bounds oversized full-source downloads', () => {
  const a = adapter(), graph = structuredClone(original), report = structuredClone(data.report);
  graph.items = Array.from({length: 256}, (_, i) => ({...structuredClone(original.items[0]),
    work_item_id: 'n'+i, declaration_id: 'n'+i, depends_on: i ? ['n'+(i-1)] : []}));
  report.nodes = graph.items.map((item, i) => ({work_item_id: item.work_item_id,
    product_id: item.product_id, operation: item.operation, depends_on: item.depends_on, layer: i}));
  const editor = a.context.MoonFlowGraphExplorer.editor(JSON.stringify(graph), report);
  editor.select(0); editor.stage('n255', true); assert.throws(() => editor.apply(), /cycle/);
  editor.cancel(); editor.select(255); editor.stage('n254', false); editor.apply();
  assert.equal(JSON.parse(editor.downloadText()).edits.length, 256);
  graph.annotation = 'x'.repeat(4 * 1024 * 1024);
  const large = a.context.MoonFlowGraphExplorer.editor(JSON.stringify(graph), report);
  large.select(255); large.stage('n254', false); large.apply();
  assert.throws(() => large.downloadText(), /4 MiB/);
});
