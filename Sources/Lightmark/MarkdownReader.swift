import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// A single CommonMark/GFM reading surface. Document text is passed as data,
/// never interpolated into JavaScript or HTML. WebKit owns selection and layout.
struct MarkdownReader: NSViewRepresentable {
    let source: String
    let readingFontSize: CGFloat
    let readingFont: ReadingFont
    let headingFont: ReadingFont
    let readingWidth: CGFloat
    var fileURL: URL?
    var documentWindow: NSWindow?
    var isActive = true
    var findController: FindController? = nil
    var onSourceChange: ((String, String) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(context.coordinator.resources, forURLScheme: "lightmark-reader")
        configuration.setURLSchemeHandler(context.coordinator.resources, forURLScheme: "lightmark-image")
        configuration.userContentController.add(context.coordinator, name: "openLink")
        configuration.userContentController.add(context.coordinator, name: "toggleTask")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        context.coordinator.webView = view
        findController?.attach(view)
        updateNSView(view, context: context)
        view.load(URLRequest(url: URL(string: "lightmark-reader://bundle/index.html")!))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isActive = isActive
        coordinator.onSourceChange = onSourceChange
        if coordinator.payload["source"] as? String != source { coordinator.sourceVersion += 1 }
        coordinator.fileURL = fileURL
        coordinator.documentWindow = documentWindow
        coordinator.resources.documentURL = fileURL
        coordinator.payload = [
            "source": source, "version": coordinator.sourceVersion, "editable": onSourceChange != nil, "identity": fileURL?.absoluteString ?? "untitled",
            "fontSize": readingFontSize, "width": readingWidth,
            "bodyFont": readingFont.rawValue, "headingFont": headingFont.rawValue,
            "dark": colorScheme == .dark
        ]
        findController?.attach(view)
        coordinator.render()
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        coordinator.resources.cancelAll()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "openLink")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "toggleTask")
        view.navigationDelegate = nil
        coordinator.webView = nil
    }


    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let resources = ReaderResources()
        weak var webView: WKWebView?
        weak var documentWindow: NSWindow?
        var fileURL: URL?
        var payload: [String: Any] = [:]
        var ready = false
        var isActive = true
        var sourceVersion = 0
        var onSourceChange: ((String, String) -> Void)?

        private func applySource(_ replacement: String, replacing original: String) {
            guard payload["source"] as? String == original else { return }
            onSourceChange?(original, replacement)
            payload["source"] = replacement
            sourceVersion += 1
            payload["version"] = sourceVersion
            render()
        }

        private var lastSubmittedPayload: NSDictionary?
        private var sending = false
        private var revision = 0

        func render() {
            revision += 1
            guard ready, isActive, !sending, let webView else { return }
            guard lastSubmittedPayload?.isEqual(to: payload) != true else { return }
            sending = true
            let submitted = revision
            let submittedPayload = payload
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                do {
                    _ = try await webView.callAsyncJavaScript("window.lightmarkRender(payload)", arguments: ["payload": submittedPayload], in: nil, contentWorld: .page)
                    self.lastSubmittedPayload = submittedPayload as NSDictionary
                } catch {
                    _ = try? await webView.callAsyncJavaScript("document.getElementById('reader').textContent = source", arguments: ["source": self.payload["source"] ?? ""], in: nil, contentWorld: .page)
                    NSLog("Lightmark reader error: %@", error.localizedDescription)
                }
                self.sending = false
                if self.revision != submitted { self.render() }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            lastSubmittedPayload = nil
            render()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ready = false
            sending = false
            webView.reload()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            return url.scheme == "lightmark-reader" && url.host == "bundle" && url.path == "/index.html" ? .allow : .cancel
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == "lightmark-reader" else { return }
            if message.name == "toggleTask" {
                guard let body = message.body as? [String: Any],
                      let version = body["version"] as? Int, version == sourceVersion,
                      let offset = body["offset"] as? Int, let checked = body["checked"] as? Bool,
                      let source = payload["source"] as? String, onSourceChange != nil else { return }
                let text = source as NSString
                guard offset > 0, offset + 1 < text.length,
                      text.substring(with: NSRange(location: offset - 1, length: 1)) == "[",
                      text.substring(with: NSRange(location: offset + 1, length: 1)) == "]",
                      [" ", "x", "X"].contains(text.substring(with: NSRange(location: offset, length: 1))) else { return }
                let replacement = text.replacingCharacters(in: NSRange(location: offset, length: 1), with: checked ? "x" : " ")
                applySource(replacement, replacing: source)
                return
            }
            guard let href = message.body as? String else { return }
            if let url = URL(string: href), let scheme = url.scheme, !scheme.isEmpty, scheme != "file" {
                if ["https", "http", "mailto", "tel"].contains(scheme.lowercased()) { NSWorkspace.shared.open(url) }
                return
            }
            guard let url = URL(string: href, relativeTo: fileURL)?.absoluteURL, url.isFileURL else { return }
            var target = url.standardizedFileURL
            if !FileManager.default.fileExists(atPath: target.path), target.pathExtension.isEmpty {
                let markdown = target.appendingPathExtension("md")
                if FileManager.default.fileExists(atPath: markdown.path) { target = markdown }
            }
            if ["md", "markdown", "mdown", "mkd", "mkdn", "txt", "text"].contains(target.pathExtension.lowercased()) {
                DocumentTabs.current.openDocument(withContentsOf: target, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
            } else {
                NSWorkspace.shared.open(target)
            }
        }
    }
}

/// Bundled assets and local images use separate schemes. Documents cannot read
/// arbitrary files: local images are constrained to the document's folder tree.
@MainActor final class ReaderResources: NSObject, WKURLSchemeHandler {
    var documentURL: URL?
    private lazy var root: URL = {
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("Reader"),
           FileManager.default.fileExists(atPath: resource.appendingPathComponent("index.html").path) { return resource }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Reader")
    }()

    private var requests: [ObjectIdentifier: Task<Void, Never>] = [:]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else { return }
        let id = ObjectIdentifier(urlSchemeTask)
        let assetRoot = root
        let document = documentURL
        requests[id] = Task { @MainActor [weak self] in
            do {
                let (data, mime) = try await Task.detached(priority: .userInitiated) {
                    try Self.readResource(requestURL, root: assetRoot, documentURL: document)
                }.value
                guard !Task.isCancelled else { return }
                urlSchemeTask.didReceive(URLResponse(url: requestURL, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                if !Task.isCancelled { urlSchemeTask.didFailWithError(error) }
            }
            self?.requests.removeValue(forKey: id)
        }
    }

    func cancelAll() {
        for request in requests.values { request.cancel() }
        requests.removeAll()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        requests.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }

    private nonisolated static func readResource(_ requestURL: URL, root: URL, documentURL: URL?) throws -> (Data, String) {
        let file: URL
        let mime: String
        if requestURL.scheme == "lightmark-reader" {
            let base = root.resolvingSymlinksInPath()
            file = base.appendingPathComponent(requestURL.path).standardizedFileURL.resolvingSymlinksInPath()
            guard file.path.hasPrefix(base.path + "/") else { throw CocoaError(.fileReadNoPermission) }
            switch file.pathExtension {
            case "js": mime = "application/javascript"
            case "css": mime = "text/css"
            case "html": mime = "text/html"
            case "woff2": mime = "font/woff2"
            case "woff": mime = "font/woff"
            case "ttf": mime = "font/ttf"
            default: throw CocoaError(.fileReadNoPermission)
            }
        } else {
            guard let documentURL,
                  let path = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "path" })?.value,
                  let resolved = URL(string: path, relativeTo: documentURL)?.absoluteURL, resolved.isFileURL else { throw CocoaError(.fileReadNoPermission) }
            file = resolved.standardizedFileURL.resolvingSymlinksInPath()
            let directory = documentURL.deletingLastPathComponent().resolvingSymlinksInPath()
            guard file.path.hasPrefix(directory.path + "/"),
                  let type = UTType(filenameExtension: file.pathExtension), type.conforms(to: .image),
                  let contentType = type.preferredMIMEType else { throw CocoaError(.fileReadNoPermission) }
            mime = contentType
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 25_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        return (data, mime)
    }
}
