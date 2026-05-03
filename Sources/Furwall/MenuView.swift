import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import Sparkle

struct MenuView: View {
    /// Plain reference, NOT @ObservedObject — see `Snapshot` below.
    let state: AppState
    let log: EventLog
    let updater: SPUUpdater

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
        var pausedUntil: Date? = nil
        // Permissions are sourced from the OS at every menu open, not from
        // AppState. AppState's gateInstalled flag only flips once the
        // CGEventTap has actually installed, which can lag the AX grant by a
        // polling tick — leaning on the OS values directly means the menu
        // never lies about whether the user still has work to do in System
        // Settings.
        var axGranted: Bool = true
        var cameraGranted: Bool = true
    }

    init(state: AppState, log: EventLog, updater: SPUUpdater) {
        self.state = state
        self.log = log
        self.updater = updater
        self._snapshot = State(initialValue: Snapshot(
            pausedUntil: state.pausedUntil,
            axGranted: AXIsProcessTrusted(),
            cameraGranted: AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        ))
    }

    var body: some View {
        Group {
            if !snapshot.cameraGranted {
                Text("Camera access required")
                Button("Open Camera Settings…") {
                    openSettings(pane: "Privacy_Camera")
                }
                Divider()
            } else if !snapshot.axGranted {
                Text("Accessibility access required")
                Button("Open Accessibility Settings…") {
                    openSettings(pane: "Privacy_Accessibility")
                }
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
            CheckForUpdatesMenuItem(updater: updater)
            Button("About Furwall…") {
                AboutController.shared.present()
            }
            Button("Quit Furwall") { NSApplication.shared.terminate(nil) }
        }
        .onAppear {
            refreshStats()
            snapshot = Snapshot(
                pausedUntil: state.pausedUntil,
                axGranted: AXIsProcessTrusted(),
                cameraGranted: AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            )
        }
    }

    @ViewBuilder
    private var statsSection: some View {
        // Single stat line — Apple-style restraint. Counts only catpures the
        // post-hoc Vision classifier confirmed as cats, so the number is
        // verifiable rather than aspirational. Unverified blocks (no frame
        // saved, classifier returned no cat) don't count.
        //
        // `^[…](inflect: true)` is Foundation's Automatic Grammar Agreement
        // markup — picks the right singular/plural form per locale at render
        // time, so "1 cat" / "2 cats" comes for free and the same string
        // localises cleanly later without code changes.
        if dayBlocks == 0 {
            Text("No cats blocked today")
        } else {
            Text("^[\(dayBlocks) cat](inflect: true) blocked today")
        }
    }

    private func refreshStats() {
        // Verified cats — only catpures the post-hoc Vision classifier confirmed.
        dayBlocks = log.recentCatBlocks(within: 1)
        weekBlocks = log.recentCatBlocks(within: 7)
    }

    private func openSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
