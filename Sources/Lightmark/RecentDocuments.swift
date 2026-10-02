import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RecentFileItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let fileName: String
    let pathDisplay: String
    let previewSnippet: String
    let modifiedDate: Date?

    var timeAgoDisplay: String {
        guard let modifiedDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: modifiedDate, relativeTo: Date())
    }
}

@MainActor
final class RecentDocumentsStore: ObservableObject {
    static let shared = RecentDocumentsStore()

    @Published private(set) var recentItems: [RecentFileItem] = []

    private let userDefaultsKey = "LightmarkRecentFilePaths"

    init() {
        refresh()
    }

    func register(url: URL) {
        guard url.isFileURL else { return }
        var current = getStoredPaths()
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if current.first == path, recentItems.first?.id == path { return }
        current.removeAll(where: { $0 == path })
        current.insert(path, at: 0)
        if current.count > 20 {
            current = Array(current.prefix(20))
        }
        UserDefaults.standard.set(current, forKey: userDefaultsKey)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            refresh()
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        NSDocumentController.shared.clearRecentDocuments(nil)
        refresh()
    }

    func remove(url: URL) {
        var current = getStoredPaths()
        let path = url.standardizedFileURL.path
        current.removeAll(where: { $0 == path })
        UserDefaults.standard.set(current, forKey: userDefaultsKey)
        refresh()
    }

    func refresh() {
        var urls: [URL] = []
        let storedPaths = getStoredPaths()
        for path in storedPaths {
            let u = URL(fileURLWithPath: path)
            if !urls.contains(where: { $0.standardizedFileURL.path == u.standardizedFileURL.path }) {
                urls.append(u)
            }
        }
        for sysUrl in NSDocumentController.shared.recentDocumentURLs {
            if !urls.contains(where: { $0.standardizedFileURL.path == sysUrl.standardizedFileURL.path }) {
                urls.append(sysUrl)
            }
        }

        // Also check if project / bundle Welcome.md exists as sample if recents list is empty
        if urls.isEmpty {
            let currentDir = FileManager.default.currentDirectoryPath
            let candidatePaths = [
                currentDir + "/Examples/Welcome.md",
                currentDir + "/Welcome.md"
            ]
            for cp in candidatePaths where FileManager.default.fileExists(atPath: cp) {
                urls.append(URL(fileURLWithPath: cp))
            }
            if let welcome = Bundle.main.url(forResource: "Welcome", withExtension: "md") {
                if !urls.contains(where: { $0.standardizedFileURL.path == welcome.standardizedFileURL.path }) {
                    urls.append(welcome)
                }
            }
        }

        var items: [RecentFileItem] = []
        let fileManager = FileManager.default

        for url in urls.prefix(20) {
            guard fileManager.fileExists(atPath: url.path) else { continue }

            let fileName = url.lastPathComponent
            let folderURL = url.deletingLastPathComponent()
            let homePath = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
            let fullPath = folderURL.standardizedFileURL.path

            var components: [String] = []
            if fullPath == homePath {
                components = ["~"]
            } else if fullPath.hasPrefix(homePath) {
                let relative = String(fullPath.dropFirst(homePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let raw = relative.components(separatedBy: "/").filter { !$0.isEmpty }
                components = raw
            } else {
                components = folderURL.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            }

            let pathDisplay = components.isEmpty ? "~" : components.joined(separator: " › ")

            var snippet = ""
            var modifiedDate: Date?

            if let attrs = try? fileManager.attributesOfItem(atPath: url.path) {
                modifiedDate = attrs[.modificationDate] as? Date
            }

            if let handle = try? FileHandle(forReadingFrom: url) {
                let data = handle.readData(ofLength: 1500)
                try? handle.close()
                if let rawText = String(data: data, encoding: .utf8) {
                    let lines = rawText.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && !$0.hasPrefix("---") && !$0.hasPrefix("```") }
                    let clean = lines.prefix(2).map { line in
                        line.replacingOccurrences(of: #"^[#>\s\-\*\+]+|\*\*|\*|`|\[|\]\([^\)]*\)"#, with: "", options: .regularExpression)
                            .trimmingCharacters(in: .whitespaces)
                    }.filter { !$0.isEmpty }.joined(separator: " ")
                    snippet = clean
                }
            }

            items.append(
                RecentFileItem(
                    id: url.standardizedFileURL.path,
                    url: url,
                    fileName: fileName,
                    pathDisplay: pathDisplay,
                    previewSnippet: snippet,
                    modifiedDate: modifiedDate
                )
            )
        }

        self.recentItems = items
    }

    private func getStoredPaths() -> [String] {
        UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? []
    }
}

/// Compact horizontal row card for list view (clean without preview content snippet)
/// Compact horizontal row card for list view in the recents sidebar
struct RecentFileListRowView: View {
    let item: RecentFileItem
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                // Unified doc.text icon matching drag-and-drop zone
                Image(systemName: "doc.text")
                    .font(.system(size: 15.5, weight: .light))
                    .foregroundStyle(Color.accentColor.opacity(isHovering ? 1.0 : 0.85))
                    .frame(width: 20, height: 20)

                // Title & Path (with time ago / chevron hover swap in top right)
                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.fileName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 4)

                        ZStack(alignment: .trailing) {
                            if !item.timeAgoDisplay.isEmpty {
                                Text(item.timeAgoDisplay)
                                    .font(.system(size: 9.5, weight: .regular))
                                    .foregroundStyle(Color.secondary.opacity(0.65))
                                    .opacity(isHovering ? 0.0 : 1.0)
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(Color.secondary.opacity(0.85))
                                .opacity(isHovering ? 1.0 : 0.0)
                                .offset(x: isHovering ? 0 : -2)
                        }
                    }

                    HStack(spacing: 3.5) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.secondary.opacity(0.70))

                        Text(item.pathDisplay)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.secondary.opacity(0.75))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isHovering
                            ? (colorScheme == .dark
                                ? Color.white.opacity(0.08)
                                : Color.black.opacity(0.045))
                            : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        Color(nsColor: .separatorColor).opacity(
                            isHovering
                                ? (colorScheme == .dark ? 0.28 : 0.18)
                                : 0.0
                        ),
                        lineWidth: 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open Document") { onOpen() }
            Button("Open in Separate Window") {
                DocumentTabs.current.openDocument(withContentsOf: item.url, display: true) { _, _, _ in }
            }
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("Copy Full Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            Divider()
            Button("Remove from Suggestions") {
                RecentDocumentsStore.shared.remove(url: item.url)
            }
        }
    }
}

/// Grid card view displaying document content preview snippet as an elegant document tile
struct RecentFileCardView: View {
    let item: RecentFileItem
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var topBackground: Color {
        if colorScheme == .dark {
            return isHovering ? Color.white.opacity(0.075) : Color.white.opacity(0.04)
        } else {
            return isHovering ? Color.white : Color.white.opacity(0.95)
        }
    }

    private var bottomBackground: Color {
        if colorScheme == .dark {
            return isHovering ? Color.white.opacity(0.032) : Color.white.opacity(0.018)
        } else {
            return isHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.36) : Color(nsColor: .controlBackgroundColor).opacity(0.60)
        }
    }

    private var dividerColor: Color {
        if colorScheme == .dark {
            return isHovering ? Color.white.opacity(0.55) : Color.white.opacity(0.24)
        } else {
            return isHovering ? Color.black.opacity(0.28) : Color.black.opacity(0.11)
        }
    }

    private var cardBorderColor: Color {
        if colorScheme == .dark {
            return isHovering ? Color.white.opacity(0.55) : Color.white.opacity(0.24)
        } else {
            return isHovering ? Color.black.opacity(0.28) : Color.black.opacity(0.11)
        }
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                // Top: Document Excerpt & Preview Canvas
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.previewSnippet.isEmpty ? "Markdown document" : item.previewSnippet)
                        .font(.system(size: 10.5, weight: .regular))
                        .lineSpacing(2.5)
                        .foregroundStyle(
                            item.previewSnippet.isEmpty
                                ? Color.secondary.opacity(0.35)
                                : (colorScheme == .dark
                                    ? Color.white.opacity(0.58)
                                    : Color.black.opacity(0.52))
                        )
                        .lineLimit(3, reservesSpace: true)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8.5)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(topBackground)

                // Divider / Upper Edge of Bottom Part
                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 0.75)

                // Bottom: Document Icon, Title, Location & Time/Chevron (contrasted fill, edge-to-edge)
                HStack(alignment: .center, spacing: 9) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 15.5, weight: .light))
                        .foregroundStyle(Color.accentColor.opacity(0.85))
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(item.fileName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer(minLength: 4)

                            ZStack(alignment: .trailing) {
                                if !item.timeAgoDisplay.isEmpty {
                                    Text(item.timeAgoDisplay)
                                        .font(.system(size: 9.5, weight: .regular))
                                        .foregroundStyle(Color.secondary.opacity(0.65))
                                        .opacity(isHovering ? 0.0 : 1.0)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundStyle(Color.secondary.opacity(0.85))
                                    .opacity(isHovering ? 1.0 : 0.0)
                                    .offset(x: isHovering ? 0 : -2)
                            }
                        }

                        HStack(spacing: 3.5) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.secondary.opacity(0.70))

                            Text(item.pathDisplay)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.secondary.opacity(0.75))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(bottomBackground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .strokeBorder(cardBorderColor, lineWidth: 0.75)
            )
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open Document") { onOpen() }
            Button("Open in Separate Window") {
                DocumentTabs.current.openDocument(withContentsOf: item.url, display: true) { _, _, _ in }
            }
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("Copy Full Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            Divider()
            Button("Remove from Suggestions") {
                RecentDocumentsStore.shared.remove(url: item.url)
            }
        }
    }
}

enum RecentViewMode: String {
    case list = "list"
    case grid = "grid"
}

extension Color {
    static func sidebarSolidBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.130, green: 0.133, blue: 0.140)
            : Color(red: 0.958, green: 0.960, blue: 0.966)
    }
}

struct RecentFilesSuggestionsSection: View {
    var columnCount: Int = 1
    var topInset: CGFloat = 18
    let onOpenFile: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("recentDocumentsDisplayMode") private var displayMode = RecentViewMode.list.rawValue
    @ObservedObject private var store = RecentDocumentsStore.shared

    @State private var isListHovered = false
    @State private var isGridHovered = false
    @State private var isClearHovered = false

    private var currentMode: RecentViewMode {
        RecentViewMode(rawValue: displayMode) ?? .list
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10, alignment: .top), count: columnCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Sticky Header (Pinned like macOS title bar)
            HStack(alignment: .center, spacing: 6) {
                // Small icon before "Recent Documents"
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.85))

                    Text("Recent Documents")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.90))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 4)

                if !store.recentItems.isEmpty {
                    // Right Group: List / Grid Switcher + Clear Button
                    HStack(spacing: 5) {
                        // List / Grid Segmented Toggle
                        HStack(spacing: 2) {
                            Button(action: {
                                displayMode = RecentViewMode.list.rawValue
                            }) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 10, weight: currentMode == .list ? .semibold : .regular))
                                    .foregroundStyle(
                                        currentMode == .list
                                            ? Color.primary
                                            : (isListHovered ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.60))
                                    )
                                    .frame(width: 22, height: 18)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(
                                                currentMode == .list
                                                    ? Color(nsColor: .controlBackgroundColor).opacity(0.95)
                                                    : (isListHovered ? Color(nsColor: .quaternaryLabelColor).opacity(0.45) : Color.clear)
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .strokeBorder(
                                                currentMode == .list
                                                    ? Color(nsColor: .separatorColor).opacity(0.35)
                                                    : Color.clear,
                                                lineWidth: 0.5
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    isListHovered = hovering
                                }
                            }
                            .help("List View")

                            Button(action: {
                                displayMode = RecentViewMode.grid.rawValue
                            }) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 9.5, weight: currentMode == .grid ? .semibold : .regular))
                                    .foregroundStyle(
                                        currentMode == .grid
                                            ? Color.primary
                                            : (isGridHovered ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.60))
                                    )
                                    .frame(width: 22, height: 18)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(
                                                currentMode == .grid
                                                    ? Color(nsColor: .controlBackgroundColor).opacity(0.95)
                                                    : (isGridHovered ? Color(nsColor: .quaternaryLabelColor).opacity(0.45) : Color.clear)
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .strokeBorder(
                                                currentMode == .grid
                                                    ? Color(nsColor: .separatorColor).opacity(0.35)
                                                    : Color.clear,
                                                lineWidth: 0.5
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    isGridHovered = hovering
                                }
                            }
                            .help("Grid View (Shows Content Previews)")
                        }
                        .padding(2)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.30))
                        )
                        .fixedSize()

                        // Clear Button with smaller x icon and matching 22pt container height
                        Button(action: {
                            store.clear()
                        }) {
                            HStack(spacing: 3.5) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7.5, weight: .semibold))
                                    .foregroundStyle(Color.secondary.opacity(isClearHovered ? 0.90 : 0.65))

                                Text("Clear")
                                    .font(.system(size: 11, weight: .regular))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundStyle(
                                isClearHovered ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.65)
                            )
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        isClearHovered
                                            ? Color(nsColor: .quaternaryLabelColor).opacity(0.45)
                                            : Color.clear
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .onHover { hovering in
                            isClearHovered = hovering
                        }
                        .help("Clear recent document suggestions")
                    }
                }
            }
            .frame(height: 22)
            .padding(.horizontal, 18)
            .padding(.top, topInset)
            .padding(.bottom, 12)
            .background(Color.sidebarSolidBackground(for: colorScheme))

            // MARK: - Scrollable Document Items Area or Empty State
            if store.recentItems.isEmpty {
                VStack(spacing: 8) {
                    Spacer()

                    Image(systemName: "clock")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color.secondary.opacity(0.40))
                        .padding(.bottom, 2)

                    Text("No Recent Documents")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.75))

                    Text("Documents you open will appear here for quick access.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.secondary.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, 36)
            } else {
                OverlayScrollView {
                    VStack(spacing: 0) {
                        if currentMode == .list {
                            LazyVStack(spacing: 6) {
                                ForEach(store.recentItems) { item in
                                    RecentFileListRowView(item: item) {
                                        onOpenFile(item.url)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .transaction { $0.animation = nil }
                        } else {
                            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                                ForEach(store.recentItems) { item in
                                    RecentFileCardView(item: item) {
                                        onOpenFile(item.url)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .transaction { $0.animation = nil }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                    .transaction { $0.animation = nil }
                }
                .transaction { $0.animation = nil }
            }
        }
    }
}
