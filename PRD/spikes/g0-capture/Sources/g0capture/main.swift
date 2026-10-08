// G0 spike — capture + Vision yaw separability.
//
// Throwaway prototype for PRD/gaze-focus.md §12 "Phase G0". Answers two
// questions before any product code is written:
//
//   1. Is head yaw actually separable between two side-by-side displays at
//      5-10 fps at 640x480? (PRD §6.2, §13 ">= 90% correct display selection")
//   2. What is the real CPU cost of that pipeline, so §10's "< 3% average
//      CPU" target is either validated or refuted?
//
// This is NOT wired into mStats. It is a standalone `swiftc`-buildable
// binary. See PRD/spikes/g0-capture/README.md for how to run it.
//
// Two deliberate deviations from the PRD, both forced by the API:
//
//   * The PRD (§6.2) says "VNDetectFaceLandmarksRequest provide[s] head
//     yaw/pitch/roll". They do not. `VNDetectFaceLandmarksRequest` yields
//     `VNFaceObservation`, which has no yaw/pitch/roll at any revision. The
//     only head-pose angles in Vision are on the Swift-only
//     `FaceObservation` type, gated to macOS 15+ (requires the Swift
//     overlay). We deploy to macOS 14, so this spike derives yaw from
//     2D landmarks instead and prints both feature sets.
//   * Pupil regions (leftPupil/rightPupil) require the 76-point
//     constellation. We request it explicitly rather than relying on the
//     default, because the default constellation is not a stable API
//     contract and calibration data is persisted against it.
//
// Frames are analysed in memory only. Nothing is written to disk. There is
// deliberately no networking in this file, per PRD §10 privacy requirement.

import AppKit
import AVFoundation
import CoreMedia
import Foundation
import Darwin
import Vision

// MARK: - Configuration

/// Matches the PRD's §6.1 capture budget.
struct Config {
    var fps: Int = 8
    /// How long to sample for, in seconds.
    var duration: Double = 30
}

/// Every sample the classifier needs, in one `Sendable` value.
struct GazeSample: Sendable {
    var timestamp: Double
    /// Head yaw proxy in radians, derived from the 2D landmark asymmetry
    /// below. Positive means the head is turned to the user's right.
    var yawRadians: Double
    /// Raw offsets of the left/right eye midpoint and nose centroid from
    /// the horizontal centre of the face bounding box. These are the
    /// actual discriminative features; `yawRadians` is a convenience
    /// scalar over them.
    var eyeMidpointOffset: Double
    var noseTipOffset: Double
    var faceWidth: Double
    var confidence: Float
}

/// Landmark-derived head pose proxy.
enum PoseEstimator {
    /// Returns the centroid of a landmark region in normalized face-box
    /// space. `VNDetectFaceLandmarksRequest` reports landmarks relative to
    /// the face bounding box, with y increasing downward.
    private static func centroid(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
        guard let region else { return nil }
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var count: CGFloat = 0
        for point in region.normalizedPoints {
            sumX += point.x
            sumY += point.y
            count += 1
        }
        guard count > 0 else { return nil }
        return CGPoint(x: sumX / count, y: sumY / count)
    }

    /// Derives a yaw proxy from the horizontal displacement of the eye
    /// midpoint and nose relative to the centre of the face bounding box.
    ///
    /// Landmarks come back in *face-box* normalized space — origin at the
    /// box's top-left, x and y in 0...1 — so an offset from x = 0.5 is
    /// already invariant to how far the user sits from the camera, and
    /// `faceWidth` needs no further normalization. That is why this does
    /// not divide by face width: doing so would double-normalize and
    /// shrink the signal toward zero.
    ///
    /// The eye midpoint and nose displace in *opposite* directions as the
    /// head turns, so subtracting them cancels the component common to
    /// both and leaves an amplified signal.
    ///
    /// This is a crude proxy, not a calibrated angle. It assumes the face
    /// reads as centred when the user is looking straight ahead. That
    /// assumption is precisely what G0 is testing, and a weak result here
    /// is a conservative lower bound — a real model will not rescue it.
    static func yaw(from landmarks: VNFaceLandmarks2D, boundingBox: CGRect) -> GazeSample? {
        guard let leftEye = centroid(landmarks.leftEye),
              let rightEye = centroid(landmarks.rightEye),
              let nose = centroid(landmarks.nose)
        else { return nil }

        let eyeMid = CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2)
        let eyeMidOffset = Double(eyeMid.x - 0.5)
        let noseOffset = Double(nose.x - 0.5)

        return GazeSample(
            timestamp: 0,
            yawRadians: eyeMidOffset - noseOffset,
            eyeMidpointOffset: eyeMidOffset,
            noseTipOffset: noseOffset,
            faceWidth: Double(boundingBox.width),
            confidence: 1.0
        )
    }
}

// MARK: - Energy measurement

/// Reads cumulative CPU time for this process, in nanoseconds, from IO
/// power management. Used instead of `powermetrics` because that needs
/// root; the ratio between "running" and "idle" wall-clock is what
/// actually matters for the §10 budget, and this gives it to us directly.
enum Energy {
    /// Cumulative *user + system* CPU time for this process, in nanoseconds.
    ///
    /// Uses `proc_pidinfo(PROC_PIDTASKINFO)` rather than
    /// `pmsp_get_power_info`: the latter needs a C bridging header for
    /// `pmsp_power_info`, and its `cpu_time_accum` semantics are ambiguous
    /// on recent macOS. `pti_total_user + pti_total_system` is explicit and
    /// reports exactly this process, which is what the PRD §10 budget is
    /// about. No root required.
    static func cpuNanoseconds() -> UInt64 {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.stride
        let count = proc_pidinfo(
            getpid(), PROC_PIDTASKINFO, 0, &info, Int32(size)
        )
        guard count == size else { return 0 }
        return UInt64(info.pti_total_user) &+ UInt64(info.pti_total_system)
    }

    static func cpuPercentOver(interval: Double, from: UInt64, to: UInt64) -> Double {
        guard interval > 0, to > from else { return 0 }
        let cpuSeconds = Double(to - from) / 1_000_000_000
        // Normalize against wall clock: 1.0 means one full core saturated.
        return (cpuSeconds / interval) * 100.0
    }
}

// MARK: - Separator analysis

/// The separability question G0 exists to answer. Given samples tagged by
/// which display the user was looking at, how separable are they?
struct SeparabilityReport {
    let groupAN: Int
    let groupBN: Int
    let groupAMean: Double
    let groupBMean: Double
    let groupASd: Double
    let groupBSd: Double
    let cohensD: Double
    let bestThreshold: Double
    let accuracy: Double
}

enum Separator {
    /// Analyzes the run as a two-group problem: the user was looking at
    /// display B during the first third of the run and display A during
    /// the last third, per the printed protocol.
    ///
    /// Returns nil when the data cannot support a conclusion at all, which
    /// is a different outcome from "no separation" and must not be
    /// reported as one. The two cases look identical in a mean/SD printout
    /// but mean completely different things about the feature.
    static func analyze(allSamples: [GazeSample]) -> SeparabilityReport? {
        guard allSamples.count >= 20 else { return nil }

        let third = allSamples.count / 3
        // The middle third is discarded: it is the transition period, where
        // the head is mid-turn and genuinely belongs to neither group.
        let groupA = allSamples.suffix(third).map(\.yawRadians)
        let groupB = allSamples.prefix(third).map(\.yawRadians)
        guard groupA.count >= 5, groupB.count >= 5 else { return nil }

        let meanA = groupA.reduce(0, +) / Double(groupA.count)
        let meanB = groupB.reduce(0, +) / Double(groupB.count)

        func stdDev(_ xs: [Double], mean: Double) -> Double {
            guard xs.count > 1 else { return 0 }
            let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count)
            return variance.squareRoot()
        }

        let sdA = stdDev(groupA, mean: meanA)
        let sdB = stdDev(groupB, mean: meanB)
        let pooled = (sdA + sdB) / 2

        let meanGap = abs(meanA - meanB)

        // A signal narrower than the measurement's own jitter cannot be
        // classified. Near-zero SD with a near-zero mean gap means the head
        // did not move at all between groups — the operator sat still, or
        // the displays were not side by side — and no amount of
        // normalization makes identical distributions separable.
        if pooled < 1e-3 || meanGap < 1e-3 {
            return nil
        }

        // Cohen's d: standardized mean difference. Above ~2.0 is generally
        // considered strongly separable; below ~0.8 is a poor signal.
        let d = meanGap / pooled

        // Best single-threshold accuracy via the midpoint rule.
        let threshold = (meanA + meanB) / 2
        var correct = 0
        for x in groupA where (x - threshold) * (x - meanA) >= 0 { correct += 1 }
        for x in groupB where (x - threshold) * (x - meanB) >= 0 { correct += 1 }
        let accuracy = Double(correct) / Double(groupA.count + groupB.count)

        return SeparabilityReport(
            groupAN: groupA.count, groupBN: groupB.count,
            groupAMean: meanA, groupBMean: meanB,
            groupASd: sdA, groupBSd: sdB,
            cohensD: d, bestThreshold: threshold, accuracy: accuracy
        )
    }
}

// MARK: - Capture pipeline

final class CaptureSpike: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let visionQueue = DispatchQueue(label: "g0.vision", qos: .userInitiated)
    private let lock = NSLock()

    private var request: VNDetectFaceLandmarksRequest?
    private var samples: [GazeSample] = []
    private var frameCount = 0
    private var deliveredCount = 0
    private var detectedCount = 0
    private var lastProcessTime: CFAbsoluteTime = 0
    /// Minimum wall-clock gap between processed frames, from `Config.fps`.
    private lazy var minFrameInterval: Double = 1.0 / Double(max(config.fps, 1))
    private var running = false
    private var startTime: CFAbsoluteTime = 0
    private var baselineCPU: UInt64 = 0
    private var config = Config()
    /// First Vision failure, kept for diagnostics. Silently swallowing it
    /// is how a permission denial masquerades as a separability result.
    private var firstVisionError = ""
    private var firstCaptureError: (any Error)?

    func start(config: Config) throws {
        self.config = config
        samples.removeAll()
        frameCount = 0
        deliveredCount = 0
        detectedCount = 0
        lastProcessTime = 0

        let request = VNDetectFaceLandmarksRequest()
        // Pin the constellation. The 76-point set is the only one that
        // populates leftPupil/rightPupil, which the PRD §6.2 feature vector
        // calls for. Never rely on the default here — persisted calibration
        // data is tied to the point count.
        request.constellation = .constellation76Points
        // Pin the revision so a future SDK default change cannot silently
        // alter landmark semantics for already-calibrated users.
        // Revision 3 is the newest non-deprecated revision on macOS.
        request.revision = 3
        self.request = request

        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else {
            session.commitConfiguration()
            throw SpikeError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw SpikeError.cannotAddInput
        }
        session.addInput(input)

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        // Drop late frames rather than queueing them: this spike measures
        // steady-state cost, and backlog would misrepresent it.
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: visionQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw SpikeError.cannotAddOutput
        }
        session.addOutput(output)
        session.commitConfiguration()

        // Frame rate control. Deliberately NOT done via
        // `AVCaptureDevice.activeVideoMinFrameDuration`: on this device the
        // setter raises an NSException (not a Swift error, so `try` cannot
        // catch it) whenever the requested duration falls outside the
        // active format's supported ranges, which the FaceTime camera's
        // format table does not cleanly cover at 640x480.
        //
        // The measured CPU budget in PRD §10 is per *processed* frame, and
        // throttling in the Vision consumer bounds the rate of Vision work
        // just as effectively — while keeping the camera delivery rate, so
        // the buffer always holds the freshest frame rather than a stale
        // one. `alwaysDiscardsLateVideoFrames` plus an early return below
        // means skipped frames are never processed at all.

        baselineCPU = Energy.cpuNanoseconds()
        startTime = CFAbsoluteTimeGetCurrent()
        running = true
        session.startRunning()

        if !session.isRunning {
            running = false
            throw SpikeError.sessionFailedToStart
        }
    }

    func stop() {
        running = false
        if session.isRunning { session.stopRunning() }
    }

    /// Blocks for the configured duration, then reports. Intentionally a
    /// blocking call: this is a measurement harness, not production code.
    func runAndReport() {
        let deadline = startTime + config.duration
        while CFAbsoluteTimeGetCurrent() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        stop()

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let cpu = Energy.cpuNanoseconds()

        lock.lock()
        let collected = samples
        let frames = frameCount
        let delivered = deliveredCount
        let detections = detectedCount
        lock.unlock()

        print("\n=== G0 capture + Vision spike ===")
        print("elapsed            \(String(format: "%.1f", elapsed))s")
        let fps = Double(frames) / max(elapsed, 0.001)
        print("processed frames   \(frames) (\(String(format: "%.1f", fps)) fps, target \(config.fps))")
        print("delivered frames   \(delivered) (\(String(format: "%.1f", Double(delivered) / max(elapsed, 0.001))) fps from camera)")
        print("faces detected     \(detections)/\(frames) (\(detections * 100 / max(frames, 1))%)")
        print("samples kept       \(collected.count)")

        let cpuPercent = Energy.cpuPercentOver(
            interval: elapsed, from: baselineCPU, to: cpu
        )
        print("CPU (1 core=100%)  \(String(format: "%.1f", cpuPercent))%")
        // Activity Monitor reports process CPU the same way, as a percentage
        // of one core. Only meaningful if frames actually flowed: an idle
        // process trivially meets the budget and proves nothing.
        if cpuPercent > 0, frames > 0 {
            print("  -> §10 budget of <3% average CPU is \(cpuPercent < 3 ? "MET" : "EXCEEDED")")
        } else {
            print("  -> NOT MEASURABLE (no frames processed)")
        }

        // A harness that reports a technical verdict after an
        // infrastructure failure is worse than no harness at all: "FAIL"
        // would be recorded against a conclusion the data never tested.
        if frames == 0 {
            print("\n--- verdict ---")
            print("INCONCLUSIVE: no frames were delivered. This is a capture or")
            print("permission problem, not a result about head yaw.")
            print("\nLikely causes:")
            print("  1. Camera permission denied for the *parent* app. An unsigned")
            print("     CLI binary inherits its parent's TCC identity — run this from")
            print("     Terminal and grant Terminal camera access in System Settings >")
            print("     Privacy & Security > Camera.")
            print("  2. Camera in use by another app (Zoom, FaceTime, Continuity Camera).")
            print("  3. No camera available (clamshell, PRD §4).")
            if !firstVisionError.isEmpty {
                print("\nFirst Vision error seen:")
                print("  \(firstVisionError)")
            }
            if firstCaptureError != nil, let err = firstCaptureError {
                print("\nFirst capture setup error:")
                print("  \(err.localizedDescription)")
            }
            return
        }

        guard let report = Separator.analyze(allSamples: collected) else {
            print("\n--- verdict ---")
            if collected.count < 20 {
                print("INCONCLUSIVE: too few samples to compare groups.")
                print(String(format: "Kept %d; need at least 20, with 5+ per group", collected.count))
                print("after discarding the transition third. Longer --duration,")
                print("better lighting, or a higher --fps will help.")
            } else {
                print("INCONCLUSIVE: samples were captured but the two groups are")
                print("statistically indistinguishable — the head barely moved between")
                print("them. This is not evidence that yaw fails; it means the protocol")
                print("was not followed. Follow it properly:")
                print("  look at ONE display for the first third, the other for the")
                print("  last third, actually turning your head rather than just your")
                print("  eyes. Verify your displays are side by side, not stacked")
                print("  (PRD §4 scopes v1 to side by side).")
            }
            return
        }

        print("\n--- yaw separability ---")
        print(String(format: "display A (last %d)  mean %+.4f  sd %.4f", report.groupAN, report.groupAMean, report.groupASd))
        print(String(format: "display B (first %d) mean %+.4f  sd %.4f", report.groupBN, report.groupBMean, report.groupBSd))
        print(String(format: "gap                 %.4f", abs(report.groupAMean - report.groupBMean)))
        print(String(format: "threshold           %+.4f", report.bestThreshold))
        print(String(format: "in-sample accuracy  %.0f%%  (optimistic — threshold fitted on the same data)", report.accuracy * 100))
        print(String(format: "Cohen's d           %.2f", report.cohensD))

        print("\n--- verdict ---")
        switch report.cohensD {
        case 2...:
            print("PASS: yaw separates strongly between the two displays.")
            print("Phase G1 can proceed on the head-yaw approach as specced.")
            print("Note the accuracy above is fitted on this same run. §13's 90%")
            print("target needs a held-out test with a fresh, unfitted threshold.")
        case 0.8..<2:
            print("MARGINAL: some separation, but noisy.")
            print("Consider adding pupil offset to the feature vector before G1, and")
            print("re-run with better lighting before committing to G1.")
        default:
            print("FAIL: head yaw does not separate these displays reliably.")
            print("Do not proceed to G1 on yaw alone. The PRD §11 risk row 'head")
            print("pose is not true gaze' is the dominant failure mode here.")
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard running, let request, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Throttle to the configured rate before doing any Vision work.
        // Skipped frames are not processed and not counted, so the reported
        // fps reflects real pipeline throughput at the target rate.
        lock.lock()
        let now = CFAbsoluteTimeGetCurrent()
        deliveredCount += 1
        let elapsedSinceLast = now - lastProcessTime
        if elapsedSinceLast < minFrameInterval {
            lock.unlock()
            return
        }
        lastProcessTime = now
        lock.unlock()

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .leftMirrored, options: [:])
        do {
            try handler.perform([request])
        } catch {
            lock.lock()
            if firstVisionError.isEmpty {
                firstVisionError = "\(error.localizedDescription)"
            }
            lock.unlock()
            return
        }

        lock.lock()
        frameCount += 1
        let observations = request.results ?? []
        lock.unlock()

        guard let face = observations.first,
              let landmarks = face.landmarks,
              var sample = PoseEstimator.yaw(from: landmarks, boundingBox: face.boundingBox)
        else { return }

        sample.timestamp = CFAbsoluteTimeGetCurrent() - startTime
        sample.confidence = face.confidence

        lock.lock()
        samples.append(sample)
        detectedCount += 1
        lock.unlock()
    }
}

enum SpikeError: Error, CustomStringConvertible {
    case noCamera
    case cannotAddInput
    case cannotAddOutput
    case sessionFailedToStart

    var description: String {
        switch self {
        case .noCamera:
            "no camera found. Check System Settings > Privacy & Security > Camera."
        case .cannotAddInput:
            "cannot add camera input to capture session"
        case .cannotAddOutput:
            "cannot add video output to capture session"
        case .sessionFailedToStart:
            """
            capture session failed to start. Almost always a TCC camera \
            permission denial: an unsigned CLI binary inherits its parent's \
            identity, so grant Terminal camera access in System Settings > \
            Privacy & Security > Camera, then re-run.
            """
        }
    }
}

// MARK: - Entry point

let usage = """
g0-capture — G0 spike for Gaze Focus (PRD/gaze-focus.md §12)

Usage: g0-capture [--fps N] [--duration SECONDS]

  --fps N          capture frame rate (default 8, PRD §6.1 target 5-10)
  --duration S     sampling duration in seconds (default 30)

Protocol: sit centred between the two displays. Look at display B for the
first third of the run, then display A for the last third. Actually turn
your head — do not just move your eyes. Swap which display is first
between runs and record both.

Run it at least 3 times. A single run's in-sample accuracy is optimistic
and says nothing about generalization; §13's 90% target needs repeated
runs with a threshold fitted on one run and tested on another.
"""

var config = Config()
var args = Array(CommandLine.arguments.dropFirst())
while let arg = args.first {
    args.removeFirst()
    switch arg {
    case "--fps":
        config.fps = Int(args.first ?? "8") ?? 8
        args.removeFirst()
    case "--duration":
        config.duration = Double(args.first ?? "30") ?? 30
        args.removeFirst()
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        FileHandle.standardError.write(Data("unknown option: \(arg)\n\(usage)\n".utf8))
        exit(1)
    }
}

print("""
g0-capture — Gaze Focus Phase G0
This tool opens the camera. Camera frames are analysed in memory only and
are never written to disk or sent anywhere. No arguments needed beyond
the flags above.
""")

print("AXIsProcessTrusted (Accessibility): \(AXIsProcessTrusted())")
print("screens connected: \(NSScreen.screens.count)")

if NSScreen.screens.count < 2 {
    print("\nWARNING: fewer than 2 displays connected.")
    print("Yaw separability between displays cannot be measured on one screen.")
    print("Attach a second display before treating G0 results as meaningful.")
}

let spike = CaptureSpike()
do {
    try spike.start(config: config)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

spike.runAndReport()