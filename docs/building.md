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

## Finder Quick Look

The app build embeds `LightmarkQuickLook.appex`; no additional dependencies or Xcode project are required. `scripts/build-quicklook.sh` compiles the extension against the installed macOS SDK and signs it before the host app. Its version and minimum OS come from the host Info.plist.

For local development, register the built extension (macOS signing policy may restrict ad-hoc extension activation):

```sh
pluginkit -a "$PWD/dist/Lightmark.app/Contents/PlugIns/LightmarkQuickLook.appex"
```

Finder discovers the production extension within the installed app. Enable Lightmark under System Settings → General → Login Items & Extensions → Quick Look if macOS leaves it disabled. Other Markdown preview extensions can affect which provider Finder selects.
