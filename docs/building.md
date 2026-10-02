# Building Lightmark

Use macOS with Xcode and Swift 6 installed.

```sh
scripts/build-app.sh debug
open dist/Lightmark.app
```

The development bundle is ad-hoc signed and its updater is disabled. No release credentials are needed. The app targets macOS 14 or later.

## Markdown renderer

Bundled reader assets are included. After editing source under `Renderer/`, regenerate them:

```sh
cd Renderer
npm ci --ignore-scripts
npm run build
```

Commit the regenerated files under `Resources/Reader/` alongside renderer changes. See [Markdown rendering](markdown-rendering.md) for ownership and syntax support.
