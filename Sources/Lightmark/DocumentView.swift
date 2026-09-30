import SwiftUI
import UniformTypeIdentifiers
import LightmarkCore

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
    @State private var isEditing = false
    @State private var showFeedback = false
    @State private var feedbackTask: Task<Void, Never>? = nil
    @State private var showCopyFeedback = false
    @State private var copyFeedbackTask: Task<Void, Never>? = nil
    @State private var lastSavedText: String = ""
    @ObservedObject private var tabs = DocumentTabs.shared
    @Environment(\.accessibilityReduceMotion) private var reduceHeaderMotion
    @Environment(\.colorScheme) private var scheme
    @State private var documentWindow: NSWindow?
    @FocusState private var isEditorFocused: Bool
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
        return document.text != lastSavedText
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
            // Main content area
            Group {
                if isEditing {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 52)
                        DocumentTextEditor(
                            text: $document.text,
                            fontSize: fontSize,
                            readingWidth: readingWidth,
                            isFocused: isEditorFocused
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Markdown source")
                    .transition(.opacity)
                } else if isDefaultNoFileView {
                    ReadingView(
                        source: document.text,
                        fileURL: fileURL,
                        documentWindow: documentWindow,
                        onStartWriting: toggleEditing
                    )
                    .padding(.top, showsDocumentTabs ? 52 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                } else {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 52)
                        ReadingView(
                            source: document.text,
                            fileURL: fileURL,
                            documentWindow: documentWindow,
                            onStartWriting: toggleEditing
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Top bar header overlay
            ZStack {
                DocumentTabBar(tabs: tabs, fallbackTitle: documentTitle)
                    .padding(.trailing, 108)
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
                .padding(.horizontal, 100)
                .opacity((showsDocumentTabs || (isDefaultNoFileView && !isEditing)) ? 0 : 1)
                .allowsHitTesting(!showsDocumentTabs && (!isDefaultNoFileView || isEditing))
                .accessibilityHidden(showsDocumentTabs || (isDefaultNoFileView && !isEditing))
            }
            .frame(height: 52)
            .animation(reduceHeaderMotion ? nil : .easeInOut(duration: 0.18), value: showsDocumentTabs)
            .transaction { if $0.disablesAnimations { $0.animation = nil } }
            .overlay(alignment: .trailing) {
                if !isDefaultNoFileView || isEditing {
                    EditModeButton(isEditing: isEditing, action: toggleEditing)
                        .padding(.trailing, 14)
                        .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottom) {
            if showCopyFeedback {
                ActionFeedbackHUD(title: "Copied All Text", systemImage: "doc.on.doc.fill", shortcut: "⌘⇧C")
                    .padding(.bottom, 28)
                    .transition(hudTransition)
                    .allowsHitTesting(false)
                    .zIndex(1000)
            } else if showFeedback {
                ModeFeedbackHUD(isEditing: isEditing)
                    .padding(.bottom, 28)
                    .transition(hudTransition)
                    .allowsHitTesting(false)
                    .zIndex(999)
            }
        }
        .background(
            Button("") {
                copyAllToClipboard()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
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
                    tabs.register(window, mode: currentWindowOpeningMode)
                }
            )
        )
        .onAppear {
            if lastSavedText.isEmpty {
                lastSavedText = document.text
            }
        }
        .onChange(of: fileURL) { _, newURL in
            if let newURL {
                RecentDocumentsStore.shared.register(url: newURL)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .markdownDocumentDidSave)) { _ in
            lastSavedText = document.text
        }
        .onReceive(NotificationCenter.default.publisher(for: .copyAllDocumentText)) { _ in
            copyAllToClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditMode)) { _ in
            toggleEditing()
        }
        .onChange(of: document.text) { _, _ in
            // NSDocument owns dirty state; read it after SwiftUI propagates the edit.
            DispatchQueue.main.async { tabs.refresh() }
        }
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
        withAnimation(.easeInOut(duration: 0.16)) {
            isEditing.toggle()
        }
        if isEditing {
            isEditorFocused = true
            DispatchQueue.main.async {
                let activeWindow = documentWindow ?? NSApp.keyWindow
                if let textView = (activeWindow?.firstResponder as? NSTextView) ?? (NSApp.keyWindow?.firstResponder as? NSTextView) {
                    let startRange = NSRange(location: 0, length: 0)
                    textView.setSelectedRange(startRange)
                    textView.scrollRangeToVisible(startRange)
                }
            }
        }
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
                    DocumentTabs.shared.refresh()
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
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(isEditing ? "View" : "Edit")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ReadingStyle.ink)

                KbdBadge(text: "⌘E")
            }
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
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
        .help(isEditing ? "Return to viewing (⌘E)" : "Edit Markdown source (⌘E)")
        .accessibilityLabel(isEditing ? "View formatted document" : "Edit Markdown source")
        .accessibilityHint("Keyboard shortcut: Command-E")
    }
}

private struct ModeFeedbackHUD: View {
    let isEditing: Bool

    var body: some View {
        HStack(spacing: 9) {
            // Accent-tinted icon circle badge with animated SF Symbol
            ZStack {
                Circle()
                    .fill(ReadingStyle.accent.opacity(0.14))
                    .frame(width: 24, height: 24)

                Image(systemName: isEditing ? "pencil.line" : "book.pages.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(ReadingStyle.accent)
                    .contentTransition(.symbolEffect(.replace.downUp))
            }

            // Mode title with fluid text transition
            Text(isEditing ? "Editing Source" : "Reading View")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.primary)
                .contentTransition(.numericText())

            // Divider
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.4))
                .frame(width: 1, height: 12)

            // Shortcut keycap
            KbdBadge(text: "⌘E")
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
        textView.allowsUndo = true
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
        nsView.readingWidth = readingWidth
        guard let textView = nsView.textView else { return }

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

fileprivate final class ReadingScrollView: NSScrollView {
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
    weak var textView: HoverableDocumentTextView?

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
}

struct ReadingView: View {
    let source: String
    var fileURL: URL? = nil
    var documentWindow: NSWindow? = nil
    var onStartWriting: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("headingFont") private var headingFont = ReadingFont.system.rawValue
    @AppStorage("readingFont") private var readingFont = ReadingFont.system.rawValue
    @AppStorage("fontSize") private var fontSize = 16.0
    @AppStorage("readingWidth") private var readingWidth = 740.0

    private var activeReadingFont: ReadingFont {
        ReadingFont.from(stored: readingFont)
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
                    onStartWriting: onStartWriting
                )
                .transition(.opacity)
            case .document:
                UnifiedReadingTextView(
                    source: source,
                    readingFontSize: fontSize,
                    readingFont: activeReadingFont,
                    headingFont: activeHeadingFont,
                    readingWidth: readingWidth,
                    fileURL: fileURL,
                    documentWindow: documentWindow
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

struct EmptyDocumentStateView: View {
    let fileURL: URL?
    let documentWindow: NSWindow?
    let onStartWriting: (() -> Void)?

    @AppStorage("windowOpeningMode") private var windowOpeningMode = WindowOpeningMode.separateWindows.rawValue
    @ObservedObject private var tabs = DocumentTabs.shared
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
            let paneSpace = max(0, availableWidth - 64)
            let recentsWidth = min(max(300, paneSpace * 0.42), 660)

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
                .frame(width: recentsWidth)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if showsDocumentTabs {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.65))
                            .frame(height: 1)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .leading) {
                    if showsDocumentTabs {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.65))
                            .frame(width: 1)
                            .allowsHitTesting(false)
                    }
                }
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
        if let documentWindow, DocumentTabs.shared.openFileInEmptyTab(url, window: documentWindow) { return }
        DocumentTabs.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
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
                   DocumentTabs.shared.openFileInEmptyTab(url, window: documentWindow) {
                    continue
                }
                DocumentTabs.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
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
                   DocumentTabs.shared.openFileInEmptyTab(url, window: targetWindow) {
                    canReuseWindow = false
                    continue
                }
                canReuseWindow = false
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DocumentTabs.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
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

private struct UnifiedReadingTextView: NSViewRepresentable {
    let source: String
    let readingFontSize: CGFloat
    let readingFont: ReadingFont
    let headingFont: ReadingFont
    let readingWidth: CGFloat
    var fileURL: URL? = nil
    var documentWindow: NSWindow? = nil

    func makeNSView(context: Context) -> ReadingScrollView {
        let scrollView = ReadingScrollView()
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

        let textView = HoverableDocumentTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0.0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.currentFileURL = fileURL
        textView.documentWindow = documentWindow

        scrollView.documentView = textView
        scrollView.textView = textView

        updateContent(in: textView)
        scrollView.updateInsets()

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ nsView: ReadingScrollView, context: Context) {
        nsView.readingWidth = readingWidth
        guard let textView = nsView.textView else { return }
        textView.currentFileURL = fileURL
        textView.documentWindow = documentWindow

        if textView.lastSource != source ||
           textView.lastFontSize != readingFontSize ||
           textView.lastReadingFont != readingFont ||
           textView.lastHeadingFont != headingFont {
            updateContent(in: textView)
        }

        nsView.updateInsets()
    }

    private func updateContent(in textView: HoverableDocumentTextView) {
        textView.lastSource = source
        textView.lastFontSize = readingFontSize
        textView.lastReadingFont = readingFont
        textView.lastHeadingFont = headingFont
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            let attr = DocumentAttributedStringBuilder.build(
                source: source,
                fontSize: readingFontSize,
                readingFont: readingFont,
                headingFont: headingFont
            )
            textView.setDocumentContent(attr)
        }
    }
}

extension NSAttributedString.Key {
    static let codeBlock = NSAttributedString.Key("LightmarkCodeBlock")
    static let inlineCode = NSAttributedString.Key("LightmarkInlineCode")
    static let blockQuote = NSAttributedString.Key("LightmarkBlockQuote")
    static let divider = NSAttributedString.Key("LightmarkDivider")
    static let tableGroup = NSAttributedString.Key("LightmarkTableGroup")
    static let tableHeader = NSAttributedString.Key("LightmarkTableHeader")
}

private enum CodeHighlighter {
    static let keywordColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.99, green: 0.37, blue: 0.64, alpha: 1.0) // #fc5fa3
            : NSColor(red: 0.61, green: 0.14, blue: 0.58, alpha: 1.0) // #9b2393
    }

    static let stringColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.99, green: 0.42, blue: 0.36, alpha: 1.0) // #fc6a5d
            : NSColor(red: 0.77, green: 0.10, blue: 0.09, alpha: 1.0) // #c41a16
    }

    static let commentColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.45, green: 0.50, blue: 0.56, alpha: 1.0) // #73808f
            : NSColor(red: 0.42, green: 0.46, blue: 0.50, alpha: 1.0) // #6a737d
    }

    static let numberColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.82, green: 0.75, blue: 0.41, alpha: 1.0) // #d0bf69
            : NSColor(red: 0.11, green: 0.00, blue: 0.81, alpha: 1.0) // #1c00cf
    }

    static let typeColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.36, green: 0.85, blue: 0.82, alpha: 1.0) // #5dd8d2
            : NSColor(red: 0.18, green: 0.44, blue: 0.49, alpha: 1.0) // #2e6f7e
    }

    static let inlineCodeTextColor = NSColor.labelColor

    private static let keywordPattern: NSRegularExpression? = {
        let words = [
            "let", "var", "func", "struct", "class", "enum", "protocol", "extension",
            "import", "init", "self", "Self", "super", "return", "if", "else",
            "guard", "switch", "case", "default", "break", "continue", "fallthrough",
            "for", "in", "while", "repeat", "do", "try", "catch", "throw", "throws",
            "rethrows", "async", "await", "actor", "some", "any", "typealias",
            "where", "defer", "is", "as", "inout", "static", "public", "private",
            "fileprivate", "internal", "open", "mutating", "nonmutating", "override",
            "weak", "unowned", "true", "false", "nil", "null", "undefined", "const",
            "function", "def", "val", "fn", "pub", "use", "impl", "trait", "from",
            "lambda", "yield", "interface", "package", "type"
        ]
        let pattern = "\\b(" + words.joined(separator: "|") + ")\\b"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    private static let stringPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\[\s\S]|[^`\\])*`"#, options: [])
    }()

    private static let commentPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"//.*$|#.*$|/\*[\s\S]*?\*/"#, options: [.anchorsMatchLines])
    }()

    private static let numberPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\b\d+(?:\.\d+)?\b|\b0x[0-9a-fA-F]+\b"#, options: [])
    }()

    private static let typePattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\b[A-Z][a-zA-Z0-9_]*\b"#, options: [])
    }()

    static func highlight(
        code: String,
        font: NSFont,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        let fullRange = NSRange(location: 0, length: (code as NSString).length)
        guard fullRange.length > 0 else { return result }

        if let typePattern {
            for match in typePattern.matches(in: code, options: [], range: fullRange) {
                result.addAttribute(.foregroundColor, value: typeColor, range: match.range)
            }
        }

        if let keywordPattern {
            for match in keywordPattern.matches(in: code, options: [], range: fullRange) {
                result.addAttribute(.foregroundColor, value: keywordColor, range: match.range)
            }
        }

        if let numberPattern {
            for match in numberPattern.matches(in: code, options: [], range: fullRange) {
                result.addAttribute(.foregroundColor, value: numberColor, range: match.range)
            }
        }

        if let stringPattern {
            for match in stringPattern.matches(in: code, options: [], range: fullRange) {
                result.addAttribute(.foregroundColor, value: stringColor, range: match.range)
            }
        }

        if let commentPattern {
            let italicDescriptor = font.fontDescriptor.withSymbolicTraits(.italic)
            let commentFont = NSFont(descriptor: italicDescriptor, size: font.pointSize) ?? font
            for match in commentPattern.matches(in: code, options: [], range: fullRange) {
                result.addAttribute(.foregroundColor, value: commentColor, range: match.range)
                result.addAttribute(.font, value: commentFont, range: match.range)
            }
        }

        return result
    }
}

private enum DocumentAttributedStringBuilder {
    static func build(
        source: String,
        fontSize: CGFloat,
        readingFont: ReadingFont,
        headingFont: ReadingFont
    ) -> NSAttributedString {
        let blocks = MarkdownParser.parse(source)
        let result = NSMutableAttributedString()

        for (index, block) in blocks.enumerated() {
            let isFirst = (index == 0)
            let isLast = (index == blocks.count - 1)

            switch block {
            case let .heading(level, text):
                let headSize = headingSize(level, baseSize: fontSize)
                let pStyle = NSMutableParagraphStyle()
                pStyle.lineSpacing = max(2.0, round(headSize * 0.14))

                let spaceAfter: CGFloat
                let spaceBefore: CGFloat
                switch level {
                case 1:
                    spaceAfter = round(headSize * 0.45)
                    spaceBefore = round(headSize * 1.05)
                case 2:
                    spaceAfter = round(headSize * 0.40)
                    spaceBefore = round(headSize * 0.92)
                case 3:
                    spaceAfter = round(headSize * 0.36)
                    spaceBefore = round(headSize * 0.82)
                case 4:
                    spaceAfter = round(headSize * 0.32)
                    spaceBefore = round(headSize * 0.72)
                case 5:
                    spaceAfter = round(headSize * 0.30)
                    spaceBefore = round(headSize * 0.60)
                default:
                    spaceAfter = round(headSize * 0.28)
                    spaceBefore = round(headSize * 0.55)
                }

                pStyle.paragraphSpacing = spaceAfter
                if !isFirst {
                    pStyle.paragraphSpacingBefore = spaceBefore
                }

                let weight: NSFont.Weight = .semibold

                let attr = buildInline(
                    source: text,
                    fontSize: headSize,
                    weight: weight,
                    font: headingFont,
                    textColor: .labelColor,
                    paragraphStyle: pStyle
                )
                result.append(attr)
                if !isLast {
                    result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: pStyle]))
                }

            case let .paragraph(text):
                let pStyle = NSMutableParagraphStyle()
                pStyle.lineSpacing = round(fontSize * 0.52)
                pStyle.paragraphSpacing = round(fontSize * 1.15)
                let attr = buildInline(
                    source: text,
                    fontSize: fontSize,
                    weight: .light,
                    font: readingFont,
                    textColor: .labelColor,
                    paragraphStyle: pStyle
                )
                result.append(attr)
                if !isLast {
                    result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: pStyle]))
                }

            case let .quote(text):
                let pStyle = NSMutableParagraphStyle()
                pStyle.lineSpacing = round(fontSize * 0.52)
                pStyle.paragraphSpacing = round(fontSize * 1.05)
                if !isFirst {
                    pStyle.paragraphSpacingBefore = round(fontSize * 0.85)
                }
                pStyle.headIndent = 20
                pStyle.firstLineHeadIndent = 20
                let quoteStartIndex = result.length
                let attr = buildInline(
                    source: text,
                    fontSize: fontSize,
                    weight: .light,
                    font: readingFont,
                    textColor: .labelColor.withAlphaComponent(0.88),
                    paragraphStyle: pStyle,
                    isItalicDefault: true
                )
                result.append(attr)
                let quoteLength = result.length - quoteStartIndex
                result.addAttribute(.blockQuote, value: true, range: NSRange(location: quoteStartIndex, length: quoteLength))
                if !isLast {
                    result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: pStyle]))
                }

            case let .code(language, text):
                let codeSize = max(11.5, round(fontSize * 0.84))
                let codeFont = NSFont.monospacedSystemFont(ofSize: codeSize, weight: .regular)
                let hasLanguage = (language != nil && !language!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                let blockStartIndex = result.length
                let codeLineSpacing = max(2.5, round(codeSize * 0.32))

                if hasLanguage, let language {
                    let langPStyle = NSMutableParagraphStyle()
                    langPStyle.lineSpacing = 2
                    langPStyle.paragraphSpacing = 6
                    if !isFirst {
                        langPStyle.paragraphSpacingBefore = round(fontSize * 1.15)
                    }
                    langPStyle.headIndent = 16
                    langPStyle.firstLineHeadIndent = 16
                    langPStyle.tailIndent = -16

                    let cleanLang = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let langAttr = NSAttributedString(
                        string: cleanLang + "\n",
                        attributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: max(10, round(codeSize * 0.82)), weight: .medium),
                            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.70),
                            .paragraphStyle: langPStyle
                        ]
                    )
                    result.append(langAttr)
                }

                let pStyle = NSMutableParagraphStyle()
                pStyle.lineSpacing = codeLineSpacing
                pStyle.paragraphSpacing = 0
                if !hasLanguage && !isFirst {
                    pStyle.paragraphSpacingBefore = round(fontSize * 1.15)
                }
                pStyle.headIndent = 16
                pStyle.firstLineHeadIndent = 16
                pStyle.tailIndent = -16

                let highlightedCode = NSMutableAttributedString(
                    attributedString: CodeHighlighter.highlight(
                        code: text,
                        font: codeFont,
                        paragraphStyle: pStyle
                    )
                )

                let fullCodeStr = highlightedCode.string as NSString
                let lastLinePStyle = NSMutableParagraphStyle()
                lastLinePStyle.lineSpacing = codeLineSpacing
                lastLinePStyle.paragraphSpacing = isLast ? 8 : round(fontSize * 1.25)
                if !hasLanguage && !isFirst && !text.contains("\n") {
                    lastLinePStyle.paragraphSpacingBefore = round(fontSize * 1.15)
                }
                lastLinePStyle.headIndent = 16
                lastLinePStyle.firstLineHeadIndent = 16
                lastLinePStyle.tailIndent = -16

                if let lastNewlineIndex = highlightedCode.string.lastIndex(of: "\n") {
                    let utf16Offset = highlightedCode.string.utf16.distance(from: highlightedCode.string.startIndex, to: lastNewlineIndex) + 1
                    let lastLineRange = NSRange(location: utf16Offset, length: fullCodeStr.length - utf16Offset)
                    highlightedCode.addAttribute(.paragraphStyle, value: lastLinePStyle, range: lastLineRange)
                } else {
                    let lastLineRange = NSRange(location: 0, length: fullCodeStr.length)
                    highlightedCode.addAttribute(.paragraphStyle, value: lastLinePStyle, range: lastLineRange)
                }

                result.append(highlightedCode)

                let blockLength = result.length - blockStartIndex
                let blockRange = NSRange(location: blockStartIndex, length: blockLength)
                result.addAttribute(.codeBlock, value: true, range: blockRange)

                result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: lastLinePStyle]))

            case let .list(ordered, start, items):
                let indent = max(24.0, round(fontSize * 1.6))
                for (itemIndex, item) in items.enumerated() {
                    let pStyle = NSMutableParagraphStyle()
                    pStyle.lineSpacing = round(fontSize * 0.46)
                    pStyle.headIndent = indent
                    pStyle.firstLineHeadIndent = 0
                    pStyle.tabStops = [NSTextTab(textAlignment: .left, location: indent, options: [:])]
                    if itemIndex == 0 && !isFirst {
                        pStyle.paragraphSpacingBefore = round(fontSize * 0.70)
                    }
                    pStyle.paragraphSpacing = (itemIndex == items.count - 1 && !isLast) ? round(fontSize * 1.15) : round(fontSize * 0.42)

                    let bullet = ordered ? "\(start + itemIndex)." : "•"
                    let bulletSize = ordered ? fontSize : round(fontSize * 1.18)
                    let bulletWeight: NSFont.Weight = ordered ? .medium : .medium
                    let bulletAttr = NSAttributedString(
                        string: "\(bullet)\t",
                        attributes: [
                            .font: readingFont.nsFont(size: bulletSize, weight: bulletWeight),
                            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.92),
                            .paragraphStyle: pStyle
                        ]
                    )
                    let itemAttr = buildInline(
                        source: item,
                        fontSize: fontSize,
                        weight: .light,
                        font: readingFont,
                        textColor: .labelColor,
                        paragraphStyle: pStyle
                    )

                    result.append(bulletAttr)
                    result.append(itemAttr)
                    if !(isLast && itemIndex == items.count - 1) {
                        result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: pStyle]))
                    }
                }

            case let .table(table):
                appendTable(table, to: result, fontSize: fontSize, readingFont: readingFont,
                            isLast: isLast)

            case .rule:
                let pStyle = NSMutableParagraphStyle()
                pStyle.paragraphSpacing = round(fontSize * 1.4)
                pStyle.paragraphSpacingBefore = round(fontSize * 1.4)
                result.append(NSAttributedString(string: "\u{2002}", attributes: [
                    .font: NSFont.systemFont(ofSize: max(fontSize, 14)),
                    .paragraphStyle: pStyle,
                    .divider: true
                ]))
                if !isLast {
                    result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: pStyle]))
                }
            }
        }

        return result
    }

    private static func appendTable(
        _ markdownTable: MarkdownTable,
        to result: NSMutableAttributedString,
        fontSize: CGFloat,
        readingFont: ReadingFont,
        isLast: Bool
    ) {
        let tableStart = result.length
        let table = NSTextTable()
        table.numberOfColumns = markdownTable.headers.count
        table.layoutAlgorithm = .automatic
        table.collapsesBorders = true
        table.setContentWidth(100, type: .percentage)

        let headerPadTop: CGFloat = 11.0
        let headerPadBottom: CGFloat = 9.0
        let bodyPadTop: CGFloat = 9.0
        let bodyPadBottom: CGFloat = 9.0
        let padX: CGFloat = 14.0
        let tableFontSize = round(fontSize * 0.90)

        let rows = [markdownTable.headers] + markdownTable.rows
        for (rowIndex, row) in rows.enumerated() {
            let rowStart = result.length
            let isHeader = (rowIndex == 0)
            for (columnIndex, source) in row.enumerated() {
                let cell = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1,
                                            startingColumn: columnIndex, columnSpan: 1)
                cell.setWidth(isHeader ? headerPadTop : bodyPadTop, type: .absolute, for: .padding, edge: .minY)
                cell.setWidth(isHeader ? headerPadBottom : bodyPadBottom, type: .absolute, for: .padding, edge: .maxY)
                cell.setWidth(padX, type: .absolute, for: .padding, edge: .minX)
                cell.setWidth(padX, type: .absolute, for: .padding, edge: .maxX)
                cell.verticalAlignment = .middle

                if rowIndex < rows.count - 1 {
                    cell.setWidth(isHeader ? 0.75 : 0.5, type: .absolute, for: .border, edge: .maxY)
                    cell.setBorderColor(
                        NSColor.separatorColor.withAlphaComponent(isHeader ? 0.35 : 0.16),
                        for: .maxY
                    )
                }

                let style = NSMutableParagraphStyle()
                style.textBlocks = [cell]
                style.lineSpacing = max(2.0, round(tableFontSize * 0.22))
                style.alignment = switch markdownTable.alignments[columnIndex] {
                case .leading: .left
                case .center: .center
                case .trailing: .right
                }

                let cellAttr = buildInline(
                    source: source.isEmpty ? "\u{200B}" : source,
                    fontSize: tableFontSize,
                    weight: isHeader ? .semibold : .regular,
                    font: readingFont,
                    textColor: isHeader ? NSColor.labelColor.withAlphaComponent(0.85) : NSColor.labelColor.withAlphaComponent(0.92),
                    paragraphStyle: style,
                    inlineCodeColor: NSColor.labelColor.withAlphaComponent(0.88)
                )
                result.append(cellAttr)
                result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
            }
            if rowIndex == 0 {
                result.addAttribute(.tableHeader, value: true,
                                    range: NSRange(location: rowStart, length: result.length - rowStart))
            }
        }
        result.addAttribute(.tableGroup, value: true,
                            range: NSRange(location: tableStart, length: result.length - tableStart))
        if !isLast {
            let spacer = NSMutableParagraphStyle()
            spacer.paragraphSpacing = round(fontSize * 1.0)
            result.append(NSAttributedString(string: "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 1), .paragraphStyle: spacer
            ]))
        }
    }

    private static func headingSize(_ level: Int, baseSize: CGFloat) -> CGFloat {
        switch level {
        case 1: return round(baseSize * 2.125)
        case 2: return round(baseSize * 1.625)
        case 3: return round(baseSize * 1.3125)
        case 4: return round(baseSize * 1.125)
        case 5: return round(baseSize * 1.0)
        default: return round(baseSize * 0.90)
        }
    }

    private static func buildInline(
        source: String,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        font: ReadingFont,
        textColor: NSColor,
        paragraphStyle: NSParagraphStyle,
        isItalicDefault: Bool = false,
        inlineCodeColor: NSColor? = nil
    ) -> NSAttributedString {
        guard let swiftAttr = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            let fallbackFont = font.nsFont(size: fontSize, weight: weight, italic: isItalicDefault)
            return NSAttributedString(
                string: source,
                attributes: [
                    .font: fallbackFont,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]
            )
        }

        let result = NSMutableAttributedString()
        for run in swiftAttr.runs {
            let runString = String(swiftAttr[run.range].characters)
            var attributes: [NSAttributedString.Key: Any] = [:]

            let isEmphasisBold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            let isItalic = isItalicDefault || (run.inlinePresentationIntent?.contains(.emphasized) == true)
            let isCode = run.inlinePresentationIntent?.contains(.code) == true
            let isStrikethrough = run.inlinePresentationIntent?.contains(.strikethrough) == true

            if isCode {
                let codeFont = NSFont.monospacedSystemFont(ofSize: round(fontSize * 0.88), weight: .regular)
                attributes[.font] = codeFont
                attributes[.inlineCode] = true
                if run.link == nil {
                    attributes[.foregroundColor] = inlineCodeColor ?? NSColor.labelColor
                }
                attributes[.paragraphStyle] = paragraphStyle

                let outerSpacer = NSAttributedString(string: "\u{2009}", attributes: [
                    .font: font.nsFont(size: fontSize, weight: weight, italic: isItalicDefault),
                    .paragraphStyle: paragraphStyle
                ])
                result.append(outerSpacer)
                result.append(NSAttributedString(string: runString, attributes: attributes))
                result.append(outerSpacer)
                continue
            } else {
                let resolvedWeight: NSFont.Weight
                if isEmphasisBold {
                    resolvedWeight = (weight == .light) ? .semibold : .bold
                } else {
                    resolvedWeight = weight
                }
                let fontChoice = font.nsFont(
                    size: fontSize,
                    weight: resolvedWeight,
                    italic: isItalic
                )
                attributes[.font] = fontChoice
            }

            if let link = run.link {
                attributes[.foregroundColor] = NSColor.controlAccentColor
                attributes[.link] = link
            } else {
                attributes[.foregroundColor] = textColor
            }

            if isStrikethrough {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }

            attributes[.paragraphStyle] = paragraphStyle
            result.append(NSAttributedString(string: runString, attributes: attributes))
        }

        return result
    }
}

private final class HoverableDocumentTextView: NSTextView, NSTextViewDelegate {
    var lastSource: String?
    var lastFontSize: CGFloat?
    var lastReadingFont: ReadingFont?
    var lastHeadingFont: ReadingFont?
    var currentFileURL: URL?
    var documentWindow: NSWindow?

    private var trackingAreaRef: NSTrackingArea?
    private var hoveredRange: NSRange?
    private var baseAttributedString: NSAttributedString?

    override var acceptsFirstResponder: Bool { true }

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: textContainer)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        self.delegate = self
        self.isEditable = false
        self.isSelectable = true
        self.drawsBackground = false
        self.backgroundColor = .clear
        self.textContainerInset = .zero
        self.textContainer?.lineFragmentPadding = 0
        self.isHorizontallyResizable = false
        self.isVerticallyResizable = true
        self.autoresizingMask = [.width]
        self.linkTextAttributes = [:]
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingAreaRef = area
    }


    func setDocumentContent(_ attributedString: NSAttributedString) {
        clearLinkHover()
        self.baseAttributedString = attributedString
        self.hoveredRange = nil
        self.textStorage?.setAttributedString(attributedString)
        self.needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard let source = lastSource, let fontSize = lastFontSize,
              let readingFont = lastReadingFont, let headingFont = lastHeadingFont else { return }
        let selection = selectedRanges
        effectiveAppearance.performAsCurrentDrawingAppearance {
            setDocumentContent(DocumentAttributedStringBuilder.build(
                source: source, fontSize: fontSize,
                readingFont: readingFont, headingFont: headingFont
            ))
        }
        selectedRanges = selection
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawTableCards()
        drawBlockQuotes()
        drawCodeBlockCards()
        drawInlineCodePills()
        drawDividers()
        super.draw(dirtyRect)
    }

    private func drawDividers() {
        guard let layoutManager, let textContainer, let textStorage,
              textStorage.length > 0 else { return }
        textStorage.enumerateAttribute(.divider, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, _ in
            guard value != nil else { return }
            layoutManager.ensureLayout(forCharacterRange: range)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let containerWidth = min(textContainer.containerSize.width, bounds.width)
            let width = min(88, containerWidth * 0.22)
            let rect = NSRect(x: textContainerOrigin.x + (containerWidth - width) / 2,
                              y: line.midY + textContainerOrigin.y,
                              width: width, height: 1.5)
            NSColor.secondaryLabelColor.withAlphaComponent(0.42).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 0.75, yRadius: 0.75).fill()
        }
    }

    private func drawTableCards() {
        guard let layoutManager, let textContainer, let textStorage,
              textStorage.length > 0 else { return }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let headerPadTop: CGFloat = 11.0
        let headerPadBottom: CGFloat = 9.0
        let bodyPadBottom: CGFloat = 9.0

        textStorage.enumerateAttribute(.tableGroup, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, _ in
            guard value != nil else { return }
            layoutManager.ensureLayout(forCharacterRange: range)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            var tableMinY: CGFloat = .infinity
            var tableMaxY: CGFloat = 0
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
                tableMinY = min(tableMinY, rect.minY)
                tableMaxY = max(tableMaxY, rect.maxY)
            }
            guard tableMinY.isFinite && tableMaxY > tableMinY else { return }

            let containerWidth = textContainer.containerSize.width > 0 ? textContainer.containerSize.width : bounds.width
            let width = min(containerWidth, bounds.width)

            var headerRange = NSRange()
            let hasHeader = (textStorage.attribute(.tableHeader, at: range.location, effectiveRange: &headerRange) != nil)
            let isHeaderOnly = hasHeader && (headerRange.length == range.length)
            let effectiveBottomPad = isHeaderOnly ? headerPadBottom : bodyPadBottom

            let cardTop = tableMinY + textContainerOrigin.y - headerPadTop
            let cardBottom = tableMaxY + textContainerOrigin.y + effectiveBottomPad
            let cardHeight = cardBottom - cardTop

            let cardRect = NSRect(
                x: textContainerOrigin.x,
                y: cardTop,
                width: width,
                height: cardHeight
            )

            let cornerRadius: CGFloat = 8.0
            let path = NSBezierPath(roundedRect: cardRect, xRadius: cornerRadius, yRadius: cornerRadius)

            // 1. Base table card background fill
            let cardBg = isDark
                ? NSColor.white.withAlphaComponent(0.035)
                : NSColor.black.withAlphaComponent(0.02)
            cardBg.setFill()
            path.fill()

            // 2. Header row background (clipped cleanly to the top rounded corners)
            if hasHeader {
                let headerGlyphs = layoutManager.glyphRange(forCharacterRange: headerRange, actualCharacterRange: nil)
                if headerGlyphs.length > 0 {
                    var hMinY: CGFloat = .infinity
                    var hMaxY: CGFloat = 0
                    layoutManager.enumerateLineFragments(forGlyphRange: headerGlyphs) { rect, _, _, _, _ in
                        hMinY = min(hMinY, rect.minY)
                        hMaxY = max(hMaxY, rect.maxY)
                    }
                    if hMinY.isFinite && hMaxY > hMinY {
                        let headerTop = hMinY + textContainerOrigin.y - headerPadTop
                        let headerBottom = hMaxY + textContainerOrigin.y + headerPadBottom
                        let headerHeight = headerBottom - headerTop
                        let headerDrawRect = NSRect(
                            x: cardRect.minX,
                            y: headerTop,
                            width: cardRect.width,
                            height: headerHeight
                        )
                        NSGraphicsContext.saveGraphicsState()
                        path.addClip()
                        let headerBg = isDark
                            ? NSColor.white.withAlphaComponent(0.06)
                            : NSColor.black.withAlphaComponent(0.04)
                        headerBg.setFill()
                        headerDrawRect.fill()
                        NSGraphicsContext.restoreGraphicsState()
                    }
                }
            }

            // 3. Card outline border
            let strokeColor = isDark
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.separatorColor.withAlphaComponent(0.35)
            strokeColor.setStroke()
            path.lineWidth = 0.75
            path.stroke()
        }
    }

    private func drawBlockQuotes() {
        guard let layoutManager = self.layoutManager,
              let textContainer = self.textContainer,
              let textStorage = self.textStorage,
              textStorage.length > 0 else { return }

        textStorage.enumerateAttribute(.blockQuote, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            layoutManager.ensureLayout(forCharacterRange: range)
            let blockRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            let barWidth: CGFloat = 3.0
            let barX = textContainerOrigin.x + 2.0
            let barY = blockRect.origin.y + textContainerOrigin.y + 1.0
            let barHeight = max(blockRect.size.height - 2.0, 8.0)
            let barRect = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)

            let path = NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5)

            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let barColor = isDark
                ? NSColor.controlAccentColor.withAlphaComponent(0.85)
                : NSColor.controlAccentColor.withAlphaComponent(0.75)
            barColor.setFill()
            path.fill()
        }
    }

    private func drawCodeBlockCards() {
        guard let layoutManager = self.layoutManager,
              let textContainer = self.textContainer,
              let textStorage = self.textStorage,
              textStorage.length > 0 else { return }

        textStorage.enumerateAttribute(.codeBlock, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            layoutManager.ensureLayout(forCharacterRange: range)
            let blockRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let containerWidth = textContainer.containerSize.width > 0 ? textContainer.containerSize.width : bounds.width

            let topPadding: CGFloat = 10
            let bottomPadding: CGFloat = 10
            let cardRect = NSRect(
                x: textContainerOrigin.x,
                y: blockRect.origin.y + textContainerOrigin.y - topPadding,
                width: containerWidth,
                height: blockRect.size.height + topPadding + bottomPadding
            )

            let path = NSBezierPath(roundedRect: cardRect, xRadius: 8, yRadius: 8)

            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let bgColor = isDark
                ? NSColor(white: 0.12, alpha: 0.70)
                : NSColor(white: 0.96, alpha: 0.85)
            bgColor.setFill()
            path.fill()

            let borderColor = isDark
                ? NSColor(white: 1.0, alpha: 0.08)
                : NSColor(white: 0.0, alpha: 0.06)
            borderColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
    }

    private func drawInlineCodePills() {
        guard let layoutManager = self.layoutManager,
              let textContainer = self.textContainer,
              let textStorage = self.textStorage,
              textStorage.length > 0 else { return }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let bgColor = isDark
            ? NSColor(white: 1.0, alpha: 0.08)
            : NSColor(white: 0.0, alpha: 0.045)
        let borderColor = isDark
            ? NSColor(white: 1.0, alpha: 0.07)
            : NSColor(white: 0.0, alpha: 0.06)

        textStorage.enumerateAttribute(.inlineCode, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, _ in
            guard value != nil else { return }
            layoutManager.ensureLayout(forCharacterRange: range)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            guard let codeFont = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return }
            let verticalPadding: CGFloat = 2.0
            let pillHeight = codeFont.ascender - codeFont.descender + 2 * verticalPadding
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, lineGlyphRange, _ in
                let segment = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard segment.length > 0 else { return }
                // Selection rects can cover the full line at a wrap, including
                // the list gutter. A per-line glyph bound follows the text.
                let glyphRect = layoutManager.boundingRect(forGlyphRange: segment, in: textContainer)
                guard glyphRect.width > 0 else { return }
                let left = max(0, glyphRect.minX - 2.5)
                let right = min(textContainer.containerSize.width, glyphRect.maxX + 2.5)
                guard right > left else { return }
                // Line fragments include leading and can have different heights
                // on wrapped lines. The code glyph baseline is the stable anchor.
                let baselineY = lineRect.minY + layoutManager.location(forGlyphAt: segment.location).y
                let pillRect = NSRect(
                    x: left + self.textContainerOrigin.x,
                    y: baselineY + self.textContainerOrigin.y - codeFont.ascender - verticalPadding,
                    width: right - left,
                    height: pillHeight
                )
                let path = NSBezierPath(roundedRect: pillRect, xRadius: 3.5, yRadius: 3.5)
                bgColor.setFill()
                path.fill()

                borderColor.setStroke()
                path.lineWidth = 0.5
                path.stroke()
            }
        }
    }

    private func linkRange(at event: NSEvent) -> NSRange? {
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        guard let textContainer, let layoutManager, let textStorage,
              textStorage.length > 0 else { return nil }
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs,
              layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                         in: textContainer).contains(containerPoint) else { return nil }
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        guard character < textStorage.length else { return nil }
        var range = NSRange()
        return textStorage.attribute(.link, at: character, effectiveRange: &range) == nil ? nil : range
    }

    private func updateLinkHover(with event: NSEvent) {
        guard !isOverDocumentScroller(self, event: event) else {
            clearLinkHover()
            NSCursor.arrow.set()
            return
        }
        let range = linkRange(at: event)
        if range != hoveredRange {
            clearLinkHover()
            if let range {
                hoveredRange = range
                layoutManager?.addTemporaryAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.controlAccentColor
                ], forCharacterRange: range)
            }
        }
        (range == nil ? NSCursor.iBeam : NSCursor.pointingHand).set()
    }

    override func mouseMoved(with event: NSEvent) {
        updateLinkHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        clearLinkHover()
        NSCursor.arrow.set()
        super.mouseExited(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateLinkHover(with: event)
    }

    private func clearLinkHover() {
        guard let range = hoveredRange else { return }
        hoveredRange = nil
        layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: range)
        layoutManager?.removeTemporaryAttribute(.underlineColor, forCharacterRange: range)
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        return handleLinkClick(link)
    }

    private func handleLinkClick(_ rawLink: Any) -> Bool {
        let rawString: String
        if let url = rawLink as? URL {
            rawString = url.isFileURL ? url.path : (url.scheme != nil ? url.absoluteString : url.relativePath)
        } else if let str = rawLink as? String {
            rawString = str
        } else {
            return false
        }

        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let unescaped = trimmed.removingPercentEncoding ?? trimmed

        // 1. Web, Email, and custom URL schemes
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "feed", "tel"].contains(scheme) {
            NSWorkspace.shared.open(url)
            return true
        }

        // 2. Resolve local file path
        let resolvedURL: URL
        if trimmed.lowercased().hasPrefix("file://") {
            if let url = URL(string: trimmed) {
                resolvedURL = URL(fileURLWithPath: url.path)
            } else {
                let pathWithoutScheme = String(trimmed.dropFirst(7))
                resolvedURL = URL(fileURLWithPath: pathWithoutScheme.removingPercentEncoding ?? pathWithoutScheme)
            }
        } else {
            let expandedPath = (unescaped as NSString).expandingTildeInPath
            if expandedPath.hasPrefix("/") {
                let directURL = URL(fileURLWithPath: expandedPath)
                if !FileManager.default.fileExists(atPath: directURL.path) && FileManager.default.fileExists(atPath: directURL.path + ".md") {
                    resolvedURL = URL(fileURLWithPath: directURL.path + ".md")
                } else {
                    resolvedURL = directURL
                }
            } else if let currentFileURL {
                let baseDir = currentFileURL.deletingLastPathComponent()
                let directURL = baseDir.appendingPathComponent(unescaped).standardizedFileURL
                if !FileManager.default.fileExists(atPath: directURL.path) && FileManager.default.fileExists(atPath: directURL.path + ".md") {
                    resolvedURL = baseDir.appendingPathComponent(unescaped + ".md").standardizedFileURL
                } else {
                    resolvedURL = directURL
                }
            } else {
                let directURL = URL(fileURLWithPath: expandedPath)
                resolvedURL = directURL
            }
        }

        // 3. Open markdown file in Lightmark or external file in default app
        let ext = resolvedURL.pathExtension.lowercased()
        let markdownExtensions = ["md", "markdown", "mdown", "mkdn", "text", "txt"]

        if markdownExtensions.contains(ext) || (!FileManager.default.fileExists(atPath: resolvedURL.path) && FileManager.default.fileExists(atPath: resolvedURL.path + ".md")) {
            let targetURL = markdownExtensions.contains(ext) ? resolvedURL : URL(fileURLWithPath: resolvedURL.path + ".md")
            let targetWindow = documentWindow ?? window ?? NSApp.keyWindow
            if let targetWindow, DocumentTabs.shared.openFileInEmptyTab(targetURL, window: targetWindow) {
                return true
            }
            DocumentTabs.shared.openDocument(withContentsOf: targetURL, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
            return true
        } else {
            NSWorkspace.shared.open(resolvedURL)
            return true
        }
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

    var body: some View {
        ReadingView(source: sample)
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
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Developer") {
            Button("Show Design Preview") { openWindow(value: "design-preview") }
        }
    }
}
#endif
