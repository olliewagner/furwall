import SwiftUI
import Sparkle

/// Sparkle integration. Boots the updater at launch (daily schedule, see
/// `SUScheduledCheckInterval` in Info.plist) and exposes a menu item that
/// reflects `canCheckForUpdates` so it's only tappable when the updater isn't
/// already mid-check.
final class UpdaterController: ObservableObject {
    let controller: SPUStandardUpdaterController

    init() {
        // Pass `startingUpdater: true` so Sparkle begins its background poll
        // immediately. Delegates are `nil` — defaults are correct for an
        // unsandboxed Developer-ID app shipping outside the App Store.
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater { controller.updater }
}

/// Drives the menu item's enabled/disabled state from the updater's
/// `canCheckForUpdates` Combine publisher. Without this, the item would stay
/// enabled while a check is in flight and double-clicks would no-op silently.
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesMenuItem: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!viewModel.canCheckForUpdates)
    }
}
