import Foundation
import Combine

/// Shared mutable state for the menu bar UI + the keyboard gate's pass/block decision.
@MainActor
final class AppState: ObservableObject {
    /// Last time the face detector saw a human face. nil = no scan completed yet.
    /// The keyboard gate considers a face "still present" within graceSeconds of this.
    @Published var lastFaceSeen: Date?

    /// Manual user pause — "let me type without checking for N minutes."
    @Published var pausedUntil: Date?

    /// Screen is currently locked. While locked, Furwall steps out of the way
    /// entirely — the lock screen has its own input gate, and watching the
    /// camera is both pointless and privacy-bad. Toggled by the
    /// com.apple.screenIsLocked / IsUnlocked distributed notifications.
    @Published var screenLocked: Bool = false

    /// True while the camera is actively powered on (drives the green dot).
    /// The detector publishes this so the menu can show a subtle "watching" indicator.
    @Published var cameraActive: Bool = false

    /// Running tally of blocked keystroke bursts since first launch.
    @Published var totalBlocks: Int = 0

    /// Most recent block timestamp — drives the menu's "Whiskers tried 3 minutes ago" line.
    @Published var lastBlockAt: Date?

    /// Whether the CGEventTap is actually installed. False until Accessibility
    /// permission is granted; the AppDelegate's retry timer flips it true.
    @Published var gateInstalled: Bool = false

    /// Path to the most recent block-catpure JPEG, or nil. Drives the menu thumbnail.
    @Published var lastCatpurePath: String?

    /// When the camera last transitioned from off → on. Used by the cold-start
    /// grace window so the user's first keystroke after returning to the computer
    /// doesn't get eaten while the camera spins up.
    @Published var cameraWokeAt: Date?

    /// Has the camera produced a frame (with or without a face) since wake?
    /// Once a single frame arrives we know the cold-start grace can end — if no
    /// face is in that frame, lockout kicks in immediately rather than waiting
    /// out the full grace window. This prevents cats from getting free keys
    /// during cold-start.
    @Published var cameraProducedFrame: Bool = false

    /// Last time a Vision inference pass completed (success or thrown). If this
    /// goes stale while the camera is supposedly active, something is wrong —
    /// camera grabbed by another process, hardware hiccup, frames not flowing.
    /// We fail open in that case rather than soft-bricking the keyboard.
    @Published var lastInferenceAt: Date?

    /// How long to optimistically pass keystrokes after camera wake while we
    /// wait for the first frame.
    let coldStartGraceSeconds: TimeInterval = 1.5

    /// If the camera has been awake longer than this without a successful
    /// inference, we treat Vision as stuck and fail open with a menu warning.
    let inferenceStaleSeconds: TimeInterval = 10.0

    /// Debounced version of `!shouldAllowInput` — only true when the gate has been
    /// blocking for at least `iconBlockDebounceSeconds`. Drives the menu bar icon
    /// so brief flips during Vision settling don't cause a red flash.
    @Published var iconShouldShowBlocking: Bool = false

    /// Anti-flicker for the icon. The actual gate stays strict (drops keys
    /// immediately on a no-face decision); the icon is more chill.
    let iconBlockDebounceSeconds: TimeInterval = 0.7


    /// Grace window: a face seen within this many seconds counts as "still present."
    /// Avoids locking the keyboard the moment you glance at a second monitor.
    let graceSeconds: TimeInterval = 5.0

    /// Vision pipeline appears stuck — camera up but no successful inference in
    /// the staleness window. We fail open + flag for the menu so the user knows
    /// something's off rather than getting silently locked out.
    var visionAppearsStuck: Bool {
        guard cameraActive else { return false }
        guard let woke = cameraWokeAt else { return false }
        // Cold-start: don't claim "stuck" until we've waited longer than the
        // staleness window since wake.
        guard Date().timeIntervalSince(woke) > inferenceStaleSeconds else { return false }
        guard let last = lastInferenceAt else { return true }
        return Date().timeIntervalSince(last) > inferenceStaleSeconds
    }

    /// Resolved gate decision: should the next keystroke pass through?
    var shouldAllowInput: Bool {
        if screenLocked { return true }
        if let until = pausedUntil, until > Date() { return true }

        // Recent face → pass.
        if let last = lastFaceSeen, Date().timeIntervalSince(last) < graceSeconds {
            return true
        }

        // Cold-start grace: camera just woke up, no frame produced yet, give it a
        // beat. Cancelled the moment the first frame arrives without a face — see
        // FaceDetector → onFrame.
        if let woke = cameraWokeAt,
           !cameraProducedFrame,
           Date().timeIntervalSince(woke) < coldStartGraceSeconds {
            return true
        }

        // Vision pipeline broke (camera grabbed by another app, frames stopped).
        // Fail open rather than locking the user out of their machine — they'll
        // see the warning in the menu and can fix it.
        if visionAppearsStuck { return true }

        // First-launch warm-up — no scan ever — fail open until camera has had a
        // turn. After that, lastFaceSeen drives the decision.
        if lastFaceSeen == nil && cameraWokeAt == nil { return true }

        return false
    }
}
