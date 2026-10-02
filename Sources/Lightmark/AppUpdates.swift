import SwiftUI
import Sparkle

/// Sparkle owns download verification, installation and relaunch. AppKit remains
/// responsible for reviewing unsaved documents before the application terminates.
@MainActor
final class AppUpdates: NSObject, ObservableObject {
    static let shared = AppUpdates()
    private var updater: SPUUpdater!
    private var driver: LightmarkUpdateDriver!
    enum HeaderState { case available, downloading, preparing, ready, restarting }
    @Published fileprivate(set) var headerState = HeaderState.available
    @Published fileprivate(set) var downloadProgress: Double?
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

    func activateHeader() { driver.activateInline() }
    func cancelDownload() { driver.cancelInlineDownload() }

    func check() {
        if driver.hasPendingOffer { driver.presentOffer() }
        else { updater.checkForUpdates() }
    }
}

/// Header-initiated updates stay inline; explicit menu checks use native dialogs.
/// Sparkle owns the trust and installation machinery for both paths.
@MainActor
private final class LightmarkUpdateDriver: SPUStandardUserDriver {
    weak var owner: AppUpdates?
    private var pendingReply: ((SPUUserUpdateChoice) -> Void)?
    private var offeredVersion: String?
    private var offeredBuild: String?
    private var presenting = false
    private var inlineFlow = false
    private var cancellation: (() -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var retryTermination: (() -> Void)?
    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0
    var hasPendingOffer: Bool { pendingReply != nil }

    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // Informational releases retain Sparkle’s standard presentation.
        guard !appcastItem.isInformationOnlyUpdate else {
            super.showUpdateFound(with: appcastItem, state: state, reply: reply)
            return
        }
        super.dismissUpdateInstallation()
        offeredBuild = appcastItem.versionString
        offeredVersion = appcastItem.displayVersionString
        pendingReply = reply
        owner?.availableVersion = offeredVersion
        if state.stage != .notDownloaded {
            inlineFlow = true
            owner?.headerState = .ready
        } else if state.userInitiated { presentOffer() }
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

    func activateInline() {
        if let reply = pendingReply {
            pendingReply = nil
            inlineFlow = true
            owner?.headerState = owner?.headerState == .ready ? .restarting : .downloading
            if let build = offeredBuild { UserDefaults.standard.set(build, forKey: "pendingUpdateBuild") }
            reply(.install)
        } else if let reply = installReply {
            installReply = nil
            owner?.headerState = .restarting
            reply(.install)
        } else if let retry = retryTermination {
            owner?.headerState = .restarting
            retry()
        }
    }

    func cancelInlineDownload() {
        let cancel = cancellation
        cancellation = nil
        cancel?()
    }

    override func showDownloadInitiated(cancellation: @escaping () -> Void) {
        guard inlineFlow else { super.showDownloadInitiated(cancellation: cancellation); return }
        self.cancellation = cancellation
        expectedBytes = 0
        receivedBytes = 0
        owner?.headerState = .downloading
        owner?.downloadProgress = nil
    }

    override func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        guard inlineFlow else { super.showDownloadDidReceiveExpectedContentLength(expectedContentLength); return }
        expectedBytes = expectedContentLength
    }

    override func showDownloadDidReceiveData(ofLength length: UInt64) {
        guard inlineFlow else { super.showDownloadDidReceiveData(ofLength: length); return }
        receivedBytes += length
        let progress = expectedBytes > 0 ? min(1, Double(receivedBytes) / Double(expectedBytes)) : nil
        // Avoid redrawing the header for every network chunk.
        if let progress, progress - (owner?.downloadProgress ?? -1) >= 0.01 || progress == 1 {
            owner?.downloadProgress = progress
        }
    }

    override func showDownloadDidStartExtractingUpdate() {
        guard inlineFlow else { super.showDownloadDidStartExtractingUpdate(); return }
        cancellation = nil
        owner?.headerState = .preparing
        owner?.downloadProgress = nil
    }

    override func showExtractionReceivedProgress(_ progress: Double) {
        if !inlineFlow { super.showExtractionReceivedProgress(progress) }
    }

    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard inlineFlow else { super.showReady(toInstallAndRelaunch: reply); return }
        installReply = reply
        owner?.headerState = .ready
    }

    override func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        guard inlineFlow else {
            super.showInstallingUpdate(withApplicationTerminated: applicationTerminated, retryTerminatingApplication: retryTerminatingApplication)
            return
        }
        // Cancellation of a native unsaved-document review must remain retryable.
        retryTermination = applicationTerminated ? nil : retryTerminatingApplication
        owner?.headerState = applicationTerminated ? .restarting : .ready
    }

    override func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let reason = (error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber
        guard let reason, reason.int32Value == SPUNoUpdateFoundReason.onLatestVersion.rawValue else {
            super.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
            return
        }
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
        if hasPendingOffer && !inlineFlow { presentOffer() } else if !inlineFlow { super.showUpdateInFocus() }
    }

    override func dismissUpdateInstallation() {
        pendingReply = nil
        offeredVersion = nil
        offeredBuild = nil
        inlineFlow = false
        cancellation = nil
        installReply = nil
        retryTermination = nil
        owner?.availableVersion = nil
        owner?.headerState = .available
        owner?.downloadProgress = nil
        super.dismissUpdateInstallation()
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var updates = AppUpdates.shared
    var body: some View {
        Button("Check for Updates…") { updates.check() }
            .disabled(!updates.canCheck && updates.availableVersion == nil)
    }
}

struct HeaderUpdateButton: View {
    var showsLabel = false
    @ObservedObject private var updates = AppUpdates.shared
    private var label: String {
        switch updates.headerState {
        case .available: "Update available"
        case .downloading: "Downloading…"
        case .preparing: "Preparing…"
        case .ready: "Restart to update"
        case .restarting: "Restarting…"
        }
    }
    var body: some View {
        if let version = updates.availableVersion {
            Button(action: updates.activateHeader) {
                HStack(spacing: 6) {
                    if updates.headerState == .downloading || updates.headerState == .preparing {
                        ProgressView(value: updates.downloadProgress)
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: updates.headerState == .available ? "arrow.down.circle" : "arrow.clockwise")
                            .font(.system(size: 15, weight: .medium))
                    }
                    if showsLabel {
                        Text(label)
                            .font(.system(size: 12, weight: .medium))
                            .fixedSize()
                    }
                }
                .foregroundStyle(Color.blue)
                .padding(.horizontal, showsLabel ? 8 : 0)
                .frame(width: showsLabel ? 148 : 30, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.borderless)
            .disabled(updates.headerState == .downloading || updates.headerState == .preparing || updates.headerState == .restarting)
            .contextMenu {
                if updates.headerState == .downloading {
                    Button("Cancel Download", action: updates.cancelDownload)
                }
            }
            .help("\(label) · Lightmark \(version)")
            .accessibilityLabel("\(label) · Lightmark \(version)")
        }
    }
}
