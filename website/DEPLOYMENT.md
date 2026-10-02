# Website deployment

The website is hosted on Cloudflare Pages with Git integration. Pushes to `main` deploy automatically.

- Root directory: `website`
- Build command: `npm ci --ignore-scripts && npm run build`
- Output directory: `site-output`
- Node.js: 22
- `SITE_URL`: `https://trylightmark.com/`

The build includes static pages, assets and signed downloads. Do not publish source directories or dependencies. App releases use the separate [release workflow](../docs/releases.md).
