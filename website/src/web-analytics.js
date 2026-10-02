// Manual loading allows the owner to exclude each browser before any beacon loads.
const flag = 'lightmarkAnalyticsExcluded';
const choice = new URLSearchParams(location.search).get('analytics');
let excluded = choice === 'off';
try {
  if (choice === 'off') localStorage.setItem(flag, 'true');
  if (choice === 'on') localStorage.removeItem(flag);
  excluded = excluded || localStorage.getItem(flag) === 'true';
} catch { /* The exclusion still applies to this visit when storage is unavailable. */ }
if (!excluded && ['trylightmark.com', 'www.trylightmark.com'].includes(location.hostname)) {
  const beacon = document.createElement('script');
  beacon.type = 'module';
  beacon.src = 'https://static.cloudflareinsights.com/beacon.min.js';
  beacon.dataset.cfBeacon = JSON.stringify({token: 'e8c6b5465def46979a8e7127a474cab3'});
  document.head.append(beacon);
}
