import { copyText } from './clipboard.js';
// Adapted directly from Lightmark Renderer/reader.js.
function copyIconSVG() {
  return `<svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden="true">
    <rect x="5" y="5" width="9" height="9" rx="2" stroke="currentColor" stroke-width="1.5"/>
    <path d="M11 5V3a2 2 0 0 0-2-2H3a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h2" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  </svg>`;
}

function checkIconSVG() {
  return `<svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden="true">
    <polyline points="2.5,8.5 6,12 13.5,4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>`;
}

function copyButtonHTML() {
  return `<span class="lm-copy-icon lm-copy-icon--idle" aria-hidden="true">${copyIconSVG()}</span>` +
         `<span class="lm-copy-icon lm-copy-icon--done" aria-hidden="true">${checkIconSVG()}</span>`;
}

function createCopyButton(className, label, onCopy) {
  const btn = document.createElement('button');
  btn.className = `lm-copy-btn ${className}`;
  btn.setAttribute('aria-label', label);
  btn.title = label;
  btn.innerHTML = copyButtonHTML();
  btn.addEventListener('pointerdown', e => e.stopPropagation());
  btn.addEventListener('mousedown', e => e.stopPropagation());
  btn.addEventListener('click', e => {
    e.stopPropagation();
    onCopy(btn);
  });
  return btn;
}


const tableResizeObserver = new ResizeObserver(entries => {
  for (const entry of entries) {
    const table = entry.target.querySelector('table') || entry.target;
    if (table) updateTopRightHeaderShiftNeed(table);
  }
});

function updateTopRightHeaderShiftNeed(table) {
  if (!table) return;
  const topTh = table.querySelector('thead tr:first-child > th:last-child, tr:first-child > th:last-child');
  if (!topTh) return;
  const content = topTh.querySelector('.lm-th-content');
  if (!content) return;

  const thWidth = topTh.clientWidth;
  if (!thWidth) return;

  // The copy button is 28px wide at right: 8px (takes up rightmost 36px).
  // With 6px safety margin, forbidden zone starts at (thWidth - 42px).
  const forbiddenStart = thWidth - 42;

  const textAlign = (topTh.style.textAlign || getComputedStyle(topTh).textAlign || '').toLowerCase();
  const contentWidth = content.offsetWidth;

  let contentEnd;
  if (textAlign === 'right') {
    // Right-aligned: sits against right padding (14px from right border)
    contentEnd = thWidth - 14;
  } else if (textAlign === 'center') {
    // Center-aligned: centered within thWidth
    contentEnd = (thWidth + contentWidth) / 2;
  } else {
    // Left-aligned (default): starts at left padding (14px from left border)
    contentEnd = 14 + contentWidth;
  }

  if (contentEnd > forbiddenStart) {
    topTh.classList.add('lm-th-needs-shift');
  } else {
    topTh.classList.remove('lm-th-needs-shift');
  }
}

function copyTextWithFeedback(text, btn) {
  if (!text) return;
  copyText(text).then(() => {
    if (btn._timer) clearTimeout(btn._timer);
    if (btn._fadeTimer) clearTimeout(btn._fadeTimer);

    btn.classList.remove('lm-copy-btn--fading');
    btn.classList.add('lm-copy-btn--done');

    const wrapper = btn.closest('.table-wrapper');
    if (wrapper) wrapper.classList.add('lm-table-copying');

    btn._timer = setTimeout(() => {
      const parent = btn.closest('.table-wrapper, .table-scroll, pre, blockquote, .katex-display, .lm-copy-math-parent') || btn.parentElement;
      const isHovered = (parent && parent.matches(':hover')) || btn.matches(':hover');

      if (isHovered) {
        // User is still hovering: smoothly crossfade from checkmark back to copy icon
        btn.classList.remove('lm-copy-btn--done');
        if (wrapper) wrapper.classList.remove('lm-table-copying');
      } else {
        // User left the block: smoothly fade out while retaining checkmark appearance
        btn.classList.add('lm-copy-btn--fading');
        btn._fadeTimer = setTimeout(() => {
          btn.classList.remove('lm-copy-btn--done');
          btn.classList.remove('lm-copy-btn--fading');
          if (wrapper) wrapper.classList.remove('lm-table-copying');
        }, 200);
      }
    }, 1800);
   }).catch(() => {
    const dialog = document.createElement('dialog');
    dialog.className = 'download-modal';
    const heading = document.createElement('h2');
    heading.textContent = 'Copy text';
    const instructions = document.createElement('p');
    instructions.textContent = 'Touch and hold the text below to select and copy it.';
    const field = document.createElement('textarea');
    field.readOnly = true;
    field.value = text;
    field.style.cssText = 'width:100%;height:180px;font-size:16px';
    const close = document.createElement('button');
    close.textContent = 'Close';
    close.autofocus = true;
    close.addEventListener('click', () => dialog.close());
    dialog.addEventListener('close', () => { dialog.remove(); btn.focus({preventScroll:true}); });
    dialog.append(heading,instructions,field,close);
    document.body.append(dialog);
    dialog.showModal();
  });
}

function copyTableAsText(table, btn) {
  // Clone to strip sort indicators and copy buttons from the copy
  const clone = table.cloneNode(true);
  clone.querySelectorAll('.lm-sort-indicator, .lm-copy-btn').forEach(el => el.remove());
  const rows = Array.from(clone.querySelectorAll('tr'));
  const text = rows.map(row =>
    Array.from(row.querySelectorAll('th,td')).map(cell => cell.textContent.trim()).join('\t')
  ).join('\n');
  copyTextWithFeedback(text, btn);
}

function copyBlockquoteAsText(bq, btn) {
  // Clone to strip any nested copy buttons from the copy
  const clone = bq.cloneNode(true);
  clone.querySelectorAll('.lm-copy-btn, .lm-sort-indicator').forEach(el => el.remove());
  copyTextWithFeedback(clone.textContent.trim(), btn);
}

function sortIconSVG() {
  return `<svg class="lm-sort-svg" width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <path class="lm-sort-up" d="M4 6.5L8 2.5L12 6.5"/>
    <path class="lm-sort-down" d="M4 9.5L8 13.5L12 9.5"/>
  </svg>`;
}

// ── Table sort ────────────────────────────────────────────────────────────────
const tableSortState = new WeakMap();

function sortTable(table, colIndex, clickedTh) {
  const state = tableSortState.get(table) ?? { col: -1, asc: true };
  const asc = state.col === colIndex ? !state.asc : true;
  tableSortState.set(table, { col: colIndex, asc });

  // Reset all headers in this table
  table.querySelectorAll('th.lm-sortable').forEach(th => {
    th.setAttribute('aria-sort', 'none');
    th.classList.remove('lm-sort-asc', 'lm-sort-desc');
  });
  clickedTh.setAttribute('aria-sort', asc ? 'ascending' : 'descending');
  clickedTh.classList.add(asc ? 'lm-sort-asc' : 'lm-sort-desc');

  const tbody = table.querySelector('tbody');
  if (!tbody) return;
  const rows = Array.from(tbody.querySelectorAll('tr'));
  rows.sort((a, b) => {
    const aCell = a.querySelectorAll('td,th')[colIndex];
    const bCell = b.querySelectorAll('td,th')[colIndex];
    const aText = aCell?.textContent.trim() ?? '';
    const bText = bCell?.textContent.trim() ?? '';
    const aNum = parseFloat(aText.replace(/[^0-9.\-]/g, ''));
    const bNum = parseFloat(bText.replace(/[^0-9.\-]/g, ''));
    const isNum = !isNaN(aNum) && !isNaN(bNum);
    let cmp = isNum ? aNum - bNum : aText.localeCompare(bText, undefined, { numeric: true, sensitivity: 'base' });
    return asc ? cmp : -cmp;
  });
  tbody.append(...rows);
  updateTopRightHeaderShiftNeed(table);
}

export function addReaderControls(fragment) {
 tableResizeObserver.disconnect();
    for (const table of fragment.querySelectorAll('table')) {
      const container = document.createElement('div');
      container.className = 'table-wrapper';
      const scroll = document.createElement('div');
      scroll.className = 'table-scroll';
      scroll.tabIndex = 0;
      scroll.setAttribute('role', 'region');
      scroll.setAttribute('aria-label', 'Table; scroll horizontally if needed');

      // Copy button for tables — pinned to top right of table-wrapper
      const tableBtn = createCopyButton('lm-copy-table-btn', 'Copy table', btn => copyTableAsText(table, btn));

      // Sortable headers — wrap content so it truncates cleanly with suspension points (ellipsis)
      table.querySelectorAll('th').forEach((th, colIndex) => {
        th.classList.add('lm-sortable');
        th.setAttribute('role', 'columnheader');
        th.setAttribute('aria-sort', 'none');

        const clip = document.createElement('span');
        clip.className = 'lm-th-clip';

        const content = document.createElement('span');
        content.className = 'lm-th-content';

        const textSpan = document.createElement('span');
        textSpan.className = 'lm-th-text';
        while (th.firstChild) textSpan.appendChild(th.firstChild);

        const indicator = document.createElement('span');
        indicator.className = 'lm-sort-indicator';
        indicator.innerHTML = sortIconSVG();

        content.append(textSpan, indicator);
        clip.append(content);
        th.appendChild(clip);
        th.addEventListener('click', () => sortTable(table, colIndex, th));
      });

      table.replaceWith(container);
      scroll.append(table);
      container.append(scroll, tableBtn);

      container.addEventListener('pointerenter', () => updateTopRightHeaderShiftNeed(table));
      tableResizeObserver.observe(container);
    }
    // Copy button for all blockquotes (including nested)
    for (const bq of fragment.querySelectorAll('blockquote')) {
      bq.style.position = 'relative';
      bq.classList.add('lm-copy-bq-parent');
      const bqBtn = createCopyButton('lm-copy-bq-btn', 'Copy quote', btn => {
        copyBlockquoteAsText(bq, btn);
      });
      bq.appendChild(bqBtn);
    }
 for (const pre of fragment.querySelectorAll('pre')) {
 pre.style.position = 'relative';
 pre.append(createCopyButton('lm-copy-code-btn', 'Copy code', btn => copyTextWithFeedback(pre.querySelector('code')?.textContent ?? '', btn)));
 }
 for (const header of fragment.querySelectorAll('th.lm-sortable')) {
 header.tabIndex = 0;
 header.addEventListener('keydown', event => {
 if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); header.click(); }
 });
 }
}
