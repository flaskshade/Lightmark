import deflist from 'markdown-it-deflist';
import mark from 'markdown-it-mark';
import sub from 'markdown-it-sub';
import sup from 'markdown-it-sup';
import { refreshDiagrams } from './diagram-loader.js';
import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import taskLists from 'markdown-it-task-lists';
import mathPlugin from '@vscode/markdown-it-katex';
import katex from 'katex';
import DOMPurify from 'dompurify';
import hljs from 'highlight.js/lib/common';

const root = document.getElementById('reader');
const md = new MarkdownIt({
  html: true, linkify: true, typographer: false,
  highlight(code, language) {
    // Unknown languages and very large fences remain readable plain code.
    if (code.length < 100_000 && language && hljs.getLanguage(language)) {
      try { return hljs.highlight(code, { language, ignoreIllegals: true }).value; } catch {}
    }
    return '';
  }
}).use(footnote).use(deflist).use(mark).use(sub).use(sup).use(taskLists, { enabled: true })
  .use(mathPlugin.default ?? mathPlugin, { katex, trust: false, throwOnError: false, maxExpand: 1000, maxSize: 20 });
md.core.ruler.after('github-task-lists', 'lightmark-task-source', state => {
  state.env.taskOffsets = new Set();
  if (!state.tokens.some(token => token.type === 'inline' && token.children?.some(child => child.content.startsWith('<input class="task-list-item-checkbox"')))) return;
  const source = state.env.originalSource ?? state.src;
  const lines = [...source.matchAll(/[^\r\n]*(?:\r\n|\n|\r|$)/g)];
  state.env.taskOffsets = new Set();
  for (const token of state.tokens) {
    if (token.type !== 'inline' || !token.map || !token.children) continue;
    const checkbox = token.children.find(child => child.type === 'html_inline' && child.content.startsWith('<input class="task-list-item-checkbox"'));
    if (!checkbox) continue;
    const line = lines[token.map[0]];
    if (!line) continue;
    const marker = line[0].match(/^(?:(?:[ \t]*>[ \t]?)|(?:[ \t]*(?:[-+*]|\d+[.)])[ \t]+))*[ \t]*\[([ xX])\](?=[ \t\r\n]|$)/);
    if (!marker) continue;
    const offset = line.index + marker[0].lastIndexOf('[') + 1;
    state.env.taskOffsets.add(offset);
    checkbox.content = checkbox.content.replace('<input ', `<input data-task-offset="${offset}" `);
  }
});
const defaultValidation = md.validateLink;
md.validateLink = url => /^file:/i.test(url) || defaultValidation(url);

// Allow simple author-provided presentation, never positioning, external CSS,
// hidden UI, executable content, or arbitrary network/resource references.
const safeStyle = new Set(['background-color','color','padding','border-radius','text-align']);
DOMPurify.addHook('uponSanitizeAttribute', (node, data) => {
  if (data.attrName === 'style') {
    const probe = document.createElement('span');
    probe.setAttribute('style', data.attrValue);
    data.attrValue = Array.from(probe.style).filter(key => safeStyle.has(key))
      .filter(key => !/url\(|expression|var\(/i.test(probe.style.getPropertyValue(key)))
      .map(key => `${key}:${probe.style.getPropertyValue(key)}`).join(';');
  }
});
// Sanitize raw HTML tokens separately: KaTeX's trusted generated positioning
// styles must survive, while document-provided styles remain constrained.
for (const type of ['html_block', 'html_inline']) {
  md.renderer.rules[type] = (tokens, idx) => DOMPurify.sanitize(tokens[idx].content, {
    FORBID_TAGS: ['script','style','iframe','object','embed','form','button','textarea','select','input','meta','link','base'],
    ADD_TAGS: ['details','summary'], ALLOW_DATA_ATTR: false
  });
}
// Inline HTML needs paired tags; sanitizing individual tags auto-closes them.
// Keep block sanitization; sanitize the complete output below for inline tags.
md.renderer.rules.html_inline = (tokens, idx) => tokens[idx].content;
md.renderer.rules.lightmark_math = (tokens, idx) => tokens[idx].content;
let lastSource = null, lastIdentity = null, lastVersion = 0;
let pending = null, scheduled = false, taskFocus = null;

function render(payload) {
  lastVersion = payload.version;
  document.documentElement.dataset.theme = payload.dark ? 'dark' : 'light';
  root.style.setProperty('--font-size', `${payload.fontSize}px`);
  root.style.setProperty('--reading-width', payload.width > 0 ? `${payload.width}px` : 'none');
  root.dataset.bodyFont = payload.bodyFont;
  root.dataset.headingFont = payload.headingFont;
  if (payload.source === lastSource && payload.identity === lastIdentity) {
    refreshDiagrams(root, payload.dark);
    return;
  }
  tableResizeObserver.disconnect();
  root.classList.remove('render-fallback');
  const scroll = window.scrollY;
  const sameDocument = payload.identity === lastIdentity;
  const environment = { originalSource: payload.source };
  let rendered;
  try {
    // Raw HTML gets sanitized before generated math is rendered below.
    const tokens = md.parse(payload.source, environment);
    // Render math as inert placeholders until the document is sanitized.
    const math = [];
    function deferMath(list) {
      for (const token of list) {
        if (['math_inline','math_block','math_inline_block','math_inline_bare_block'].includes(token.type)) {
          const block = token.type !== 'math_inline';
          const id = math.length;
          math.push({ text: token.content, block });
          token.type = 'lightmark_math';
          token.content = `<${block ? 'div' : 'span'} class="lm-math" data-math="${id}"></${block ? 'div' : 'span'}>`;
        }
        if (token.children) deferMath(token.children);
      }
    }
    // Use KaTeX plugin parsing, then render math after sanitization to avoid
    // weakening HTML sanitization for its generated style attributes.
    deferMath(tokens);
    rendered = md.renderer.render(tokens, md.options, environment);
    const fragment = DOMPurify.sanitize(rendered, {
      RETURN_DOM_FRAGMENT: true, ADD_TAGS: ['details','summary'], ADD_ATTR: ['data-math', 'data-task-offset'],
      FORBID_TAGS: ['script','style','iframe','object','embed','form','button','textarea','select','meta','link','base'],
      ALLOW_DATA_ATTR: false, ALLOW_UNKNOWN_PROTOCOLS: false,
      ADD_URI_SAFE_ATTR: [],
      ALLOWED_URI_REGEXP: /^(?:(?:https?|mailto|tel|file):|[^a-z]|[a-z+.-]+(?:[^a-z+.-:]|$))/i
    });
    for (const element of fragment.querySelectorAll('.lm-math[data-math]')) {
      const entry = math[Number(element.dataset.math)];
      if (!entry) { element.remove(); continue; }
      katex.render(entry.text, element, { displayMode: entry.block, trust: false, throwOnError: false, maxExpand: 1000, maxSize: 20 });
      if (entry.block) {
        element.style.position = 'relative';
        element.classList.add('lm-copy-math-parent');
        const tex = entry.text;
        const mathBtn = createCopyButton('lm-copy-math-btn', 'Copy LaTeX', btn => {
          copyTextWithFeedback(tex, btn);
        });
        element.appendChild(mathBtn);
      }
    }
    // A light author-specified HTML background still needs dark text when the
    // app is dark. Respect explicit foreground colors; otherwise ensure contrast.
    for (const element of fragment.querySelectorAll('[style]')) {
      if (element.style.backgroundColor && !element.style.color) {
        const rgb = element.style.backgroundColor.match(/\d+(?:\.\d+)?/g);
        if (rgb?.length >= 3) {
          const luminance = .2126 * Number(rgb[0]) + .7152 * Number(rgb[1]) + .0722 * Number(rgb[2]);
          element.style.color = luminance > 145 ? '#272729' : '#eeeeef';
        }
      }
    }
    for (const input of fragment.querySelectorAll('input')) {
      if (input.type !== 'checkbox') input.remove();
      else {
        input.disabled = !payload.editable || !environment.taskOffsets.has(Number(input.dataset.taskOffset));
        input.setAttribute('aria-label', input.closest('li')?.textContent.trim() || 'Task');
      }
    }
    const headings = new Map();
    for (const heading of fragment.querySelectorAll('h1,h2,h3,h4,h5,h6')) {
      const slug = heading.textContent.trim().toLowerCase().replace(/[^\p{L}\p{N}_\-\s]/gu, '').replace(/\s+/g, '-') || 'section';
      const count = headings.get(slug) ?? 0;
      headings.set(slug, count + 1);
      heading.id = count ? `${slug}-${count}` : slug;
    }
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
    for (const pre of fragment.querySelectorAll('pre')) {
      pre.style.position = 'relative';
      const codeEl = pre.querySelector('code');
      const codeBtn = createCopyButton('lm-copy-code-btn', 'Copy code', btn => {
        copyTextWithFeedback(codeEl ? codeEl.textContent : pre.textContent, btn);
      });
      pre.appendChild(codeBtn);
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
    for (const img of fragment.querySelectorAll('img')) {
      const src = img.getAttribute('src') ?? '';
      img.removeAttribute('srcset');
      img.loading = 'lazy'; img.decoding = 'async'; img.referrerPolicy = 'no-referrer';
      if (!/^(https?:|data:image\/(png|jpeg|gif|webp);)/i.test(src)) {
        img.src = `lightmark-image://document/?path=${encodeURIComponent(src)}`;
      }
      img.addEventListener('error', () => {
        const fallback = document.createElement('span');
        fallback.className = 'image-fallback'; fallback.textContent = img.alt || 'Image unavailable';
        fallback.title = src; img.replaceWith(fallback);
      }, { once: true });
    }
    root.replaceChildren(fragment);
    refreshDiagrams(root, payload.dark, true);
    for (const table of root.querySelectorAll('table')) {
      updateTopRightHeaderShiftNeed(table);
    }
    if (sameDocument && taskFocus !== null) {
      root.querySelector(`input[data-task-offset="${taskFocus}"]`)?.focus({ preventScroll: true });
    }
    taskFocus = null;
    lastSource = payload.source; lastIdentity = payload.identity;
    window.scrollTo(0, sameDocument ? scroll : 0);
  } catch (error) {
    root.textContent = payload.source; root.classList.add('render-fallback');
    console.error('Markdown rendering failed', error);
  }
}
window.lightmarkRender = payload => {
  pending = payload;
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(() => { scheduled = false; render(pending); });
};
root.addEventListener('click', event => {
  const link = event.target.closest('a');
  if (!link) return;
  event.preventDefault();
  const href = link.getAttribute('href');
  if (!href) return;
  if (href === '#') { window.scrollTo(0, 0); return; }
  if (href.startsWith('#')) {
    try {
      const target = document.getElementById(decodeURIComponent(href.slice(1)));
      target?.scrollIntoView({ block: 'center' });
      if (target && (link.classList.contains('footnote-ref') || link.closest('.footnote-ref'))) {
        target.getAnimations().forEach(animation => animation.cancel());
        target.animate([
          { backgroundColor: 'transparent' },
          { backgroundColor: 'rgba(100,165,235,.22)', offset: .12 },
          { backgroundColor: 'rgba(100,165,235,.22)', offset: .55 },
          { backgroundColor: 'transparent' }
        ], { duration: matchMedia('(prefers-reduced-motion: reduce)').matches ? 700 : 1600 });
      }
    } catch {}
    return;
  }
  window.webkit.messageHandlers.openLink.postMessage(href);
});

root.addEventListener('change', event => {
  const input = event.target;
  if (!(input instanceof HTMLInputElement) || input.disabled || !input.hasAttribute('data-task-offset')) return;
  taskFocus = input === document.activeElement ? Number(input.dataset.taskOffset) : null;
  input.disabled = true;
  window.webkit.messageHandlers.toggleTask.postMessage({ offset: Number(input.dataset.taskOffset), checked: input.checked, version: lastVersion });
});

// ── Copy helpers ──────────────────────────────────────────────────────────────
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
  navigator.clipboard.writeText(text).then(() => {
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
  }).catch(() => {});
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
