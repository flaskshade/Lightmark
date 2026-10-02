import SwiftUI
import UniformTypeIdentifiers

@main
struct LightmarkApp: App {
    @AppStorage("windowOpeningMode") private var windowOpeningMode = WindowOpeningMode.separateWindows.rawValue

    private var usesTabs: Bool { WindowOpeningMode.from(stored: windowOpeningMode) == .tabbed }

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { PreferencesView() }
        .commands {
            #if DEBUG
            DesignPreviewCommands()
            #endif
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    DocumentTabs.newWindow()
                }
                .keyboardShortcut("n")

                if usesTabs {
                    Button("New Tab") {
                        DocumentTabs.current.newTab()
                    }
                    .keyboardShortcut("t")
                }
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") { NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil) }
                    .keyboardShortcut("s")
                Button("Save As…") { NSApp.sendAction(#selector(NSDocument.saveAs(_:)), to: nil, from: nil) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                Button("Open…") { NSDocumentController.shared.openDocument(nil) }.keyboardShortcut("o")
                Button("Close") { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut("w")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { NSApp.keyWindow?.undoManager?.undo() }.keyboardShortcut("z")
                Button("Redo") { NSApp.keyWindow?.undoManager?.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Button("Toggle Edit Mode") {
                    NotificationCenter.default.post(name: .toggleEditMode, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])

                Button("Copy All Text") {
                    NotificationCenter.default.post(name: .copyAllDocumentText, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }

            if usesTabs {
                CommandMenu("Tabs") {
                    Button("Next Tab") { DocumentTabs.current.selectRelative(1) }
                        .keyboardShortcut("]", modifiers: [.command, .shift])
                    Button("Previous Tab") { DocumentTabs.current.selectRelative(-1) }
                        .keyboardShortcut("[", modifiers: [.command, .shift])
                    Divider()
                    Button("Close Tab") { DocumentTabs.current.closeActiveTab() }
                }
            }
        }


    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let documentController = LightmarkDocumentController()
    private var hasOpenedFile = false
    private var reviewingQuit = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !reviewingQuit else { return .terminateLater }
        guard !DocumentCloseCoordinator.shared.hasPendingReview,
              !NSApp.windows.contains(where: { $0.attachedSheet != nil }) else { return .terminateCancel }
        reviewingQuit = true
        DispatchQueue.main.async {
            NSDocumentController.shared.closeAllDocuments(withDelegate: self,
                didCloseAllSelector: #selector(self.didReviewQuit(_:didCloseAll:contextInfo:)), contextInfo: nil)
        }
        return .terminateLater
    }

    @objc private func didReviewQuit(_ controller: NSDocumentController, didCloseAll: Bool, contextInfo: UnsafeMutableRawPointer?) {
        reviewingQuit = false
        NSApp.reply(toApplicationShouldTerminate: didCloseAll)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FirstLaunch.shared.start()
        DispatchQueue.main.async {
            if !self.hasOpenedFile && NSDocumentController.shared.documents.isEmpty { DocumentTabs.newWindow() }
            FirstLaunch.shared.presentIfNeeded()
        }
        CustomFonts.registerOnce()
        AppTheme.apply(stored: UserDefaults.standard.string(forKey: "appTheme") ?? "system")
        UserDefaults.standard.register(defaults: [
            "NSQuitAlwaysKeepsWindows": false
        ])

        for arg in CommandLine.arguments.dropFirst() {
            if !arg.hasPrefix("-") && FileManager.default.fileExists(atPath: arg) {
                hasOpenedFile = true
                let url = URL(fileURLWithPath: arg)
                DocumentTabs.current.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        hasOpenedFile = true
        for url in urls {
            DocumentTabs.current.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        hasOpenedFile = true
        let url = URL(fileURLWithPath: filename)
        DocumentTabs.current.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        hasOpenedFile = true
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            DocumentTabs.current.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
        }
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if !hasOpenedFile && NSDocumentController.shared.documents.isEmpty { DocumentTabs.newWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !reviewingQuit
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        DispatchQueue.main.async {
            if !self.hasOpenedFile && NSDocumentController.shared.documents.isEmpty { DocumentTabs.newWindow() }
        }
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if WindowOpeningMode.from(stored: UserDefaults.standard.string(forKey: "windowOpeningMode") ?? "windows") == .tabbed {
                DocumentTabs.current.newTab()
            } else {
                DocumentTabs.newWindow()
            }
            return false
        }
        return true
    }
}

extension Notification.Name {
    static let documentTabGroupsDidChange = Notification.Name("documentTabGroupsDidChange")
    static let copyAllDocumentText = Notification.Name("copyAllDocumentText")
    static let toggleEditMode = Notification.Name("toggleEditMode")
}

struct MarkdownDocument {
    var text = ""
}
