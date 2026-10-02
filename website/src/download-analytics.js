// Only the Download event is emitted; the Plausible tracker is configured separately.
const params = new URLSearchParams(location.search);
let excluded = false;
try {
  if (params.get('analytics') === 'off') localStorage.setItem('plausible_ignore', 'true');
  if (params.get('analytics') === 'on') localStorage.removeItem('plausible_ignore');
  excluded = localStorage.getItem('plausible_ignore') === 'true';
} catch {
  // If storage is blocked, the exclusion link still works for this visit.
  excluded = params.get('analytics') === 'off';
}
export function trackDownload() {
  if (excluded || location.hostname !== 'trylightmark.com') return;
  // Never let an unavailable or blocked analytics script interfere with downloads.
  try { globalThis.plausible?.('Download', {url: 'https://trylightmark.com/'}); } catch {}
}
