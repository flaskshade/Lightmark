import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Manages in-page find operations for both WebKit reading view and NSTextView editor.
@MainActor final class FindController: ObservableObject {
    @Published var isVisible = false
    @Published private(set) var focusRequest = 0
    @Published var query = ""
    @Published var matchCount = 0
    @Published var currentMatch = 0

    var isEditing = false {
        didSet {
            guard oldValue != isEditing else { return }
            if isVisible {
                clearHighlights()
                if !query.isEmpty {
                    search(query)
                }
            }
        }
    }

    private weak var webView: WKWebView?
    private weak var textView: NSTextView?
    private var textMatches: [NSRange] = []

    func attach(_ wv: WKWebView) {
        webView = wv
    }

    func attach(_ tv: NSTextView) {
        textView = tv
    }

    func detachWebView() {
        webView = nil
    }

    func detachTextView() {
        clearTextViewHighlights()
        textView = nil
    }

    func show() {
        if isEditing, let textView {
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0 && selectedRange.length < 200 {
                let selectedText = (textView.string as NSString).substring(with: selectedRange)
                if !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    query = selectedText
                }
            }
        }
        isVisible = true
        focusRequest += 1
        if !query.isEmpty {
            search(query)
        }
    }

    func close() {
        withAnimation(.easeOut(duration: 0.18)) { isVisible = false }
        clearHighlights()
        if isEditing, let textView {
            textView.window?.makeFirstResponder(textView)
        }
        // Delay clearing query/counts so the find bar does not visibly glitch or shrink during exit animation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self, !self.isVisible else { return }
            self.query = ""
            self.matchCount = 0
            self.currentMatch = 0
            self.clearHighlights()
        }
    }

    func search(_ text: String) {
        if text.isEmpty {
            clearHighlights()
            matchCount = 0
            currentMatch = 0
            textMatches = []
            return
        }

        if isEditing {
            searchInTextView(text)
        } else {
            searchInWebView(text)
        }
    }

    func refreshEditorMatches() {
        guard isEditing && isVisible && !query.isEmpty else { return }
        searchInTextView(query)
    }

    private func searchInTextView(_ text: String) {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        let nsString = textView.string as NSString
        let totalLength = nsString.length

        clearTextViewHighlights()

        guard totalLength > 0 else {
            matchCount = 0
            currentMatch = 0
            textMatches = []
            return
        }

        var matches: [NSRange] = []
        var searchRange = NSRange(location: 0, length: totalLength)
        while searchRange.location < totalLength {
            let found = nsString.range(of: text, options: .caseInsensitive, range: searchRange)
            if found.location != NSNotFound {
                matches.append(found)
                searchRange.location = found.location + max(found.length, 1)
                searchRange.length = totalLength - searchRange.location
            } else {
                break
            }
        }

        self.textMatches = matches
        self.matchCount = matches.count

        guard !matches.isEmpty else {
            self.currentMatch = 0
            return
        }

        let highlightColor = NSColor.findHighlightColor
        for range in matches {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: highlightColor, forCharacterRange: range)
        }

        let selected = textView.selectedRange()
        let matchIndex = matches.firstIndex { $0.location >= selected.location } ?? 0
        self.currentMatch = matchIndex + 1

        let targetRange = matches[matchIndex]
        textView.setSelectedRange(targetRange)
        textView.scrollRangeToVisible(targetRange)
    }

    private func searchInWebView(_ text: String) {
        guard let webView else { return }
        let config = WKFindConfiguration()
        config.caseSensitive = false
        config.wraps = true
        webView.find(text, configuration: config) { [weak self] result in
            guard let self else { return }
            if result.matchFound {
                self.currentMatch = 1
                self.countMatches(text)
            } else {
                self.matchCount = 0
                self.currentMatch = 0
            }
        }
    }

    func findNext() {
        if isEditing {
            guard let textView, !textMatches.isEmpty else { return }
            currentMatch = (currentMatch % textMatches.count) + 1
            let targetRange = textMatches[currentMatch - 1]
            textView.setSelectedRange(targetRange)
            textView.scrollRangeToVisible(targetRange)
            return
        }

        guard let webView, !query.isEmpty else { return }
        let config = WKFindConfiguration()
        config.caseSensitive = false
        config.wraps = true
        webView.find(query, configuration: config) { [weak self] result in
            guard let self, result.matchFound else { return }
            if self.matchCount > 0 {
                self.currentMatch = (self.currentMatch % self.matchCount) + 1
            }
        }
    }

    func findPrevious() {
        if isEditing {
            guard let textView, !textMatches.isEmpty else { return }
            currentMatch = currentMatch <= 1 ? textMatches.count : currentMatch - 1
            let targetRange = textMatches[currentMatch - 1]
            textView.setSelectedRange(targetRange)
            textView.scrollRangeToVisible(targetRange)
            return
        }

        guard let webView, !query.isEmpty else { return }
        let config = WKFindConfiguration()
        config.caseSensitive = false
        config.backwards = true
        config.wraps = true
        webView.find(query, configuration: config) { [weak self] result in
            guard let self, result.matchFound else { return }
            if self.matchCount > 0 {
                self.currentMatch = self.currentMatch <= 1 ? self.matchCount : self.currentMatch - 1
            }
        }
    }

    private func countMatches(_ text: String) {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = """
        (() => {
            const text = document.getElementById('reader')?.textContent ?? '';
            const query = '\(escaped)'.toLowerCase();
            if (!query) return 0;
            let count = 0, pos = 0;
            const lower = text.toLowerCase();
            while ((pos = lower.indexOf(query, pos)) !== -1) { count++; pos += query.length; }
            return count;
        })()
        """
        webView?.evaluateJavaScript(js) { [weak self] result, _ in
            if let count = result as? Int {
                self?.matchCount = count
                if count > 0 && (self?.currentMatch ?? 0) == 0 {
                    self?.currentMatch = 1
                }
            }
        }
    }

    private func clearHighlights() {
        // Clear DOM selection and active focus
        let js = """
        (() => {
            try {
                const sel = window.getSelection();
                if (sel) {
                    sel.removeAllRanges();
                    if (typeof sel.empty === 'function') sel.empty();
                }
                if (document.selection && typeof document.selection.empty === 'function') {
                    document.selection.empty();
                }
                if (document.activeElement && document.activeElement !== document.body) {
                    document.activeElement.blur();
                }
            } catch (e) {}
        })()
        """
        webView?.evaluateJavaScript(js) { _, _ in }

        // Execute a non-matching search to force WKWebView's native find layer to dismiss active match highlights
        let config = WKFindConfiguration()
        config.caseSensitive = false
        config.wraps = false
        webView?.find("__lightmark_find_clear_\(UUID().uuidString)__", configuration: config) { _ in }

        clearTextViewHighlights()
    }

    private func clearTextViewHighlights() {
        textMatches = []
        guard let textView, let layoutManager = textView.layoutManager else { return }
        let length = (textView.string as NSString).length
        if length > 0 {
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
        }
    }
}


private enum ReadingStyle {
    static let canvas = Color(nsColor: .textBackgroundColor)
    static let ink = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let accent = Color.accentColor
    static let code = Color(nsColor: .controlBackgroundColor)
}

struct DocumentView: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL? = nil
    @State private var tabs = DocumentTabs.current
    @State private var window: NSWindow?

    var body: some View {
        DocumentContentView(document: $document, fileURL: fileURL, tabs: tabs) { window in
            self.window = window
            tabs = DocumentTabs.owner(of: window)
        }
        .onReceive(NotificationCenter.default.publisher(for: .documentTabGroupsDidChange)) { _ in
            if let window { tabs = DocumentTabs.owner(of: window) }
        }
    }
}

private struct DocumentContentView: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL? = nil
    @ObservedObject private var appUpdates = AppUpdates.shared
    @State private var isEditing = false
    @State private var showFeedback = false
    @State private var feedbackTask: Task<Void, Never>? = nil
    @State private var showCopyFeedback = false
    @State private var copyFeedbackTask: Task<Void, Never>? = nil
    @ObservedObject var tabs: DocumentTabs
    var onWindowResolved: (NSWindow) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceHeaderMotion
    @Environment(\.colorScheme) private var scheme
    @State private var documentWindow: NSWindow?
    @FocusState private var isEditorFocused: Bool
    @StateObject private var findController = FindController()
    @FocusState private var isFindFocused: Bool
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("fontSize") private var fontSize = 16.0
    @AppStorage("readingWidth") private var readingWidth = 740.0
    @AppStorage("backgroundStyle") private var backgroundStyle = BackgroundStyle.translucent.rawValue
    @AppStorage("windowOpeningMode") private var windowOpeningMode = WindowOpeningMode.separateWindows.rawValue

    private var documentTitle: String {
        if let fileURL {
            return fileURL.lastPathComponent
        }
        return "New Tab"
    }

    private var isEdited: Bool {
        if let window = documentWindow,
           let nativeDocument = NSDocumentController.shared.document(for: window) {
            return nativeDocument.isDocumentEdited
        }
        return false
    }

    private var isDefaultNoFileView: Bool {
        fileURL == nil && document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentBackgroundStyle: BackgroundStyle {
        BackgroundStyle.from(stored: backgroundStyle)
    }

    private var currentWindowOpeningMode: WindowOpeningMode {
        WindowOpeningMode.from(stored: windowOpeningMode)
    }

    private var showsDocumentTabs: Bool {
        currentWindowOpeningMode == .tabbed && tabs.items.count > 1
    }

    private var hudTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.94, anchor: .bottom))
                .combined(with: .offset(y: 8)),
            removal: .opacity
                .combined(with: .scale(scale: 0.96, anchor: .bottom))
                .combined(with: .offset(y: 4))
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Keep the reader mounted while editing; parsing pauses until preview.
            ReadingView(
                source: document.text,
                fileURL: fileURL,
                documentWindow: documentWindow,
                onStartWriting: toggleEditing,
                isActive: !isEditing,
                findController: findController,
                onSourceChange: { expected, replacement in
                    guard document.text == expected else { return }
                    document.text = replacement
                }
            )
            .padding(.top, isDefaultNoFileView && !showsDocumentTabs ? 0 : 52)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isEditing ? 0 : 1)
            .allowsHitTesting(!isEditing)
            .accessibilityHidden(isEditing)
            .transaction { $0.animation = nil }

            if isEditing {
                DocumentTextEditor(text: $document.text, fontSize: fontSize,
                                   readingWidth: readingWidth, isFocused: isEditorFocused,
                                   findController: findController)
                    .padding(.top, 52)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Markdown source")
                    .transition(.identity)
                    .transaction { $0.animation = nil }
            }

            // Keep label visibility and reserved header space driven by one size.
            GeometryReader { header in
                let sidebarInset = isDefaultNoFileView && !isEditing && !showsDocumentTabs
                    ? NewTabLayout.recentsWidth(in: header.size.width) + 1 : 0
                let headerWidth = max(0, header.size.width - sidebarInset)
                let isEmptyHeader = isDefaultNoFileView && !isEditing && !showsDocumentTabs
                let requiredHeaderWidth: CGFloat = showsDocumentTabs
                    ? 400 + DocumentTabBar.minimumContentWidth(for: tabs.items.count)
                    : (isEmptyHeader ? 280 : 640)
                let showsUpdateLabel = headerWidth >= requiredHeaderWidth
                let updateInset: CGFloat = appUpdates.availableVersion == nil && !appUpdates.isChecking ? 0 : (showsUpdateLabel ? 154 : 36)
            ZStack {
                DocumentTabBar(tabs: tabs, fallbackTitle: documentTitle)
                    .padding(.trailing, 108 + updateInset)
                    .opacity(showsDocumentTabs ? 1 : 0)
                    .allowsHitTesting(showsDocumentTabs)
                    .accessibilityHidden(!showsDocumentTabs)

                DocumentTitleMenuButton(
                    title: documentTitle,
                    isEdited: isEdited,
                    fileURL: fileURL,
                    window: documentWindow
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 100 + updateInset)
                .opacity((showsDocumentTabs || (isDefaultNoFileView && !isEditing)) ? 0 : 1)
                .allowsHitTesting(!showsDocumentTabs && (!isDefaultNoFileView || isEditing))
                .accessibilityHidden(showsDocumentTabs || (isDefaultNoFileView && !isEditing))
            }
            .frame(height: 52)
            .animation(reduceHeaderMotion ? nil : .easeInOut(duration: 0.18), value: showsDocumentTabs)
            .transaction { if $0.disablesAnimations { $0.animation = nil } }
            .overlay(alignment: .trailing) {
                HStack(spacing: 4) {
                    HeaderUpdateButton(showsLabel: showsUpdateLabel)
                    if !isDefaultNoFileView || isEditing {
                        EditModeButton(
                            isEditing: isEditing,
                            returnsToNewTab: isDefaultNoFileView,
                            action: toggleEditing
                        )
                        .transition(.opacity)
                    }
                }
                .padding(.trailing, 14 + sidebarInset)
            }
            }
            .frame(height: 52)
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottom) {
            if showFeedback || appUpdates.showUpdateComplete || appUpdates.feedback != nil {
                ModeFeedbackHUD(isEditing: isEditing, updateComplete: appUpdates.showUpdateComplete, feedback: appUpdates.feedback)
                    .padding(.bottom, 12)
                    .transition(hudTransition)
                    .allowsHitTesting(false)
                    .zIndex(995)
            }
        }
        .animation(reduceHeaderMotion ? nil : .easeInOut(duration: 0.18), value: appUpdates.showUpdateComplete)
        .animation(reduceHeaderMotion ? nil : .easeInOut(duration: 0.18), value: appUpdates.feedback)
        .overlay(alignment: .bottom) {
            if showCopyFeedback {
                ActionFeedbackHUD(title: "Copied All Text", systemImage: "doc.on.doc.fill", shortcut: "⌘⇧C")
                    .padding(.bottom, 12)
                    .transition(hudTransition)
                    .allowsHitTesting(false)
                    .zIndex(1000)
            }
        }
        .overlay(alignment: .bottom) {
            if findController.isVisible {
                FindBar(controller: findController, isFocused: $isFindFocused)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 12)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 10)),
                        removal: .opacity.combined(with: .offset(y: 8))
                    ))
                    .zIndex(990)
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: findController.isVisible)
        .background(
            Button("") {
                copyAllToClipboard()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            Button("") {
                findController.show()
            }
            .keyboardShortcut("f", modifiers: [.command])
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            Button("") {
                if findController.isVisible {
                    findController.findNext()
                }
            }
            .keyboardShortcut("g", modifiers: [.command])
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            Button("") {
                if findController.isVisible {
                    findController.findPrevious()
                }
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(windowBackdrop)
        .background(
            TransparentTitlebar(
                openingMode: currentWindowOpeningMode,
                fileURL: fileURL,
                title: documentTitle,
                onWindowResolved: { window in
                    documentWindow = window
                    onWindowResolved(window)

                    DocumentTabs.owner(of: window).register(window, mode: currentWindowOpeningMode)
                }
            )
        )
        .onChange(of: fileURL) { _, newURL in
            if let newURL {
                RecentDocumentsStore.shared.register(url: newURL)
            }
        }
        .onChange(of: isEditing) { _, newValue in
            findController.isEditing = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .copyAllDocumentText)) { _ in
            guard documentWindow === NSApp.keyWindow else { return }
            copyAllToClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditMode)) { _ in
            guard documentWindow === NSApp.keyWindow else { return }
            toggleEditing()
        }
        .onChange(of: document.text) { _, _ in tabs.refresh() }
        .frame(minWidth: 640, minHeight: 400)
    }

    @ViewBuilder
    private var windowBackdrop: some View {
        switch currentBackgroundStyle {
        case .translucent:
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea()
        case .solid:
            Color(nsColor: .textBackgroundColor)
                .ignoresSafeArea()
        }
    }

    private func copyAllToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(document.text, forType: .string)

        feedbackTask?.cancel()
        showFeedback = false

        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            showCopyFeedback = true
        }

        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 950_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                showCopyFeedback = false
            }
        }
    }

    private func toggleEditing() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            isEditing.toggle()
        }
        if isEditing {
            isEditorFocused = true
            if !findController.isVisible {
                DispatchQueue.main.async {
                    let activeWindow = documentWindow ?? NSApp.keyWindow
                    if let textView = (activeWindow?.firstResponder as? NSTextView) ?? (NSApp.keyWindow?.firstResponder as? NSTextView) {
                        let startRange = NSRange(location: 0, length: 0)
                        textView.setSelectedRange(startRange)
                        textView.scrollRangeToVisible(startRange)
                    }
                }
            }
        }

        let isNewTabState = fileURL == nil && document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !isNewTabState {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                showFeedback = true
            }

            feedbackTask?.cancel()
            feedbackTask = Task {
                try? await Task.sleep(nanoseconds: 950_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    showFeedback = false
                }
            }
        }
    }
}

@MainActor
enum DocumentActionHelper {
    static func findDocument(for window: NSWindow?, fileURL: URL?) -> NSDocument? {
        if let window {
            if let doc = window.windowController?.document as? NSDocument {
                return doc
            }
            if let doc = NSDocumentController.shared.document(for: window) {
                return doc
            }
        }
        if let fileURL {
            if let doc = NSDocumentController.shared.document(for: fileURL) {
                return doc
            }
            if let doc = NSDocumentController.shared.documents.first(where: { $0.fileURL == fileURL }) {
                return doc
            }
        }
        if let keyWin = NSApp.keyWindow {
            if let doc = keyWin.windowController?.document as? NSDocument {
                return doc
            }
            if let doc = NSDocumentController.shared.document(for: keyWin) {
                return doc
            }
        }
        if let mainWin = NSApp.mainWindow {
            if let doc = mainWin.windowController?.document as? NSDocument {
                return doc
            }
            if let doc = NSDocumentController.shared.document(for: mainWin) {
                return doc
            }
        }
        return NSDocumentController.shared.currentDocument ?? NSDocumentController.shared.documents.first
    }

    static func triggerRenameOrSave(for window: NSWindow?, fileURL: URL?) {
        let targetWindow = window ?? NSApp.keyWindow ?? NSApp.mainWindow
        let doc = findDocument(for: targetWindow, fileURL: fileURL)
        let resolvedURL = fileURL ?? doc?.fileURL

        guard let currentURL = resolvedURL else {
            let saveSel = NSSelectorFromString("saveDocument:")
            if let doc, doc.responds(to: saveSel) {
                doc.perform(saveSel, with: targetWindow)
                return
            }
            if let targetWindow, NSApp.sendAction(saveSel, to: nil, from: targetWindow) {
                return
            }
            _ = NSApp.sendAction(saveSel, to: nil, from: nil)
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Move or Rename Document"
        savePanel.prompt = "Move"
        savePanel.nameFieldStringValue = currentURL.lastPathComponent
        savePanel.directoryURL = currentURL.deletingLastPathComponent()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = true

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let destinationURL = savePanel.url else { return }
            if destinationURL == currentURL { return }

            let finalizeUI = {
                DispatchQueue.main.async {
                    targetWindow?.representedURL = destinationURL
                    targetWindow?.title = destinationURL.deletingPathExtension().lastPathComponent
                    DocumentTabs.current.refresh()
                }
            }

            if let doc {
                doc.move(to: destinationURL) { error in
                    DispatchQueue.main.async {
                        if error != nil {
                            do {
                                if FileManager.default.fileExists(atPath: destinationURL.path) {
                                    try FileManager.default.removeItem(at: destinationURL)
                                }
                                try FileManager.default.moveItem(at: currentURL, to: destinationURL)
                                doc.fileURL = destinationURL
                                finalizeUI()
                            } catch {
                                let alert = NSAlert(error: error)
                                if let targetWindow {
                                    alert.beginSheetModal(for: targetWindow)
                                } else {
                                    alert.runModal()
                                }
                            }
                        } else {
                            finalizeUI()
                        }
                    }
                }
            } else {
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.moveItem(at: currentURL, to: destinationURL)
                    finalizeUI()
                } catch {
                    let alert = NSAlert(error: error)
                    if let targetWindow {
                        alert.beginSheetModal(for: targetWindow)
                    } else {
                        alert.runModal()
                    }
                }
            }
        }

        if let targetWindow {
            savePanel.beginSheetModal(for: targetWindow, completionHandler: completion)
        } else {
            savePanel.begin(completionHandler: completion)
        }
    }

    static func triggerSaveAs(for window: NSWindow?, fileURL: URL?) {
        let targetWindow = window ?? NSApp.keyWindow ?? NSApp.mainWindow
        let doc = findDocument(for: targetWindow, fileURL: fileURL)
        let saveAsSel = NSSelectorFromString("saveDocumentAs:")
        if let doc {
            if doc.responds(to: saveAsSel) {
                doc.perform(saveAsSel, with: targetWindow)
                return
            }
            if NSApp.sendAction(saveAsSel, to: doc, from: targetWindow) {
                return
            }
        }
        if let targetWindow, NSApp.sendAction(saveAsSel, to: nil, from: targetWindow) {
            return
        }
        _ = NSApp.sendAction(saveAsSel, to: nil, from: nil)
    }

    static func triggerMove(for window: NSWindow?, fileURL: URL?) {
        triggerRenameOrSave(for: window, fileURL: fileURL)
    }

    static func triggerDuplicate(for window: NSWindow?, fileURL: URL?) {
        let targetWindow = window ?? NSApp.keyWindow ?? NSApp.mainWindow
        let doc = findDocument(for: targetWindow, fileURL: fileURL)
        let dupSel = NSSelectorFromString("duplicateDocument:")
        let dupAltSel = NSSelectorFromString("duplicate:")
        if let doc {
            if doc.responds(to: dupSel) {
                doc.perform(dupSel, with: targetWindow)
                return
            }
            if doc.responds(to: dupAltSel) {
                doc.perform(dupAltSel, with: targetWindow)
                return
            }
            if NSApp.sendAction(dupSel, to: doc, from: targetWindow) {
                return
            }
        }
        if let targetWindow, NSApp.sendAction(dupSel, to: nil, from: targetWindow) {
            return
        }
        _ = NSApp.sendAction(dupSel, to: nil, from: nil)
    }
}

struct DocumentTitleMenuButton: View {
    let title: String
    let isEdited: Bool
    let fileURL: URL?
    let window: NSWindow?
    @State private var isHovering = false

    var body: some View {
        if let fileURL {
            Button(action: handleTitleClick) {
                titleLabel(hasChevron: true)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.6) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovering)
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                    isHovering = hovering
                }
            }
            .help("Document Title — Click to rename or move")
            .contextMenu {
                Button("Rename or Move...") {
                    handleTitleClick()
                }
                Button("Duplicate Document") {
                    triggerDuplicateModal()
                }
                Button("Save As...") {
                    triggerSaveAsModal()
                }

                Divider()

                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }

                Button("Copy Full Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fileURL.path, forType: .string)
                }

                if let pathHierarchy = pathHierarchy(for: fileURL), !pathHierarchy.isEmpty {
                    Divider()
                    ForEach(pathHierarchy, id: \.url) { item in
                        Button(action: {
                            NSWorkspace.shared.open(item.url)
                        }) {
                            Label(item.name, systemImage: "folder")
                        }
                    }
                }
            }
        } else {
            // Untitled / New tab: Clean static non-clickable label
            titleLabel(hasChevron: false)
                .padding(.horizontal, 8)
                .frame(height: 26)
        }
    }

    private func titleLabel(hasChevron: Bool) -> some View {
        HStack(spacing: 5.5) {
            Image(systemName: "doc.text")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ReadingStyle.secondary)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ReadingStyle.ink)

            if isEdited {
                HStack(spacing: 3.5) {
                    Circle()
                        .fill(Color.secondary.opacity(0.85))
                        .frame(width: 4.5, height: 4.5)
                    Text("Edited")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(ReadingStyle.secondary)
                }
            }

            if hasChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(ReadingStyle.ink.opacity(0.85))
                    .opacity(isHovering ? 1.0 : 0.0)
                    .scaleEffect(isHovering ? 1.0 : 0.65)
                    .offset(x: isHovering ? 0 : -3)
                    .padding(.leading, 1)
            }
        }
    }

    private func handleTitleClick() {
        DocumentActionHelper.triggerRenameOrSave(for: window, fileURL: fileURL)
    }

    private func triggerSaveAsModal() {
        DocumentActionHelper.triggerSaveAs(for: window, fileURL: fileURL)
    }

    private func triggerMoveModal() {
        DocumentActionHelper.triggerMove(for: window, fileURL: fileURL)
    }

    private func triggerDuplicateModal() {
        DocumentActionHelper.triggerDuplicate(for: window, fileURL: fileURL)
    }

    private struct PathItem {
        let name: String
        let url: URL
    }

    private func pathHierarchy(for url: URL?) -> [PathItem]? {
        guard let url else { return nil }
        var items: [PathItem] = []
        var current = url.deletingLastPathComponent()
        while current.path != "/" && !current.path.isEmpty {
            items.append(PathItem(name: current.lastPathComponent, url: current))
            current = current.deletingLastPathComponent()
        }
        if current.path == "/" {
            items.append(PathItem(name: "/", url: current))
        }
        return items
    }
}

struct KbdBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .default))
            .tracking(0.4)
            .foregroundStyle(Color.primary.opacity(0.75))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5.5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
            )
            .fixedSize()
    }
}

private struct EditButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.16, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct EditModeButton: View {
    let isEditing: Bool
    var returnsToNewTab: Bool = false
    let action: () -> Void
    @State private var isHovering = false

    private var buttonText: String {
        if isEditing {
            return returnsToNewTab ? "New Tab" : "View"
        }
        return "Edit"
    }

    private var helpText: String {
        if isEditing {
            return returnsToNewTab ? "Return to New Tab (⌘E)" : "Return to viewing (⌘E)"
        }
        return "Edit Markdown source (⌘E)"
    }

    private var accessibilityText: String {
        if isEditing {
            return returnsToNewTab ? "Return to New Tab" : "View formatted document"
        }
        return "Edit Markdown source"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(buttonText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ReadingStyle.ink)
                    .contentTransition(.numericText())

                KbdBadge(text: "⌘E")
            }
            .fixedSize()
            .padding(.horizontal, 7.5)
            .frame(height: 31)
            .background(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(isHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.60) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(EditButtonStyle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                isHovering = hovering
            }
        }
        .keyboardShortcut("e", modifiers: [.command])
        .help(helpText)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Keyboard shortcut: Command-E")
    }
}

private struct ModeFeedbackHUD: View {
    let isEditing: Bool
    var updateComplete = false
    var feedback: String?

    var body: some View {
        HStack(spacing: 7.5) {
            // Mode icon
            ZStack {
                Circle()
                    .fill(ReadingStyle.accent.opacity(0.14))
                    .frame(width: 22, height: 22)

                if updateComplete || feedback != nil {
                    Image(systemName: feedback?.hasPrefix("Couldn’t") == true ? "exclamationmark" : "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ReadingStyle.accent)
                } else if isEditing {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ReadingStyle.accent)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.72)),
                            removal: .opacity.combined(with: .scale(scale: 0.72))
                        ))
                } else {
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ReadingStyle.accent)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.72)),
                            removal: .opacity.combined(with: .scale(scale: 0.72))
                        ))
                }
            }
            .animation(.spring(response: 0.12, dampingFraction: 0.78), value: isEditing)

            // Mode title
            Text(feedback ?? (updateComplete ? "Update complete" : (isEditing ? "Editing Source" : "Reading View")))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary)
                .contentTransition(.numericText())
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 5.5)
        .background(
            Capsule()
                .fill(.regularMaterial)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 3)
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

private struct ActionFeedbackHUD: View {
    let title: String
    let systemImage: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(ReadingStyle.accent.opacity(0.14))
                    .frame(width: 24, height: 24)

                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(ReadingStyle.accent)
            }

            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.primary)

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.4))
                .frame(width: 1, height: 12)

            KbdBadge(text: shortcut)
        }
        .padding(.leading, 7)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.regularMaterial)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 3)
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

/// Native-feeling find bar that floats over the reading view. Delegates all find
/// operations to FindController which calls WKWebView.find(_:configuration:).
private struct FindBar: View {
    @ObservedObject var controller: FindController
    @FocusState.Binding var isFocused: Bool
    @State private var isHoveringClose = false
    @State private var isHoveringPrev = false
    @State private var isHoveringNext = false

    private var matchLabel: String? {
        guard !controller.query.isEmpty else { return nil }
        if controller.matchCount == 0 { return "No matches" }
        return "\(controller.currentMatch) of \(controller.matchCount)"
    }

    var body: some View {
        HStack(spacing: 6) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 16, height: 16)

            // Text field with stable fixed width
            TextField("Find in document", text: $controller.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(width: 175)
                .focused($isFocused)
                .onSubmit { controller.findNext() }
                .onChange(of: controller.query) { _, newValue in
                    controller.search(newValue)
                }

            // Match count — fixed width single-line slot so typing never causes horizontal or vertical shifts
            Text(matchLabel ?? "")
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(controller.matchCount == 0 && !controller.query.isEmpty ? Color.red.opacity(0.85) : Color.secondary)
                .frame(width: 78, alignment: .trailing)
                .opacity(matchLabel == nil ? 0 : 1)
                .animation(.easeInOut(duration: 0.12), value: matchLabel != nil)

            // Prev / Next buttons
            HStack(spacing: 2) {
                findNavButton(
                    systemImage: "chevron.up",
                    isHovering: $isHoveringPrev,
                    action: controller.findPrevious
                )
                findNavButton(
                    systemImage: "chevron.down",
                    isHovering: $isHoveringNext,
                    action: controller.findNext
                )
            }

            // Close button — circular hover background matching capsule end curve
            Button(action: controller.close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isHoveringClose ? Color.primary : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(isHoveringClose
                                  ? Color(nsColor: .quaternaryLabelColor).opacity(0.55)
                                  : Color.clear)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringClose = $0 }
            .keyboardShortcut(.escape, modifiers: [])
            .help("Close (Escape)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .task(id: controller.focusRequest) {
            // Request focus after the conditional field has joined the view tree.
            isFocused = false
            await Task.yield()
            guard !Task.isCancelled, controller.isVisible else { return }
            isFocused = true
        }
        .onDisappear { isFocused = false }
    }

    @ViewBuilder
    private func findNavButton(
        systemImage: String,
        isHovering: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovering.wrappedValue ? Color.primary : Color.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovering.wrappedValue
                              ? Color(nsColor: .quaternaryLabelColor).opacity(0.55)
                              : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering.wrappedValue = $0 }
    }
}

private struct BlurredWindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct DocumentTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let readingWidth: CGFloat
    let isFocused: Bool
    var findController: FindController? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> EditorScrollView {
        let scrollView = EditorScrollView()
        scrollView.readingWidth = readingWidth
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerKnobStyle = .default

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = EditorNSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0.0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesFindPanel = false
        textView.findController = findController
        findController?.attach(textView)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        let editorParagraphStyle = NSMutableParagraphStyle()
        editorParagraphStyle.lineSpacing = max(4.0, round(fontSize * 0.44))
        textView.defaultParagraphStyle = editorParagraphStyle
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .light)
        textView.textColor = NSColor.labelColor.withAlphaComponent(0.92)
        textView.insertionPointColor = .controlAccentColor
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .light),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.92),
            .paragraphStyle: editorParagraphStyle
        ]

        scrollView.documentView = textView
        scrollView.textView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        textView.string = text
        let startRange = NSRange(location: 0, length: 0)
        textView.setSelectedRange(startRange)
        scrollView.updateInsets()

        DispatchQueue.main.async {
            let targetWindow = textView.window ?? NSApp.keyWindow
            targetWindow?.makeFirstResponder(textView)
            textView.setSelectedRange(startRange)
            textView.scrollRangeToVisible(startRange)
        }

        return scrollView
    }

    func updateNSView(_ nsView: EditorScrollView, context: Context) {
        context.coordinator.parent = self
        nsView.readingWidth = readingWidth
        guard let textView = nsView.textView else { return }

        textView.findController = findController
        findController?.attach(textView)

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        let targetFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .light)
        if textView.font != targetFont {
            textView.font = targetFont
            let editorParagraphStyle = NSMutableParagraphStyle()
            editorParagraphStyle.lineSpacing = max(4.0, round(fontSize * 0.44))
            textView.defaultParagraphStyle = editorParagraphStyle
            textView.typingAttributes = [
                .font: targetFont,
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.92),
                .paragraphStyle: editorParagraphStyle
            ]
        }

        nsView.updateInsets()

        if isFocused && nsView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(textView)
            }
        }
    }

    static func dismantleNSView(_ nsView: EditorScrollView, coordinator: Coordinator) {
        coordinator.parent.findController?.detachTextView()
    }

    fileprivate final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DocumentTextEditor
        weak var textView: EditorNSTextView?
        weak var scrollView: EditorScrollView?

        init(_ parent: DocumentTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if self.parent.text != textView.string {
                self.parent.text = textView.string
            }
            self.parent.findController?.refreshEditorMatches()
        }
    }
}

fileprivate final class EditorScrollView: NSScrollView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if let scroller = verticalScroller, !scroller.isHidden,
           scroller.frame.contains(local) {
            return scroller
        }
        return super.hitTest(point)
    }

    var readingWidth: CGFloat = 740 {
        didSet {
            updateInsets()
        }
    }
    weak var textView: EditorNSTextView?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    override func layout() {
        super.layout()
        updateInsets()
    }

    func updateInsets() {
        guard let textView else { return }
        let hPadding = readingWidth <= 0 ? 52.0 : max(52.0, (bounds.width - readingWidth) / 2.0)
        let inset = NSSize(width: hPadding, height: 42.0)
        if textView.textContainerInset != inset {
            textView.textContainerInset = inset
        }
    }
}

@MainActor
private func isOverDocumentScroller(_ view: NSView, event: NSEvent) -> Bool {
    guard let scroll = view.enclosingScrollView, scroll.hasVerticalScroller else { return false }
    let point = scroll.convert(event.locationInWindow, from: nil)
    let width = NSScroller.scrollerWidth(for: .regular, scrollerStyle: scroll.scrollerStyle)
    return point.x >= scroll.bounds.maxX - width && scroll.bounds.contains(point)
}

fileprivate final class EditorNSTextView: NSTextView {
    weak var findController: FindController?

    override func cursorUpdate(with event: NSEvent) {
        if isOverDocumentScroller(self, event: event) {
            NSCursor.arrow.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            window.makeFirstResponder(self)
            let startRange = NSRange(location: 0, length: 0)
            setSelectedRange(startRange)
            scrollRangeToVisible(startRange)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .shift, .control, .option]) == .command,
           event.charactersIgnoringModifiers == "f" {
            if let findController {
                findController.show()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func performFindPanelAction(_ sender: Any?) {
        guard let findController else {
            super.performFindPanelAction(sender)
            return
        }
        if let menuItem = sender as? NSMenuItem {
            switch menuItem.tag {
            case 1: // NSFindPanelActionShowFindPanel
                findController.show()
            case 2: // NSFindPanelActionNext
                findController.findNext()
            case 3: // NSFindPanelActionPrevious
                findController.findPrevious()
            default:
                findController.show()
            }
            return
        }
        findController.show()
    }
}

struct ReadingView: View {
    let source: String
    var fileURL: URL? = nil
    var documentWindow: NSWindow? = nil
    var onStartWriting: (() -> Void)? = nil

    var isActive = true
    var findController: FindController? = nil
    var onSourceChange: ((String, String) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("headingFont") private var headingFont = ReadingFont.system.rawValue
    @AppStorage("readingFont") private var readingFont = ReadingFont.system.rawValue
    @AppStorage("fontSize") private var fontSize = 16.0
    @AppStorage("readingWidth") private var readingWidth = 740.0

    private var activeReadingFont: ReadingFont {
        let font = ReadingFont.from(stored: readingFont)
        return font == .instrumentSerif ? .system : font
    }

    private var activeHeadingFont: ReadingFont {
        ReadingFont.from(stored: headingFont)
    }

    private enum Presentation: Equatable {
        case newTab, emptyFile, document
    }

    private var presentation: Presentation {
        if !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .document
        }
        return fileURL == nil ? .newTab : .emptyFile
    }

    var body: some View {
        ZStack {
            switch presentation {
            case .newTab, .emptyFile:
                EmptyDocumentStateView(
                    fileURL: fileURL,
                    documentWindow: documentWindow,
                    onStartWriting: onStartWriting,
                    tabs: documentWindow.map { DocumentTabs.owner(of: $0) } ?? DocumentTabs.current
                )
                .transition(.opacity)
            case .document:
                MarkdownReader(
                    source: source,
                    readingFontSize: fontSize,
                    readingFont: activeReadingFont,
                    headingFont: activeHeadingFont,
                    readingWidth: readingWidth,
                    fileURL: fileURL,
                    documentWindow: documentWindow,
                    isActive: isActive,
                    findController: findController,
                    onSourceChange: onSourceChange
                )
                .accessibilityLabel("Markdown reading view")
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: presentation)
        .transaction { $0.disablesAnimations = false }
    }
}

struct OverlayScrollView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(CompactScrollerConfiguration())
        }
    }
}

private struct CompactScrollerConfiguration: NSViewRepresentable {
    final class ScrollerConfigView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyConfiguration()
        }

        override func layout() {
            super.layout()
            applyConfiguration()
        }

        func applyConfiguration() {
            guard let scroll = enclosingScrollView else { return }
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.automaticallyAdjustsContentInsets = false
            scroll.contentInsets = NSEdgeInsetsZero
            scroll.scrollerInsets = NSEdgeInsetsZero
            if let scroller = scroll.verticalScroller {
                scroller.controlSize = .small
                scroller.scrollerStyle = .overlay
            }
        }
    }

    func makeNSView(context: Context) -> ScrollerConfigView {
        ScrollerConfigView()
    }

    func updateNSView(_ nsView: ScrollerConfigView, context: Context) {
        nsView.applyConfiguration()
    }
}

private struct PulsatingDropBackgroundView: View {
    let isTargeted: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPulsing = false

    private static let grainImage: NSImage = {
        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }
        var seed: UInt32 = 0x5deece66
        for y in 0..<128 {
            for x in 0..<128 {
                seed = (seed &* 1664525) &+ 1013904223
                let lum = CGFloat((seed >> 16) & 0xFF) / 255.0
                let alpha = (lum * 0.16)
                ctx.setFillColor(CGColor(gray: lum > 0.5 ? 1.0 : 0.0, alpha: alpha))
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        image.unlockFocus()
        return image
    }()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Layer 1: Breathing atmospheric radial glow
                RadialGradient(
                    colors: [
                        Color.accentColor.opacity(
                            scheme == .dark
                                ? (isPulsing ? 0.22 : 0.13)
                                : (isPulsing ? 0.14 : 0.08)
                        ),
                        Color.purple.opacity(
                            scheme == .dark
                                ? (isPulsing ? 0.08 : 0.03)
                                : (isPulsing ? 0.05 : 0.02)
                        ),
                        .clear
                    ],
                    center: .init(x: 0.5, y: 0.5),
                    startRadius: 0,
                    endRadius: max(geometry.size.width, geometry.size.height) * (isPulsing ? 0.78 : 0.64)
                )
                .scaleEffect(isPulsing ? 1.04 : 0.96)

                // Layer 2: Subtle linear directional glow
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(isPulsing ? 0.05 : 0.02),
                        Color.clear,
                        Color.purple.opacity(isPulsing ? 0.06 : 0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Layer 3: Tactile micro-grain texture
                Image(nsImage: Self.grainImage)
                    .resizable(resizingMode: .tile)
                    .opacity(scheme == .dark ? 0.22 : 0.15)
                    .blendMode(scheme == .dark ? .plusLighter : .multiply)
            }
            .opacity(isTargeted ? 1.0 : 0.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: isTargeted)
            .onChange(of: isTargeted) { _, targeted in
                if targeted && !reduceMotion {
                    withAnimation(
                        .easeInOut(duration: 1.6)
                        .repeatForever(autoreverses: true)
                    ) {
                        isPulsing = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isPulsing = false
                    }
                }
            }
            .onAppear {
                if isTargeted && !reduceMotion {
                    withAnimation(
                        .easeInOut(duration: 1.6)
                        .repeatForever(autoreverses: true)
                    ) {
                        isPulsing = true
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private enum NewTabLayout {
    static func recentsWidth(in windowWidth: CGFloat) -> CGFloat {
        min(max(300, max(0, windowWidth - 64) * 0.42), 660)
    }
}

struct EmptyDocumentStateView: View {
    let fileURL: URL?
    let documentWindow: NSWindow?
    let onStartWriting: (() -> Void)?

    @AppStorage("windowOpeningMode") private var windowOpeningMode = WindowOpeningMode.separateWindows.rawValue
    @ObservedObject var tabs: DocumentTabs
    @State private var isDropTargeted = false
    @State private var isOpeningDrop = false
    @State private var isOpenHovering = false
    @State private var isWriteHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var recentStore = RecentDocumentsStore.shared

    private var showsDocumentTabs: Bool {
        WindowOpeningMode.from(stored: windowOpeningMode) == .tabbed && tabs.items.count > 1
    }

    var body: some View {
        Group {
            if let fileURL {
                existingFileEmptyView(fileURL: fileURL)
            } else {
                newTabOpenView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url], isTargeted: $isDropTargeted) { providers in
            handleFileDrop(providers: providers)
        }
    }

    private var newTabOpenView: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width
            let recentsWidth = NewTabLayout.recentsWidth(in: availableWidth)

            HStack(spacing: 0) {
                // Left side: Clean, spacious, vertically centered hero drop zone
                VStack {
                    Spacer()
                    heroDropView
                    Spacer()
                }
                .offset(y: -8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    PulsatingDropBackgroundView(isTargeted: isDropTargeted)
                }

                // Real Division: Native full-height vertical separator to window top edge
                Rectangle()
                    .fill(
                        isDropTargeted && !showsDocumentTabs
                            ? (scheme == .dark ? Color.white.opacity(0.38) : Color.black.opacity(0.24))
                            : Color(nsColor: .separatorColor).opacity(0.65)
                    )
                    .frame(width: showsDocumentTabs ? 0 : 1)
                    .frame(maxHeight: .infinity)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isDropTargeted)

                // Right side: Dedicated sidebar container with sticky header and scrollable items / empty state
                ZStack(alignment: .top) {
                    Color.sidebarSolidBackground(for: scheme)
                        .frame(maxHeight: .infinity)

                    RecentFilesSuggestionsSection(
                        columnCount: recentsWidth >= 520 ? 2 : 1,
                        topInset: 22
                    ) { url in
                        openRecentFile(url)
                    }
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: showsDocumentTabs ? 8 : 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
                .overlay {
                    if showsDocumentTabs {
                        TopLeadingCornerBorder(radius: 8)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: recentsWidth)
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var heroDropView: some View {
        VStack(spacing: 20) {
            // Icon slot with frozen layout position and NO '+' badge
            Image(systemName: "doc.text")
                .font(.system(size: 46, weight: .ultraLight))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.50))
                .frame(width: 52, height: 52)

            // Primary prompt with instantaneous text switch (no animated fading)
            Group {
                if isDropTargeted {
                    Text("Release to open")
                } else {
                    Text("Drop a file to open")
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isDropTargeted ? Color.primary : Color.secondary)
            .frame(height: 20)
            .transaction { $0.animation = nil }

            // Wider left/right edge-justified buttons, vertically successive
            VStack(spacing: 10) {
                Button(action: openFromFinder) {
                    HStack {
                        Text("Open…")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        KbdBadge(text: "⌘O")
                    }
                    .padding(.horizontal, 14)
                    .frame(width: 200, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isOpenHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.85) : Color(nsColor: .quaternaryLabelColor).opacity(0.40))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("o", modifiers: [.command])
                .onHover { isOpenHovering = $0 }

                Button(action: { onStartWriting?() }) {
                    HStack {
                        Text("Write")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        KbdBadge(text: "⌘E")
                    }
                    .padding(.horizontal, 14)
                    .frame(width: 200, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isWriteHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.85) : Color(nsColor: .quaternaryLabelColor).opacity(0.40))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("e", modifiers: [.command])
                .onHover { isWriteHovering = $0 }
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 32)
        .accessibilityLabel("Drop a file to open, press Command-O to open Finder, or Command-E to start writing.")
    }

    private func openRecentFile(_ url: URL) {
        if let documentWindow, DocumentTabs.current.openFileInEmptyTab(url, window: documentWindow) { return }
        DocumentTabs.current.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    private func existingFileEmptyView(fileURL: URL) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color.secondary.opacity(0.50))
                .padding(.bottom, 2)

            VStack(spacing: 3) {
                Text(fileURL.lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ReadingStyle.ink)

                Text("Document is empty")
                    .font(.system(size: 12.5))
                    .foregroundStyle(ReadingStyle.secondary.opacity(0.85))
            }

            Button(action: { onStartWriting?() }) {
                HStack(spacing: 6) {
                    Text("Start Writing")
                        .font(.system(size: 12.5, weight: .medium))
                    KbdBadge(text: "⌘E")
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isWriteHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.85) : Color(nsColor: .quaternaryLabelColor).opacity(0.40))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("e", modifiers: [.command])
            .onHover { isWriteHovering = $0 }
            .padding(.top, 2)
        }
        .accessibilityLabel("\(fileURL.lastPathComponent) is empty. Choose Start Writing (Command-E).")
    }

    private func openFromFinder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            UTType(filenameExtension: "mdown") ?? .plainText,
            UTType(filenameExtension: "mkd") ?? .plainText,
            UTType.plainText,
            UTType.text
        ]
        panel.prompt = "Open"
        panel.message = "Choose a Markdown file from your Mac"

        panel.begin { response in
            guard response == .OK else { return }
            for (index, url) in panel.urls.enumerated() {
                if index == 0, let documentWindow,
                   DocumentTabs.current.openFileInEmptyTab(url, window: documentWindow) {
                    continue
                }
                DocumentTabs.current.openDocument(withContentsOf: url, display: true) { document, _, error in
                    if let error { NSApp.presentError(error) }
                }
            }
        }
    }

    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty, !isOpeningDrop else { return false }
        isOpeningDrop = true
        let targetWindow = documentWindow

        Task { @MainActor in
            defer { isOpeningDrop = false }
            var openedURLs = Set<URL>()
            var canReuseWindow = true
            for provider in files {
                let url: URL? = await withCheckedContinuation { continuation in
                    Self.extractFileURL(from: provider) { continuation.resume(returning: $0) }
                }
                guard let url else {
                    NSApp.presentError(CocoaError(.fileReadInvalidFileName))
                    continue
                }
                guard openedURLs.insert(url.standardizedFileURL).inserted else { continue }
                if canReuseWindow, let targetWindow,
                   DocumentTabs.current.openFileInEmptyTab(url, window: targetWindow) {
                    canReuseWindow = false
                    continue
                }
                canReuseWindow = false
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DocumentTabs.current.openDocument(withContentsOf: url, display: true) { document, _, error in
                        if let error { NSApp.presentError(error) }
                        continuation.resume()
                    }
                }
            }
        }
        return true
    }

    private nonisolated static func extractFileURL(
        from provider: NSItemProvider,
        completion: @escaping @Sendable (URL?) -> Void
    ) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let value = item as? URL {
                url = value
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let value = item as? String {
                url = value.hasPrefix("/") ? URL(fileURLWithPath: value) : URL(string: value)
            } else {
                url = nil
            }
            completion(url?.isFileURL == true ? url : nil)
        }
    }
}

private struct TopLeadingCornerBorder: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        if radius > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

private struct TransparentTitlebar: NSViewRepresentable {
    var openingMode: WindowOpeningMode = .separateWindows
    var fileURL: URL? = nil
    var title: String = ""
    var onWindowResolved: ((NSWindow) -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        let view = TitlebarConfigurationView()
        view.openingMode = openingMode
        view.fileURL = fileURL
        view.docTitle = title
        view.onWindowResolved = onWindowResolved
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? TitlebarConfigurationView {
            view.openingMode = openingMode
            view.fileURL = fileURL
            view.docTitle = title
            view.onWindowResolved = onWindowResolved
            view.applyConfiguration()
        }
    }

    private final class TitlebarConfigurationView: NSView {
        var openingMode: WindowOpeningMode = .separateWindows
        var fileURL: URL? = nil
        var docTitle: String = ""
        var onWindowResolved: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = self.window else { return }
            window.animationBehavior = .none
            applyConfiguration()
            self.onWindowResolved?(window)
        }

        func applyConfiguration() {
            guard let window else { return }
            window.animationBehavior = .none
            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
            if !window.titlebarAppearsTransparent {
                window.titlebarAppearsTransparent = true
            }
            if window.titlebarSeparatorStyle != .none {
                window.titlebarSeparatorStyle = .none
            }
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            if window.toolbar?.isVisible == true {
                window.toolbar?.isVisible = false
            }
            if !window.isMovableByWindowBackground {
                window.isMovableByWindowBackground = true
            }
            if window.isOpaque {
                window.isOpaque = false
            }
            if window.backgroundColor != .clear {
                window.backgroundColor = .clear
            }

            if let fileURL, window.representedURL != fileURL {
                window.representedURL = fileURL
            }
            if !docTitle.isEmpty && window.title != docTitle {
                window.title = docTitle
            }

            if window.isRestorable {
                window.isRestorable = false
            }

            window.minSize = CGSize(width: 640, height: 400)
            window.tabbingMode = .disallowed
            window.tabbingIdentifier = "LightmarkDocument"
            NSWindow.allowsAutomaticWindowTabbing = false
        }
    }
}

#if DEBUG
struct DesignPreview: View {
    @State private var showStressDocument = false
    @AppStorage("backgroundStyle") private var backgroundStyle = BackgroundStyle.translucent.rawValue
    @AppStorage("windowOpeningMode") private var windowOpeningMode = WindowOpeningMode.separateWindows.rawValue

    private var currentBackgroundStyle: BackgroundStyle {
        BackgroundStyle.from(stored: backgroundStyle)
    }

    private var currentWindowOpeningMode: WindowOpeningMode {
        WindowOpeningMode.from(stored: windowOpeningMode)
    }

    private let sample = """
    # A clear place to read

    Markdown should feel like a document. **Strong text**, *emphasis*, and [links](https://example.com) are part of the page.

    ## The small details

    - Comfortable line length
    - Quiet spacing
    - Native controls
    - `Resources/Info.plist` owns file registration; `scripts/build-app.sh` packages the application and keeps a wrapped inline path aligned with this list.

    > A reading surface should stay out of the way.

    ```swift
    let focus = "the document"
    ```

    ---

    More words, with room to breathe.
    """

    private var stressSample: String {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Reader/stress.md"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return "Stress document unavailable in this build."
        }
        return source
    }

    var body: some View {
        ReadingView(source: showStressDocument ? stressSample : sample)
            .toolbar {
                Picker("Document", selection: $showStressDocument) {
                    Text("Primitives").tag(false)
                    Text("Markdown stress document").tag(true)
                }
            }
            .background(windowBackdrop)
            .background(TransparentTitlebar(openingMode: currentWindowOpeningMode))
    }

    @ViewBuilder
    private var windowBackdrop: some View {
        switch currentBackgroundStyle {
        case .translucent:
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea()
        case .solid:
            Color(nsColor: .textBackgroundColor)
                .ignoresSafeArea()
        }
    }
}

struct DesignPreviewCommands: Commands {

    var body: some Commands {
        CommandMenu("Developer") {
            Button("Show Design Preview") { DesignPreviewWindow.show() }
            Button("Replay Welcome") { FirstLaunch.shared.present(welcome: true) }
        }
    }
}
@MainActor private enum DesignPreviewWindow {
    static var controller: NSWindowController?
    static func show() {
        if controller == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Design Preview"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: DesignPreview())
            window.center()
            controller = NSWindowController(window: window)
        }
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
    }
}
#endif
