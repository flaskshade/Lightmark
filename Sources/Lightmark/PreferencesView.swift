import SwiftUI


enum BackgroundStyle: String, CaseIterable, Identifiable {
    case translucent = "translucent"
    case solid = "solid"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .translucent: "Translucent"
        case .solid: "Solid"
        }
    }

    static func from(stored: String) -> BackgroundStyle {
        switch stored {
        case "solid", "plainWhite": return .solid
        default: return .translucent
        }
    }
}

enum WindowOpeningMode: String, CaseIterable, Identifiable {
    case separateWindows = "windows"
    case tabbed = "tabs"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .separateWindows: "Separate"
        case .tabbed: "Tabs"
        }
    }

    var subtitle: String {
        switch self {
        case .separateWindows: "Separate Windows"
        case .tabbed: "Adaptive Tabs"
        }
    }

    static func from(stored: String) -> WindowOpeningMode {
        switch stored {
        case "tabs", "tabbed": return .tabbed
        default: return .separateWindows
        }
    }
}

enum PageWidthPreset: Double, CaseIterable, Identifiable {
    case narrow = 620.0
    case standard = 740.0
    case wide = 860.0
    case full = 0.0

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .narrow: "Narrow"
        case .standard: "Standard"
        case .wide: "Wide"
        case .full: "Full"
        }
    }

    var label: String {
        switch self {
        case .narrow, .standard, .wide:
            "\(Int(rawValue)) pt"
        case .full:
            "Full width"
        }
    }
}

enum PreferencesTab: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case shortcuts = "Shortcuts"
    case about = "About"

    var id: String { rawValue }
    var title: String { rawValue }

    var icon: String {
        switch self {
        case .appearance: return "paintpalette.fill"
        case .shortcuts: return "command"
        case .about: return "info.circle.fill"
        }
    }
}

struct PreferencesView: View {
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("backgroundStyle") private var backgroundStyle = BackgroundStyle.translucent.rawValue
    @AppStorage("windowOpeningMode") private var windowOpeningMode = WindowOpeningMode.separateWindows.rawValue
    @AppStorage("headingFont") private var headingFont = ReadingFont.system.rawValue
    @AppStorage("readingFont") private var readingFont = ReadingFont.system.rawValue
    @AppStorage("fontSize") private var fontSize = 16.0
    @AppStorage("readingWidth") private var readingWidth = 740.0

    @State private var selectedTab: PreferencesTab = .appearance
    @Namespace private var segmentNamespace
    @Environment(\.colorScheme) private var colorScheme
    @State private var isResetHovering = false
    @State private var isSignatureHovering = false

    private var activeTheme: AppTheme {
        AppTheme.from(stored: appTheme)
    }

    private var activeBackground: BackgroundStyle {
        BackgroundStyle.from(stored: backgroundStyle)
    }

    private var activeWindowMode: WindowOpeningMode {
        WindowOpeningMode.from(stored: windowOpeningMode)
    }

    private var activeHeadingFont: ReadingFont {
        ReadingFont.from(stored: headingFont)
    }

    private var activeReadingFont: ReadingFont {
        let font = ReadingFont.from(stored: readingFont)
        return font == .instrumentSerif ? .system : font
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(PreferencesTab.allCases) { tab in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch tab {
                        case .appearance: appearanceSection
                        case .shortcuts: shortcutsSection
                        case .about: aboutSection
                        }
                        if tab == .appearance {
                            footerView
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                    .background(ScrollViewScrollerConfigurator())
                }
                .tabItem { Label(tab.title, systemImage: tab.icon) }
                .tag(tab)
            }
        }
        .frame(width: 580, height: 620)
    }

    // MARK: - 1. Appearance Section
    @ViewBuilder
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Theme & Window Group
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5.5) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    Text("Theme & Window")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
                .padding(.leading, 3)

                VStack(spacing: 0) {
                    // Theme Row (System / Light / Dark)
                    HStack(alignment: .center, spacing: 12) {
                        Text("Theme")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.primary)

                        Spacer()

                        SettingsThemeSegmentedControl(
                            selected: activeTheme,
                            namespace: segmentNamespace
                        ) { newTheme in
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                appTheme = newTheme.rawValue
                            }
                            AppTheme.apply(stored: newTheme.rawValue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Divider().opacity(0.20).padding(.horizontal, 16)

                    // Window Mode Visual Picker
                    SettingsVisualPickerRow(
                        title: "Window Mode",
                        subtitle: "Open documents in separate windows or adaptive tabs"
                    ) {
                        HStack(spacing: 14) {
                            SettingsVisualCard(
                                title: "Separate",
                                helpText: "Open each document in its own independent window",
                                isDefault: true,
                                isSelected: activeWindowMode == .separateWindows,
                                namespace: segmentNamespace,
                                group: "win"
                            ) {
                                ZStack {
                                    Color(nsColor: .controlBackgroundColor).opacity(0.6)

                                    ZStack {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(Color(nsColor: .windowBackgroundColor))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                    .stroke(Color(nsColor: .separatorColor).opacity(0.80), lineWidth: 0.75)
                                            )
                                            .frame(width: 46, height: 30)
                                            .offset(x: 9, y: -5)
                                            .opacity(0.7)

                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(Color(nsColor: .windowBackgroundColor))
                                            .overlay(
                                                VStack(alignment: .leading, spacing: 2) {
                                                    RoundedRectangle(cornerRadius: 0.8)
                                                        .fill(Color.primary.opacity(0.55))
                                                        .frame(width: 16, height: 2)
                                                    RoundedRectangle(cornerRadius: 0.5)
                                                        .fill(Color.primary.opacity(0.30))
                                                        .frame(width: 26, height: 1.6)
                                                }
                                                .padding(.leading, 6)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                    .stroke(Color(nsColor: .separatorColor).opacity(0.90), lineWidth: 0.75)
                                            )
                                            .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1.5)
                                            .frame(width: 46, height: 30)
                                            .offset(x: -7, y: 4)
                                    }
                                }
                            } action: {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                    windowOpeningMode = WindowOpeningMode.separateWindows.rawValue
                                }
                                DispatchQueue.main.async {
                                    DocumentTabs.current.changeMode(to: .separateWindows)
                                }
                            }

                            SettingsVisualCard(
                                title: "Tabs",
                                helpText: "A focused title for one document; tabs appear when you open more",
                                isSelected: activeWindowMode == .tabbed,
                                namespace: segmentNamespace,
                                group: "win"
                            ) {
                                ZStack {
                                    Color(nsColor: .controlBackgroundColor).opacity(0.6)

                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color(nsColor: .windowBackgroundColor))
                                        .overlay(
                                            VStack(spacing: 0) {
                                                HStack(spacing: 2) {
                                                    HStack(spacing: 2) {
                                                        Circle().fill(Color.accentColor).frame(width: 2.5, height: 2.5)
                                                        RoundedRectangle(cornerRadius: 0.5).fill(Color.primary.opacity(0.75)).frame(width: 11, height: 2)
                                                    }
                                                    .padding(.horizontal, 3)
                                                    .frame(height: 6.5)
                                                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 1.5))

                                                    HStack(spacing: 2) {
                                                        RoundedRectangle(cornerRadius: 0.5).fill(Color.secondary.opacity(0.50)).frame(width: 11, height: 2)
                                                    }
                                                    .padding(.horizontal, 3)
                                                    .frame(height: 6.5)

                                                    Spacer()
                                                }
                                                .padding(.horizontal, 3.5)
                                                .padding(.top, 2.5)

                                                Divider().opacity(0.60).padding(.top, 1.5)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    RoundedRectangle(cornerRadius: 0.8)
                                                        .fill(Color.primary.opacity(0.55))
                                                        .frame(width: 18, height: 2)
                                                    RoundedRectangle(cornerRadius: 0.5)
                                                        .fill(Color.primary.opacity(0.30))
                                                        .frame(width: 36, height: 1.5)
                                                }
                                                .padding(.leading, 6)
                                                .padding(.top, 3)
                                                .frame(maxWidth: .infinity, alignment: .leading)

                                                Spacer()
                                            }
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .stroke(Color(nsColor: .separatorColor).opacity(0.88), lineWidth: 0.75)
                                        )
                                        .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1.5)
                                        .frame(width: 60, height: 35)
                                }
                            } action: {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                    windowOpeningMode = WindowOpeningMode.tabbed.rawValue
                                }
                                DispatchQueue.main.async {
                                    DocumentTabs.current.changeMode(to: .tabbed)
                                }
                            }
                        }
                    }

                    Divider().opacity(0.20).padding(.horizontal, 16)

                    // Window Backdrop Visual Picker
                    SettingsVisualPickerRow(
                        title: "Window Backdrop",
                        subtitle: "Choose between translucent material or solid background"
                    ) {
                        HStack(spacing: 14) {
                            SettingsVisualCard(
                                title: "Translucent",
                                helpText: "Show subtle desktop wallpaper translucency behind text",
                                isDefault: true,
                                isSelected: activeBackground == .translucent,
                                namespace: segmentNamespace,
                                group: "bg"
                            ) {
                                ZStack {
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.22, green: 0.40, blue: 0.95),
                                            Color(red: 0.55, green: 0.25, blue: 0.85),
                                            Color(red: 0.85, green: 0.35, blue: 0.65)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )

                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(.ultraThickMaterial)

                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.40))

                                        VStack(alignment: .leading, spacing: 2.5) {
                                            RoundedRectangle(cornerRadius: 1)
                                                .fill(Color.primary.opacity(0.75))
                                                .frame(width: 22, height: 2.5)
                                            RoundedRectangle(cornerRadius: 0.8)
                                                .fill(Color.primary.opacity(0.40))
                                                .frame(width: 38, height: 2)
                                            RoundedRectangle(cornerRadius: 0.8)
                                                .fill(Color.primary.opacity(0.40))
                                                .frame(width: 28, height: 2)
                                        }
                                        .padding(.horizontal, 8)
                                    }
                                    .frame(width: 68, height: 42)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.white.opacity(0.60), lineWidth: 0.75)
                                    )
                                    .shadow(color: Color.black.opacity(0.25), radius: 4, y: 2)
                                }
                            } action: {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                    backgroundStyle = BackgroundStyle.translucent.rawValue
                                }
                            }

                            SettingsVisualCard(
                                title: "Solid",
                                helpText: "Use an opaque solid background",
                                isSelected: activeBackground == .solid,
                                namespace: segmentNamespace,
                                group: "bg"
                            ) {
                                ZStack {
                                    Color(nsColor: .controlBackgroundColor).opacity(0.6)

                                    HStack(spacing: 0) {
                                        ZStack {
                                            Color.white
                                            VStack(alignment: .leading, spacing: 2.5) {
                                                RoundedRectangle(cornerRadius: 1)
                                                    .fill(Color.black.opacity(0.85))
                                                    .frame(width: 14, height: 2.5)
                                                RoundedRectangle(cornerRadius: 0.8)
                                                    .fill(Color.black.opacity(0.40))
                                                    .frame(width: 20, height: 2)
                                                RoundedRectangle(cornerRadius: 0.8)
                                                    .fill(Color.black.opacity(0.40))
                                                    .frame(width: 16, height: 2)
                                            }
                                            .padding(.leading, 6)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }

                                        ZStack {
                                            Color(red: 0.13, green: 0.13, blue: 0.15)
                                            VStack(alignment: .leading, spacing: 2.5) {
                                                RoundedRectangle(cornerRadius: 1)
                                                    .fill(Color.white.opacity(0.90))
                                                    .frame(width: 14, height: 2.5)
                                                RoundedRectangle(cornerRadius: 0.8)
                                                    .fill(Color.white.opacity(0.45))
                                                    .frame(width: 20, height: 2)
                                                RoundedRectangle(cornerRadius: 0.8)
                                                    .fill(Color.white.opacity(0.45))
                                                    .frame(width: 16, height: 2)
                                            }
                                            .padding(.leading, 6)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .frame(width: 68, height: 42)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color(nsColor: .separatorColor).opacity(0.85), lineWidth: 0.75)
                                    )
                                    .shadow(color: Color.black.opacity(0.25), radius: 4, y: 2)
                                }
                            } action: {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                    backgroundStyle = BackgroundStyle.solid.rawValue
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .background(settingsCardBackground)
            }

            // Typography Group
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5.5) {
                    Image(systemName: "textformat")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    Text("Typography")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
                .padding(.leading, 3)

                VStack(spacing: 0) {
                    // Headings Row
                    SettingsRow(title: "Headings") {
                        SettingsFontSegmentedControl(
                            fonts: ReadingFont.headingOptions,
                            selected: activeHeadingFont,
                            namespace: segmentNamespace,
                            group: "heading_seg"
                        ) { font in
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                headingFont = font.rawValue
                            }
                        }
                    }

                    Divider().opacity(0.20).padding(.horizontal, 16)

                    // Body Text Row
                    SettingsRow(title: "Body Text") {
                        SettingsFontSegmentedControl(
                            fonts: ReadingFont.bodyOptions,
                            selected: activeReadingFont,
                            namespace: segmentNamespace,
                            group: "body_seg"
                        ) { font in
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                readingFont = font.rawValue
                            }
                        }
                    }

                    Divider().opacity(0.20).padding(.horizontal, 16)

                    // Unified Font Size Slider Row
                    SettingsSliderRow(
                        title: "Font Size",
                        value: $fontSize,
                        range: 12...24,
                        defaultValue: 16.0
                    )
                }
                .frame(maxWidth: .infinity)
                .background(settingsCardBackground)
            }

            // Column Width Group
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5.5) {
                    Image(systemName: "ruler.fill")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    Text("Column Width")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
                .padding(.leading, 3)

                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        ForEach(PageWidthPreset.allCases) { preset in
                            ColumnWidthCard(
                                preset: preset,
                                isSelected: preset == .full ? readingWidth <= 0 : abs(readingWidth - preset.rawValue) < 20,
                                namespace: segmentNamespace
                            ) {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                    readingWidth = preset.rawValue
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
                .frame(maxWidth: .infinity)
                .background(settingsCardBackground)
            }
        }
    }

    // MARK: - 3. Shortcuts Section
    @ViewBuilder
    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Document & Editing Group
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5.5) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    Text("Document & Editing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
                .padding(.leading, 3)

                VStack(spacing: 0) {
                    ShortcutRow(
                        title: "Toggle Edit Mode",
                        subtitle: "Switch between distraction-free reader and source editor",
                        shortcut: "⌘E"
                    )

                    Divider().opacity(0.20).padding(.horizontal, 16)

                    ShortcutRow(
                        title: "Copy All Text",
                        subtitle: "Copies entire markdown source to clipboard",
                        shortcut: "⇧⌘C"
                    )

                    Divider().opacity(0.20).padding(.horizontal, 16)

                    ShortcutRow(
                        title: "Open Document",
                        subtitle: "Choose an existing markdown file from disk",
                        shortcut: "⌘O"
                    )

                    Divider().opacity(0.20).padding(.horizontal, 16)

                    ShortcutRow(
                        title: "Save",
                        subtitle: "Save modifications to disk",
                        shortcut: "⌘S"
                    )

                    Divider().opacity(0.20).padding(.horizontal, 16)

                    ShortcutRow(
                        title: "Close Document",
                        subtitle: "Close active tab or window",
                        shortcut: "⌘W"
                    )

                    Divider().opacity(0.20).padding(.horizontal, 16)

                    ShortcutRow(
                        title: "Find in Document",
                        subtitle: "Search within the current reading view",
                        shortcut: "⌘F"
                    )
                }
                .frame(maxWidth: .infinity)
                .background(settingsCardBackground)
            }

            // Navigation & Tabs Group
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5.5) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    Text("Navigation & Windows")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
                .padding(.leading, 3)

                VStack(spacing: 0) {
                    ShortcutRow(
                        title: "New Window",
                        subtitle: "Open a fresh document window",
                        shortcut: "⌘N"
                    )

                    Divider().opacity(0.20).padding(.horizontal, 16)

                    ShortcutRow(
                        title: "New Tab",
                        subtitle: "Open a fresh document tab (in Tabbed mode)",
                        shortcut: "⌘T"
                    )

                    Divider().opacity(0.20).padding(.horizontal, 16)

                    ShortcutRow(
                        title: "Next Tab",
                        subtitle: "Cycle forward through open document tabs",
                        shortcut: "⇧⌘]"
                    )

                    Divider().opacity(0.20).padding(.horizontal, 16)

                    ShortcutRow(
                        title: "Previous Tab",
                        subtitle: "Cycle backward through open document tabs",
                        shortcut: "⇧⌘["
                    )

                    Divider().opacity(0.20).padding(.horizontal, 16)

                    ShortcutRow(
                        title: "Preferences",
                        subtitle: "Open application settings",
                        shortcut: "⌘,"
                    )
                }
                .frame(maxWidth: .infinity)
                .background(settingsCardBackground)
            }
        }
    }

    // MARK: - About
    private var aboutSection: some View {
        VStack(spacing: 12) {
            Image("LightmarkIcon", bundle: .main)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .accessibilityLabel("Lightmark app icon")

            Text("Lightmark")
                .font(.title2.weight(.semibold))

            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("A focused & lightweight companion for Markdown on macOS.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            if FirstLaunch.shared.isInstalled {
                Button("Default Markdown App…") { FirstLaunch.shared.present() }
                    .padding(.top, 8)
            }

            signatureView
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var signatureView: some View {
            Button(action: {
                if let url = URL(string: "https://x.com/flaskshade") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                VStack(alignment: .center, spacing: 5) {
                    Text("A PROJECT BY")
                        .font(.system(size: 7.5, weight: .semibold))
                        .kerning(1.0)
                        .foregroundStyle(Color.secondary.opacity(0.40))
                        .multilineTextAlignment(.center)

                    Text("Flaskshade")
                        .font(.custom("Baunk", size: 14.5))
                        .foregroundStyle(
                            isSignatureHovering
                                ? (colorScheme == .dark
                                    ? Color(red: 226 / 255.0, green: 200 / 255.0, blue: 255 / 255.0)
                                    : Color(red: 142 / 255.0, green: 65 / 255.0, blue: 230 / 255.0))
                                : Color.secondary.opacity(0.65)
                        )
                        .shadow(
                            color: Color(red: 216 / 255.0, green: 160 / 255.0, blue: 255 / 255.0).opacity(
                                isSignatureHovering ? (colorScheme == .dark ? 0.22 : 0.12) : 0
                            ),
                            radius: isSignatureHovering ? 3 : 0,
                            x: 0,
                            y: 0
                        )
                        .padding(6.5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(
                                    Color(red: 168 / 255.0, green: 85 / 255.0, blue: 247 / 255.0).opacity(
                                        isSignatureHovering ? (colorScheme == .dark ? 0.05 : 0.03) : 0
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(
                                    Color(red: 216 / 255.0, green: 160 / 255.0, blue: 255 / 255.0).opacity(
                                        isSignatureHovering ? (colorScheme == .dark ? 0.20 : 0.14) : 0
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                }
                .animation(.spring(response: 0.20, dampingFraction: 0.8), value: isSignatureHovering)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isSignatureHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help("Visit @flaskshade on x.com")
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack(alignment: .center) {


            Spacer()

            Button(action: restoreDefaults) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .medium))
                    Text("Reset to Defaults")
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isResetHovering ? Color.primary.opacity(0.85) : Color.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5.5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isResetHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.70) : Color(nsColor: .quaternaryLabelColor).opacity(0.40))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(isResetHovering ? 0.40 : 0.20), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isResetHovering = $0 }
        }
        .padding(.top, 18)
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var settingsCardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.42))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
    }

    private func restoreDefaults() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            appTheme = AppTheme.system.rawValue
            backgroundStyle = BackgroundStyle.translucent.rawValue
            windowOpeningMode = WindowOpeningMode.separateWindows.rawValue
            headingFont = ReadingFont.system.rawValue
            readingFont = ReadingFont.system.rawValue
            fontSize = 16.0
            readingWidth = 740.0
        }
        AppTheme.apply(stored: AppTheme.system.rawValue)
        DispatchQueue.main.async {
            DocumentTabs.current.changeMode(to: .separateWindows)
        }
    }
}

private struct ScrollViewScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView {
                configure(scrollView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let scrollView = nsView.enclosingScrollView {
                configure(scrollView)
            }
        }
    }

    private func configure(_ scrollView: NSScrollView) {
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
    }
}

// MARK: - Settings Style Components

private struct SettingsRow<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.secondary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            content()
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SettingsVisualPickerRow<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.secondary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)

            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct DiscreteDefaultBadge: View {
    var body: some View {
        Text("DEFAULT")
            .font(.system(size: 7.5, weight: .bold))
            .kerning(0.4)
            .foregroundStyle(Color.primary.opacity(0.65))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.88))
                    .overlay(
                        Capsule()
                            .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 1.5, y: 0.5)
            )
            .padding(4.5)
    }
}

private struct SettingsVisualCard<Graphic: View>: View {
    let title: String
    var helpText: String? = nil
    var isDefault: Bool = false
    let isSelected: Bool
    let namespace: Namespace.ID
    let group: String
    @ViewBuilder let graphic: () -> Graphic
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    init(
        title: String,
        helpText: String? = nil,
        isDefault: Bool = false,
        isSelected: Bool,
        namespace: Namespace.ID,
        group: String,
        @ViewBuilder graphic: @escaping () -> Graphic,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.helpText = helpText
        self.isDefault = isDefault
        self.isSelected = isSelected
        self.namespace = namespace
        self.group = group
        self.graphic = graphic
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    graphic()
                        .frame(width: 110, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.55), lineWidth: isSelected ? 1.5 : 0.75)
                        )

                    if isDefault {
                        DiscreteDefaultBadge()
                    }
                }

                HStack {
                    Text(title)
                        .font(.system(size: 11.5, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    ZStack {
                        if isSelected {
                            if colorScheme == .dark {
                                Capsule()
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.95))
                                    .matchedGeometryEffect(id: "\(group)_capsule", in: namespace)
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                    )
                                    .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
                            } else {
                                Capsule()
                                    .fill(Color.white)
                                    .matchedGeometryEffect(id: "\(group)_capsule", in: namespace)
                                    .overlay(
                                        Capsule()
                                            .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.75)
                                    )
                                    .shadow(color: Color.black.opacity(0.04), radius: 1.5, y: 0.5)
                            }
                        } else if isHovering {
                            Capsule()
                                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                        }
                    }
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText ?? title)
        .onHover { isHovering = $0 }
    }
}

private struct SettingsThemeSegmentedControl: View {
    let selected: AppTheme
    let namespace: Namespace.ID
    let onSelect: (AppTheme) -> Void
    @State private var hoveredTheme: AppTheme? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTheme.allCases, id: \.self) { theme in
                let isCurrent = (theme == selected)
                let isHovered = (theme == hoveredTheme && !isCurrent)
                Button(action: { onSelect(theme) }) {
                    HStack(spacing: 5) {
                        Image(systemName: iconName(for: theme))
                            .font(.system(size: 11, weight: .medium))
                        Text(theme.title)
                            .font(.system(size: 12, weight: isCurrent ? .medium : .regular))
                    }
                    .frame(width: 80, height: 24)
                    .foregroundStyle(isCurrent ? Color.primary : (isHovered ? Color.primary : Color.secondary))
                    .background(
                        ZStack {
                            if isCurrent {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .matchedGeometryEffect(id: "theme_pill", in: namespace)
                                    .shadow(color: Color.black.opacity(0.12), radius: 1.5, y: 1)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                                    )
                            } else if isHovered {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.40))
                            }
                        }
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    if isHovering {
                        hoveredTheme = theme
                    } else if hoveredTheme == theme {
                        hoveredTheme = nil
                    }
                }
            }
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.42))
        )
        .animation(.spring(response: 0.18, dampingFraction: 0.8), value: hoveredTheme)
    }

    private func iconName(for theme: AppTheme) -> String {
        switch theme {
        case .system: "circle.righthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

private struct SettingsSegmentedControl<T: Equatable & Identifiable, Label: View>: View {
    let options: [T]
    let selected: T
    let namespace: Namespace.ID
    let group: String
    let onSelect: (T) -> Void
    @ViewBuilder let label: (T) -> Label
    @State private var hoveredOption: T? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isCurrent = (option == selected)
                let isHovered = (option == hoveredOption && !isCurrent)
                Button(action: { onSelect(option) }) {
                    label(option)
                        .foregroundStyle(isCurrent ? Color.primary : (isHovered ? Color.primary : Color.secondary))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            ZStack {
                                if isCurrent {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .matchedGeometryEffect(id: "\(group)_pill", in: namespace)
                                        .shadow(color: Color.black.opacity(0.12), radius: 1.5, y: 1)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                                        )
                                } else if isHovered {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.40))
                                }
                            }
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    if isHovering {
                        hoveredOption = option
                    } else if hoveredOption == option {
                        hoveredOption = nil
                    }
                }
            }
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.42))
        )
        .animation(.spring(response: 0.18, dampingFraction: 0.8), value: hoveredOption)
    }
}

private struct SliderStepperButton: View {
    let icon: String
    let isDisabled: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(
                    isDisabled
                        ? Color.secondary.opacity(0.25)
                        : (isHovering ? Color.primary : Color.secondary)
                )
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            isDisabled
                                ? Color.clear
                                : (isHovering
                                    ? (colorScheme == .dark ? Color.white.opacity(0.14) : Color(nsColor: .quaternaryLabelColor).opacity(0.55))
                                    : (colorScheme == .dark ? Color.white.opacity(0.06) : Color(nsColor: .quaternaryLabelColor).opacity(0.22)))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(
                            Color(nsColor: .separatorColor).opacity(
                                isDisabled ? 0.12 : (isHovering ? 0.60 : 0.30)
                            ),
                            lineWidth: 0.5
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.18, dampingFraction: 0.8), value: isHovering)
    }
}

private struct SettingsSliderRow: View {
    let title: String
    let subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double

    init(title: String, subtitle: String? = nil, value: Binding<Double>, range: ClosedRange<Double>, defaultValue: Double) {
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.range = range
        self.defaultValue = defaultValue
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.secondary.opacity(0.9))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                if Int(value) != Int(defaultValue) {
                    Button(action: {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                            value = defaultValue
                        }
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default (\(Int(defaultValue)) pt)")
                }

                SliderStepperButton(
                    icon: "minus",
                    isDisabled: value <= range.lowerBound
                ) {
                    if value > range.lowerBound {
                        withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                            value -= 1
                        }
                    }
                }

                Slider(value: $value, in: range, step: 1)
                    .frame(width: 180)

                SliderStepperButton(
                    icon: "plus",
                    isDisabled: value >= range.upperBound
                ) {
                    if value < range.upperBound {
                        withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                            value += 1
                        }
                    }
                }

                Text("\(Int(value)) pt")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SettingsFontSegmentedControl: View {
    var fonts: [ReadingFont] = ReadingFont.allCases
    let selected: ReadingFont
    let namespace: Namespace.ID
    let group: String
    let onSelect: (ReadingFont) -> Void
    @State private var hoveredFont: ReadingFont? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(fonts) { font in
                let isCurrent = (font == selected)
                let isHovered = (font == hoveredFont && !isCurrent)
                Button(action: { onSelect(font) }) {
                    Text(font.title)
                        .font(font.swiftUIFont(size: 12, weight: isCurrent ? .medium : .regular))
                        .foregroundStyle(isCurrent ? Color.primary : (isHovered ? Color.primary : Color.secondary))
                        .lineLimit(1)
                        .frame(width: 80, height: 24)
                        .background(
                            ZStack {
                                if isCurrent {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .matchedGeometryEffect(id: "\(group)_pill", in: namespace)
                                        .shadow(color: Color.black.opacity(0.12), radius: 1.5, y: 1)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                                        )
                                } else if isHovered {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.40))
                                }
                            }
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    if isHovering {
                        hoveredFont = font
                    } else if hoveredFont == font {
                        hoveredFont = nil
                    }
                }
            }
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.42))
        )
        .animation(.spring(response: 0.18, dampingFraction: 0.8), value: hoveredFont)
    }
}

private struct ColumnWidthCard: View {
    let preset: PageWidthPreset
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var columnWidthFraction: CGFloat {
        switch preset {
        case .narrow: 0.44
        case .standard: 0.68
        case .wide: 0.86
        case .full: 1.0
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    // Mini document page illustration
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))

                        // Simulated reading column
                        VStack(alignment: .leading, spacing: 3.5) {
                            // Title bar
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.55))
                                .frame(height: 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .scaleEffect(x: 0.60, anchor: .leading)

                            // Body line 1
                            RoundedRectangle(cornerRadius: 1)
                                .fill(isSelected ? Color.accentColor.opacity(0.70) : Color.primary.opacity(0.30))
                                .frame(height: 2)

                            // Body line 2
                            RoundedRectangle(cornerRadius: 1)
                                .fill(isSelected ? Color.accentColor.opacity(0.70) : Color.primary.opacity(0.30))
                                .frame(height: 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .scaleEffect(x: 0.78, anchor: .leading)
                        }
                        .padding(.horizontal, 10)
                        .scaleEffect(x: columnWidthFraction, y: 1.0)
                    }
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.55), lineWidth: isSelected ? 1.5 : 0.75)
                    )

                    if preset == .standard {
                        DiscreteDefaultBadge()
                    }
                }

                // Label & points
                VStack(spacing: 1.5) {
                    Text(preset.title)
                        .font(.system(size: 11.5, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)

                    Text(preset.label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.secondary.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    ZStack {
                        if isSelected {
                            if colorScheme == .dark {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.95))
                                    .matchedGeometryEffect(id: "width_pill", in: namespace)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                    )
                                    .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
                            } else {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white)
                                    .matchedGeometryEffect(id: "width_pill", in: namespace)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.75)
                                    )
                                    .shadow(color: Color.black.opacity(0.04), radius: 1.5, y: 0.5)
                            }
                        } else if isHovering {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
                        }
                    }
                )
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct ShortcutRow: View {
    let title: String
    var subtitle: String? = nil
    let shortcut: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.secondary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            KbdBadge(text: shortcut)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10.5)
    }
}

