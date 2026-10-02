import AppKit
import QuickLookUI
import WebKit
import OSLog

@objc(LightmarkPreviewController)
@MainActor final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController, WKNavigationDelegate {
    private lazy var resources = ReaderResources(bundle: Bundle(for: PreviewViewController.self), offline: true)
    private var webView: WKWebView!
    private var readTask: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var completion: ((Error?) -> Void)?
    private var payload: [String: Any]?
    private var ready = false
    private var rendering = false
    private var generation = 0
    #if DEBUG
    private var preparationStarted = Date()
    #endif

    override func loadView() {
        let container = PreviewContainer(frame: NSRect(x: 0, y: 0, width: 780, height: 620))
        container.appearanceChanged = { [weak self] in self?.updateAppearance() }
        view = container
        preferredContentSize = container.frame.size
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(resources, forURLScheme: "lightmark-reader")
        configuration.setURLSchemeHandler(resources, forURLScheme: "lightmark-image")
        webView = WKWebView(frame: container.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.underPageBackgroundColor = .windowBackgroundColor
        container.addSubview(webView)
        webView.load(URLRequest(url: URL(string: "lightmark-reader://bundle/index.html")!))
    }

    func preparePreviewOfFile(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        finish(CocoaError(.userCancelled))
        readTask?.cancel()
        generation += 1
        let request = generation
        completion = completionHandler
        #if DEBUG
        preparationStarted = Date()
        #endif
        payload = nil
        rendering = false
        _ = view
        resources.documentURL = url
        // Load bounded source while WebKit starts, without retaining a file descriptor.
        let work = Task.detached(priority: .userInitiated) { () throws -> (String, Bool) in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let limit = 2 * 1024 * 1024
            let data = try handle.read(upToCount: limit + 1) ?? Data()
            try Task.checkCancellation()
            let shortened = data.count > limit
            let bytes = data.prefix(limit)
            let sourceBytes = Data(bytes)
            var source: String
            if sourceBytes.starts(with: [0xff, 0xfe]) || sourceBytes.starts(with: [0xfe, 0xff]) {
                source = String(data: sourceBytes, encoding: .utf16) ?? String(decoding: sourceBytes, as: UTF8.self)
            } else {
                source = String(decoding: sourceBytes, as: UTF8.self)
                if source.hasPrefix("\u{feff}") { source.removeFirst() }
            }
            if shortened { source += "\n\n[Preview shortened for this large document]" }
            return (source, shortened || source.utf16.count > 500_000)
        }
        readTask = Task { @MainActor [weak self] in
            let result = await withTaskCancellationHandler {
                await work.result
            } onCancel: { work.cancel() }
            guard let self, !Task.isCancelled, self.generation == request else { return }
            switch result {
            case .success(let (source, plainText)):
                self.payload = ["source": source, "version": request, "identity": url.absoluteString,
                    "fontSize": 16, "width": 740, "bodyFont": "system", "headingFont": "system",
                    "editable": false, "preview": true, "plainText": plainText, "dark": self.isDark]
                self.render()
            case .failure(let error): self.finish(error)
            }
        }
        deadline = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.generation == request else { return }
            self.readTask?.cancel()
            self.webView.stopLoading()
            self.finish(CocoaError(.fileReadUnknown))
        }
    }

    private var isDark: Bool {
        view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func updateAppearance() {
        guard payload != nil else { return }
        payload?["dark"] = isDark
        render()
    }

    private func render() {
        guard ready, !rendering, let payload else { return }
        rendering = true
        let request = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.webView.callAsyncJavaScript("""
                    window.lightmarkRender(payload);
                    """, arguments: ["payload": payload], in: nil, contentWorld: .page)
                guard self.generation == request else { return }
                self.rendering = false
                self.finish(nil)
                if self.payload?["dark"] as? Bool != payload["dark"] as? Bool { self.render() }
            } catch {
                guard self.generation == request else { return }
                self.rendering = false
                self.finish(error)
            }
        }
    }

    private func finish(_ error: Error?) {
        deadline?.cancel()
        deadline = nil
        let handler = completion
        completion = nil
        #if DEBUG
        if handler != nil {
            let elapsed = Int(Date().timeIntervalSince(preparationStarted) * 1000)
            let logger = Logger(subsystem: "app.lightmark.reader.quicklook", category: "Preview")
            if let error = error as NSError? {
                logger.error("Preview failed: \(error.domain, privacy: .public) \(error.code) after \(elapsed) ms")
            } else {
                logger.notice("Preview prepared in \(elapsed) ms")
            }
        }
        #endif
        handler?(error)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        generation += 1
        payload = nil
        readTask?.cancel()
        resources.cancelAll()
        webView?.stopLoading()
        finish(CocoaError(.userCancelled))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        render()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(CocoaError(.fileReadUnknown)) }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let url = navigationAction.request.url
        return navigationAction.navigationType != .linkActivated && url?.scheme == "lightmark-reader"
            && url?.host == "bundle" ? .allow : .cancel
    }
}

@MainActor private final class PreviewContainer: NSView {
    var appearanceChanged: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?()
    }
}
