import AppKit
import SwiftUI

/// Custom document tabs backed by document windows. The incoming window is
/// raised before the outgoing one is hidden to keep a continuous visual frame.
@MainActor
final class DocumentTabs: NSObject, ObservableObject {
    static let shared = DocumentTabs()

    struct Item: Identifiable {
        let id: ObjectIdentifier
        let window: NSWindow
        let title: String
        let isSelected: Bool
        let isEdited: Bool
        let fileURL: URL?
    }

    @Published private(set) var items: [Item] = []

    private var windows: [NSWindow] = []
    private weak var selectedWindow: NSWindow?
    private var closingObserver: NSObjectProtocol?
    private var keyObserver: NSObjectProtocol?
    private var isPreparingDocument = false
    private var isActivating = false
    private let closedWindows = NSHashTable<NSWindow>.weakObjects()

    private func document(for window: NSWindow) -> NSDocument? {
        (window.windowController?.document as? NSDocument)
            ?? NSDocumentController.shared.document(for: window)
    }

    private override init() {
        super.init()
        closingObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.removeClosedWindow(window) }
        }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                guard let self, !self.isPreparingDocument, !self.isActivating,
                      self.windows.contains(where: { $0 === window }) else { return }
                if self.selectedWindow !== window {
                    self.activate(window)
                } else {
                    for sibling in self.windows where sibling !== window { sibling.orderOut(nil) }
                }
            }
        }
    }

    isolated deinit {
        if let closingObserver { NotificationCenter.default.removeObserver(closingObserver) }
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
    }

    static let maxTabCount = 50

    /// Returns true if a window is an unedited, blank "New Tab" ready to be used.
    func isReadyNewTab(_ window: NSWindow) -> Bool {
        guard let doc = document(for: window) else {
            return window.representedURL == nil && !window.isDocumentEdited
        }
        return doc.fileURL == nil && !doc.isDocumentEdited && !window.isDocumentEdited
    }

    /// Finds the first existing ready-to-serve blank tab, if any.
    var readyNewTab: NSWindow? {
        windows.first { isReadyNewTab($0) }
    }

    /// Build the document UI before showing it. SwiftUI's newDocument action
    /// places its window after viewDidMoveToWindow, overriding the tab frame.
    @discardableResult
    func newTab() -> NSDocument? {
        // 1. If an empty, unedited New Tab is already open and ready, redirect to it!
        if let existing = readyNewTab {
            if selectedWindow !== existing {
                activate(existing)
            } else {
                existing.makeKeyAndOrderFront(nil)
            }
            return document(for: existing)
        }

        // 2. Prevent opening an absurd amount of tabs
        if windows.count >= DocumentTabs.maxTabCount {
            NSSound.beep()
            return nil
        }

        isPreparingDocument = true
        defer { isPreparingDocument = false }
        do {
            let document = try NSDocumentController.shared.openUntitledDocumentAndDisplay(false)
            if document.windowControllers.isEmpty { document.makeWindowControllers() }
            for controller in document.windowControllers {
                controller.shouldCascadeWindows = false
            }
            guard let window = document.windowControllers.first?.window else {
                document.close()
                throw NSError(domain: "Lightmark", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "The new document window could not be created."
                ])
            }
            window.contentView?.layoutSubtreeIfNeeded()
            isPreparingDocument = false
            register(window, mode: .tabbed)
            return document
        } catch {
            NSApp.presentError(error)
            return nil
        }
    }

    private typealias OpenCompletion = (NSDocument?, Bool, Error?) -> Void
    private var pendingOpens: [URL: [OpenCompletion]] = [:]

    /// File loading never presents a window in Tabs mode. Presentation belongs
    /// exclusively to this coordinator, after SwiftUI has finished layout.
    func openDocument(withContentsOf url: URL, display: Bool = true,
                      completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        if pendingOpens[canonicalURL] != nil {
            pendingOpens[canonicalURL]?.append(completionHandler)
            return
        }
        pendingOpens[canonicalURL] = [completionHandler]
        NSDocumentController.shared.openDocument(withContentsOf: canonicalURL, display: false) { [self] document, alreadyOpen, error in
            var presentationError = error
            if let document, error == nil, display {
                isPreparingDocument = true
                if document.windowControllers.isEmpty { document.makeWindowControllers() }
                let mode = WindowOpeningMode.from(stored: UserDefaults.standard.string(forKey: "windowOpeningMode") ?? "windows")
                for controller in document.windowControllers {
                    controller.shouldCascadeWindows = mode != .tabbed
                }
                if let window = document.windowControllers.first?.window {
                    window.contentView?.layoutSubtreeIfNeeded()
                    isPreparingDocument = false
                    if mode == .tabbed {
                        if windows.contains(where: { $0 === window }) {
                            activate(window)
                        } else {
                            register(window, mode: mode)
                        }
                    } else {
                        document.showWindows()
                        window.makeKeyAndOrderFront(nil)
                    }
                } else {
                    presentationError = CocoaError(.fileReadUnknown)
                }
                isPreparingDocument = false
            }
            if let document, presentationError == nil, let fileURL = document.fileURL {
                RecentDocumentsStore.shared.register(url: fileURL)
            }
            let callbacks = pendingOpens.removeValue(forKey: canonicalURL) ?? []
            for callback in callbacks { callback(document, alreadyOpen, presentationError) }
        }
    }

    private func activate(_ window: NSWindow) {
        guard !isActivating, !closedWindows.contains(window) else { return }
        isActivating = true
        defer { isActivating = false }
        if let previous = selectedWindow, previous !== window {
            window.setFrame(previous.frame, display: false)
        }
        selectedWindow = window
        window.animationBehavior = .none
        window.makeKeyAndOrderFront(nil)
        // Hide every sibling, including any window revealed by a system action.
        for sibling in windows where sibling !== window { sibling.orderOut(nil) }
        refresh()
    }

    func register(_ window: NSWindow, mode: WindowOpeningMode) {
        guard mode == .tabbed, !isPreparingDocument, !closedWindows.contains(window) else { return }
        if windows.count >= DocumentTabs.maxTabCount && !windows.contains(where: { $0 === window }) {
            NSSound.beep()
            return
        }
        window.animationBehavior = .none
        window.windowController?.shouldCascadeWindows = false
        guard !windows.contains(where: { $0 === window }) else {
            refresh()
            return
        }

        windows.append(window)
        activate(window)
    }

    func select(_ item: Item) {
        guard windows.contains(where: { $0 === item.window }) else { return }
        activate(item.window)
    }

    private var pendingCloses = Set<ObjectIdentifier>()

    func close(_ item: Item) {
        guard windows.contains(where: { $0 === item.window }) else { return }
        guard let document = document(for: item.window) else {
            item.window.performClose(nil)
            return
        }
        if !document.isDocumentEdited {
            document.close()
            return
        }
        let id = ObjectIdentifier(document)
        guard pendingCloses.insert(id).inserted else { return }
        // Unsaved documents need a visible window for their save/cancel sheet.
        if document.isDocumentEdited { activate(item.window) }
        document.canClose(withDelegate: self,
                          shouldClose: #selector(document(_:shouldClose:contextInfo:)),
                          contextInfo: nil)
    }

    @objc private func document(_ document: NSDocument, shouldClose: Bool,
                                contextInfo: UnsafeMutableRawPointer?) {
        defer { pendingCloses.remove(ObjectIdentifier(document)) }
        if shouldClose { document.close() }
    }

    /// A file chosen in a blank document replaces it in either window mode.
    /// Keep the window and controller in place so the surface never disappears.
    @discardableResult
    func openFileInEmptyTab(_ url: URL, window: NSWindow) -> Bool {
        guard let document = document(for: window),
              document.fileURL == nil, !document.isDocumentEdited else { return false }

        if let alreadyOpen = NSDocumentController.shared.document(for: url),
           alreadyOpen !== document,
           let existingWindow = alreadyOpen.windowControllers.first?.window {
            if let item = items.first(where: { $0.window === existingWindow }) {
                select(item)
            } else {
                existingWindow.makeKeyAndOrderFront(nil)
            }
            RecentDocumentsStore.shared.register(url: url)
            document.close()
            return true
        }

        do {
            let type = try NSDocumentController.shared.typeForContents(of: url)
            try document.read(from: url, ofType: type)
            document.fileType = type
            document.fileURL = url
            document.updateChangeCount(.changeCleared)
            window.representedURL = url
            window.title = url.lastPathComponent
            RecentDocumentsStore.shared.register(url: url)
            refresh()
        } catch {
            NSApp.presentError(error)
        }
        return true
    }

    private func resolveTabTitle(for window: NSWindow) -> String {
        if let url = window.representedURL {
            return url.lastPathComponent
        }
        if !window.title.isEmpty && window.title != "Untitled" {
            return window.title
        }
        return "New Tab"
    }

    func selectRelative(_ offset: Int) {
        guard windows.count > 1,
              let selectedWindow,
              let index = windows.firstIndex(where: { $0 === selectedWindow }) else { return }
        let nextIndex = (index + offset + windows.count) % windows.count
        let nextWindow = windows[nextIndex]
        let title = resolveTabTitle(for: nextWindow)
        select(Item(id: ObjectIdentifier(nextWindow), window: nextWindow, title: title,
                    isSelected: false, isEdited: nextWindow.isDocumentEdited,
                    fileURL: nextWindow.representedURL))
    }

    func refresh() {
        items = windows.map { window in
            let title = resolveTabTitle(for: window)
            return Item(id: ObjectIdentifier(window), window: window, title: title,
                        isSelected: window === selectedWindow, isEdited: document(for: window)?.isDocumentEdited ?? window.isDocumentEdited,
                        fileURL: window.representedURL)
        }
    }

    func changeMode(to mode: WindowOpeningMode) {
        let current = selectedWindow ?? NSApp.keyWindow
        if mode == .separateWindows {
            let groupedWindows = windows
            windows.removeAll()
            selectedWindow = nil
            refresh()
            var cascadePoint = current.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) } ?? .zero
            for window in groupedWindows where window !== current {
                window.windowController?.shouldCascadeWindows = true
                cascadePoint = window.cascadeTopLeft(from: cascadePoint)
                window.orderFront(nil)
            }
            current?.windowController?.shouldCascadeWindows = true
            current?.makeKeyAndOrderFront(nil)
            return
        }
        let documentWindows = NSApp.windows.filter {
            $0.tabbingIdentifier == "LightmarkDocument" && !$0.isMiniaturized
        }
        for window in documentWindows where !windows.contains(where: { $0 === window }) {
            register(window, mode: mode)
        }
        if let item = items.first(where: { $0.window === current }) { select(item) }
    }

    private func removeClosedWindow(_ window: NSWindow) {
        closedWindows.add(window)
        guard let index = windows.firstIndex(where: { $0 === window }) else { return }
        windows.remove(at: index)
        if selectedWindow === window {
            let next = windows.isEmpty ? nil : windows[min(index, windows.count - 1)]
            selectedWindow = next
            if let next {
                next.setFrame(window.frame, display: false)
                next.makeKeyAndOrderFront(nil)
            }
        }
        withAnimation(.snappy(duration: 0.20, extraBounce: 0)) {
            refresh()
        }
    }
}

private final class NonVisibleScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 0 }
    override func draw(_ dirtyRect: NSRect) {}
    override func drawKnob() {}
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override init(frame frameRect: NSRect) {
        super.init(frame: .zero)
        self.isHidden = true
        self.alphaValue = 0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.isHidden = true
        self.alphaValue = 0
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct TabScrollViewConfigurator: NSViewRepresentable {
    let onAttach: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView {
                onAttach(scrollView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let scrollView = nsView.enclosingScrollView {
                onAttach(scrollView)
            }
        }
    }
}

@MainActor
final class TabScrollController: ObservableObject {
    weak var scrollView: NSScrollView?
    @Published var scrollOffset: CGFloat = 0
    @Published var contentWidth: CGFloat = 0
    @Published var isDragging: Bool = false
    private var boundsObserver: NSObjectProtocol?
    private var frameObserver: NSObjectProtocol?

    func attach(to scrollView: NSScrollView) {
        suppressNativeScroller(scrollView)
        if self.scrollView === scrollView {
            updateMetrics()
            return
        }
        self.scrollView = scrollView

        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        clipView.postsFrameChangedNotifications = true

        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }

        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMetrics() }
        }

        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMetrics() }
        }

        updateMetrics()
    }

    func suppressNativeScroller(_ scrollView: NSScrollView) {
        scrollView.hasHorizontalScroller = false
        if !(scrollView.horizontalScroller is NonVisibleScroller) {
            scrollView.horizontalScroller = NonVisibleScroller()
        }
        scrollView.hasVerticalScroller = false
        if !(scrollView.verticalScroller is NonVisibleScroller) {
            scrollView.verticalScroller = NonVisibleScroller()
        }
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        for subview in scrollView.subviews {
            if let scroller = subview as? NSScroller, !(scroller is NonVisibleScroller) {
                scroller.isHidden = true
                scroller.alphaValue = 0
                scroller.removeFromSuperview()
            }
        }
    }

    func updateMetrics() {
        guard let scrollView else { return }
        suppressNativeScroller(scrollView)
        let clipView = scrollView.contentView
        let newOffset = max(0, clipView.bounds.origin.x)
        let docWidth = scrollView.documentView?.frame.size.width ?? 0

        if !isDragging && abs(scrollOffset - newOffset) > 0.5 {
            scrollOffset = newOffset
        }
        if docWidth > 0 && abs(contentWidth - docWidth) > 0.5 {
            contentWidth = docWidth
        }
    }

    func scrollTo(offset: CGFloat) {
        guard let scrollView else { return }
        let clipView = scrollView.contentView
        let maxOffset = max(0, (scrollView.documentView?.frame.size.width ?? contentWidth) - clipView.bounds.size.width)
        let clamped = max(0, min(offset, maxOffset))
        clipView.scroll(to: NSPoint(x: clamped, y: 0))
        scrollView.reflectScrolledClipView(clipView)
        scrollOffset = clamped
    }
}

private struct CustomTabScrollBar: View {
    @ObservedObject var controller: TabScrollController
    @State private var isHovering = false
    @State private var dragStartOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let availableWidth = max(0, geo.size.width)
            let isOverflowing = controller.contentWidth > (availableWidth + 1)
            let maxScroll = max(1.0, controller.contentWidth - availableWidth)
            let ratio = controller.contentWidth > 0 ? min(1.0, availableWidth / controller.contentWidth) : 1.0
            let thumbWidth = max(36.0, availableWidth * ratio)
            let travel = max(1.0, availableWidth - thumbWidth)
            let progress = max(0.0, min(1.0, controller.scrollOffset / maxScroll))
            let thumbOffset = travel * progress
            let isActive = isHovering || controller.isDragging
            let barHeight: CGFloat = isActive ? 5.5 : 3.5

            ZStack(alignment: .leading) {
                // Subtle track
                Capsule()
                    .fill(Color(nsColor: .separatorColor).opacity(isActive ? 0.22 : 0.08))
                    .frame(height: barHeight)

                // Sleek thumb (Apple-like feel)
                Capsule()
                    .fill(
                        controller.isDragging
                            ? Color(nsColor: .labelColor).opacity(0.65)
                            : (isHovering ? Color(nsColor: .labelColor).opacity(0.50) : Color(nsColor: .secondaryLabelColor).opacity(0.40))
                    )
                    .frame(width: thumbWidth, height: barHeight)
                    .offset(x: thumbOffset)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                    isHovering = hovering
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !controller.isDragging {
                            controller.isDragging = true
                            let startX = gesture.startLocation.x
                            let currentThumbStart = thumbOffset
                            let currentThumbEnd = currentThumbStart + thumbWidth

                            if startX < currentThumbStart || startX > currentThumbEnd {
                                let jumpedProgress = max(0.0, min(1.0, (startX - thumbWidth / 2) / travel))
                                let newOffset = jumpedProgress * maxScroll
                                controller.scrollTo(offset: newOffset)
                                dragStartOffset = newOffset
                            } else {
                                dragStartOffset = controller.scrollOffset
                            }
                        } else {
                            let deltaX = gesture.translation.width
                            let deltaOffset = (deltaX / travel) * maxScroll
                            controller.scrollTo(offset: dragStartOffset + deltaOffset)
                        }
                    }
                    .onEnded { _ in
                        controller.isDragging = false
                    }
            )
            .opacity(isOverflowing ? 1.0 : 0.0)
            .allowsHitTesting(isOverflowing)
            .animation(.easeInOut(duration: 0.2), value: isOverflowing)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isActive)
        }
    }
}

struct DocumentTabBar: View {
    @ObservedObject var tabs: DocumentTabs
    let fallbackTitle: String

    @StateObject private var scrollController = TabScrollController()

    private let tabSpacing: CGFloat = 5
    private let maxTabWidth: CGFloat = 230
    private let minTabWidth: CGFloat = 90

    private func computeTabWidth(availableWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return maxTabWidth }
        let effectiveCount = max(2, count)
        let totalSpacing = CGFloat(effectiveCount - 1) * tabSpacing
        let remaining = max(0, availableWidth - totalSpacing)
        let calculated = remaining / CGFloat(effectiveCount)
        return min(maxTabWidth, max(minTabWidth, calculated))
    }

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                let availableWidth = max(0, proxy.size.width)
                let tabWidth = computeTabWidth(availableWidth: availableWidth, count: tabs.items.count)

                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: tabSpacing) {
                            if tabs.items.isEmpty {
                                Text(fallbackTitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 14)
                            } else {
                                ForEach(tabs.items) { item in
                                    DocumentTab(
                                        item: item,
                                        width: tabWidth,
                                        select: {
                                            tabs.select(item)
                                            scrollProxy.scrollTo(item.id, anchor: nil)
                                        },
                                        close: { tabs.close(item) }
                                    )
                                    .id(item.id)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                        removal: .opacity.combined(with: .scale(scale: 0.88))
                                    ))
                                }
                            }
                        }
                        .animation(.snappy(duration: 0.22, extraBounce: 0.0), value: tabs.items.map(\.id))
                        .padding(.vertical, 2)
                        .background(
                            GeometryReader { contentGeo in
                                Color.clear.preference(
                                    key: TabScrollPreferenceKey.self,
                                    value: TabScrollPreferenceData(
                                        contentWidth: contentGeo.size.width,
                                        minX: contentGeo.frame(in: .named("TabScrollViewSpace")).minX
                                    )
                                )
                            }
                        )
                        .background(
                            TabScrollViewConfigurator { scrollView in
                                scrollController.attach(to: scrollView)
                            }
                        )
                    }
                    .coordinateSpace(name: "TabScrollViewSpace")
                    .onPreferenceChange(TabScrollPreferenceKey.self) { data in
                        if scrollController.contentWidth == 0 || abs(scrollController.contentWidth - data.contentWidth) > 1 {
                            scrollController.contentWidth = data.contentWidth
                        }
                        if !scrollController.isDragging && abs(scrollController.scrollOffset - (-data.minX)) > 1 {
                            scrollController.scrollOffset = -data.minX
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onAppear {
                        if let selected = tabs.items.first(where: { $0.isSelected }) {
                            scrollProxy.scrollTo(selected.id, anchor: nil)
                        }
                    }
                    .onChange(of: availableWidth) { _, _ in
                        scrollController.updateMetrics()
                        if let selected = tabs.items.first(where: { $0.isSelected }) {
                            scrollProxy.scrollTo(selected.id, anchor: nil)
                        }
                    }
                    .onChange(of: tabs.items.first(where: { $0.isSelected })?.id) { _, selectedId in
                        if let selectedId {
                            scrollProxy.scrollTo(selectedId, anchor: nil)
                        }
                    }
                }
            }
            .frame(height: 40)
        }
        .padding(.leading, 88)
        .padding(.trailing, 14)
        .frame(height: 52)
        .overlay(alignment: .bottom) {
            CustomTabScrollBar(controller: scrollController)
                .padding(.leading, 88)
                .padding(.trailing, 14)
                .frame(height: 14)
                .offset(y: -1)
        }
    }
}

private struct TabScrollPreferenceData: Equatable, Sendable {
    let contentWidth: CGFloat
    let minX: CGFloat
}

private struct TabScrollPreferenceKey: PreferenceKey {
    static let defaultValue = TabScrollPreferenceData(contentWidth: 0, minX: 0)
    static func reduce(value: inout TabScrollPreferenceData, nextValue: () -> TabScrollPreferenceData) {
        let next = nextValue()
        if next.contentWidth > 0 {
            value = next
        }
    }
}

private struct DocumentTab: View {
    let item: DocumentTabs.Item
    let width: CGFloat
    let select: () -> Void
    let close: () -> Void
    @State private var isTabHovering = false
    @State private var isTitleHovering = false
    @State private var isCloseHovering = false
    @State private var isClosing = false

    private var isCompact: Bool {
        width < 120
    }

    private func handleClose() {
        guard !isClosing else { return }
        if item.isEdited {
            close()
            return
        }
        withAnimation(.easeOut(duration: 0.12)) {
            isClosing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            close()
        }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Main tab content area
            HStack(spacing: 0) {
                if item.isSelected {
                    if let fileURL = item.fileURL {
                        Button(action: {
                            DocumentActionHelper.triggerRenameOrSave(for: item.window, fileURL: fileURL)
                        }) {
                            tabTitleContent(hasChevron: true)
                                .padding(.horizontal, isCompact ? 5 : 7)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                        .fill(isTitleHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.60) : Color.clear)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                isTitleHovering = hovering
                            }
                        }
                        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isTitleHovering)
                        .accessibilityLabel("Document Title: \(item.title) — Click to rename or move")
                        .help("Document Title — Click to rename or move")
                    } else {
                        // Untitled / New tab: Static label, NOT clickable, no hover button, no chevron, no Finder modal
                        tabTitleContent(hasChevron: false)
                            .padding(.horizontal, isCompact ? 5 : 7)
                            .frame(height: 26)
                    }

                    Spacer(minLength: 0)
                } else {
                    Button(action: select) {
                        HStack(spacing: isCompact ? 4.5 : 6) {
                            if item.isEdited {
                                Circle()
                                    .fill(Color.secondary.opacity(0.85))
                                    .frame(width: 4.5, height: 4.5)
                                    .accessibilityLabel("Unsaved changes")
                            }

                            Image(systemName: "doc.text")
                                .font(.system(size: isCompact ? 10.5 : 11.5))
                                .foregroundStyle(isTabHovering ? Color.primary.opacity(0.80) : Color.secondary)

                            Text(item.title)
                                .font(.system(size: isCompact ? 11.5 : 12.5, weight: .medium))
                                .foregroundStyle(isTabHovering ? Color.primary : Color.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, isCompact ? 5 : 7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Switch to \(item.title)")
                    .help(item.fileURL?.path ?? item.title)
                }
            }
            .padding(.leading, 4.5)
            .padding(.trailing, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            // Close button pinned to trailing edge with equal 4.5pt margins
            Button(action: handleClose) {
                Image(systemName: "xmark")
                    .font(.system(size: isCompact ? 8 : 9, weight: .semibold))
                    .foregroundStyle(isCloseHovering ? Color.primary : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background {
                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                            .fill(isCloseHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.75) : Color.clear)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(TabCloseButtonStyle())
            .padding(.trailing, 4.5)
            .opacity(item.isSelected || isTabHovering || isCloseHovering ? 1 : 0.35)
            .onHover { isCloseHovering = $0 }
            .help("Close \(item.title)")
            .accessibilityLabel("Close \(item.title)")
        }
        .frame(width: width, height: 35)
        .scaleEffect(isClosing ? 0.88 : 1.0)
        .opacity(isClosing ? 0.0 : 1.0)
        .allowsHitTesting(!isClosing)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    item.isSelected
                        ? Color(nsColor: .controlBackgroundColor)
                        : (isTabHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.35) : Color(nsColor: .quaternaryLabelColor).opacity(0.18))
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    item.isSelected
                        ? Color(nsColor: .separatorColor).opacity(0.85)
                        : (isTabHovering ? Color(nsColor: .separatorColor).opacity(0.40) : Color(nsColor: .separatorColor).opacity(0.20)),
                    lineWidth: 0.8
                )
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                isTabHovering = hovering
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isTabHovering)

        .help(item.fileURL != nil ? (item.isSelected ? "Document Title — Click to rename or move" : (item.fileURL?.path ?? item.title)) : (item.isSelected ? "Click to save document" : item.title))
        .contextMenu {
            if item.fileURL != nil {
                Button("Rename or Move...") {
                    DocumentActionHelper.triggerRenameOrSave(for: item.window, fileURL: item.fileURL)
                }
                Button("Duplicate Document") {
                    DocumentActionHelper.triggerDuplicate(for: item.window, fileURL: item.fileURL)
                }
                Button("Save As...") {
                    DocumentActionHelper.triggerSaveAs(for: item.window, fileURL: item.fileURL)
                }

                Divider()

                Button("Show in Finder") {
                    if let fileURL = item.fileURL {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                }

                Button("Copy Full Path") {
                    if let fileURL = item.fileURL {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fileURL.path, forType: .string)
                    }
                }

                if let pathHierarchy = pathHierarchy(for: item.fileURL), !pathHierarchy.isEmpty {
                    Divider()
                    ForEach(pathHierarchy, id: \.url) { pathItem in
                        Button(action: {
                            NSWorkspace.shared.open(pathItem.url)
                        }) {
                            Label(pathItem.name, systemImage: "folder")
                        }
                    }
                }

                Divider()
            } else {
                Button("Save...") {
                    DocumentActionHelper.triggerRenameOrSave(for: item.window, fileURL: item.fileURL)
                }
                Divider()
            }
            Button("Close Tab") {
                handleClose()
            }
        }
    }

    private func tabTitleContent(hasChevron: Bool) -> some View {
        HStack(spacing: isCompact ? 4.5 : 6) {
            if item.isEdited {
                Circle()
                    .fill(Color.secondary.opacity(0.85))
                    .frame(width: 4.5, height: 4.5)
                    .accessibilityLabel("Unsaved changes")
            }

            Image(systemName: "doc.text")
                .font(.system(size: isCompact ? 10.5 : 11.5))
                .foregroundStyle(Color.primary.opacity(0.80))

            Text(item.title)
                .font(.system(size: isCompact ? 11.5 : 12.5, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if hasChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .opacity(isTitleHovering ? 1.0 : 0.0)
                    .scaleEffect(isTitleHovering ? 1.0 : 0.65)
                    .offset(x: isTitleHovering ? 0 : -3)
                    .padding(.leading, 1)
            }
        }
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

private struct TabCloseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1.0)
            .opacity(configuration.isPressed ? 0.65 : 1.0)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}
