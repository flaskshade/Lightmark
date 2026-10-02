import AppKit
import SwiftUI

/// The single owner of contents, undo, saved state and AppKit's close/quit review.
@objc(LightmarkDocument)
final class NativeMarkdownDocument: NSDocument, ObservableObject {
    @Published private(set) var content = MarkdownDocument()
    private var savedText = ""

    override nonisolated class var autosavesInPlace: Bool { false }
    override var isDocumentEdited: Bool { content.text != savedText }
    override var fileURL: URL? {
        didSet { objectWillChange.send() }
    }

    func replaceText(_ text: String, actionName: String = "Edit") {
        guard text != content.text else { return }
        let previous = content.text
        undoManager?.registerUndo(withTarget: self) { document in
            document.replaceText(previous, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        content.text = text
        // Dirty state is already synchronous; AppKit observes undo groups and
        // maintains its change count. Do not increment that count twice.
        for controller in windowControllers { controller.window?.isDocumentEdited = isDocumentEdited }
        if let window = windowControllers.first?.window { DocumentTabs.owner(of: window).refresh() }
    }

    private struct SaveCheckpoint {
        let nativeToken: Any
        let text: String
    }

    override func changeCountToken(for saveOperation: NSDocument.SaveOperationType) -> Any {
        SaveCheckpoint(nativeToken: super.changeCountToken(for: saveOperation), text: content.text)
    }

    override func updateChangeCount(withToken token: Any, for saveOperation: NSDocument.SaveOperationType) {
        guard let checkpoint = token as? SaveCheckpoint else {
            super.updateChangeCount(withToken: token, for: saveOperation)
            return
        }
        // AppKit invokes this only after a successful save. Export/backup writes
        // must not mark the actual document saved; failed writes never get here.
        if saveOperation == .saveOperation || saveOperation == .saveAsOperation {
            savedText = checkpoint.text
        }
        super.updateChangeCount(withToken: checkpoint.nativeToken, for: saveOperation)
        for controller in windowControllers { controller.window?.isDocumentEdited = isDocumentEdited }
        objectWillChange.send()
        if let window = windowControllers.first?.window { DocumentTabs.owner(of: window).refresh() }
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        for controller in windowControllers { controller.window?.isDocumentEdited = isDocumentEdited }
        objectWillChange.send()
        if let window = windowControllers.first?.window { DocumentTabs.owner(of: window).refresh() }
    }

    override nonisolated class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        // Concurrent reading is disabled: AppKit calls this on the main thread.
        MainActor.assumeIsolated {
            content.text = text
            savedText = text
            undoManager?.removeAllActions()
        }
    }

    override func data(ofType typeName: String) throws -> Data { Data(content.text.utf8) }

    override var windowForSheet: NSWindow? {
        guard let window = windowControllers.first?.window else { return super.windowForSheet }
        return window.isVisible ? window : DocumentTabs.owner(of: window).presentationWindow ?? window
    }

    override func makeWindowControllers() {
        guard windowControllers.isEmpty else { return }
        let window = MarkdownWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 640, height: 400)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.tabbingIdentifier = "LightmarkDocument"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.center()
        if let previous = NSApp.orderedWindows.first(where: {
            $0 is MarkdownWindow && $0.isVisible && !$0.isMiniaturized && $0.isOnActiveSpace
        }) {
            window.cascadeTopLeft(from: NSPoint(x: previous.frame.minX, y: previous.frame.maxY))
        }
        let controller = MarkdownWindowController(window: window)
        controller.shouldCascadeWindows = false
        addWindowController(controller)
        window.delegate = controller
        window.contentView = NSHostingView(rootView: NativeDocumentContent(document: self))
    }
}

private struct NativeDocumentContent: View {
    @ObservedObject var document: NativeMarkdownDocument
    var body: some View {
        DocumentView(document: Binding(get: { document.content }, set: { document.replaceText($0.text) }),
                     fileURL: document.fileURL)
    }
}

private final class MarkdownWindowController: NSWindowController, NSWindowDelegate {
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        (document as? NSDocument)?.undoManager
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let document = document as? NSDocument else { return true }
        DocumentCloseCoordinator.shared.close(document)
        return false
    }
}

/// Tab buttons and window controls use the same native approval as app quit.
@MainActor final class DocumentCloseCoordinator: NSObject {
    static let shared = DocumentCloseCoordinator()
    private var pending = Set<ObjectIdentifier>()
    var hasPendingReview: Bool { !pending.isEmpty }

    func close(_ document: NSDocument) {
        guard document.windowForSheet?.attachedSheet == nil,
              pending.insert(ObjectIdentifier(document)).inserted else { return }
        document.canClose(withDelegate: self, shouldClose: #selector(didReview(_:shouldClose:contextInfo:)), contextInfo: nil)
    }

    @objc private func didReview(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        pending.remove(ObjectIdentifier(document))
        if shouldClose { document.close() }
    }
}

@MainActor final class LightmarkDocumentController: NSDocumentController {
    override func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let group = DocumentTabs.current
        let window = NSApp.keyWindow
        panel.begin { response in
            guard response == .OK else { return }
            for (index, url) in panel.urls.enumerated() {
                if index == 0, let window, group.openFileInEmptyTab(url, window: window) { continue }
                group.openDocument(withContentsOf: url) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
            }
        }
    }
}

/// Native document windows do not depend on a SwiftUI scene being focused for
/// the standard Close shortcut. Sheets retain their own native key handling.
private final class MarkdownWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w", attachedSheet == nil {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
