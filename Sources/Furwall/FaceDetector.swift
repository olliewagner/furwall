import AVFoundation
import Vision
import AppKit

/// Camera-on-keystroke face detector. The camera is *off* by default — only powered
/// up when `poke()` is called (the keyboard gate calls this on every keystroke).
/// While powered, it samples ~1 Hz; after `idleTimeout` of no pokes, it powers down.
///
/// This keeps the macOS green camera-active dot lit only while you're actively typing,
/// not all day.
@MainActor
final class FaceDetector {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sampleQueue = DispatchQueue(label: "furwall.face.sample", qos: .userInitiated)
    private let delegate: SampleDelegate
    private var configured = false
    private var idleTimer: Timer?
    private let idleTimeout: TimeInterval = 30
    private let onSeen: (Date) -> Void
    private let onCameraStateChange: (Bool) -> Void
    /// Fired on the first frame after a wake — used to cancel cold-start grace.
    private let onFirstFrameAfterWake: () -> Void
    /// Fired after every Vision inference pass completes (success OR throw).
    /// Drives `AppState.lastInferenceAt` so a stuck pipeline can fail open.
    private let onInferenceComplete: () -> Void
    private var producedFrameSinceWake = false

    /// The detector is fail-open if there's no FaceTime camera available (closed lid,
    /// external display only). Caller can read this to decide whether to even enable
    /// gating.
    let hasCamera: Bool

    init(
        onSeen: @escaping (Date) -> Void,
        onCameraStateChange: @escaping (Bool) -> Void,
        onFirstFrameAfterWake: @escaping () -> Void = {},
        onInferenceComplete: @escaping () -> Void = {}
    ) {
        self.onSeen = onSeen
        self.onCameraStateChange = onCameraStateChange
        self.onFirstFrameAfterWake = onFirstFrameAfterWake
        self.onInferenceComplete = onInferenceComplete
        self.hasCamera = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front
        ) != nil
        self.delegate = SampleDelegate()
        self.delegate.onPixelBuffer = { [weak self] buffer in
            self?.handleSample(buffer)
        }
    }

    /// Save the most-recent camera frame to `url` as a JPEG. Returns true on success.
    /// Called from the AppDelegate on a confirmed block. The catpure happens on the
    /// sample queue so we don't read `latestPixelBuffer` mid-write.
    nonisolated func catpureSnapshot(to url: URL, completion: @escaping (Bool) -> Void) {
        sampleQueue.async { [weak self] in
            guard let self = self, let buffer = self.latestPixelBuffer else {
                completion(false); return
            }
            let ci = CIImage(cvPixelBuffer: buffer)
            let context = CIContext()
            guard let cg = context.createCGImage(ci, from: ci.extent) else {
                completion(false); return
            }
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = NSSize(width: ci.extent.width, height: ci.extent.height)
            guard let data = rep.representation(
                using: .jpeg, properties: [.compressionFactor: 0.85]
            ) else { completion(false); return }
            do {
                try data.write(to: url)
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    /// Called by the keyboard gate on each keystroke. Wakes the camera if asleep,
    /// extends the auto-power-down window if already awake.
    func poke() {
        guard hasCamera else { return }
        ensureConfigured()
        if !session.isRunning {
            producedFrameSinceWake = false
            sampleQueue.async { [weak self] in
                self?.session.startRunning()
                Task { @MainActor in self?.onCameraStateChange(true) }
            }
        }
        scheduleIdleShutdown()
    }

    private func ensureConfigured() {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .low  // we only need rough face detection, not 4K
        if let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front
        ),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        output.setSampleBufferDelegate(delegate, queue: sampleQueue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }

    private func scheduleIdleShutdown() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.powerDown() }
        }
    }

    private func powerDown() {
        guard session.isRunning else { return }
        sampleQueue.async { [weak self] in
            self?.session.stopRunning()
            Task { @MainActor in self?.onCameraStateChange(false) }
        }
    }

    /// Force the camera off NOW, ignoring the idle-timeout window. Used when
    /// the screen locks — we want the green dot off immediately rather than
    /// waiting out the 30s idle timer.
    func forceShutdown() {
        idleTimer?.invalidate()
        idleTimer = nil
        powerDown()
    }

    /// Vision face-rectangles request — we don't need landmarks, just "is there a face."
    private let faceRequest: VNDetectFaceRectanglesRequest = {
        let r = VNDetectFaceRectanglesRequest()
        r.revision = VNDetectFaceRectanglesRequestRevision3
        return r
    }()

    /// Upper-body human detection — much more robust than face detection for the
    /// at-keyboard case: backlighting, glasses glare, and looking-at-keys head
    /// angles all break face detection but rarely break body detection. We treat
    /// "face OR upper body present" as "human present."
    private let bodyRequest: VNDetectHumanRectanglesRequest = {
        let r = VNDetectHumanRectanglesRequest()
        r.upperBodyOnly = true
        return r
    }()

    /// Throttle: we get frames at ~30 fps but only need ~1-2 inferences per second.
    private var lastInferenceAt: Date = .distantPast

    /// Most recent pixel buffer — protected by sampleQueue, used by `catpureSnapshot`.
    private var latestPixelBuffer: CVPixelBuffer?

    private func handleSample(_ buffer: CVPixelBuffer) {
        latestPixelBuffer = buffer
        let now = Date()
        guard now.timeIntervalSince(lastInferenceAt) > 0.5 else { return }
        lastInferenceAt = now

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
        var humanPresent = false
        do {
            try handler.perform([faceRequest, bodyRequest])

            let faces = (faceRequest.results ?? []).filter { $0.confidence > 0.4 }
            if !faces.isEmpty { humanPresent = true }

            // Body detection is the more robust signal for at-keyboard use. Lower
            // threshold than face because the request returns fewer false positives
            // overall and we'd rather err toward "user is here."
            if !humanPresent {
                let bodies = (bodyRequest.results ?? []).filter { $0.confidence > 0.3 }
                if !bodies.isEmpty { humanPresent = true }
            }

            if humanPresent {
                Task { @MainActor in self.onSeen(Date()) }
            }
        } catch {
            // Vision errors here are non-fatal — fail open: if Vision is broken
            // we shouldn't punish the user by locking them out.
            NSLog("Furwall: vision error \(error)")
            Task { @MainActor in self.onSeen(Date()) }
        }

        // First INFERENCE completed → cold-start grace can end. Critically, this
        // fires after we've actually checked for a face, not just received a
        // frame. Without this, the gate flipped to "blocked" while Vision was
        // still throttle-waiting — the visible red blink the user reported.
        if !producedFrameSinceWake {
            producedFrameSinceWake = true
            let cb = onFirstFrameAfterWake
            Task { @MainActor in cb() }
        }

        // Liveness ping for the stale-Vision detector. Fires regardless of
        // whether a human was found — the point is "the pipeline is alive."
        let liveness = onInferenceComplete
        Task { @MainActor in liveness() }
    }

    private final class SampleDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        var onPixelBuffer: ((CVPixelBuffer) -> Void)?
        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            onPixelBuffer?(buffer)
        }
    }
}
