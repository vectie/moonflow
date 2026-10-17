#!/usr/bin/env node
// Actual emitted page events and Blob bytes, using a DOM adapter, not a live browser.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const [pagePath, formPath] = process.argv.slice(2);
assert.ok(pagePath && formPath, 'usage: node test_timeout_editor.mjs emitted.html new-form.json');
const html = readFileSync(pagePath, 'utf8');
assert.match(html, /Edit prerequisite links and timeouts/);
assert.match(html, /Dependencies and selected-item timeouts are editable/);
assert.match(html, /local dependency and timeout proposal/);
assert.match(html, /Download dependency and timeout plan form/);
assert.doesNotMatch(html, /Only dependencies are editable/);
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

test('artifact preview apply undo cancel reset and actual Blob', async () => {
  const a = adapter(); a.focus('left');
  a.input('edit-inputs', 'requests/alternate.json\nnotes/brief.txt'); a.click('edit-inputs-preview');
  assert.equal(a.get('edit-download').disabled, true); a.apply();
  assert.match(a.get('edit-changes').textContent, /alternate.json/);
  a.click('edit-undo'); assert.equal(a.get('edit-download').disabled, true);
  a.input('edit-inputs', 'requests/alternate.json\nnotes/brief.txt'); a.click('edit-inputs-preview'); a.apply();
  a.focus('right'); a.input('edit-inputs', 'requests/discard.json'); a.click('edit-inputs-preview'); a.click('edit-cancel');
  assert.equal(a.get('edit-inputs').value, 'requests/right.json');
  a.click('edit-reset'); assert.equal(a.get('edit-download').disabled, true); a.click('edit-undo');
  a.click('edit-download'); const text = await a.blobs[0].text(); const form = JSON.parse(text);
  assert.ok(text.includes('"source_graph":' + data.authoring.source_text + ',"edits":'));
  assert.deepEqual(form.edits.find(x => x.work_item_id === 'left').input_artifacts, ['requests/alternate.json', 'notes/brief.txt']);
  for (const item of form.edits) { const before = original.items.find(x => x.work_item_id === item.work_item_id);
    assert.deepEqual(item.depends_on, before.depends_on); assert.equal(item.timeout_ms, before.timeout_ms);
    assert.deepEqual(item.acceptance_criteria, before.acceptance_criteria);
  }
  writeFileSync(formPath, text);
});
test('invalid paths leave pending state intact, selection discards unapplied edits', () => {
 const a = adapter(); a.focus('left');
 for(const value of ['', '../secret', '/absolute', 'a//b', 'a\n' + 'a']) {
  a.input('edit-inputs', value); a.click('edit-inputs-preview'); assert.equal(a.get('edit-apply').disabled, true);
 }
 a.input('edit-inputs', 'new.json'); a.click('edit-inputs-preview'); a.focus('right'); a.focus('left');
 assert.equal(a.get('edit-inputs').value, 'requests/left.json');
});

test('criteria preview apply cancel undo reset and exact multiline download', async () => {
 const a = adapter(); a.focus('left');
 const criteria = [' Review exact result\nincluding second line ', '確認 "quoted" result'];
 a.input('edit-criteria-json', JSON.stringify(criteria)); a.click('edit-criteria-preview');
 assert.equal(a.get('edit-download').disabled, true);
 assert.equal(a.get('edit-criteria').children[0].textContent, criteria[0]);
 a.apply(); assert.equal(a.get('edit-download').disabled, false);
 a.click('edit-undo'); assert.equal(a.get('edit-download').disabled, true);
 a.input('edit-criteria-json', JSON.stringify(criteria)); a.click('edit-criteria-preview'); a.apply();
 a.input('edit-criteria-json', '["discard"]'); a.click('edit-criteria-preview'); a.click('edit-cancel');
 assert.deepEqual(JSON.parse(a.get('edit-criteria-json').value), criteria);
 a.click('edit-reset'); assert.equal(a.get('edit-download').disabled, true); a.click('edit-undo');
 a.click('edit-download'); const text = await a.blobs[0].text(); const form = JSON.parse(text);
 assert.deepEqual(form.edits.find(x => x.work_item_id === 'left').acceptance_criteria, criteria);
 assert.ok(text.includes('"source_graph":' + data.authoring.source_text + ',"edits":'));
 for (const item of form.edits) {
   const before = original.items.find(x => x.work_item_id === item.work_item_id);
   assert.deepEqual(item.input_artifacts, before.input_artifacts);
   assert.deepEqual(item.depends_on, before.depends_on); assert.equal(item.timeout_ms, before.timeout_ms);
   if (item.work_item_id !== 'left') assert.deepEqual(item.acceptance_criteria, before.acceptance_criteria);
 }
 writeFileSync(formPath + '.criteria.json', text);
});

test('invalid criteria preserve staged state and selection cancels preview', () => {
 const a = adapter(); a.focus('left');
 a.input('edit-criteria-json', '["valid"]'); a.click('edit-criteria-preview');
 for (const value of ['bad', '[]', '[null]', '[" "]', '["same","same"]', '{}', JSON.stringify(['x'.repeat(16385)]), '["\\ud800"]']) {
   a.input('edit-criteria-json', value); a.click('edit-criteria-preview');
   assert.match(a.get('edit-message').textContent, /Provide/);
   assert.equal(a.get('edit-criteria').children[0].textContent, 'valid');
 }
 a.focus('right'); a.focus('left');
 assert.deepEqual(JSON.parse(a.get('edit-criteria-json').value), original.items.find(x => x.work_item_id === 'left').acceptance_criteria);
 assert.equal(a.get('edit-apply').disabled, true);
});

test('saved criteria resume and combine atomically with timeout edits', () => {
 const a = adapter();
 const edits = original.items.map(item => ({...item}));
 edits[1].acceptance_criteria = ['saved\ncriterion'];
 const editor = a.context.MoonFlowGraphExplorer.editor(data.authoring.source_text, data.report, edits);
 editor.select(1); assert.deepEqual(plain(editor.criteria()), ['saved\ncriterion']);
 editor.stageCriteria('["next"]'); editor.stageTimeout('1234'); editor.apply();
 const edited = JSON.parse(editor.downloadText()).edits[1];
 assert.deepEqual(edited.acceptance_criteria, ['next']); assert.equal(edited.timeout_ms, 1234);
 editor.undo(); assert.deepEqual(plain(editor.criteria()), ['saved\ncriterion']);
 assert.equal(editor.timeout(), original.items[1].timeout_ms);
});
