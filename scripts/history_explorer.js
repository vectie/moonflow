/* This portable view never fetches, executes references, or writes storage. */
(() => {
  'use strict';
  const rows = JSON.parse(document.getElementById('timeline-data').textContent);
  const cards = [...document.querySelectorAll('article[data-index]')];
  const item = document.getElementById('item');
  const kind = document.getElementById('kind');
  const search = document.getElementById('search');
  function update() {
    const query = search.value.toLowerCase();
    let visible = 0;
    rows.forEach((row, i) => {
      const show = (item.value === '' || String(row.item) === item.value)
        && (kind.value === '' || String(row.kind) === kind.value)
        && row.text.toLowerCase().includes(query);
      cards[i].hidden = !show;
      if (show) visible += 1;
    });
    document.getElementById('count').textContent = `${visible} of ${rows.length} events`;
    document.getElementById('empty').hidden = visible !== 0;
  }
  [item, kind, search].forEach(control => control.addEventListener('input', update));
  document.getElementById('reset').addEventListener('click', () => {
    item.value = ''; kind.value = ''; search.value = ''; update();
  });
  document.querySelector('nav').hidden = false;
  update();
})();
