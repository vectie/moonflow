/* Offline topology inspection and optional source-backed dependency and timeout authoring. */
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

  function editor(sourceText, originalReport, resumedEdits = null) {
    const clone = value => JSON.parse(JSON.stringify(value));
    const source = JSON.parse(sourceText);
    const original = clone(originalReport);
    const sourceIds = original.nodes.map(node => node.work_item_id);
    let ids = [...sourceIds], templates = new Map(), pendingStep = null;
    let dependencies = original.nodes.map(node => [...node.depends_on]);
    const originalTimeouts = source.items.map(item => item.timeout_ms);
    let timeouts = [...originalTimeouts], pendingTimeout = null;
    const originalInputs = source.items.map(item => [...item.input_artifacts]);
    let inputs = clone(originalInputs), pendingInputs = [];
    const originalCriteria = source.items.map(item => [...item.acceptance_criteria]);
    let criteria = clone(originalCriteria), pendingCriteria = [];
    let selected = null, pending = [], history = [];
    const same = (left, right) => JSON.stringify(left) === JSON.stringify(right);
    function require(condition, message) {if (!condition) throw new Error(message);}
    function topology(values) {
      const depths = new Map(), layers = [];
      for (let i = 0; i < values.length; i++) {
        require(values[i].every(id => ids.includes(id)), 'Unknown prerequisite.');
        require(!values[i].includes(ids[i]), 'An item cannot require itself.');
        require(new Set(values[i]).size === values[i].length, 'Duplicate prerequisite.');
      }
      while (depths.size < ids.length) {
        const ready = ids.filter((id, index) => !depths.has(id) && values[index].every(dep => depths.has(dep)));
        require(ready.length, 'These prerequisites create a dependency cycle. Remove a link or cancel.');
        ready.forEach(id => depths.set(id, layers.length));
        layers.push(ready);
      }
      return {depths, layers};
    }
    function snapshot() {
      const report = clone(original), {depths, layers} = topology(dependencies);
      report.nodes = ids.map(id => ({...clone(original.nodes[sourceIds.indexOf(templates.get(id) ?? id)]), work_item_id: id}));
      report.nodes.forEach((node, index) => {node.depends_on = [...dependencies[index]]; node.layer = depths.get(ids[index]);});
      report.layers = layers;
      report.edge_count = dependencies.reduce((sum, deps) => sum + deps.length, 0);
      report.root_item_ids = ids.filter((_, index) => !dependencies[index].length);
      const used = new Set(dependencies.flat());
      report.leaf_item_ids = ids.filter(id => !used.has(id));
      return report;
    }
    function dirty() {return pendingStep !== null || (selected !== null && (!same(pending, dependencies[selected]) || pendingTimeout !== timeouts[selected] || !same(pendingInputs, inputs[selected]) || !same(pendingCriteria, criteria[selected])));}
    function select(index) {
      require(index === null || (Number.isInteger(index) && index >= 0 && index < ids.length), 'Unknown work item.');
      const discarded = dirty();
      pendingStep = null;
      selected = index;
      pending = index === null ? [] : [...dependencies[index]];
      pendingTimeout = index === null ? null : timeouts[index];
      pendingInputs = index === null ? [] : [...inputs[index]];
      pendingCriteria = index === null ? [] : [...criteria[index]];
      return discarded;
    }
    function stage(target, adding) {
      require(pendingStep === null, 'Apply or cancel the pending step change first.');
      require(selected !== null, 'Choose a work item first.');
      require(ids.includes(target), 'Choose a known prerequisite.');
      require(target !== ids[selected], 'An item cannot require itself.');
      require(adding ? !pending.includes(target) : pending.includes(target),
        adding ? 'This prerequisite is already present.' : 'This prerequisite is not present.');
      pending = adding ? [...pending, target] : pending.filter(id => id !== target);
      // Re-adding an original edge does not create an order-only change.
      const order = [...original.nodes[sourceIds.indexOf(templates.get(ids[selected]) ?? ids[selected])].depends_on, ...ids];
      pending.sort((a, b) => order.indexOf(a) - order.indexOf(b));
    }
    function stageTimeout(value) {
      require(pendingStep === null, 'Apply or cancel the pending step change first.');
      require(selected !== null, 'Choose a work item first.');
      require(/^[0-9]+$/.test(String(value)) && Number.isSafeInteger(Number(value)) && Number(value) >= 1 && Number(value) <= 86400000,
        'Timeout must be an integer from 1 to 86400000 milliseconds.');
      pendingTimeout = Number(value);
    }
    function stageInputs(value) {
      require(pendingStep === null, 'Apply or cancel the pending step change first.');
      require(selected !== null, "Choose a work item first.");
      const next = value.split(/\r?\n/).filter(line => line.trim() !== "");
      require(next.length > 0 && new Set(next).size === next.length, "Provide at least one unique input artifact, one per line.");
      require(next.every(path => {const normalized = path.trim().replaceAll("\\", "/"); return normalized && !normalized.startsWith("/") && normalized.split("/").every(part => part !== ".." && part !== "");}), "Input artifacts must be workspace-relative paths without empty or parent segments.");
      pendingInputs = next;
    }
    function stageCriteria(value) {
      require(pendingStep === null, 'Apply or cancel the pending step change first.');
      require(selected !== null, 'Choose a work item first.');
      let next;
      try { next = JSON.parse(value); } catch { throw new Error('Provide acceptance criteria as a JSON array of strings.'); }
      require(Array.isArray(next) && next.length > 0 && next.every(item => typeof item === 'string' && item.trim()) && new Set(next).size === next.length,
        'Provide at least one distinct, nonblank acceptance criterion.');
      require(next.every(item => {const chars = Array.from(item); return chars.length <= 16384 && chars.every(char => char.codePointAt(0) < 0xD800 || char.codePointAt(0) > 0xDFFF);}),
        'Provide criteria of at most 16384 Unicode scalar characters each, matching saved-form validation.');
      pendingCriteria = [...next];
    }
    function stageDuplicate(id) {
      require(selected !== null, 'Choose a work item first.');
      require(!dirty(), 'Apply or cancel pending changes first.');
      require(/^[A-Za-z0-9_.-]{1,128}$/.test(id) && id !== '.' && !id.includes('..'), 'Use a safe new ID: 1–128 ASCII letters, digits, dots, hyphens or underscores; no .. segments.');
      require(!sourceIds.includes(id) && !ids.includes(id), 'The new ID must not reuse any source or current item ID.');
      require(ids.length < 256, 'A plan supports at most 256 items.');
      pendingStep = {kind: 'add', id, template: templates.get(ids[selected]) ?? ids[selected]};
    }
    function stageRemoval() {
      require(selected !== null, 'Choose a work item first.');
      require(!dirty(), 'Apply or cancel pending changes first.');
      require(ids.length > 1, 'Keep at least one declared item.');
      const consumers = ids.filter((_, i) => dependencies[i].includes(ids[selected]));
      require(!consumers.length, 'Repair prerequisites explicitly before removing this step. Still referenced by: ' + consumers.join(', '));
      pendingStep = {kind: 'remove', id: ids[selected]};
    }
    function remember() {history.push({ids: [...ids], templates: new Map(templates), selectedId: ids[selected], dependencies: dependencies.map(deps => [...deps]), timeouts: [...timeouts], inputs: clone(inputs), criteria: clone(criteria)}); if (history.length > 20) history.shift();}
    function apply() {
      require(dirty(), 'No pending declaration changes.');
      if (pendingStep) {
        remember();
        if (pendingStep.kind === 'add') {
          ids.push(pendingStep.id); templates.set(pendingStep.id, pendingStep.template);
          dependencies.push([...dependencies[selected]]); timeouts.push(timeouts[selected]);
          inputs.push([...inputs[selected]]); criteria.push([...criteria[selected]]);
          select(ids.length - 1);
        } else {
          templates.delete(ids[selected]);
          for (const values of [ids, dependencies, timeouts, inputs, criteria]) values.splice(selected, 1);
          select(null);
        }
        return;
      }
      const next = dependencies.map((deps, i) => i === selected ? [...pending] : [...deps]);
      topology(next); remember(); dependencies = next; timeouts[selected] = pendingTimeout; inputs[selected] = [...pendingInputs];
      criteria[selected] = [...pendingCriteria];
    }
    function undo() {require(history.length, 'Nothing to undo.'); const previous = history.pop(); ids = previous.ids; templates = previous.templates; dependencies = previous.dependencies; timeouts = previous.timeouts; inputs = previous.inputs; criteria = previous.criteria; const index = ids.indexOf(previous.selectedId); select(index < 0 ? null : index);}
    function reset() {
      const selectedId = ids[selected];
      if (changes().length) {
        remember(); ids = [...sourceIds]; templates = new Map(); dependencies = original.nodes.map(node => [...node.depends_on]); timeouts = [...originalTimeouts]; inputs = clone(originalInputs); criteria = clone(originalCriteria);
      }
      const index = ids.indexOf(selectedId); select(index < 0 ? null : index);
    }
    function changes() {
      return [
        ...sourceIds.filter(id => !ids.includes(id)).map(id => ({kind: 'remove', work_item_id: id})),
        ...ids.flatMap((id, index) => {
          const base = sourceIds.indexOf(templates.get(id) ?? id);
          return !templates.has(id) && same(dependencies[index], original.nodes[base].depends_on) && timeouts[index] === originalTimeouts[base] && same(inputs[index], originalInputs[base]) && same(criteria[index], originalCriteria[base]) ? [] : [{
            kind: templates.has(id) ? 'add' : 'edit', template: templates.get(id), work_item_id: id,
            before: [...original.nodes[base].depends_on], after: [...dependencies[index]], timeoutBefore: originalTimeouts[base], timeoutAfter: timeouts[index], inputsBefore: [...originalInputs[base]], inputsAfter: [...inputs[index]], criteriaBefore: [...originalCriteria[base]], criteriaAfter: [...criteria[index]]
          }];
        })
      ];
    }
    function downloadText() {
      require(!dirty(), 'Apply or cancel pending changes before downloading.');
      require(changes().length, 'No applied declaration changes to download.');
      topology(dependencies);
      const edits = ids.map((id, index) => ({work_item_id: id,
        input_artifacts: [...inputs[index]], depends_on: [...dependencies[index]],
        acceptance_criteria: [...criteria[index]], timeout_ms: timeouts[index]}));
      // Never stringify parsed source: preserve ALL original source JSON verbatim,
      // including unknown fields and integers outside JavaScript's exact range.
      const expanded = templates.size > 0 || ids.length !== sourceIds.length;
      const text = '{"contract_id":"moonflow.declared-plan-form-input.' + (expanded ? 'v2' : 'v1') + '","source_kind":"existing-graph","source_graph":' +
        sourceText + ',"edits":' + JSON.stringify(edits) + (expanded ? ',"added_templates":' + JSON.stringify(Object.fromEntries(templates)) : '') + '}\n';
      require(new TextEncoder().encode(text).length <= 4 * 1024 * 1024, 'Plan form exceeds the 4 MiB download limit.');
      return text;
    }
    if (resumedEdits !== null) {
      // The renderer validates the complete saved form and its lossless source
      // binding before embedding this detached, source-ordered edit list.
      const saved = Array.isArray(resumedEdits) ? {edits: resumedEdits} : resumedEdits;
      resumedEdits = saved.edits;
      templates = new Map(Object.entries(saved.added_templates ?? {}));
      ids = resumedEdits.map(edit => edit.work_item_id);
      require(ids.length > 0 && ids.length <= 256 && new Set(ids).size === ids.length && ids.every(id => sourceIds.includes(id) || sourceIds.includes(templates.get(id))), 'Saved plan does not match source work items.');
      dependencies = resumedEdits.map(edit => [...edit.depends_on]);
      timeouts = resumedEdits.map(edit => edit.timeout_ms);
      inputs = resumedEdits.map(edit => [...edit.input_artifacts]);
      criteria = resumedEdits.map(edit => [...edit.acceptance_criteria]);
    }
    topology(dependencies);
    return {select, stage, stageTimeout, stageInputs, stageCriteria, stageDuplicate, stageRemoval, pendingStep: () => pendingStep && {...pendingStep}, selectedIndex: () => selected, inputs: () => [...pendingInputs], criteria: () => [...pendingCriteria], timeout: () => pendingTimeout, apply, undo, reset, changes, snapshot, downloadText, dirty,
      cancel: () => select(selected), pending: () => [...pending], canUndo: () => history.length > 0,
      original: () => clone(original)};
  }

  function mount(document) {
    const data = JSON.parse(document.getElementById('graph-data').textContent);
    let report = data.report, graph = model(report);
    const products = data.products;
    const author = data.authoring ? editor(data.authoring.source_text, report, data.authoring.resume ?? null) : null;
    const get = id => document.getElementById(id);
    const controls = {search: get('search'), product: get('product'), focus: get('focus'), scope: get('scope')};
    let cards = Array.from(document.querySelectorAll('[data-index]'));
    let layers = Array.from(document.querySelectorAll('[data-layer]'));
    let buttons = Array.from(document.querySelectorAll('[data-select]'));
    const state = {query: '', product: '', focus: null, scope: 'all'};
    function add(parent, tag, text, className) {
      const element = document.createElement(tag);
      if (text !== undefined) element.textContent = text;
      if (className) element.className = className;
      parent.appendChild(element);
      return element;
    }
    function select(index, reveal = false) {
      if (author && index !== state.focus) {
        const discarded = author.select(index);
        get('edit-message').textContent = discarded ? 'Pending changes canceled when switching work items.' : '';
        get('edit-target').value = '';
      }
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
      if (author) authorDetails();
    }
    function authorDetails() {
      get('authoring').hidden = false;
      get('edit-node').textContent = state.focus === null ? 'Choose a work item above.' :
        `Editing declarations of ${report.nodes[state.focus].work_item_id}.`;
      const step = author.pendingStep();
      get('edit-step-preview').textContent = step ? (step.kind === 'add' ? `Pending addition: ${step.id}, copied from source operation ${step.template}. Apply to add this step.` : `Pending removal: ${step.id}. Apply to remove only this step.`) : '';
      for (const name of ['edit-new-id', 'edit-duplicate', 'edit-remove-step']) get(name).disabled = state.focus === null || author.dirty();
      const criteria = get('edit-criteria'); criteria.replaceChildren();
      for (const value of author.criteria()) add(criteria, 'li', value);
      get('edit-criteria-json').value = JSON.stringify(author.criteria(), null, 2);
      get('edit-criteria-json').disabled = get('edit-criteria-preview').disabled = state.focus === null;
      get('edit-inputs').value = author.inputs().join('\n');
      get('edit-inputs').disabled = get('edit-inputs-preview').disabled = state.focus === null;
      get('edit-inputs-pending').textContent = state.focus === null ? '' : 'Pending inputs: ' + author.inputs().join(', ');
      get('edit-timeout').value = author.timeout() === null ? '' : String(author.timeout());
      get('edit-timeout').disabled = get('edit-timeout-preview').disabled = state.focus === null;
      get('edit-timeout-pending').textContent = state.focus === null ? '' : `Pending timeout: ${author.timeout()} ms. Apply to retain this declaration.`;
      const pending = get('edit-pending'); pending.replaceChildren();
      for (const id of author.pending()) add(pending, 'li', id);
      if (!author.pending().length) add(pending, 'li', 'None');
      for (const name of ['edit-target', 'edit-add', 'edit-remove']) get(name).disabled = state.focus === null;
      get('edit-apply').disabled = get('edit-cancel').disabled = !author.dirty();
      get('edit-undo').disabled = !author.canUndo();
      const changes = author.changes();
      get('edit-reset').disabled = !changes.length && !author.dirty();
      get('edit-download').disabled = !changes.length || author.dirty();
      const list = get('edit-changes'); list.replaceChildren();
      for (const change of changes) {
        if (change.kind === 'remove') {add(list, 'li', `${change.work_item_id}: removed declared step.`); continue;}
        if (change.kind === 'add') add(list, 'li', `${change.work_item_id}: added declared step from source template ${change.template}; no acceptance is copied.`);
        if (JSON.stringify(change.criteriaBefore) !== JSON.stringify(change.criteriaAfter)) add(list, 'li', `${change.work_item_id}: acceptance criteria ${JSON.stringify(change.criteriaBefore)} → ${JSON.stringify(change.criteriaAfter)}.`);
        if (JSON.stringify(change.inputsBefore) !== JSON.stringify(change.inputsAfter)) add(list, 'li', `${change.work_item_id}: inputs [${change.inputsBefore.join(', ')}] → [${change.inputsAfter.join(', ')}].`);
        if (change.timeoutBefore !== change.timeoutAfter) add(list, 'li', `${change.work_item_id}: timeout ${change.timeoutBefore} → ${change.timeoutAfter} ms.`);
        const added = change.after.filter(id => !change.before.includes(id));
        const removed = change.before.filter(id => !change.after.includes(id));
        add(list, 'li', `${change.work_item_id}: added [${added.join(', ')}]; removed [${removed.join(', ')}].`);
      }
      const original = author.original(), baseline = model(original);
      const describe = (indexes, snapshot) => indexes.map(index => snapshot.nodes[index].work_item_id);
      for (let i = 0; i < report.nodes.length; i++) {
        const oldIndex = original.nodes.findIndex(node => node.work_item_id === report.nodes[i].work_item_id);
        const before = oldIndex < 0 ? [] : describe(baseline.relations(oldIndex).allPrerequisites, original);
        const after = describe(graph.relations(i).allPrerequisites, report);
        if (JSON.stringify(before) !== JSON.stringify(after)) {
          add(list, 'li', `${report.nodes[i].work_item_id} transitive prerequisites: [${before.join(', ') || 'none'}] → [${after.join(', ') || 'none'}].`);
        }
      }
      if (!changes.length) add(list, 'li', 'No applied changes.');
    }
    function rebuildCards() {
      const root = get('graph'); root.replaceChildren();
      for (const [control, prompt] of [[controls.focus, 'Choose an item'], [get('edit-target'), 'Choose a prerequisite']]) {
        control.replaceChildren(); add(control, 'option', prompt).value = '';
        report.nodes.forEach((node, index) => {add(control, 'option', node.work_item_id).value = String(index);});
      }
      state.focus = author.selectedIndex();
      controls.focus.value = state.focus === null ? '' : String(state.focus);
      get('edit-target').value = '';
      if (state.focus === null) {state.scope = 'all'; controls.scope.value = 'all';}
      cards = []; layers = []; buttons = [];
      for (let depth = 0; depth < report.layers.length; depth++) {
        const layer = add(root, 'section', undefined, 'layer');
        layer.dataset.layer = String(depth); layers.push(layer);
        add(layer, 'h2', `Dependency depth ${depth} (edited declaration)`);
        const group = add(layer, 'div', undefined, 'cards');
        for (const id of report.layers[depth]) {
          const index = report.nodes.findIndex(node => node.work_item_id === id), node = report.nodes[index];
          const card = add(group, 'article', undefined, 'node');
          card.id = `node-${index}`; card.dataset.index = String(index); cards.push(card);
          add(card, 'h3', id); add(card, 'p', node.product_id, 'product'); add(card, 'p', node.operation, 'operation');
          for (const [title, indexes] of [['Prerequisites', graph.relations(index).prerequisites],
            ['Direct consumers', graph.relations(index).consumers]]) {
            const line = add(card, 'p'); add(line, 'strong', `${title}: `);
            if (!indexes.length) add(line, 'span', 'None');
            indexes.forEach((related, j) => {
              if (j) add(line, 'span', ', ');
              const link = add(line, 'a', report.nodes[related].work_item_id);
              link.href = `#node-${related}`;
              link.addEventListener('click', () => select(related, true));
            });
          }
          const button = add(card, 'button', 'Explore this item'); button.type = 'button';
          button.dataset.select = String(index); buttons.push(button);
          button.addEventListener('click', () => select(index));
        }
      }
    }
    function authorAction(action, message, refresh = false) {
      try {
        action();
        if (refresh) {report = author.snapshot(); graph = model(report); rebuildCards();}
        get('edit-message').textContent = message;
      } catch (error) {get('edit-message').textContent = error.message;}
      update();
    }
    if (author) {
      function target() {
        const value = get('edit-target').value;
        return value === '' ? null : report.nodes[Number(value)]?.work_item_id;
      }
      get('edit-inputs-preview').addEventListener('click', () => authorAction(() => author.stageInputs(get('edit-inputs').value), 'Input artifact preview staged. Apply or cancel before download.'));
      get('edit-duplicate').addEventListener('click', () => authorAction(() => author.stageDuplicate(get('edit-new-id').value), 'Declared step addition preview staged. Apply or cancel.'));
      get('edit-remove-step').addEventListener('click', () => authorAction(() => author.stageRemoval(), 'Declared step removal preview staged. Apply or cancel.'));
      get('edit-criteria-preview').addEventListener('click', () => authorAction(() => author.stageCriteria(get('edit-criteria-json').value), 'Acceptance criteria preview staged. Apply or cancel before download.'));
      get('edit-timeout-preview').addEventListener('click', () => authorAction(() => author.stageTimeout(get('edit-timeout').value), 'Timeout preview staged. Apply or cancel before download.'));
      get('edit-add').addEventListener('click', () => authorAction(() => author.stage(target(), true), 'Prerequisite added to pending changes.'));
      get('edit-remove').addEventListener('click', () => authorAction(() => author.stage(target(), false), 'Prerequisite removed from pending changes.'));
      get('edit-apply').addEventListener('click', () => authorAction(() => author.apply(), 'Declarations applied locally. Review changes before download.', true));
      get('edit-cancel').addEventListener('click', () => authorAction(() => author.cancel(), 'Pending changes canceled.'));
      get('edit-undo').addEventListener('click', () => authorAction(() => author.undo(), 'Last applied edit undone; pending changes discarded.', true));
      get('edit-reset').addEventListener('click', () => authorAction(() => author.reset(), 'All edits reset to the original source. Applied resets can be undone.', true));
      get('edit-download').addEventListener('click', () => authorAction(() => {
        const blob = new Blob([author.downloadText()], {type: 'application/json'});
        const url = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = url; anchor.download = 'moonflow-dependency-plan.json';
        document.body.appendChild(anchor);
        try {anchor.click();} finally {anchor.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);}
      }, 'Dependency plan download requested. Native validation and preparation are still required.'));
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
    if (author && data.authoring.resume) {
      report = author.snapshot(); graph = model(report); rebuildCards();
      get('edit-message').textContent = 'Saved plan restored. Review its changes or continue editing before download.';
    }
    get('controls').hidden = false;
    update();
    return {graph, state};
  }
  globalThis.MoonFlowGraphExplorer = Object.freeze({model, editor, mount});
  if (typeof document !== 'undefined') mount(document);
})();
