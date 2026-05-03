import SwiftUI
import AppKit

/// Picker sheet for the three curated animal-welfare charities. Each row
/// opens the org's own donate page in the user's browser — money never
/// flows through Furwall, we're a deep-link referrer only. Keeps a local,
/// anonymous count of donate-page opens so the user has visible feedback
/// of their contribution flow over time.
struct DonateView: View {
    @ObservedObject private var tracker = DonationTracker.shared
    @ObservedObject private var remote = RemoteStats.shared

    // Heartbeat hover state. Lub-dub-pause rhythm, slightly under 60 BPM for
    // a "calm and content" feel rather than clinical-resting. The two beats
    // are asymmetric (S1 louder than S2) which mirrors real cardiac
    // mechanics and reads as emotional rather than metronomic. Haptic +
    // visual scale fire from the same call site so they're frame-locked.
    @State private var isHoveringHeart = false
    @State private var beatScale: CGFloat = 1.0
    @State private var glowActive = false
    @State private var heartTimer: Timer?
    private let cyclePeriod: TimeInterval = 1.1      // ~55 BPM — calm, intimate
    private let dubOffset: TimeInterval = 0.25       // gap between lub and dub
    private let beatDuration: TimeInterval = 0.10    // how long each beat stays expanded
    private let lubScale: CGFloat = 1.20             // primary beat — pronounced
    private let dubScale: CGFloat = 1.10             // secondary beat — softer echo
    private let glowBaseOpacity: Double = 0.15
    private let glowPeakOpacity: Double = 0.24
    private let glowFadeDuration: TimeInterval = 0.55  // lingers through the dub + into diastole

    var body: some View {
        VStack(spacing: 24) {
            hero
            VStack(spacing: 14) {
                ForEach(Charities.curated) { charity in
                    charityRow(charity)
                }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 0)

            footer
        }
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(width: 520, height: 620)
        .background(.regularMaterial)
        .task { await remote.refresh() }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                // Single pop of color in the otherwise monochrome design —
                // system red is the universal "love / care" signal Apple uses
                // for Health, Activity, etc. Auto-adapts in dark mode.
                Circle()
                    .fill(Color.red.opacity(glowActive ? glowPeakOpacity : glowBaseOpacity))
                    .frame(width: 64, height: 64)
                Image(systemName: "heart.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .scaleEffect(beatScale)
                    // Sharp ease so the contraction snaps — actual heart muscles
                    // don't ease in/out, they pop. The asymmetric lub/dub scales
                    // give the rhythm a "story" rather than a metronome feel.
                    .animation(.easeOut(duration: beatDuration), value: beatScale)
            }
            .onHover { hovering in
                isHoveringHeart = hovering
                hovering ? startHeartbeat() : stopHeartbeat()
            }
            Text("Help Animals").font(.system(size: 24, weight: .semibold))
            Text("Furwall opens each charity's donate page directly. Your contribution goes straight to them — Furwall never handles money.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
        }
    }

    /// Start the synced lub-dub heartbeat. Each cycle: lub (haptic + scale),
    /// brief settle, dub (haptic + scale), brief settle, then a long diastolic
    /// pause until the next cycle. The first cycle runs immediately so the user
    /// feels feedback the instant they hover.
    private func startHeartbeat() {
        fireLubDub()
        heartTimer?.invalidate()
        heartTimer = Timer.scheduledTimer(withTimeInterval: cyclePeriod, repeats: true) { _ in
            Task { @MainActor in fireLubDub() }
        }
    }

    private func fireLubDub() {
        // S1 — primary contraction. Stronger haptic (.generic), bigger scale.
        // The lub also triggers the warmth glow on the bg circle — a soft
        // halo that lingers through the dub and into the diastole.
        triggerGlow()
        beat(scale: lubScale, haptic: .generic)
        DispatchQueue.main.asyncAfter(deadline: .now() + dubOffset) { [self] in
            // Bail if the user has already left the heart between lub and dub —
            // dropping a stray dub haptic into a non-hover state feels weird.
            guard isHoveringHeart else { return }
            // S2 — gentler echo. Softer haptic (.alignment), smaller scale.
            beat(scale: dubScale, haptic: .alignment)
        }
    }

    /// Fast swell, slow fade — the bg circle's red opacity pumps to peak in
    /// 50ms (synced with the lub contraction) then eases back over half a
    /// second, like warmth radiating outward and lingering in the chest.
    private func triggerGlow() {
        withAnimation(.easeOut(duration: 0.05)) {
            glowActive = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: glowFadeDuration)) {
                glowActive = false
            }
        }
    }

    /// One contraction: haptic tap, scale up to `scale`, scale back down to 1.0
    /// after beatDuration. Each call uses its own scale + haptic intensity so
    /// the lub and dub can be asymmetric (real S1 is louder than S2).
    private func beat(scale: CGFloat, haptic: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(haptic, performanceTime: .now)
        beatScale = scale
        DispatchQueue.main.asyncAfter(deadline: .now() + beatDuration) {
            beatScale = 1.0
        }
    }

    private func stopHeartbeat() {
        heartTimer?.invalidate()
        heartTimer = nil
        beatScale = 1.0
        withAnimation(.easeOut(duration: 0.3)) { glowActive = false }
    }

    @ViewBuilder
    private func charityRow(_ charity: Charity) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.furwallAccent.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.furwallAccent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(charity.name).font(.system(size: 14, weight: .semibold))
                Text(charity.mission)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Donate") {
                tracker.recordClick(for: charity)
                remote.reportClick(charityID: charity.id)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    remote.optimisticBump()
                }
                NSWorkspace.shared.open(charity.donateURL)
            }
            .controlSize(.regular)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private var footer: some View {
        // No Close button — the panel's close button, ⌘W, and Escape (via the
        // DonatePanel cancelOperation override) all dismiss. Footer is just
        // the global stat when the worker responds; otherwise nothing.
        if let total = remote.globalTotal, total > 0 {
            // contentTransition + numericText animates digits as a tick
            // (rolling odometer feel), tied to `total` so SwiftUI knows
            // which value to interpolate between when it changes.
            Text("Together, Furwall users have opened \(total) donation page\(total == 1 ? "" : "s").")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(total)))
                .animation(.spring(response: 0.45, dampingFraction: 0.78), value: total)
                .padding(.horizontal, 28)
        }
    }
}
