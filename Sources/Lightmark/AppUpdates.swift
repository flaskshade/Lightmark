import SwiftUI
import Sparkle

/// Sparkle owns download verification, installation and relaunch. AppKit remains
/// responsible for reviewing unsaved documents before the application terminates.
@MainActor
final class AppUpdates: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = AppUpdates()
    private var controller: SPUStandardUpdaterController!
    @Published private(set) var canCheck = false
    @Published private(set) var availableVersion: String?
    private var observation: NSKeyValueObservation?

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let available = change.newValue ?? false
            Task { @MainActor in self?.canCheck = available }
        }
    }

    func start() {
        // Development bundles must never install production updates over themselves.
        #if !DEBUG
        controller.startUpdater()
        #endif
    }

    func check() { controller.checkForUpdates(nil) }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var updates = AppUpdates.shared
    var body: some View {
        Button("Check for Updates…") { updates.check() }
            .disabled(!updates.canCheck)
    }
}


extension AppUpdates {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
    }

    func standardUserDriverWillFinishUpdateSession() { availableVersion = nil }
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
