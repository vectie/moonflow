/* Uses only the embedded, validated graph-map report. No fetching or storage. */
(() => {
  'use strict';
  function model(report) {
    const nodes = report.nodes;
    const indexes = new Map(nodes.map((node, index) => [node.work_item_id, index]));
    const prerequisites = nodes.map(node => node.depends_on.map(id => indexes.get(id)));
    const consumers = nodes.map(() => []);
    prerequisites.forEach((deps, index) => deps.forEach(dep => consumers[dep].push(index)));
    function closure(index, direction) {
      const visited = new Set();
      const pending = [...direction[index]];
      while (pending.length) {
        const next = pending.pop();
        if (visited.has(next)) continue;
        visited.add(next);
        pending.push(...direction[next]);
      }
      return nodes.map((_, i) => i).filter(i => visited.has(i));
    }
    function relations(index) {
      return {prerequisites: prerequisites[index], consumers: consumers[index],
        allPrerequisites: closure(index, prerequisites), allConsumers: closure(index, consumers)};
    }
    function visible({query = '', product = '', focus = null, scope = 'all'}) {
      const text = query.toLowerCase();
      let scoped = null;
      if (focus !== null && scope !== 'all') {
        scoped = new Set([focus, ...closure(focus, scope === 'prerequisites' ? prerequisites : consumers)]);
      }
      return nodes.map((node, index) => index).filter(index => {
        const node = nodes[index];
        return (!scoped || scoped.has(index)) && (!product || node.product_id === product) &&
          [node.work_item_id, node.product_id, node.operation].some(value => value.toLowerCase().includes(text));
      });
    }
    return {relations, visible};
  }

  function mount(document) {
    const {report, products} = JSON.parse(document.getElementById('graph-data').textContent);
    const graph = model(report);
    const get = id => document.getElementById(id);
    const controls = {search: get('search'), product: get('product'), focus: get('focus'), scope: get('scope')};
    const cards = Array.from(document.querySelectorAll('[data-index]'));
    const layers = Array.from(document.querySelectorAll('[data-layer]'));
    const buttons = Array.from(document.querySelectorAll('[data-select]'));
    const state = {query: '', product: '', focus: null, scope: 'all'};
    function add(parent, tag, text, className) {
      const element = document.createElement(tag);
      if (text !== undefined) element.textContent = text;
      if (className) element.className = className;
      parent.appendChild(element);
      return element;
    }
    function select(index, reveal = false) {
      state.focus = index;
      controls.focus.value = index === null ? '' : String(index);
      if (index === null) {
        state.scope = 'all';
        controls.scope.value = 'all';
      }
      if (reveal) {
        controls.search.value = controls.product.value = '';
        state.query = state.product = '';
      }
      update();
    }
    function details() {
      const container = get('selection');
      container.replaceChildren();
      container.hidden = state.focus === null;
      if (state.focus === null) return;
      const node = report.nodes[state.focus];
      add(container, 'h2', node.work_item_id);
      add(container, 'p', `${node.product_id} · ${node.operation}`);
      add(container, 'p', 'These relationships include the complete graph, even when search or product filters hide cards. Selecting a relationship clears those filters.');
      const rel = graph.relations(state.focus);
      for (const [title, values] of [
        ['Direct prerequisites', rel.prerequisites], ['All prerequisites', rel.allPrerequisites],
        ['Direct consumers', rel.consumers], ['All downstream consumers', rel.allConsumers]
      ]) {
        add(container, 'h3', `${title} (${values.length})`);
        if (!values.length) add(container, 'p', 'None');
        else {
          const list = add(container, 'ul', undefined, 'relations');
          for (const index of values) {
            const item = add(list, 'li');
            const button = add(item, 'button', report.nodes[index].work_item_id);
            button.type = 'button';
            button.addEventListener('click', () => select(index, true));
          }
        }
      }
    }
    function update() {
      controls.scope.disabled = state.focus === null;
      const shown = new Set(graph.visible(state));
      for (const card of cards) {
        const index = Number(card.dataset.index);
        card.hidden = !shown.has(index);
        card.classList.toggle('selected', index === state.focus);
      }
      for (const layer of layers) {
        layer.hidden = !report.nodes.some((node, index) => node.layer === Number(layer.dataset.layer) && shown.has(index));
      }
      for (const button of buttons) button.setAttribute('aria-pressed', String(Number(button.dataset.select) === state.focus));
      get('summary').textContent = `Showing ${shown.size} of ${report.nodes.length} work items. ` +
        (state.focus === null ? 'Choose an item to explore its dependencies.' : `Selected: ${report.nodes[state.focus].work_item_id}.`);
      get('empty').hidden = shown.size !== 0;
      details();
    }
    controls.search.addEventListener('input', () => {state.query = controls.search.value; update();});
    controls.product.addEventListener('change', () => {
      state.product = controls.product.value === '' ? '' : products[Number(controls.product.value)]; update();
    });
    controls.focus.addEventListener('change', () => select(controls.focus.value === '' ? null : Number(controls.focus.value)));
    controls.scope.addEventListener('change', () => {state.scope = controls.scope.value; update();});
    get('reset').addEventListener('click', () => {
      controls.search.value = controls.product.value = '';
      state.query = state.product = '';
      select(null);
    });
    for (const button of buttons) {
      button.hidden = false;
      button.addEventListener('click', () => select(Number(button.dataset.select)));
    }
    // Unhide an anchor's target before the browser follows its local fragment.
    for (const link of document.querySelectorAll('[data-link]')) {
      link.addEventListener('click', () => select(Number(link.dataset.link), true));
    }
    get('controls').hidden = false;
    update();
    return {graph, state};
  }
  globalThis.MoonFlowGraphExplorer = Object.freeze({model, mount});
  if (typeof document !== 'undefined') mount(document);
})();
