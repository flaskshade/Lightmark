import AppKit
import CoreText
import SwiftUI

enum CustomFonts {
    nonisolated(unsafe) private static var isRegistered = false
    private static let lock = NSLock()

    static func registerOnce() {
        lock.lock()
        defer { lock.unlock() }
        guard !isRegistered else { return }
        isRegistered = true
        registerCustomFonts()
    }

    private static func registerCustomFonts() {
        let fontFileNames = [
            "InstrumentSerif-Regular.ttf",
            "InstrumentSerif-Italic.ttf",
            "BricolageGrotesque.ttf"
        ]

        var candidateDirectories: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidateDirectories.append(resourceURL.appendingPathComponent("Fonts"))
            candidateDirectories.append(resourceURL)
        }
        let bundleContents = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Fonts")
        candidateDirectories.append(bundleContents)

        #if DEBUG
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidateDirectories.append(cwd.appendingPathComponent("Resources/Fonts"))
        candidateDirectories.append(cwd.appendingPathComponent("Resources"))
        #endif

        for fileName in fontFileNames {
            for dir in candidateDirectories {
                let fontURL = dir.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fontURL.path) {
                    var error: Unmanaged<CFError>?
                    let success = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
                    if success {
                        break
                    } else if let err = error?.takeRetainedValue() {
                        let cfErr = err as Error as NSError
                        // Error code 105: already registered (kCTFontManagerErrorAlreadyRegistered)
                        if cfErr.code == 105 {
                            break
                        }
                    }
                }
            }
        }
    }
}

enum ReadingFont: String, CaseIterable, Identifiable {
    case system = "system"
    case instrumentSerif = "instrumentSerif"
    case monospaced = "monospaced"

    static let headingOptions: [ReadingFont] = [.system, .instrumentSerif, .monospaced]
    static let bodyOptions: [ReadingFont] = [.system, .monospaced]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .instrumentSerif: "Serif"
        case .monospaced: "Mono"
        }
    }

    var subtitle: String {
        switch self {
        case .system: "Apple SF Pro"
        case .instrumentSerif: "Instrument Serif"
        case .monospaced: "Apple SF Mono"
        }
    }

    static func from(stored: String) -> ReadingFont {
        switch stored {
        case "instrumentSerif", "serif": return .instrumentSerif
        case "monospaced", "mono": return .monospaced
        default: return .system
        }
    }

    func swiftUIFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        CustomFonts.registerOnce()
        switch self {
        case .system:
            return .system(size: size, weight: weight, design: .default)
        case .instrumentSerif:
            // Instrument Serif has delicate strokes and a smaller optical volume; bias size up (+22%) and enhance weight
            let scaledSize = round(size * 1.22)
            let base = Font.custom("InstrumentSerif-Regular", size: scaledSize)
            return (weight == .semibold || weight == .bold || weight == .heavy || weight == .black) ? base.weight(.bold) : base
        case .monospaced:
            return .system(size: size, weight: weight, design: .monospaced)
        }
    }

    func nsFont(size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        CustomFonts.registerOnce()
        switch self {
        case .system:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if italic {
                var traits = base.fontDescriptor.symbolicTraits
                traits.insert(.italic)
                let desc = base.fontDescriptor.withSymbolicTraits(traits)
                return NSFont(descriptor: desc, size: size) ?? base
            }
            return base

        case .instrumentSerif:
            // Instrument Serif has delicate strokes and a smaller optical size; bias size up (+22%) and enhance weight
            let scaledSize = round(size * 1.22)
            let fontName = italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular"
            if let font = NSFont(name: fontName, size: scaledSize) {
                if weight == .bold || weight == .heavy || weight == .black || weight == .semibold {
                    let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                    return boldFont
                }
                return font
            }
            // Fallback to system serif if font file is missing
            let base = NSFont.systemFont(ofSize: scaledSize, weight: weight)
            let desc = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
            return NSFont(descriptor: desc, size: scaledSize) ?? base

        case .monospaced:
            let base = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            if italic {
                var traits = base.fontDescriptor.symbolicTraits
                traits.insert(.italic)
                let desc = base.fontDescriptor.withSymbolicTraits(traits)
                return NSFont(descriptor: desc, size: size) ?? base
            }
            return base
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static func from(stored: String) -> AppTheme {
        switch stored {
        case "light": return .light
        case "dark": return .dark
        default: return .system
        }
    }

    @MainActor
    static func apply(stored: String) {
        let theme = from(stored: stored)
        // AppKit is the single appearance owner, including hosted SwiftUI views.
        // nil restores live system appearance instead of retaining a window override.
        for window in NSApp.windows { window.appearance = nil }
        NSApp.appearance = theme.nsAppearance
    }
}
