import SwiftUI
import AppKit

/// Hosts the About window — Furwall's user-facing disclosure surface.
/// Mirrors the OnboardingController / DonateController pattern: lazy NSWindow,
/// NSHostingController bridge, single floating window reused on re-open.
@MainActor
final class AboutController {
    static let shared = AboutController()
    private var window: NSWindow?

    func present() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = AboutView()
        let host = NSHostingController(rootView: view)
        // Let the SwiftUI body's intrinsic size drive the window — keeps the
        // window snug against content instead of a fixed frame stretching the
        // layout with dead space.
        host.sizingOptions = [.preferredContentSize]
        // NSPanel (with the cancelOperation override below) gets us Escape-to-
        // close for free, matching macOS conventions for inspector / About-style
        // surfaces. Plain NSWindow doesn't route Escape to the responder chain.
        let w = AboutPanel(contentViewController: host)
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = String(localized: "About Furwall")
        w.isMovableByWindowBackground = true
        // Seed roughly so the first center() lands close to the final position
        // before SwiftUI's intrinsic resize kicks in.
        w.setContentSize(NSSize(width: 480, height: 660))
        w.center()
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.delegate = AboutWindowDelegate.shared
        AboutWindowDelegate.shared.onClose = { [weak self] in self?.window = nil }
        self.window = w

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Re-center after SwiftUI's first layout pass resizes the window to
        // its preferred content size — otherwise the seed-then-center we just
        // did is left off-axis once intrinsic height settles.
        DispatchQueue.main.async { [weak w] in w?.center() }
    }

    fileprivate func close() {
        window?.close()
        window = nil
    }
}

private final class AboutWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = AboutWindowDelegate()
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}

/// Custom NSPanel that closes on Escape. NSPanel routes `cancelOperation(_:)`
/// to the first responder chain when Escape is pressed; subclassing lets us
/// catch it at the window level even when no view consumes the key. Also
/// override `canBecomeKey` so the panel actually accepts the keystroke
/// (NSPanel's default for nonactivating panels is false).
private final class AboutPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}

private struct AboutView: View {
    @State private var showingLicense = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        return short
    }

    var body: some View {
        VStack(spacing: 22) {
            hero
            disclosures
            footer
        }
        .padding(.top, 30)
        .padding(.bottom, 28)
        .frame(width: 480)
        .background(.regularMaterial)
        .sheet(isPresented: $showingLicense) {
            LicenseSheet(onClose: { showingLicense = false })
        }
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Group {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 96, height: 96)
                } else {
                    Image(systemName: "cat.fill")
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(Color.furwallAccent)
                        .frame(width: 96, height: 96)
                }
            }
            Text("Furwall")
                .font(.system(size: 24, weight: .semibold))
            Text("Version \(version)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {
                if let url = URL(string: "https://olliewagner.com/furwall") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("olliewagner.com/furwall")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
    }

    private var disclosures: some View {
        VStack(alignment: .leading, spacing: 18) {
            section(
                glyph: "lock.fill",
                title: "Private by Design",
                body: "Camera frames are processed entirely on your Mac with Apple’s Vision framework. Furwall never uploads, transmits, or stores video. Accessibility access is used solely to drop keystrokes when no human is present—keystrokes are never read, logged, or transmitted."
            )
            section(
                glyph: "heart.fill",
                title: "Donations Go Direct",
                body: "Furwall opens each charity’s donate page in your browser. Money flows from you to the charity. Furwall never handles funds and receives no portion of any donation."
            )
            section(
                glyph: "chart.bar.fill",
                title: "Anonymous Tally",
                body: "When you open a charity page, Furwall increments a global click count so the community can see total impact. Only the charity’s name is sent—no IP retention, no identifiers, no tracking."
            )
            section(
                glyph: "doc.text.fill",
                title: "Open Source, No Warranty",
                // Markdown link to a custom scheme — intercepted below by the
                // OpenURLAction so it opens the in-app license sheet instead
                // of being handed to the system.
                body: "Furwall is free, open source software under the [MIT License](furwall://license). It comes with no warranty of any kind, express or implied. Use at your own risk."
            )
        }
        .padding(.horizontal, 28)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "furwall" && url.host == "license" {
                showingLicense = true
                return .handled
            }
            return .systemAction
        })
    }

    @ViewBuilder
    private func section(glyph: String, title: String, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.furwallAccent.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: glyph)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.furwallAccent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // No buttons — Apple About windows are content-only. The window's close
    // button (and ⌘W) handles dismissal; the MIT License link inline above
    // opens the license sheet without needing a chunky footer button.
    private var footer: some View {
        Text("© 2026 Ollie Wagner")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28)
            .padding(.top, 12)
    }
}

private struct LicenseSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("MIT License")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                Text(AboutLicenseText.mit)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
        .padding(20)
        .frame(width: 520, height: 440)
    }
}

private enum AboutLicenseText {
    static let mit = """
    MIT License

    Copyright (c) 2026 Ollie Wagner / Yap Studios LLC

    Permission is hereby granted, free of charge, to any person obtaining a copy \
    of this software and associated documentation files (the "Software"), to deal \
    in the Software without restriction, including without limitation the rights \
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
    copies of the Software, and to permit persons to whom the Software is \
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in \
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN \
    THE SOFTWARE.
    """
}
