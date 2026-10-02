import { trackDownload } from './download-analytics.js';
import { installMobileScrollbar } from './mobile-scrollbar.js';
import { copyText } from './clipboard.js';
import { installWindowFrame } from './window-frame.js';
import MarkdownIt from 'markdown-it';
import DOMPurify from 'dompurify';
import { addReaderControls } from './reader-controls.js';

const parser = new MarkdownIt({ html: false, linkify: false });
const documents = { welcome: { title: "Lightmark.md", source: "# Lightmark\n\n macOS comes with **dedicated apps** for most common file types:\n\n| File                   | Default Utility  |\n| ---------------------- | ---------------- |\n| `.pdf`, `.jpg`, `.png` | Preview          |\n| `.txt`, `.rtf`         | TextEdit         |\n| `.mp4`, `.mov`, `.mp3` | QuickTime Player |\n| `.zip`                 | Archive Utility  |\n\nBut there is **no equivalent default utility** for **Markdown files**.\n\n| File                 | Default Utility |\n| -------------------- | --------------- |\n| **`.md` (Markdown)** | ?               |\n\n### \u2192 Lightmark: a simple, native macOS utility for Markdown\n\n> Lightmark is a **lightweight Mac app** for **opening, reading, and editing** Markdown files.\n>\n> - Open, read, and edit `.md` files\n> - The essentials you'd expect from a default utility\n> - **Native, simple, and lightweight**\n" } };
const preview = document.querySelector('#preview');
const editor = document.querySelector('#editor');
const editToggle = document.querySelector('#edit-toggle');
let activeDocument = 'welcome';
let editing = false;

function render() {
  preview.innerHTML = DOMPurify.sanitize(parser.render(documents[activeDocument].source));
  addReaderControls(preview);
}
function changeMode(value) {
  editing = value;
  document.querySelector(".document-surface").classList.toggle("is-editing", editing);
  if (!editing) render();
  editor.hidden = !editing;
  preview.hidden = editing;
  editToggle.innerHTML = `${editing ? 'View' : 'Edit'} <kbd aria-hidden="true">⌘E</kbd>`;
  editToggle.setAttribute('aria-pressed', String(editing));
  if (editing) editor.focus({ preventScroll: true });
}
function selectDocument(key) {
  activeDocument = key;
  editor.value = documents[key].source;
  document.querySelector('#window-title').textContent = documents[key].title;
  for (const tab of document.querySelectorAll('.tab')) {
    const selected = tab.dataset.document === key;
    tab.classList.toggle('active', selected);
    if (selected) tab.setAttribute('aria-current', 'page');
    else tab.removeAttribute('aria-current');
  }
  render();
  document.querySelector('.document-surface').scrollTop = 0;
}
editor.addEventListener('input', () => {
  documents[activeDocument].source = editor.value;
});
editToggle.addEventListener('click', () => changeMode(!editing));
for (const tab of document.querySelectorAll('.tab')) tab.addEventListener('click', () => selectDocument(tab.dataset.document));
document.querySelector('#demo-window').addEventListener('keydown', event => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'e') {
    event.preventDefault(); changeMode(!editing);
  }
});
selectDocument(activeDocument);

installWindowFrame(document.querySelector("#demo-window"));

const download = document.querySelector('.download');
const modal = document.querySelector('.download-modal');
const downloadLink = document.querySelector('#download-link');
const copyButton = document.querySelector('#copy-download');
const copyStatus = document.querySelector('#copy-status');
const mobileDevice = () => /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
download.addEventListener('click', event => {
  if (!mobileDevice()) { trackDownload(); return; }
  event.preventDefault();
  downloadLink.value = new URL(download.getAttribute('href'), location.href).href;
  copyStatus.textContent = '';
  copyButton.textContent = 'Copy link';
  modal.showModal();
  document.querySelector("#close-download").focus({ preventScroll: true });
});
document.querySelector('#close-download').addEventListener('click', () => modal.close());
modal.addEventListener('click', event => {
  const rect = modal.getBoundingClientRect();
  if (event.target === modal && (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom)) modal.close();
});
modal.addEventListener('close', () => download.focus({ preventScroll: true }));
copyButton.addEventListener('click', async () => {
  try {
    await copyText(downloadLink.value);
    copyButton.textContent = 'Copied';
    copyStatus.textContent = 'Link copied. Open it on your Mac.';
  } catch {
    downloadLink.focus();
    downloadLink.select();
    downloadLink.setSelectionRange(0, downloadLink.value.length);
    copyStatus.textContent = 'Touch and hold the selected link to copy it.';
  }
});

// Release the entrance transform so the CTA's hover/pressed states can take over.
download.addEventListener('animationend', () => { download.style.animation = 'none'; });

installMobileScrollbar(document.querySelector("#demo-window"));
