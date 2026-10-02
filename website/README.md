# Lightmark website

A static, single-screen website with two equal halves: an interactive Lightmark window on the left; the dark icon, a short introduction, a free Mac download and a discreet GitHub star link on the right. No account or external fonts. Cloudflare provides basic website analytics; the document demo has no runtime CDN dependencies.

## Local preview

From this directory:

```sh
npm ci --ignore-scripts
npm run build
npm run dev
```

Open `http://127.0.0.1:4173`. Serve `website/` as the static site root when publishing. Production only needs `index.html`, `style.css`, `assets/`, and the download archive; do not upload `node_modules` or build sources.

Desktop uses the two-column single-screen layout at widths of 1000px and above. Below that, the page flows vertically: app presentation and download first, then the embedded demo. Mobile page scrolling and independent document scrolling are both available. Short desktop windows also allow page scrolling to keep controls accessible. Entry animation respects Reduce Motion.

## Ownership

- `index.html`: page content, metadata, download link, platform/version labels.
- `style.css`: the split-screen layout and simulated native window chrome.
- `assets/reader.css`: scoped default block styles copied from `../Renderer/reader.css`; keep these aligned when the app reader changes.
- `src/main.js`: the editable presentation document and Edit/View switch. Edits stay local and reset on reload.
- `src/reader-controls.js`: table sorting and block copy controls adapted from the app reader, including hover feedback and header clearance.
- `build.mjs`, `package.json`, `package-lock.json`: pinned build dependencies and the offline JS bundle. Markdown is sanitized before display; the demo never runs document HTML.
- `assets/lightmark.png`: an optimized copy of the supplied dark app artwork.
- `downloads/Lightmark.zip`: signed/notarized release archive tracked in the repository.

## Download and distribution

The button targets the notarized `downloads/Lightmark.dmg` with a drag-to-Applications window. The ZIP remains an optional archive. Production downloads are Developer ID signed, Apple-notarized and stapled. Release with `scripts/publish-release.sh` from the repository root; see [../docs/releases.md](../docs/releases.md). Do not replace the public archive with a development build.

The app's authoritative source artwork stays in `../App icons/`; native source and release packaging stay outside this directory.

## Native window contour

`src/window-frame.js` uses the three cubic segments exported by SwiftUI's continuous `RoundedRectangle` on macOS 27. The outer radius is 16 CSS pixels; its transition extends approximately 24.46 pixels along each edge. `tools/export-native-corners.swift` preserves the native extraction source. Run it on macOS with `swift -module-cache-path /tmp/lightmark-swift-module-cache tools/export-native-corners.swift` to inspect the coordinates. The stroke uses concentric inset contours and the shadow follows the clipped silhouette. This reproduces SwiftUI's shape geometry, not a measured WindowServer window mask; browser antialiasing can differ.

## Sharing and touch controls

Open Graph and large-image Twitter cards use `assets/social-preview.png` and the `https://trylightmark.com/` canonical URL. Change the domain with `SITE_URL=https://your-domain.example npm run build` before deployment. The metadata is server-readable static HTML. Generate the social artwork on macOS using `swift -module-cache-path /tmp/lightmark-swift-module-cache tools/render-social.swift`.

Touch devices have persistent draggable scroll indicators and visible copy/sort controls. Copy uses the Clipboard API on HTTPS, a user-initiated legacy fallback on local HTTP, and a selectable-text dialog if copying is blocked. Live mobile verification and social crawler verification after deployment remain necessary.

## Information pages and domain

`contact/index.html` and `privacy/index.html` are standalone pages styled by `pages.css`. Contact uses `team@trylightmark.com` and Flaskshade’s X profile. Privacy identifies Cloudflare hosting and its request processing; the website uses basic Cloudflare Web Analytics.

The registered domain `trylightmark.com` is live on Cloudflare Pages. The repository’s `main` branch deploys automatically using root `website` and output `site-output/`, an allowlisted folder built by `npm run build`. Never publish source files or `node_modules`. See [DEPLOYMENT.md](DEPLOYMENT.md) for domain/email configuration and [../docs/releases.md](../docs/releases.md) for app releases. `RELEASE_DOWNLOAD_URL` can override the download link in generated output without changing source HTML.

`changelog/index.html` owns the brief public release history, newest first. Keep entries focused on user-visible changes when publishing an app release. The page is included in the deployment allowlist.

## Basic website analytics

Cloudflare Web Analytics is manually loaded by `src/web-analytics.js` on the production domain only. Keep Cloudflare in **Enable with JS Snippet installation** mode; automatic injection bypasses local exclusions and duplicates the beacon. The public site token is not a secret. No application telemetry or custom download-click counter is enabled.

To exclude a browser from metrics, visit `https://trylightmark.com/?analytics=off` in that browser. This saves only a local exclusion preference and prevents the analytics script from loading. It lasts until site storage is cleared; private sessions need their own exclusion. `?analytics=on` restores counting. Localhost and preview deployments never load the beacon. The privacy policy describes the enabled metrics.
