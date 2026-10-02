import { build } from 'esbuild';
await build({ entryPoints: ['src/main.js'], bundle: true, minify: true, target: 'safari17', outfile: 'assets/main.js', legalComments: 'eof' });

await build({ entryPoints: ['src/contact-card.js'], bundle: true, minify: true, target: 'safari17', outfile: 'assets/contact-card.js' });

// Preserve the notices of dependencies shipped inside the static JS bundle.
import { readdir, readFile, writeFile } from 'node:fs/promises';
let notices = 'Lightmark website — bundled third-party licenses\n';
for (const entry of await readdir('node_modules', { withFileTypes: true })) {
  if (!entry.isDirectory() || entry.name.startsWith('.') || entry.name.startsWith('@') || entry.name === 'esbuild') continue;
  const directory = `node_modules/${entry.name}`;
  for (const file of await readdir(directory)) {
    if (/^(license|copying)/i.test(file)) notices += `\n--- ${entry.name} ---\n${await readFile(`${directory}/${file}`, 'utf8')}\n`;
  }
}
await writeFile('assets/THIRD-PARTY-NOTICES.txt', notices);

// Override the provisional domain without changing the sharing metadata by hand.
const siteURL = new URL(process.env.SITE_URL || 'https://trylightmark.com/');
if (siteURL.protocol !== 'https:') throw new Error('SITE_URL must use HTTPS');
siteURL.pathname = siteURL.pathname.replace(/\/?$/, '/');
siteURL.search = ''; siteURL.hash = '';
let html = await readFile('index.html', 'utf8');
html = html.replace(/(<link rel="canonical" href=")[^"]+("[^>]*>)/, `$1${siteURL.href}$2`)
 .replace(/(<meta property="og:url" content=")[^"]+("[^>]*>)/, `$1${siteURL.href}$2`)
 .replace(/(<meta (?:property="og:image"|name="twitter:image") content=")[^"]+("[^>]*>)/g, `$1${new URL('assets/social-preview.png',siteURL).href}$2`);
const releaseURL = process.env.RELEASE_DOWNLOAD_URL;
// Keep the existing release available until the first verified DMG is published.
if (!releaseURL && !(await readdir('downloads')).includes('Lightmark.dmg')) {
 html = html.replaceAll('Lightmark.dmg', 'Lightmark.zip');
}
if (releaseURL) {
 const url = new URL(releaseURL);
 if (url.protocol !== 'https:') throw new Error('Release downloads must use HTTPS');
 html = html.replace(/href="downloads\/Lightmark\.(?:zip|dmg)"/, `href="${url.href}"`).replace(/ download="Lightmark\.(?:zip|dmg)"/, '');
}

// Only deploy the allowlisted static output, never the source tree.
const { cp, mkdir, rm } = await import('node:fs/promises');
const output = 'site-output';
await rm(output, { recursive:true, force:true });
await mkdir(output);
for (const file of ['style.css','pages.css','assets','contact','privacy','changelog']) {
 await cp(file, `${output}/${file}`, { recursive:true });
}
await writeFile(`${output}/index.html`,html);
if (!releaseURL) {
 await mkdir('downloads',{recursive:true});
 await cp('downloads',`${output}/downloads`,{recursive:true});
}
await writeFile(`${output}/_headers`, `/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  X-Frame-Options: DENY
`);
