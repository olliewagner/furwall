import AppKit
import CoreGraphics

/// CGEventTap that drops keyboard events when the gate's `shouldPass` predicate
/// returns false. Inserted at the head of the session-level event stream so we
/// run before Spotlight, the focused app, etc.
///
/// Requires Accessibility + Input Monitoring permissions (granted in System Settings
/// → Privacy & Security). Without them, `CGEvent.tapCreate` returns nil; we surface
/// that state via `isInstalled` so the menu can prompt the user.
final class KeyboardGate {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Synchronously evaluated for every keystroke. Must be cheap and main-actor-safe
    /// reads; we hop to the main thread to read AppState atomically.
    private let shouldPass: () -> Bool
    /// Called whenever an event is dropped. Use to log + wake the camera so the
    /// next attempt has a fresh face check ready.
    private let onBlock: () -> Void
    /// Called whenever an event passes — used to "poke" the camera so it stays warm.
    private let onPass: () -> Void
    /// Called when the user mashes Escape `panicCount` times within `panicWindow`.
    /// Safety net: even if face detection is broken, this always frees the keyboard.
    private let onPanic: () -> Void

    var isInstalled: Bool { tap != nil }

    /// Escape-key panic detection. The CGEventTap callback runs on a single thread
    /// (the run loop we attached to), so this ring buffer doesn't need a lock.
    private var escapeTimestamps: [CFTimeInterval] = []
    private let panicCount = 5
    private let panicWindow: CFTimeInterval = 1.5
    /// kVK_Escape — stable across keyboard layouts.
    private let escapeKeyCode: Int64 = 53

    init(
        shouldPass: @escaping () -> Bool,
        onBlock: @escaping () -> Void,
        onPass: @escaping () -> Void,
        onPanic: @escaping () -> Void = {}
    ) {
        self.shouldPass = shouldPass
        self.onBlock = onBlock
        self.onPass = onPass
        self.onPanic = onPanic
    }

    /// Record an Escape keyDown and return true if the panic threshold has been
    /// reached. Called from the tap callback; safe because the callback runs on
    /// a single thread.
    fileprivate func recordEscapeAndCheckPanic() -> Bool {
        let now = CACurrentMediaTime()
        escapeTimestamps.append(now)
        // Prune anything outside the window.
        while let first = escapeTimestamps.first, now - first > panicWindow {
            escapeTimestamps.removeFirst()
        }
        if escapeTimestamps.count >= panicCount {
            escapeTimestamps.removeAll()
            return true
        }
        return false
    }

    func start() {
        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.keyUp.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            // Re-enable on system-issued tap-disable events (timeout, user-initiated).
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon = refcon {
                    let gate = Unmanaged<KeyboardGate>.fromOpaque(refcon).takeUnretainedValue()
                    if let tap = gate.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                }
                return Unmanaged.passUnretained(event)
            }

            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let gate = Unmanaged<KeyboardGate>.fromOpaque(refcon).takeUnretainedValue()

            // Panic Escape detection runs FIRST, before the block decision —
            // we want it to work even when the gate is locked down. If the
            // user hits Escape 5× in 1.5s we trigger onPanic (which pauses
            // the gate) and let this 5th Escape pass through.
            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if keyCode == gate.escapeKeyCode, gate.recordEscapeAndCheckPanic() {
                    gate.onPanic()
                    gate.onPass()
                    return Unmanaged.passUnretained(event)
                }
            }

            if gate.shouldPass() {
                gate.onPass()
                return Unmanaged.passUnretained(event)
            } else {
                gate.onBlock()
                // nil = drop the event entirely. The next consumer in the chain
                // (Spotlight, focused app) never sees it.
                return nil
            }
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Furwall: CGEvent.tapCreate failed — Accessibility permission likely missing")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
    }

    func stop() {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }
}
