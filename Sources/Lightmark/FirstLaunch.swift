import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreServices

/// Owns the one-time welcome and explicit Markdown association request.
@MainActor
final class FirstLaunch {
    static let shared = FirstLaunch()
    private var panel: NSPanel?
    private let welcomeKey = "hasSeenFirstLaunchWelcome"

    var isDefault: Bool {
        guard let handler = LSCopyDefaultRoleHandlerForContentType("net.daringfireball.markdown" as CFString, .all)?.takeRetainedValue() else { return false }
        return (handler as String) == Bundle.main.bundleIdentifier
    }

    var isInstalled: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(documentBecameKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)
    }

    @objc private func documentBecameKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.windowController?.document is NativeMarkdownDocument else { return }
        DispatchQueue.main.async { self.presentIfNeeded() }
    }

    func presentIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: welcomeKey) else { return }
        present(welcome: true)
    }

    func present(welcome: Bool = false) {
        guard welcome || isInstalled else { return }
        guard panel == nil, let parent = NSApp.keyWindow ?? NSApp.mainWindow,
              parent.attachedSheet == nil else { return }
        let sheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 310),
                            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        sheet.titleVisibility = .hidden
        sheet.titlebarAppearsTransparent = true
        sheet.isReleasedWhenClosed = false
        sheet.contentView = NSHostingView(rootView: WelcomeView(showIntro: welcome) { [weak self, weak parent, weak sheet] in
            if let sheet { parent?.endSheet(sheet) }
            self?.panel = nil
        })
        panel = sheet
        parent.beginSheet(sheet)
        if welcome { UserDefaults.standard.set(true, forKey: welcomeKey) }
    }

    func makeDefault() async throws {
        guard isInstalled, let type = UTType("net.daringfireball.markdown"),
              type.identifier != UTType.plainText.identifier else {
            throw NSError(domain: "Lightmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "The default app could not be changed."])
        }
        try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
        NotificationCenter.default.post(name: .defaultMarkdownAppDidChange, object: nil)
    }
}

private struct WelcomeView: View {
    let showIntro: Bool
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var intro = true
    @State private var visible = false
    @State private var auraExpanded = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: [Color(red: 237/255, green: 225/255, blue: 154/255).opacity(colorScheme == .dark ? 0.24 : 0.30), .clear], center: .center, startRadius: 0, endRadius: 95))
                    .frame(width: 180, height: 150).blur(radius: 18)
                    .scaleEffect(auraExpanded ? 1.08 : 0.94)
                    .opacity(auraExpanded ? 1 : 0.78)
                    .accessibilityHidden(true)
                Image("LightmarkIcon", bundle: .main)
                    .resizable().scaledToFit().frame(width: 92, height: 92)
                    .accessibilityLabel("Lightmark")
            }.frame(width: 92, height: 92)
            if intro {
                Text("Lightmark")
                    .font(.custom("InstrumentSerif-Regular", size: 42))
                    .tracking(-1)
                    .foregroundStyle(LinearGradient(colors: colorScheme == .dark
                        ? [.white, .white.opacity(0.55)]
                        : [Color(white: 0.13), Color(white: 0.27)], startPoint: .top, endPoint: .bottom))
            } else {
                Text(FirstLaunch.shared.isDefault ? "You're ready." : "Use Lightmark for Markdown files?")
                    .font(.system(size: 19, weight: .semibold))
                Text(LocalizedStringKey(error ?? (FirstLaunch.shared.isDefault
                    ? "Lightmark is your default Markdown app."
                    : "Make Lightmark the default app for opening `.md` files")))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    if !FirstLaunch.shared.isDefault {
                        Button("Not Now", action: dismiss).keyboardShortcut(.cancelAction)
                        Button(working ? "Setting Default…" : "Make Default") {
                            working = true
                            Task {
                                do { try await FirstLaunch.shared.makeDefault(); dismiss() }
                                catch { self.error = error.localizedDescription; working = false }
                            }
                        }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(working || !FirstLaunch.shared.isInstalled)
                    } else {
                        Button("Continue", action: dismiss).keyboardShortcut(.defaultAction)
                    }
                }
                .disabled(working)
                .padding(.top, 2)
            }
        }
        .padding(28).frame(width: 390, height: 310)
        .opacity(visible ? 1 : 0)
        .task {
            intro = showIntro
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3125)) { visible = true }
            if showIntro {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 2.1)) { auraExpanded = true }
                do { try await Task.sleep(for: .seconds(reduceMotion ? 0.5 : 2.25)) }
                catch { return }
                if !FirstLaunch.shared.isInstalled || FirstLaunch.shared.isDefault {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { visible = false }
                    try? await Task.sleep(for: .seconds(reduceMotion ? 0 : 0.3))
                    guard !Task.isCancelled else { return }
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { intro = false }
                }
            }
        }
    }
}

extension Notification.Name {
    static let defaultMarkdownAppDidChange = Notification.Name("defaultMarkdownAppDidChange")
}
