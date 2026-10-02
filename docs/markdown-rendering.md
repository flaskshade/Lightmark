# Markdown reading surface

## Ownership

- `Sources/Lightmark/MarkdownReader.swift`: native WebKit lifecycle, preferences, document links, bundled assets, scoped local image access.
- `Renderer/reader.js`: CommonMark/GFM parsing, extensions, sanitization, headings/footnotes, tables, image fallback, incremental page updates.
- `Renderer/diagram-loader.js` and `diagrams.js`: viewport-triggered, serialized Mermaid rendering in a separate offline bundle.
- `Renderer/reader.css`: reading primitives and both themes. The editor, empty state, document windows, and custom tabs remain native SwiftUI/AppKit.
- `Renderer/package.json` and `package-lock.json`: exact direct versions and reproducible dependency graph.
- `Resources/Reader`: generated, bundled runtime assets plus third-party notices. There are no runtime CDN dependencies. JavaScript rendering occurs in WebKit's content process.
- `Examples/MarkdownStressTest.md`: the reference fixture, also exposed in the debug Design Preview through the production reader.
- `LightmarkCore/MarkdownParser.swift` and its existing tests are legacy code, no longer linked into the app or used to judge production rendering coverage.

## Syntax contract

CommonMark nesting is owned by markdown-it, not regular expressions or a second native parser. The default GFM-style extensions include tables and strikethrough. Dedicated extensions provide task lists, footnotes, dollar-delimited math, definition lists, `==highlight==`, `H~2~O` subscripts and `x^2^` superscripts. Fenced `mermaid` blocks support flowcharts, sequence diagrams and the bundled Mermaid diagram families. Invalid or oversized diagrams remain fenced source. KaTeX typesets math; highlight.js highlights recognized fenced languages. Unknown languages remain plain code.

Supported examples include ATX/setext headings, emphasis nesting, multi-backtick code spans, arbitrary supported list/quote nesting, continuous ordered numbering, indented/fenced code, reference links and titles, linked images, aligned pipe tables, thematic breaks, multi-paragraph footnotes with backlinks, inline/block math, and sanitized HTML including details/summary. HTML comments are removed. Markdown inside raw HTML follows CommonMark (it is not recursively reparsed). Unchecked `[ ]` and checked `[x]` tasks toggle from the reader. Parser line maps identify the original marker, preserving surrounding Markdown and line endings. The native bridge validates the source revision and UTF-16 marker offset before replacing one character through the native document binding, with one shared undo manager and saved-text baseline. Preview-only showcases remain read-only.

Heading anchors are generated from Unicode-aware slugs with duplicate suffixes. Links within the page stay in the page; footnote references briefly highlight the destination. Local Markdown links use `DocumentTabs.openDocument`; external links use the native workspace. Unknown URL schemes cannot navigate the reader.

## Security and resources

The source is passed through structured JavaScript arguments, never string-interpolated into code. DOMPurify sanitizes all document-generated HTML. Only a small set of inline presentation styles is retained. Scripts, frames, forms, external stylesheets and other active HTML are removed. A restrictive Content Security Policy provides another boundary. KaTeX runs with `trust: false`, expansion and size limits, and renders after document HTML sanitization so its generated layout styles remain intact.

Libraries/fonts ship locally. The diagram engine is a separate bundle loaded only near a visible diagram; strict configuration, character/edge limits, serialized rendering and SVG image isolation apply. Bundled assets and local images are read off the main thread with cancellation-aware delivery. Only images explicitly referenced by a document can fetch HTTP(S) resources; images have no referrer and the WebKit store is nonpersistent. Missing/unreachable images display their alt text. The stress fixture uses a remote placeholder service; availability is outside the renderer's control.

Local images use a separate URL scheme, are limited to image types within the current document's folder tree after symlink resolution, and have a 25 MB byte limit. Images outside that tree show fallback text. SVG scripts cannot execute in an image context. Local resource access never grants WebKit unrestricted file-system access.

## Performance and interaction

The reader stays mounted during source editing, with rendering paused until preview resumes. Unchanged payloads do not cross the native/WebKit bridge. Table observers disconnect before content replacement. One page per reader instance; preference changes update CSS without replacing document content or selection. Identical source/identity is not parsed again. Native updates coalesce and the page keeps only the latest pending render. New source replaces the document once; same-file updates retain scroll offset. Images decode asynchronously/lazily. Tables, code blocks, and display math contain their own horizontal overflow. Highlighting is skipped for fences above 100,000 characters. Reader side gutters live outside the text column. The reader uses `position: relative` to establish a WebKit selection root, bounding native gap painting to that column. Preserve continuous native selection across paragraphs; do not wrap text nodes or disable selection on ancestor blocks, which creates striped highlights without fixing the selection root. The native WebKit selection range and copy semantics remain unchanged. WebKit handles normal text selection, links, accessibility and scrolling; do not reintroduce native text cursor tracking over this view.

No generalized virtualization is used: document-wide selection/copy and nested layout must remain coherent. Huge-document performance and VoiceOver need separate measurement; build success is not performance evidence.

## Build and maintenance

For renderer changes:

```sh
cd Renderer
npm ci --ignore-scripts
npm run build
cd ..
scripts/build-app.sh debug
```

Commit/package the generated `Resources/Reader` output with the source and lockfile. Ordinary Swift app builds copy those assets and do not require npm or network access. `build.mjs` includes dependency licenses; retain them with redistribution. Review sanitizer and dependency changes deliberately. The app build targets macOS 14+ and uses the installed SDK.

## Verification status

The JavaScript bundle and Swift development app compile. npm's installation audit reported no vulnerabilities in the resolved graph. Runtime verification remains separate from compilation. The fixture is included for direct review; visual fidelity, accessibility and large-document timings are not yet verified.

For the MVP performance review and remaining distribution gates, see [release-audit.md](release-audit.md).
