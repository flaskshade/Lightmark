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
    @Published fileprivate(set) var isChecking = false
    @Published fileprivate(set) var checkResult: String?
    @Published private(set) var feedback: String?
    private var feedbackTask: Task<Void, Never>?
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

    func activateUpdate() { driver.activateInline() }
    func cancelDownload() { driver.cancelInlineDownload() }

    func check() {
        if driver.hasPendingOffer {
            showFeedback("Update available")
        } else if canCheck && !isChecking {
            checkResult = nil
            isChecking = true
            updater.checkForUpdates()
        }
    }

    fileprivate func showFeedback(_ message: String) {
        feedbackTask?.cancel()
        feedback = message
        feedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.feedback = nil
        }
    }
}

/// Update checks and header-initiated downloads stay inline.
/// Sparkle owns the trust and installation machinery for both paths.
@MainActor
private final class LightmarkUpdateDriver: SPUStandardUserDriver {
    weak var owner: AppUpdates?
    private var pendingReply: ((SPUUserUpdateChoice) -> Void)?
    private var offeredBuild: String?
    private var inlineFlow = false
    private var cancellation: (() -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var retryTermination: (() -> Void)?
    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0
    var hasPendingOffer: Bool { pendingReply != nil }

    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        owner?.isChecking = false
        owner?.checkResult = nil
        // Informational releases retain Sparkle’s standard presentation.
        guard !appcastItem.isInformationOnlyUpdate else {
            super.showUpdateFound(with: appcastItem, state: state, reply: reply)
            return
        }
        super.dismissUpdateInstallation()
        offeredBuild = appcastItem.versionString
        pendingReply = reply
        owner?.availableVersion = appcastItem.displayVersionString
        if state.stage != .notDownloaded {
            inlineFlow = true
            owner?.headerState = .ready
        } else {
            owner?.headerState = .available
        }
    }

    override func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        owner?.isChecking = true
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
        owner?.isChecking = false
        let reason = (error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber
        let latest = reason?.int32Value == SPUNoUpdateFoundReason.onLatestVersion.rawValue
        let message = latest ? "You’re up to date" : "No update available"
        owner?.checkResult = message
        owner?.showFeedback(message)
        acknowledgement()
    }

    override func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let wasVisible = owner?.isChecking == true || inlineFlow
        owner?.isChecking = false
        if wasVisible {
            owner?.checkResult = "Couldn’t update. Try again"
            owner?.showFeedback("Couldn’t update. Try again later")
        }
        acknowledgement()
    }

    override func showUpdateInFocus() {
        if hasPendingOffer { owner?.showFeedback("Update available") }
    }

    override func dismissUpdateInstallation() {
        pendingReply = nil
        offeredBuild = nil
        inlineFlow = false
        cancellation = nil
        installReply = nil
        retryTermination = nil
        owner?.availableVersion = nil
        owner?.isChecking = false
        owner?.headerState = .available
        owner?.downloadProgress = nil
        super.dismissUpdateInstallation()
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var updates = AppUpdates.shared
    var body: some View {
        Button("Check for Updates…") { updates.check() }
            .disabled(updates.isChecking || (!updates.canCheck && updates.headerState != .available) || (!updates.canCheck && updates.availableVersion == nil))
    }
}

struct HeaderUpdateButton: View {
    var showsLabel = false
    @ObservedObject private var updates = AppUpdates.shared
    private var label: String {
        if updates.isChecking { return "Checking…" }
        return switch updates.headerState {
        case .available: "Update available"
        case .downloading: "Downloading…"
        case .preparing: "Preparing…"
        case .ready: "Restart to update"
        case .restarting: "Restarting…"
        }
    }
    var body: some View {
        if updates.isChecking || updates.availableVersion != nil {
            Button(action: updates.activateUpdate) {
                HStack(spacing: 6) {
                    if updates.isChecking || updates.headerState == .downloading || updates.headerState == .preparing {
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
            .disabled(updates.isChecking || updates.headerState == .downloading || updates.headerState == .preparing || updates.headerState == .restarting)
            .contextMenu {
                if updates.headerState == .downloading {
                    Button("Cancel Download", action: updates.cancelDownload)
                }
            }
            .help(label)
            .accessibilityLabel(label)
        }
    }
}


struct SettingsUpdateSection: View {
    @ObservedObject private var updates = AppUpdates.shared

    private var status: String {
        if updates.isChecking { return "Checking for updates…" }
        if updates.availableVersion != nil {
            return switch updates.headerState {
            case .available: "Update available"
            case .downloading: "Downloading update…"
            case .preparing: "Preparing update…"
            case .ready: "Update ready"
            case .restarting: "Restarting…"
            }
        }
        return updates.checkResult ?? "Check for Updates…"
    }

    var body: some View {
        VStack(spacing: 10) {
            Button(action: updates.check) {
                HStack(spacing: 7) {
                    if updates.isChecking {
                        ProgressView().controlSize(.small).frame(width: 14, height: 14)
                    }
                    Text(status)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(UpdateSettingsButtonStyle())
            .disabled(updates.isChecking || updates.availableVersion != nil || !updates.canCheck)

            if let version = updates.availableVersion {
                Text("Lightmark \(version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                switch updates.headerState {
                case .available, .ready:
                    Button(action: updates.activateUpdate) {
                        Label(updates.headerState == .ready ? "Restart to update" : "Download update",
                              systemImage: updates.headerState == .ready ? "arrow.clockwise" : "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(UpdateSettingsButtonStyle(prominent: true))
                case .downloading, .preparing, .restarting:
                    ProgressView(value: updates.headerState == .downloading ? updates.downloadProgress : nil)
                        .progressViewStyle(.linear)
                        .accessibilityLabel(status)
                    if updates.headerState == .downloading {
                        Button("Cancel download", action: updates.cancelDownload)
                            .buttonStyle(UpdateSettingsButtonStyle())
                    }
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .frame(width: 220)
    }
}

private struct UpdateSettingsButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(prominent
                        ? Color.accentColor.opacity(configuration.isPressed ? 0.70 : (isHovered && isEnabled ? 0.85 : 1))
                        : Color.primary.opacity(configuration.isPressed ? 0.12 : (isHovered && isEnabled ? 0.08 : 0.045)))
            }
            .opacity(isEnabled ? 1 : 0.65)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }
}
