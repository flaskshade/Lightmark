import Foundation
import WebKit
import UniformTypeIdentifiers

/// Bundled assets and local images use separate schemes. Documents cannot read
/// arbitrary files: local images are constrained to the document's folder tree.
@MainActor final class ReaderResources: NSObject, WKURLSchemeHandler {
    var documentURL: URL?
    private let resourceBundle: Bundle
    private let offline: Bool

    init(bundle: Bundle = .main, offline: Bool = false) {
        self.resourceBundle = bundle
        self.offline = offline
        super.init()
    }

    private lazy var root: URL = {
        if let resource = resourceBundle.resourceURL?.appendingPathComponent("Reader"),
           FileManager.default.fileExists(atPath: resource.appendingPathComponent("index.html").path) { return resource }
        #if DEBUG
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Reader")
        #else
        return resourceBundle.bundleURL.appendingPathComponent("Contents/Resources/Reader")
        #endif
    }()

    private var requests: [ObjectIdentifier: Task<Void, Never>] = [:]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else { return }
        let id = ObjectIdentifier(urlSchemeTask)
        let assetRoot = root
        let document = documentURL
        let offline = offline
        requests[id] = Task { @MainActor [weak self] in
            do {
                let (data, mime) = try await Task.detached(priority: .userInitiated) {
                    try Self.readResource(requestURL, root: assetRoot, documentURL: document, offline: offline)
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

    private nonisolated static func readResource(_ requestURL: URL, root: URL, documentURL: URL?, offline: Bool) throws -> (Data, String) {
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
        var data = try Data(contentsOf: file, options: .mappedIfSafe)
        if offline && file.lastPathComponent == "index.html" && requestURL.scheme == "lightmark-reader" {
            let html = String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: "img-src lightmark-image: https: http: data:", with: "img-src lightmark-image: data:")
            data = Data(html.utf8)
        }
        return (data, mime)
    }
}
