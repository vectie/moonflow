#!/usr/bin/env node
// Executes the actual renderer-produced page script under a small DOM adapter.
// Does not qualify browser layout, accessibility tooling or file:// behavior.
import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import vm from 'node:vm';
import test from 'node:test';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const report = JSON.parse(readFileSync(join(root, 'examples/graph-explorer/graph-map.json')));
// Exercise multiple real product labels and text needing HTML escaping.
report.nodes[3].product_id = 'moonbook';
report.nodes[4].product_id = 'moonbook';
report.nodes[5].operation = 'inspect/図 </script><img src=x onerror=alert(1)> & "quote"';
const temp = mkdtempSync(join(tmpdir(), 'moonflow-explorer-'));
let html;
try {
  writeFileSync(join(temp, 'report.json'), JSON.stringify(report));
  const result = spawnSync('python3', ['-B', join(root, 'scripts/graph_explorer.py'), join(temp, 'report.json'), join(temp, 'explorer.html')], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  html = readFileSync(join(temp, 'explorer.html'), 'utf8');
} finally { rmSync(temp, {recursive: true, force: true}); }
const dataText = html.match(/<script id="graph-data" type="application\/json">([\s\S]*?)<\/script>/)[1];
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];

class Element {
  constructor(tag = 'div', attributes = {}) {
    this.tagName = tag.toUpperCase(); this.attributes = attributes; this.dataset = {};
    for (const [name, value] of Object.entries(attributes)) if (name.startsWith('data-')) this.dataset[name.slice(5)] = value;
    this.hidden = 'hidden' in attributes; this.disabled = 'disabled' in attributes;
    this.value = ''; this.children = []; this.handlers = {}; this._text = '';
    const classes = new Set();
    this.classList = {toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name); }, contains(name) {return classes.has(name);}};
  }
  get textContent() {return this._text + this.children.map(child => child.textContent).join('');}
  set textContent(text) {this._text = String(text); this.children = [];}
  appendChild(child) {this.children.push(child); return child;}
  replaceChildren(...children) {this._text = ''; this.children = children;}
  setAttribute(name, value) {this.attributes[name] = value;}
  addEventListener(type, handler) {(this.handlers[type] ??= []).push(handler);}
  dispatch(type) {for (const handler of this.handlers[type] ?? []) handler({target: this});}
}
function adapter() {
  const elements = [], byId = new Map();
  // Select elements and attributes from the actual generated artifact.
  for (const match of html.matchAll(/<([a-z][a-z0-9-]*)\b([^>]*)>/gi)) {
    const attributes = {};
    for (const attr of match[2].matchAll(/([a-z][a-z0-9-]*)(?:="([^"]*)")?/gi)) attributes[attr[1]] = attr[2] ?? '';
    const element = new Element(match[1], attributes); elements.push(element);
    if (attributes.id) byId.set(attributes.id, element);
  }
  byId.get('graph-data').textContent = dataText;
  byId.get('scope').value = 'all';
  const document = {
    getElementById(id) {assert.ok(byId.has(id), `missing actual HTML element ${id}`); return byId.get(id);},
    querySelectorAll(selector) {
      const key = selector.match(/^\[([^\]]+)\]$/)[1];
      return elements.filter(element => key in element.attributes);
    },
    createElement(tag) {return new Element(tag);}
  };
  const context = vm.createContext({document});
  vm.runInContext(script, context);
  const get = id => document.getElementById(id);
  const cards = document.querySelectorAll('[data-index]');
  const visible = () => cards.filter(card => !card.hidden).map(card => Number(card.dataset.index)).sort((a,b) => a-b);
  const input = (id, value, type = 'change') => {get(id).value = value; get(id).dispatch(type);};
  return {document, context, get, cards, visible, input};
}
const plain = value => JSON.parse(JSON.stringify(value));
function buttons(element) {return element.children.flatMap(child => child.tagName === 'BUTTON' ? [child] : buttons(child));}

test('emitted page mounts with complete graph and explicit declaration boundary', () => {
  const a = adapter();
  assert.deepEqual(a.visible(), [0,1,2,3,4,5]);
  assert.equal(a.get('controls').hidden, false);
  assert.equal(a.get('scope').disabled, true);
  assert.equal(a.get('selection').hidden, true);
  assert.equal(a.get('empty').hidden, true);
  assert.match(a.get('summary').textContent, /Showing 6 of 6/);
  assert.match(html, /do not indicate readiness, execution, timing, authority or acceptance/);
});

test('case-insensitive search and empty results update actual cards and layers', () => {
  const a = adapter();
  a.input('search', 'MODEL', 'input'); assert.deepEqual(a.visible(), [1]);
  a.input('search', 'absent', 'input'); assert.deepEqual(a.visible(), []);
  assert.equal(a.get('empty').hidden, false);
  assert.ok(a.document.querySelectorAll('[data-layer]').every(layer => layer.hidden));
  a.input('search', '', 'input'); assert.equal(a.visible().length, 6);
});

test('product filter intersects with search and uses exact exported product identity', () => {
  const a = adapter();
  a.input('product', '1'); assert.deepEqual(a.visible(), [3,4]);
  a.input('search', 'license', 'input'); assert.deepEqual(a.visible(), [4]);
  a.input('search', 'capture', 'input'); assert.deepEqual(a.visible(), []);
});

test('selecting a card shows direct and transitive relationships without duplicates', () => {
  const a = adapter();
  a.document.querySelectorAll('[data-select]').find(b => b.dataset.select === '3').dispatch('click');
  assert.equal(a.get('focus').value, '3');
  assert.equal(a.get('scope').disabled, false);
  assert.equal(a.get('selection').hidden, false);
  assert.match(a.get('selection').textContent, /Direct prerequisites \(3\)/);
  assert.match(a.get('selection').textContent, /All prerequisites \(4\)/);
  const model = a.context.MoonFlowGraphExplorer.model(report);
  assert.deepEqual(plain(model.relations(3)), {
    prerequisites:[1,2,4], consumers:[], allPrerequisites:[0,1,2,4], allConsumers:[]
  });
  assert.deepEqual(plain(model.relations(0).allConsumers), [1,2,3]);
});

test('prerequisite scope includes selected target, entire closure and outside branch', () => {
  const a = adapter();
  a.input('focus', '3'); a.input('scope', 'prerequisites');
  assert.deepEqual(a.visible(), [0,1,2,3,4]);
  assert.ok(a.cards.find(c => c.dataset.index === '3').classList.contains('selected'));
  a.input('product', '1'); assert.deepEqual(a.visible(), [3,4]);
  assert.match(a.get('selection').textContent, /All prerequisites \(4\)/);
});

test('downstream scope excludes unrelated roots and includes the selected root', () => {
  const a = adapter();
  a.input('focus', '0'); a.input('scope', 'consumers');
  assert.deepEqual(a.visible(), [0,1,2,3]);
  a.input('focus', '5'); assert.deepEqual(a.visible(), [5]);
  assert.match(a.get('selection').textContent, /All downstream consumers \(0\)/);
});

test('relationship navigation clears filters and retains the chosen scope', () => {
  const a = adapter();
  a.input('focus', '3'); a.input('scope', 'prerequisites');
  a.input('product', '1'); a.input('search', 'publish', 'input');
  assert.deepEqual(a.visible(), [3]);
  const capture = buttons(a.get('selection')).find(button => button.textContent === 'capture');
  assert.ok(capture); capture.dispatch('click');
  assert.equal(a.get('focus').value, '0'); assert.equal(a.get('product').value, '');
  assert.equal(a.get('search').value, ''); assert.deepEqual(a.visible(), [0]);
  assert.equal(a.get('scope').value, 'prerequisites');
});

test('clearing selection removes scope and reset repeatedly restores the initial view', () => {
  const a = adapter();
  a.input('focus', '3'); a.input('scope', 'prerequisites'); a.input('focus', '');
  assert.equal(a.get('scope').value, 'all'); assert.equal(a.get('scope').disabled, true);
  assert.deepEqual(a.visible(), [0,1,2,3,4,5]);
  for (let i = 0; i < 3; i++) {
    a.input('focus', '0'); a.input('scope', 'consumers'); a.input('search', 'absent', 'input');
    a.get('reset').dispatch('click');
    assert.deepEqual(a.visible(), [0,1,2,3,4,5]);
    assert.equal(a.get('focus').value, ''); assert.equal(a.get('selection').hidden, true);
    assert.equal(a.get('empty').hidden, true);
  }
});

test('Unicode and markup-like operation names remain literal text in search and details', () => {
  const a = adapter();
  a.input('search', '図', 'input'); assert.deepEqual(a.visible(), [5]);
  a.input('focus', '5');
  assert.ok(a.get('selection').textContent.includes(report.nodes[5].operation));
  function tags(element) {return [element.tagName, ...element.children.flatMap(tags)];}
  assert.ok(!tags(a.get('selection')).includes('IMG'));
  assert.ok(!tags(a.get('selection')).includes('SCRIPT'));
});

test('model supports non-topological source order and independent singleton closure', () => {
  const a = adapter();
  const reversed = {...report, nodes:[...report.nodes].reverse()};
  const model = a.context.MoonFlowGraphExplorer.model(reversed);
  assert.deepEqual(plain(model.relations(2).allPrerequisites), [1,3,4,5]);
  assert.deepEqual(plain(model.visible({focus:0, scope:'prerequisites'})), [0]);
  assert.deepEqual(plain(model.visible({focus:0, scope:'consumers'})), [0]);
});


test('static relationship anchors reveal filtered targets before local fragment navigation', () => {
  const a = adapter();
  a.input('focus', '3'); a.input('scope', 'prerequisites');
  a.input('product', '1'); a.input('search', 'publish', 'input');
  assert.deepEqual(a.visible(), [3]);
  const link = a.document.querySelectorAll('[data-link]').find(link => link.dataset.link === '1');
  assert.ok(link); link.dispatch('click');
  assert.equal(a.get('focus').value, '1');
  assert.deepEqual(a.visible(), [0,1]);
  assert.equal(link.attributes.href, '#node-1');
});
