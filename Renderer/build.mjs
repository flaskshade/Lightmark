import { build } from 'esbuild';
import { mkdir, cp, readdir, readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
const out = resolve('../Resources/Reader');
await mkdir(out, { recursive: true });
await build({ entryPoints: ['reader.js'], bundle: true, minify: true, target: 'safari17', outfile: join(out, 'reader.js'), alias: { katex: resolve('node_modules/katex') }, legalComments: 'eof' });
await build({ entryPoints: ['diagrams.js'], bundle: true, minify: true, format: 'iife', target: 'safari17', outfile: join(out, 'diagrams.js'), legalComments: 'eof' });
await cp('reader.css', join(out, 'reader.css'));
await cp('index.html', join(out, 'index.html'));
await cp('../Examples/MarkdownStressTest.md', join(out, 'stress.md'));
await cp('node_modules/katex/dist/katex.min.css', join(out, 'katex.min.css'));
await cp('node_modules/katex/dist/fonts', join(out, 'fonts'), { recursive: true });
await cp('../Resources/Fonts/InstrumentSerif-Regular.ttf', join(out, 'InstrumentSerif-Regular.ttf'));
let notices = 'Lightmark reader — bundled third-party licenses\n\n';
async function licenses(dir) {
  for (const item of await readdir(dir, { withFileTypes: true })) {
    if (!item.isDirectory() || item.name.startsWith('.')) continue;
    const path = join(dir, item.name);
    if (item.name.startsWith('@')) { await licenses(path); continue; }
    try {
      const pkg = JSON.parse(await readFile(join(path, 'package.json'), 'utf8'));
      if (pkg.name.startsWith('@esbuild') || pkg.name === 'esbuild') continue;
      for (const file of await readdir(path)) {
        if (/^(license|copying)/i.test(file)) notices += `\n--- ${pkg.name} ${pkg.version} ---\n` + await readFile(join(path, file), 'utf8') + '\n';
      }
    } catch {}
  }
}
await licenses('node_modules');
await writeFile(join(out, 'THIRD-PARTY-NOTICES.txt'), notices);
