import AVFoundation
import CoreMedia
import Foundation
import Vision

/// Owns the camera session and the Vision pipeline. Every blocking call
/// (device discovery, `startRunning`, Vision) happens on its own queues, so
/// `start()` and `stop()` return immediately — a hard requirement, because the
/// caller is `AppDelegate.reconcile()`, which runs on the main actor and owns
/// every status item in the app.
///
/// Frames are analysed in memory and dropped. Nothing is written to disk and
/// there is deliberately no networking in this type.
public final class GazeCaptureEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public enum Event: Sendable {
        /// A processed frame. nil features means no usable face was found.
        case frame(GazeFeatureVector?)
        /// The camera was taken by another app or went away; capture stopped.
        case interrupted
        /// The session could not start or hit a runtime error.
        case failed(String)
    }

    public static let defaultFPS = 8.0

    private let control = DispatchQueue(label: "com.hartono.mStats.gaze.control", qos: .userInitiated)
    private let frames = DispatchQueue(label: "com.hartono.mStats.gaze.frames", qos: .userInitiated)
    private let lock = NSLock()
    private let onEvent: @Sendable (Event) -> Void

    // control queue only
    private var session: AVCaptureSession?
    private var observers: [NSObjectProtocol] = []

    // guarded by `lock`
    private var accepting = false
    private var minFrameInterval = 1.0 / GazeCaptureEngine.defaultFPS
    private var lastProcessed: CFAbsoluteTime = 0

    // frames queue only
    private let request: VNDetectFaceLandmarksRequest

    public init(onEvent: @escaping @Sendable (Event) -> Void) {
        self.onEvent = onEvent
        let request = VNDetectFaceLandmarksRequest()
        // Pinned, not defaulted: only the 76-point constellation populates the
        // pupils, and persisted calibration is only valid for one point count
        // and revision (see GazeCalibrationProfile).
        request.constellation = .constellation76Points
        request.revision = GazeCalibrationProfile.pipelineRevision
        self.request = request
        super.init()
    }

    /// Returns immediately; the camera comes up on a background queue.
    public func start() {
        control.async { [self] in
            guard session == nil else { return }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                ?? AVCaptureDevice.default(for: .video)
            else {
                onEvent(.failed("No camera found"))
                return
            }

            let session = AVCaptureSession()
            session.beginConfiguration()
            if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    onEvent(.failed("Cannot use the camera as an input"))
                    return
                }
                session.addInput(input)
            } catch {
                session.commitConfiguration()
                onEvent(.failed(error.localizedDescription))
                return
            }

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            // Drop late frames instead of queueing them: no backlog, and the
            // buffer being processed is always the freshest one.
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: frames)
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                onEvent(.failed("Cannot read frames from the camera"))
                return
            }
            session.addOutput(output)
            session.commitConfiguration()

            self.session = session
            observe(session, device: device)

            lock.lock()
            accepting = true
            lastProcessed = 0
            lock.unlock()

            session.startRunning()
            if !session.isRunning {
                teardownLocked()
                onEvent(.failed("The camera session failed to start"))
            }
        }
    }

    /// Returns immediately; releases the camera (and its indicator light).
    public func stop() {
        control.async { [self] in teardownLocked() }
    }

    /// Frame rate is throttled in the consumer, not on the device: setting
    /// `activeVideoMinFrameDuration` raises an uncatchable NSException when the
    /// duration falls outside the active format's supported ranges.
    public func setTargetFPS(_ fps: Double) {
        lock.lock()
        minFrameInterval = 1.0 / max(fps, 0.5)
        lock.unlock()
    }

    private func teardownLocked() {
        lock.lock()
        accepting = false
        lock.unlock()

        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()

        guard let session else { return }
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.commitConfiguration()
        self.session = nil
    }

    private func observe(_ session: AVCaptureSession, device: AVCaptureDevice) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { [weak self] note in
            guard let self else { return }
            let message = (note.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription ?? "Camera error"
            control.async { self.teardownLocked() }
            onEvent(.failed(message))
        })
        observers.append(center.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            control.async { self.teardownLocked() }
            onEvent(.interrupted)
        })
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        lock.lock()
        let now = CFAbsoluteTimeGetCurrent()
        guard accepting, now - lastProcessed >= minFrameInterval else {
            lock.unlock()
            return
        }
        lastProcessed = now
        lock.unlock()

        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .leftMirrored, options: [:])
        do {
            try handler.perform([request])
        } catch {
            onEvent(.frame(nil))
            return
        }

        guard let face = request.results?.first, let landmarks = face.landmarks else {
            onEvent(.frame(nil))
            return
        }
        onEvent(.frame(Self.features(from: landmarks)))
    }

    private static func features(from landmarks: VNFaceLandmarks2D) -> GazeFeatureVector? {
        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] { region?.normalizedPoints ?? [] }
        return GazeFeatureExtractor.features(
            leftEye: points(landmarks.leftEye),
            rightEye: points(landmarks.rightEye),
            nose: points(landmarks.nose),
            leftPupil: points(landmarks.leftPupil),
            rightPupil: points(landmarks.rightPupil)
        )
    }
}
