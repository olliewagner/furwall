import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices

// Brand colors live in BrandColors.swift (Color.furwallAccent / .furwallAccentText).

/// First-launch onboarding. Explains the app, asks for the two permissions
/// it needs (Camera + Accessibility), and waits — auto-polling — for both to
/// become live before letting the user dismiss it.
///
/// The trick that separates this from "indie tool" feel: the Accessibility row
/// flips to ✓ automatically the moment the user toggles Furwall on in System
/// Settings, no relaunch required. They never have to come back and click anything.
@MainActor
final class OnboardingController {
    static let shared = OnboardingController()
    private let onboardedKey = "furwall.onboarded.v1"
    private var window: NSWindow?

    /// Show on launch when the user needs to do permissions work — either
    /// they've never onboarded, or they've onboarded previously but a required
    /// permission is now missing (revoked in System Settings, OS reset, etc.).
    /// The window is the single canonical surface for permission grants; it
    /// auto-polls and flips its checkmarks live as the user grants in System
    /// Settings, so reappearing it covers the recovery case for free.
    func showIfNeeded() {
        let onboarded = UserDefaults.standard.bool(forKey: onboardedKey)
        let cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let axGranted = AXIsProcessTrusted()
        if onboarded && cameraGranted && axGranted { return }
        present()
    }

    private func present() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(
            onContinue: { [weak self] in
                UserDefaults.standard.set(true, forKey: self?.onboardedKey ?? "")
                self?.close()
            }
        )

        let host = NSHostingController(rootView: view)
        // Let the SwiftUI body's intrinsic size drive the window — keeps the
        // window snug against content instead of a fixed frame stretching the
        // layout with dead space.
        host.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Welcome to Furwall"
        w.isMovableByWindowBackground = true
        // Seed the window with a size close to the SwiftUI body's natural
        // size so the first center() lands in roughly the right spot — keeps
        // the window from visibly snapping into place after layout settles.
        w.setContentSize(NSSize(width: 520, height: 600))
        w.center()
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.delegate = OnboardingWindowDelegate.shared
        OnboardingWindowDelegate.shared.onClose = { [weak self] in self?.window = nil }
        self.window = w

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // SwiftUI's first layout pass runs after we order-front and may resize
        // the window to fit the body's intrinsic height. Re-center on the next
        // runloop turn so the final position is centered no matter what the
        // natural size lands at.
        DispatchQueue.main.async { [weak w] in w?.center() }
    }

    fileprivate func close() {
        window?.close()
        window = nil
    }
}

/// Bridges NSWindow's close into a SwiftUI-friendly callback.
private final class OnboardingWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowDelegate()
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}

private struct OnboardingView: View {
    let onContinue: () -> Void

    @State private var cameraStatus: AVAuthorizationStatus =
        AVCaptureDevice.authorizationStatus(for: .video)
    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var pollTask: Task<Void, Never>?

    var bothGranted: Bool {
        cameraStatus == .authorized && accessibilityGranted
    }

    var body: some View {
        VStack(spacing: 28) {
            hero
            VStack(alignment: .leading, spacing: 22) {
                permissionRow(
                    title: "Camera",
                    detail: "Furwall checks for a human face before allowing keyboard input. Frames never leave your Mac.",
                    glyph: "camera.fill",
                    tint: .furwallAccent,
                    granted: cameraStatus == .authorized,
                    primary: cameraStatus == .notDetermined ? "Allow Camera Access" : nil,
                    secondary: cameraStatus == .denied ? "Open Camera Settings…" : nil,
                    onPrimary: { requestCamera() },
                    onSecondary: { openCameraSettings() }
                )
                permissionRow(
                    title: "Accessibility",
                    detail: "Required to block keystrokes when no one's there. Nothing is ever read or stored.",
                    glyph: "keyboard.fill",
                    tint: .furwallAccent,
                    granted: accessibilityGranted,
                    primary: accessibilityGranted ? nil : "Open Accessibility Settings…",
                    secondary: nil,
                    onPrimary: { openAccessibilitySettings() },
                    onSecondary: nil
                )
            }
            .padding(.horizontal, 36)

            // Trust line. The whole app drops keystrokes, which is the kind of
            // thing users need to feel they can escape from before they install.
            // Three independent fallbacks, named plainly — reassurance, not a
            // warning. Sits just above the CTA so it's the last thing read
            // before clicking through.
            Text("Three ways out: glance at the camera, quit from the menu bar, or tap Escape five times.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
                .padding(.top, 4)

            // Pill-shaped accent button — borrowed from Apple Fitness's pattern.
            Button(action: onContinue) {
                // Single label across all states — disabled state communicates
                // the gating; using two labels read as a different action.
                Text("Start Watching")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(bothGranted ? Color.furwallAccentText : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(bothGranted ? Color.furwallAccent : Color.secondary.opacity(0.18))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!bothGranted)
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
        }
        .frame(width: 520)
        .background(.regularMaterial)
        .onAppear { startPolling() }
        .onDisappear { pollTask?.cancel() }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            // The bundle's app icon (Resources/AppIcon.icns). Falls back to the
            // SF Symbol if for some reason the bundle has no icon set — should
            // never trigger in a shipped build but keeps the preview honest.
            Group {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 128, height: 128)
                } else {
                    Image(systemName: "cat.fill")
                        .font(.system(size: 72, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 128, height: 128)
                }
            }
            Text("Furwall")
                .font(.system(size: 28, weight: .semibold))
            Text("Blocks catasstrophes.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 36)
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        detail: String,
        glyph: String,
        tint: Color,
        granted: Bool,
        primary: String?,
        secondary: String?,
        onPrimary: (() -> Void)?,
        onSecondary: (() -> Void)?
    ) -> some View {
        // Apple Fitness-style row: tinted-circle icon + title + body.
        // When granted, the tinted circle gets a checkmark badge in the
        // corner — keeps the icon stable so the row doesn't shift visually.
        HStack(alignment: .top, spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 38, height: 38)
                    Image(systemName: glyph)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
                if granted {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 16, height: 16)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .overlay(
                        Circle()
                            .stroke(Color(NSColor.windowBackgroundColor), lineWidth: 2)
                    )
                    .offset(x: 2, y: 2)
                }
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    HStack(spacing: 8) {
                        if let primary, let onPrimary {
                            Button(primary, action: onPrimary)
                        }
                        if let secondary, let onSecondary {
                            Button(secondary, action: onSecondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            Task { @MainActor in
                cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }

    private func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openAccessibilitySettings() {
        // First call AXIsProcessTrustedWithOptions to get Furwall registered in
        // the list — without this, it doesn't always appear for the user to toggle.
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Poll both permissions at 1 Hz so the row flips to ✓ the moment the user
    /// grants in System Settings — no relaunch, no manual refresh.
    private func startPolling() {
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                let cam = AVCaptureDevice.authorizationStatus(for: .video)
                let ax = AXIsProcessTrusted()
                if cam != cameraStatus { cameraStatus = cam }
                if ax != accessibilityGranted { accessibilityGranted = ax }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
