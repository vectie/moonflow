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

test('timeout select preview apply undo reset and source-exact Blob', async () => {
  const a = adapter();
  assert.equal(a.get('edit-timeout').disabled, true);
  a.focus('left');
  const before = original.items.find(x => x.work_item_id === 'left').timeout_ms;
  assert.equal(Number(a.get('edit-timeout').value), before);
  a.input('edit-timeout', '45000'); a.click('edit-timeout-preview');
  assert.match(a.get('edit-timeout-pending').textContent, /45000/);
  assert.equal(a.get('edit-download').disabled, true);
  a.apply(); assert.match(a.get('edit-changes').textContent, /timeout .* → 45000 ms/);
  a.click('edit-undo'); assert.equal(Number(a.get('edit-timeout').value), before);
  assert.equal(a.get('edit-download').disabled, true);
  a.input('edit-timeout', '45000'); a.click('edit-timeout-preview'); a.apply();
  a.click('edit-reset'); assert.equal(a.get('edit-download').disabled, true);
  a.click('edit-undo'); assert.match(a.get('edit-changes').textContent, /45000/);
  a.focus('right'); a.input('edit-timeout', '86400000'); a.click('edit-timeout-preview'); a.apply();
  a.focus('root'); a.input('edit-timeout', '1'); a.click('edit-timeout-preview'); a.apply();
  a.click('edit-download');
  const text = await a.blobs[0].text(), form = JSON.parse(text);
  assert.ok(text.includes('"source_graph":' + data.authoring.source_text + ',"edits":'));
  assert.deepEqual(form.source_graph, original);
  const expected = {left:45000, right:86400000, root:1};
  for (const edit of form.edits) {
    const source = original.items.find(x => x.work_item_id === edit.work_item_id);
    assert.equal(edit.timeout_ms, expected[edit.work_item_id] ?? source.timeout_ms);
    for (const key of ['depends_on','input_artifacts','acceptance_criteria']) assert.deepEqual(edit[key], source[key]);
  }
  writeFileSync(formPath, text, {flag:'wx'});
});
test('invalid timeout values refuse; cancel and selection changes discard previews', () => {
  const a = adapter(); a.focus('left');
  for (const value of ['', '0', '-1', '86400001', '1.5', '1e3', 'NaN', 'Infinity', ' 42 ', '9007199254740993']) {
    a.input('edit-timeout', value); a.click('edit-timeout-preview');
    assert.match(a.get('edit-message').textContent, /integer from 1 to 86400000/);
    assert.equal(a.get('edit-apply').disabled, true);
  }
  a.input('edit-timeout', '123'); a.click('edit-timeout-preview'); a.click('edit-cancel');
  assert.equal(a.get('edit-apply').disabled, true);
  a.input('edit-timeout', '123'); a.click('edit-timeout-preview'); a.focus('join');
  assert.match(a.get('edit-message').textContent, /Pending changes canceled/);
  assert.equal(a.get('edit-download').disabled, true);
});
test('combined timeout and prerequisite edit undoes atomically; reopening has original state', () => {
  const a = adapter(); a.focus('left'); a.edge('root', false);
  a.input('edit-timeout', '123'); a.click('edit-timeout-preview'); a.apply();
  assert.match(a.get('edit-changes').textContent, /removed \[root\]/);
  assert.match(a.get('edit-changes').textContent, /123 ms/);
  a.click('edit-undo'); assert.equal(a.get('edit-download').disabled, true);
  const b = adapter(); assert.equal(b.get('edit-download').disabled, true);
});
