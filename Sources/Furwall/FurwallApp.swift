import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import UserNotifications

@main
struct FurwallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        MenuBarExtra {
            MenuView(
                state: appDelegate.state,
                log: appDelegate.eventLog,
                updater: updater.updater
            )
        } label: {
            MenuBarIcon(state: appDelegate.state)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Menu bar icon. Three visual states share an identical frame so the icon never
/// jumps when state flips:
///   - allowed:  cat.fill, system tint (template)
///   - locked:   cat.fill + standard SF slash overlay, orange
///   - paused:   cat.fill, dimmed gray
///
/// All three render through the same ImageRenderer pipeline at the same canvas
/// size — switching states swaps the bitmap in place, no layout shift.
struct MenuBarIcon: View {
    @ObservedObject var state: AppState

    var body: some View {
        Image(nsImage: rendered)
    }

    private var rendered: NSImage {
        // Use the debounced flag — actual gate stays strict, but icon waits ~0.7s
        // before flipping to red so brief Vision settling doesn't flash on the bar.
        if state.iconShouldShowBlocking {
            return Self.renderCat(slashed: true, baked: Color(nsColor: .systemRed))
        }
        // Not blocking: template image at reduced alpha. System handles light/dark.
        return Self.renderCat(slashed: false, baked: nil, alpha: 0.6)
    }

    private var isPaused: Bool {
        if let until = state.pausedUntil, until > Date() { return true }
        return false
    }

    /// Render `cat.fill`, optionally with the SF Symbols-standard diagonal slash.
    ///
    /// - `baked: someColor` → non-template image, color baked in (use for the
    ///   blocked-state red — we want the alert color regardless of appearance).
    /// - `baked: nil` → template image, alpha-only. The system tints to white in
    ///   dark menu bar / dark in light menu bar — works correctly without us
    ///   having to detect appearance (which is unreliable for LSUIElement apps).
    ///
    /// `alpha` < 1 reduces the bitmap's opacity before template tinting, giving
    /// us a "secondary" tone that adapts to the menu bar's appearance for free.
    @MainActor
    private static func renderCat(
        slashed: Bool,
        baked: Color?,
        alpha: Double = 1.0
    ) -> NSImage {
        let canvas = CGSize(width: 18, height: 18)
        let drawColor: Color = baked ?? Color.black

        let view = ZStack {
            Group {
                if slashed {
                    Image(systemName: "cat.fill")
                        .mask(SlashMaskedRegion().fill(style: FillStyle(eoFill: true)))
                } else {
                    Image(systemName: "cat.fill")
                }
            }
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(drawColor)

            if slashed {
                SlashStrokePath()
                    .fill(drawColor)
            }
        }
        .opacity(alpha)
        .frame(width: canvas.width, height: canvas.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let img = renderer.nsImage else {
            return NSImage(size: canvas)
        }
        img.isTemplate = (baked == nil)
        return img
    }
}

/// The mask that punches a thin diagonal gap through the cat where the slash will
/// sit. Even-odd fill rule: the outer rect = visible region, the inner parallelogram
/// = transparent. Coords match the SF Symbols 32×32 design grid.
private struct SlashMaskedRegion: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 32.0
        var p = Path()
        // Full bounding rect (everything visible by default)
        p.addRect(rect)
        // Punched gap parallelogram (taken verbatim from mic.slash.fill mask)
        p.move(to: CGPoint(x: 24.30 * s, y: 27.64 * s))
        p.addCurve(to: CGPoint(x: 27.92 * s, y: 27.62 * s),
                   control1: CGPoint(x: 25.30 * s, y: 28.64 * s),
                   control2: CGPoint(x: 26.95 * s, y: 28.64 * s))
        p.addCurve(to: CGPoint(x: 27.91 * s, y: 24.04 * s),
                   control1: CGPoint(x: 28.89 * s, y: 26.63 * s),
                   control2: CGPoint(x: 28.89 * s, y: 25.04 * s))
        p.addLine(to: CGPoint(x: 7.55 * s, y: 3.71 * s))
        p.addCurve(to: CGPoint(x: 3.93 * s, y: 3.71 * s),
                   control1: CGPoint(x: 6.57 * s, y: 2.71 * s),
                   control2: CGPoint(x: 4.93 * s, y: 2.71 * s))
        p.addCurve(to: CGPoint(x: 3.93 * s, y: 7.32 * s),
                   control1: CGPoint(x: 2.95 * s, y: 4.68 * s),
                   control2: CGPoint(x: 2.95 * s, y: 6.33 * s))
        p.closeSubpath()
        return p
    }
}

/// The slash itself — a thin rounded parallelogram from upper-left to lower-right.
/// Path verbatim from `mic.slash.fill`'s slash layer.
private struct SlashStrokePath: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 32.0
        var p = Path()
        p.move(to: CGPoint(x: 25.39 * s, y: 26.57 * s))
        p.addCurve(to: CGPoint(x: 26.83 * s, y: 26.57 * s),
                   control1: CGPoint(x: 25.79 * s, y: 26.96 * s),
                   control2: CGPoint(x: 26.43 * s, y: 26.96 * s))
        p.addCurve(to: CGPoint(x: 26.83 * s, y: 25.13 * s),
                   control1: CGPoint(x: 27.21 * s, y: 26.16 * s),
                   control2: CGPoint(x: 27.22 * s, y: 25.53 * s))
        p.addLine(to: CGPoint(x: 6.47 * s, y: 4.79 * s))
        p.addCurve(to: CGPoint(x: 5.03 * s, y: 4.79 * s),
                   control1: CGPoint(x: 6.08 * s, y: 4.41 * s),
                   control2: CGPoint(x: 5.42 * s, y: 4.39 * s))
        p.addCurve(to: CGPoint(x: 5.03 * s, y: 6.22 * s),
                   control1: CGPoint(x: 4.64 * s, y: 5.18 * s),
                   control2: CGPoint(x: 4.64 * s, y: 5.84 * s))
        p.closeSubpath()
        return p
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    let eventLog = EventLog()
    private var faceDetector: FaceDetector?
    private var gate: KeyboardGate?
    private var permissionRetryTimer: Timer?
    private var iconDebounceTimer: Timer?
    /// First time we observed shouldAllowInput=false in the current "blocking" run.
    /// Reset to nil whenever it goes true. Used for the icon's debounce.
    private var blockingSince: Date?

    /// Throttle: mouse-move events fire ~60-120 Hz during normal use; we only
    /// need to poke the camera ~once a second.
    private var lastPokeAt: CFTimeInterval = 0

    /// Coalesce rapid block events into a single log entry per "burst" — a cat
    /// pressing 50 keys in 2 seconds is one event for stats purposes.
    private var lastLoggedBlockAt: Date = .distantPast
    private let blockBurstWindow: TimeInterval = 2.0

    /// KVO token for system appearance changes. Drives runtime swap of the app
    /// icon (Any variant in light mode, AppIcon-Dark.icns in dark mode). The
    /// asset catalog can't reliably ship a dark variant for macOS app icons —
    /// actool drops them — so we do the swap here. Affects in-app surfaces
    /// that read `NSApp.applicationIconImage` (the onboarding hero is the
    /// main one, since LSUIElement = no Dock tile).
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.totalBlocks = eventLog.recentBlocks(within: 365 * 10)

        // Sweep the catpures folder for false positives the classifier already
        // identified as human-only. Runs in the background so launch isn't
        // blocked. Idempotent — missing files are skipped.
        Task.detached(priority: .utility) { [eventLog] in
            _ = eventLog.sweepNonCatCatpures()
        }

        // Apply the right icon for the current appearance, and keep it in
        // sync as the user toggles light/dark in System Settings.
        applyDynamicAppIcon()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.applyDynamicAppIcon() }
        }

        // Request notification permission for the panic banner. Silent if denied.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // First-launch onboarding window. Polls Camera + Accessibility status
        // so the user never has to relaunch after toggling AX on. No-op on
        // subsequent launches.
        OnboardingController.shared.showIfNeeded()

        // Up-front explicit permission requests. Both will surface the system prompt
        // if the user hasn't decided yet; if already decided, they no-op.
        requestCameraPermission()
        requestAccessibilityPermission()

        // Detector: publishes face-seen timestamps + camera on/off state to AppState.
        let detector = FaceDetector(
            onSeen: { [weak self] date in
                self?.state.lastFaceSeen = date
            },
            onCameraStateChange: { [weak self] active in
                guard let self = self else { return }
                self.state.cameraActive = active
                if active {
                    self.state.cameraWokeAt = Date()
                    self.state.cameraProducedFrame = false
                    self.state.lastInferenceAt = nil
                } else {
                    self.state.cameraWokeAt = nil
                    self.state.cameraProducedFrame = false
                }
            },
            onFirstFrameAfterWake: { [weak self] in
                self?.state.cameraProducedFrame = true
            },
            onInferenceComplete: { [weak self] in
                self?.state.lastInferenceAt = Date()
            }
        )
        self.faceDetector = detector

        // Pre-warm the camera on signals that mean "user is back at the keyboard"
        // so by the time they type, the camera is already producing frames and
        // lastFaceSeen is recent. Three sources: workspace wake, screen unlock,
        // and any mouse-down (sparse, cheap to monitor).
        installPrewarmHooks()

        // Icon debounce. Polls every 100ms and updates state.iconShouldShowBlocking
        // — only flips to true when the gate has been blocking for >0.7s. Stops
        // brief Vision settling moments from flashing red on the menu bar.
        iconDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.state.shouldAllowInput {
                    self.blockingSince = nil
                    if self.state.iconShouldShowBlocking { self.state.iconShouldShowBlocking = false }
                } else {
                    if self.blockingSince == nil { self.blockingSince = Date() }
                    let elapsed = Date().timeIntervalSince(self.blockingSince!)
                    let shouldShow = elapsed >= self.state.iconBlockDebounceSeconds
                    if self.state.iconShouldShowBlocking != shouldShow {
                        self.state.iconShouldShowBlocking = shouldShow
                    }
                }
            }
        }

        // Gate: synchronously consults state.shouldAllowInput, drops events on miss.
        // shouldPass / onBlock / onPass run on the CGEventTap thread — keep them tight,
        // hop to main for state mutation only.
        let gate = KeyboardGate(
            shouldPass: { [weak self] in
                guard let self = self else { return true }
                // Cheap synchronous read of @Published — fine to call from non-main
                // because we never mutate from the tap thread.
                return MainActor.assumeIsolated { self.state.shouldAllowInput }
            },
            onBlock: { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in
                    self.handleBlock()
                    self.faceDetector?.poke()
                }
            },
            onPass: { [weak self] in
                Task { @MainActor in self?.faceDetector?.poke() }
            },
            onPanic: { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
                    // 5 Escapes in 1.5s = "let me out." Pause for 5 minutes,
                    // log it, post a banner so the user knows it worked.
                    self.state.pausedUntil = Date().addingTimeInterval(5 * 60)
                    self.eventLog.recordPanic(at: Date())
                    self.notifyPanic()
                }
            }
        )
        gate.start()
        self.gate = gate

        // If the gate didn't install (Accessibility not yet granted), poll until it
        // does. The user may flip the toggle while the app is running and we want to
        // pick that up without requiring a relaunch.
        if !gate.isInstalled {
            state.gateInstalled = false
            permissionRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                guard let self = self, let gate = self.gate else { timer.invalidate(); return }
                if AXIsProcessTrusted() {
                    gate.start()
                    if gate.isInstalled {
                        Task { @MainActor in
                            self.state.gateInstalled = true
                        }
                        timer.invalidate()
                    }
                }
            }
        } else {
            state.gateInstalled = true
        }
    }

    /// Pick the right app-icon variant for the current system appearance and
    /// install it via `NSApp.applicationIconImage`. Light mode = bundle
    /// default (the Any variant from Assets.xcassets); dark mode =
    /// AppIcon-Dark.icns loaded from the bundle. Called once at launch and
    /// again whenever `NSApp.effectiveAppearance` changes.
    private func applyDynamicAppIcon() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [
            .darkAqua, .vibrantDark,
            .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark,
        ]) != nil

        if isDark,
           let path = Bundle.main.path(forResource: "AppIcon-Dark", ofType: "icns"),
           let dark = NSImage(contentsOfFile: path) {
            NSApp.applicationIconImage = dark
        } else {
            // nil = revert to the bundle's default (the Any variant).
            NSApp.applicationIconImage = nil
        }
    }

    /// Fire the system Camera permission dialog if the user hasn't decided yet.
    /// On already-granted or already-denied, this is a no-op.
    private func requestCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        default:
            break
        }
    }

    /// Register Furwall in the Accessibility list silently, without showing
    /// the system "Accessibility Access" prompt. Our welcome window already
    /// explains the request and offers a deep-link button to System Settings;
    /// the OS dialog spawns *behind* our floating panel and doesn't auto-
    /// dismiss when the user grants access, which reads as broken.
    /// `prompt: false` still registers the process so it shows up as a
    /// togglable row in System Settings → Privacy & Security → Accessibility.
    private func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: false] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Wake-the-camera-early hooks. The point is to have the camera producing
    /// frames *before* the user's first keystroke, so cold-start latency hits
    /// only the most adversarial path (return-and-immediately-type-without-mouse).
    private func installPrewarmHooks() {
        let nc = NSWorkspace.shared.notificationCenter

        // System resumed from sleep.
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.faceDetector?.poke()
        }
        // Display turned on (lid open, monitor woke).
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.faceDetector?.poke()
        }
        // User session became active (login, fast-user-switch back to us).
        nc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.faceDetector?.poke()
        }
        // Frontmost app changed — user just switched apps and is often about
        // to type. Cheap signal, gets the camera spinning before the first
        // keystroke arrives. Doesn't fire on intra-app focus changes.
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.faceDetector?.poke()
        }

        // Global mouse monitor: any motion or click pokes the camera. Movement
        // is the most reliable "user is back" signal — the user often nudges the
        // mouse before they type, with no click. Throttled to 1 Hz so we don't
        // burn cycles on every 60-120 Hz mouse delta.
        NSEvent.addGlobalMonitorForEvents(matching: [
            .mouseMoved,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged,
        ]) { [weak self] _ in
            guard let self = self else { return }
            let now = CACurrentMediaTime()
            guard now - self.lastPokeAt > 1.0 else { return }
            self.lastPokeAt = now
            self.faceDetector?.poke()
        }
    }

    /// Surface the panic-key unlock as a transient banner so the user knows it
    /// worked. Uses UNUserNotificationCenter — falls back silently if the
    /// notification permission hasn't been granted.
    private func notifyPanic() {
        let content = UNMutableNotificationContent()
        content.title = "Furwall Paused"
        content.body = "Five Escapes detected. Keyboard unlocked for 5 minutes."
        let req = UNNotificationRequest(
            identifier: "furwall.panic.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    private func handleBlock() {
        let now = Date()
        state.lastBlockAt = now
        // Coalesce: don't log a second block-event within the burst window.
        guard now.timeIntervalSince(lastLoggedBlockAt) > blockBurstWindow else { return }
        lastLoggedBlockAt = now
        state.totalBlocks += 1

        // Catpure the current camera frame ~400ms later — gives the camera a beat
        // to pull a fresh frame after waking from sleep, and lets the cat actually
        // be on the keyboard when we shoot. If catpure fails (no frame yet), we
        // still log the block, just without the photo.
        let catpureURL = EventLog.newCatpureURL(for: now)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self = self else { return }
            self.faceDetector?.catpureSnapshot(to: catpureURL) { success in
                let path = success ? catpureURL.path : nil
                if success {
                    Task { @MainActor in
                        self.state.lastCatpurePath = catpureURL.path
                    }
                }
                // Classify off the main actor — the result determines whether
                // the headline "N cats blocked today" stat counts this entry.
                // If catpure failed (no frame), record without classification;
                // it'll fall under "blocked but unverified" and won't count
                // toward the cat tally.
                Task {
                    let result: CatpureClassifier.Result?
                    if let path {
                        result = await CatpureClassifier.classify(
                            jpegURL: URL(fileURLWithPath: path)
                        )
                    } else {
                        result = nil
                    }
                    // Catpures folder is cat-confirmed only. Anything the
                    // classifier didn't tag as a cat — confirmed humans,
                    // "unverified" frames where Vision missed both species,
                    // and frames where classification failed outright — gets
                    // deleted. Keeps the folder reviewable as a cat catalog
                    // rather than a privacy hazard. The JSONL audit entry is
                    // preserved either way; only the path is nulled.
                    var loggedPath = path
                    if result?.containsCat != true, let path {
                        try? FileManager.default.removeItem(atPath: path)
                        loggedPath = nil
                    }
                    await MainActor.run {
                        self.eventLog.recordBlock(
                            at: now,
                            catpurePath: loggedPath,
                            containsCat: result?.containsCat,
                            containsHuman: result?.containsHuman
                        )
                    }
                }
            }
        }
    }
}
