import SwiftUI
import UniformTypeIdentifiers

@main
struct LightmarkApp: App {
    @Environment(\.newDocument) private var newDocument
    @AppStorage("windowOpeningMode") private var windowOpeningMode = WindowOpeningMode.separateWindows.rawValue

    private var usesTabs: Bool { WindowOpeningMode.from(stored: windowOpeningMode) == .tabbed }

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1040, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    newDocument(contentType: MarkdownDocument.markdownType)
                }
                .keyboardShortcut("n")

                if usesTabs {
                    Button("New Tab") {
                        DocumentTabs.shared.newTab()
                    }
                    .keyboardShortcut("t")
                }
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
                Button("Next Tab") { DocumentTabs.shared.selectRelative(1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { DocumentTabs.shared.selectRelative(-1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                }
            }
        }

        Settings {
            PreferencesView()
        }

        #if DEBUG
        WindowGroup(for: String.self) { _ in
            DesignPreview()
        }
        .defaultSize(width: 860, height: 620)
        .commands {
            DesignPreviewCommands()
        }
        #endif
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasOpenedFile = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        CustomFonts.registerOnce()
        AppTheme.apply(stored: UserDefaults.standard.string(forKey: "appTheme") ?? "system")
        UserDefaults.standard.register(defaults: [
            "NSQuitAlwaysKeepsWindows": false
        ])

        for arg in CommandLine.arguments.dropFirst() {
            if !arg.hasPrefix("-") && FileManager.default.fileExists(atPath: arg) {
                hasOpenedFile = true
                let url = URL(fileURLWithPath: arg)
                DocumentTabs.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        hasOpenedFile = true
        for url in urls {
            DocumentTabs.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        hasOpenedFile = true
        let url = URL(fileURLWithPath: filename)
        DocumentTabs.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        hasOpenedFile = true
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            DocumentTabs.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return !hasOpenedFile
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if WindowOpeningMode.from(stored: UserDefaults.standard.string(forKey: "windowOpeningMode") ?? "windows") == .tabbed {
                DocumentTabs.shared.newTab()
            } else {
                NSDocumentController.shared.newDocument(nil)
            }
            return false
        }
        return true
    }
}

extension Notification.Name {
    static let markdownDocumentDidSave = Notification.Name("markdownDocumentDidSave")
    static let copyAllDocumentText = Notification.Name("copyAllDocumentText")
    static let toggleEditMode = Notification.Name("toggleEditMode")
}

struct MarkdownDocument: FileDocument {
    static let markdownType = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    static var readableContentTypes: [UTType] { [markdownType, .plainText] }
    static var writableContentTypes: [UTType] { [markdownType, .plainText] }

    var text = ""

    init() {}

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let decoded = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        text = decoded
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .markdownDocumentDidSave, object: nil)
        }
        return FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
