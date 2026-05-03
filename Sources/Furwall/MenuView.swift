import SwiftUI
import AppKit

struct MenuView: View {
    /// Plain reference, NOT @ObservedObject — see `Snapshot` below.
    let state: AppState
    let log: EventLog

    @State private var weekBlocks: Int = 0
    @State private var dayBlocks: Int = 0
    @State private var openAtLogin: Bool = LoginItem.isEnabled
    @State private var snapshot: Snapshot

    /// Frozen copy of the AppState fields the menu reads. We snapshot at open
    /// time and render exclusively from this — observing AppState live causes
    /// the menu to re-lay-out under the user's cursor every time the camera
    /// pipeline ticks (every ~100ms), shifting button rows mid-hover and
    /// landing clicks on the wrong item.
    ///
    /// We deliberately do NOT include lock/unlock status here. The menu bar
    /// icon is the canonical surface for that — restating it inside the menu
    /// risks the two views drifting (snapshot is frozen at open, icon updates
    /// live via the debounce timer).
    private struct Snapshot {
        var gateInstalled: Bool = true
        var pausedUntil: Date? = nil
    }

    init(state: AppState, log: EventLog) {
        self.state = state
        self.log = log
        self._snapshot = State(initialValue: Snapshot(
            gateInstalled: state.gateInstalled,
            pausedUntil: state.pausedUntil
        ))
    }

    var body: some View {
        Group {
            if !snapshot.gateInstalled {
                permissionSection
                Divider()
            }
            statsSection
            Button("Reveal Catpures") {
                NSWorkspace.shared.open(EventLog.catpuresDir)
            }
            // Resume only appears when paused — manual pause buttons are gone;
            // the only thing that sets pausedUntil now is the Escape-mash panic
            // (5-minute auto-pause). Users who don't want to wait it out tap Resume.
            if let until = snapshot.pausedUntil, until > Date() {
                Divider()
                Button("Resume") { state.pausedUntil = nil }
            }
            Divider()
            Toggle("Open at Login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { newValue in
                    let actual = LoginItem.setEnabled(newValue)
                    if actual != newValue { openAtLogin = actual }
                }
            Button("Donate to Help Animals…") {
                DonateController.shared.present()
            }
            Button("About Furwall…") {
                AboutController.shared.present()
            }
            Button("Quit Furwall") { NSApplication.shared.terminate(nil) }
        }
        .onAppear {
            refreshStats()
            snapshot = Snapshot(
                gateInstalled: state.gateInstalled,
                pausedUntil: state.pausedUntil
            )
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        Text("Accessibility access required")
        Button("Open Accessibility Settings…") {
            // Direct deep-link into the Accessibility privacy pane.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @ViewBuilder
    private var statsSection: some View {
        // Single stat line — Apple-style restraint. Counts only catpures the
        // post-hoc Vision classifier confirmed as cats, so the number is
        // verifiable rather than aspirational. Unverified blocks (no frame
        // saved, classifier returned no cat) don't count.
        Text("\(dayBlocks) cats blocked today")
    }

    private func refreshStats() {
        // Verified cats — only catpures the post-hoc Vision classifier confirmed.
        dayBlocks = log.recentCatBlocks(within: 1)
        weekBlocks = log.recentCatBlocks(within: 7)
    }
}
