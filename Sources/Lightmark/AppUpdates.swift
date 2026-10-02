import SwiftUI
import Sparkle

/// Sparkle owns download verification, installation and relaunch. AppKit remains
/// responsible for reviewing unsaved documents before the application terminates.
@MainActor
final class AppUpdates: NSObject, ObservableObject {
    static let shared = AppUpdates()
    private var updater: SPUUpdater!
    private var driver: LightmarkUpdateDriver!
    @Published private(set) var canCheck = false
    @Published private(set) var showUpdateComplete = false
    @Published fileprivate(set) var availableVersion: String?
    private var observation: NSKeyValueObservation?

    private override init() {
        super.init()
        driver = LightmarkUpdateDriver(hostBundle: .main, delegate: nil)
        driver.owner = self
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let available = change.newValue ?? false
            Task { @MainActor in self?.canCheck = available }
        }
    }

    func start() {
        #if !DEBUG
        if let target = UserDefaults.standard.string(forKey: "pendingUpdateBuild"),
           let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           current.compare(target, options: .numeric) != .orderedAscending {
            UserDefaults.standard.removeObject(forKey: "pendingUpdateBuild")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                showUpdateComplete = true
                try? await Task.sleep(for: .seconds(2.5))
                showUpdateComplete = false
            }
        }
        do { try updater.start() } catch { NSApp.presentError(error) }
        #endif
    }

    func check() {
        if driver.hasPendingOffer { driver.presentOffer() }
        else { updater.checkForUpdates() }
    }
}

/// Customize the offer only; retain Sparkle's standard progress, trust checks,
/// installation and cancellation UI.
@MainActor
private final class LightmarkUpdateDriver: SPUStandardUserDriver {
    weak var owner: AppUpdates?
    private var pendingReply: ((SPUUserUpdateChoice) -> Void)?
    private var offeredVersion: String?
    private var offeredBuild: String?
    private var presenting = false
    var hasPendingOffer: Bool { pendingReply != nil }

    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // Let Sparkle handle exceptional informational updates and resumed installs.
        guard !appcastItem.isInformationOnlyUpdate, state.stage == .notDownloaded else {
            super.showUpdateFound(with: appcastItem, state: state, reply: reply)
            return
        }
        super.dismissUpdateInstallation()
        offeredBuild = appcastItem.versionString
        offeredVersion = appcastItem.displayVersionString
        pendingReply = reply
        owner?.availableVersion = offeredVersion
        if state.userInitiated { presentOffer() }
    }

    func presentOffer() {
        guard !presenting, pendingReply != nil, let version = offeredVersion else { return }
        presenting = true
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let alert = NSAlert()
        alert.messageText = "Lightmark \(version) is available"
        alert.informativeText = "You’re currently using version \(current).\nWould you like to download the latest version?"
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Not Now")
        let link = NSButton(title: "Changelog", target: self, action: #selector(openChangelog))
        link.isBordered = false
        link.font = .systemFont(ofSize: 11)
        link.contentTintColor = .secondaryLabelColor
        link.frame = NSRect(x: 0, y: 0, width: 115, height: 22)
        alert.accessoryView = link
        let response = alert.runModal()
        let reply = pendingReply
        if response == .alertFirstButtonReturn, let build = offeredBuild {
            UserDefaults.standard.set(build, forKey: "pendingUpdateBuild")
        }
        pendingReply = nil
        offeredVersion = nil
        owner?.availableVersion = nil
        presenting = false
        reply?(response == .alertFirstButtonReturn ? .install : .dismiss)
    }

    override func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        super.dismissUpdateInstallation()
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let alert = NSAlert()
        alert.messageText = "You’re up to date"
        alert.informativeText = "Lightmark \(current) is the latest version."
        alert.addButton(withTitle: "OK")
        let link = NSButton(title: "Changelog", target: self, action: #selector(openChangelog))
        link.isBordered = false
        link.font = .systemFont(ofSize: 11)
        link.contentTintColor = .secondaryLabelColor
        link.frame = NSRect(x: 0, y: 0, width: 90, height: 22)
        alert.accessoryView = link
        alert.runModal()
        acknowledgement()
    }

    @objc private func openChangelog() {
        NSWorkspace.shared.open(URL(string: "https://trylightmark.com/changelog/")!)
    }

    override func showUpdateInFocus() {
        if hasPendingOffer { presentOffer() } else { super.showUpdateInFocus() }
    }

    override func dismissUpdateInstallation() {
        pendingReply = nil
        offeredVersion = nil
        owner?.availableVersion = nil
        super.dismissUpdateInstallation()
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var updates = AppUpdates.shared
    var body: some View {
        Button("Check for Updates…") { updates.check() }
            .disabled(!updates.canCheck)
    }
}

struct HeaderUpdateButton: View {
    @ObservedObject private var updates = AppUpdates.shared
    var body: some View {
        if let version = updates.availableVersion {
            Button(action: updates.check) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.borderless)
            .help("Update to Lightmark \(version)")
            .accessibilityLabel("Update to Lightmark \(version)")
        }
    }
}
