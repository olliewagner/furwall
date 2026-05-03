import SwiftUI
import AppKit

/// Manages a single floating window that hosts `DonateView` — the picker for
/// the curated animal-welfare charities. Mirrors the OnboardingController
/// pattern: lazy NSWindow, NSHostingController bridge, close handler.
@MainActor
final class DonateController {
    static let shared = DonateController()
    private var window: NSWindow?

    /// Open the donate window, reusing the existing one if already on screen.
    func present() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = DonateView()
        let host = NSHostingController(rootView: view)
        // Let the SwiftUI body's intrinsic size drive the window — keeps it
        // snug against content rather than stretching a fixed frame.
        host.sizingOptions = [.preferredContentSize]
        // NSPanel + cancelOperation override gets us Escape-to-close for free.
        let w = DonatePanel(contentViewController: host)
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Help Animals"
        w.isMovableByWindowBackground = true
        // Seed roughly so the first center() lands close to the final position
        // before SwiftUI's intrinsic resize kicks in.
        w.setContentSize(NSSize(width: 520, height: 560))
        w.center()
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.delegate = DonateWindowDelegate.shared
        DonateWindowDelegate.shared.onClose = { [weak self] in self?.window = nil }
        self.window = w

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Re-center after SwiftUI's first layout pass resizes the window to
        // its intrinsic content size.
        DispatchQueue.main.async { [weak w] in w?.center() }
    }

    fileprivate func close() {
        window?.close()
        window = nil
    }
}

private final class DonateWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = DonateWindowDelegate()
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}

/// NSPanel subclass that closes on Escape — same pattern as AboutPanel.
private final class DonatePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}
