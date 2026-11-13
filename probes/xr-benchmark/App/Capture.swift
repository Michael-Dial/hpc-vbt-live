import AVFoundation
import AprilTag
import UIKit

struct BenchConfig {
    var family: TagFamily = .tag36h11
    var fps = 120
    var detectEvery = 1   // 1 = every frame, 2 = every second frame
    var record = true

    /// Detection edge in metres for the 90 mm printed tags.
    var tagSize: Double { family == .tag36h11 ? 0.072 : 0.050 }
}

enum BenchError: LocalizedError {
    case noCamera, noFormat(Int), cameraDenied
    var errorDescription: String? {
        switch self {
        case .noCamera: return "No back camera found."
        case .noFormat(let fps): return "This phone offers no 1920x1080 format at \(fps) fps."
        case .cameraDenied: return "Camera access is off. Turn it on in Settings > XR Bench."
        }
    }
}

/// One capture session feeding an HEVC writer and the tag detector, as the capture research recommends.
final class CaptureController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let stats = BenchStats()
    private(set) var runDirectory: URL?

    private let captureQueue = DispatchQueue(label: "bench.capture", qos: .userInteractive)
    private let detectQueue = DispatchQueue(label: "bench.detect", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private var config = BenchConfig()

    // Capture queue only.
    private var frameIndex = 0
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var framesLog: FileHandle?
    private var framesBuffer = Data()
    private var fallbackIntrinsics: Intrinsics?

    // Shared between the queues, guarded by busyLock.
    private let busyLock = NSLock()
    private var detectBusy = false
    private var luma: UnsafeMutablePointer<UInt8>?
    private var lumaCapacity = 0

    // Detection queue only.
    private var detector: TagDetector?
    private var window: SearchWindow?
    private var misses = 0
    private var detectionsLog: FileHandle?
    private var detectionsBuffer = Data()

    var movieURL: URL? { runDirectory?.appendingPathComponent("recording.mov") }

    func start(_ config: BenchConfig) throws {
        self.config = config
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw BenchError.noCamera
        }
        let fps = Double(config.fps)
        func is1080(_ f: AVCaptureDevice.Format) -> Bool {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return d.width == 1920 && d.height == 1080
        }
        func describe(_ f: AVCaptureDevice.Format) -> String {
            let sub = CMFormatDescriptionGetMediaSubType(f.formatDescription)
            let code = String(bytes: [24, 16, 8, 0].map { UInt8((sub >> $0) & 0xff) }, encoding: .ascii) ?? "?"
            let rates = f.videoSupportedFrameRateRanges.map { "\(Int($0.minFrameRate))-\(Int($0.maxFrameRate))" }
            return "1920x1080 \(code) fps \(rates.joined(separator: ",")) fov \(f.videoFieldOfView)"
                + (f.isVideoBinned ? " binned" : "") + (f.isVideoHDRSupported ? " hdr" : "")
        }
        let all1080 = device.formats.filter(is1080)
        let videoRange = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        // Prefer the format whose top rate is closest to the target, so 120 fps does not pay for 240.
        let pick = all1080
            .filter { CMFormatDescriptionGetMediaSubType($0.formatDescription) == videoRange }
            .filter { $0.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= fps - 0.5 } }
            .min { a, b in
                (a.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0)
                    < (b.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0)
            }
        guard let format = pick else { throw BenchError.noFormat(config.fps) }

        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.sessionPreset = .inputPriority
        session.addInput(try AVCaptureDeviceInput(device: device))

        try device.lockForConfiguration()
        device.activeFormat = format
        let duration = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }  // one scan, then holds
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.activeMaxExposureDuration = CMTime(value: 1, timescale: 250)  // limit motion blur
        device.automaticallyAdjustsVideoHDREnabled = false
        if format.isVideoHDRSupported { device.isVideoHDREnabled = false }
        device.unlockForConfiguration()

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: videoRange]
        output.alwaysDiscardsLateVideoFrames = false
        output.automaticallyConfiguresOutputBufferDimensions = false
        output.deliversPreviewSizedOutputBuffers = false
        output.setSampleBufferDelegate(self, queue: captureQueue)
        session.addOutput(output)
        var intrinsicsDelivered = false
        if let connection = output.connection(with: .video) {
            if connection.isCameraIntrinsicMatrixDeliverySupported {
                connection.isCameraIntrinsicMatrixDeliveryEnabled = true
                intrinsicsDelivered = true
            }
            if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
        }
        session.commitConfiguration()

        let focal = 960 / tan(Double(format.videoFieldOfView) * .pi / 360)
        fallbackIntrinsics = Intrinsics(fx: focal, fy: focal, cx: 960, cy: 540)

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("run-\(stamp)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        runDirectory = dir
        func log(_ name: String, header: String) -> FileHandle? {
            let url = dir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data((header + "\n").utf8))
            let handle = try? FileHandle(forWritingTo: url)
            handle?.seekToEndOfFile()
            return handle
        }
        let frames = log("frames.csv", header: "frame,pts_s,encoded")
        let detections = log("detections.csv",
                             header: "frame,pts_s,ms,windowed,found,id,margin,cx_px,cy_px,tx_m,ty_m,tz_m")

        stats.reset(
            nominalInterval: 1 / fps, formatLine: describe(format), formats: all1080.map(describe),
            settings: ["family": config.family.rawValue, "fps": config.fps, "detect_every": config.detectEvery,
                       "record": config.record, "tag_size_m": config.tagSize,
                       "intrinsics_from_camera": intrinsicsDelivered,
                       "max_exposure_s": 1.0 / 250, "exposure": "continuous auto", "focus": "single scan then held"])
        captureQueue.sync { frameIndex = 0; writer = nil; writerInput = nil; framesLog = frames; framesBuffer = Data() }
        detectQueue.sync {
            detector = TagDetector(family: config.family)
            window = nil; misses = 0; detectionsLog = detections; detectionsBuffer = Data()
        }
        session.startRunning()
    }

    /// Stops capture, finishes the Recording, and writes summary.json. Returns the run folder.
    func stop(completion: @escaping (URL?) -> Void) {
        session.stopRunning()
        captureQueue.async { [self] in
            framesLog?.write(framesBuffer); try? framesLog?.close(); framesLog = nil
            detectQueue.sync { detectionsLog?.write(detectionsBuffer); try? detectionsLog?.close(); detectionsLog = nil }
            let finish = { [self] in
                if let dir = runDirectory {
                    let summary = stats.summary(fileBytes: Self.size(movieURL))
                    if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
                        try? data.write(to: dir.appendingPathComponent("summary.json"))
                    }
                }
                DispatchQueue.main.async { completion(self.runDirectory) }
            }
            if let writer, writer.status == .writing {
                writerInput?.markAsFinished()
                writer.finishWriting(completionHandler: finish)
            } else {
                finish()
            }
            writer = nil; writerInput = nil
        }
    }

    static func size(_ url: URL?) -> Int64 {
        guard let url, let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return 0 }
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: Capture queue

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let pts = time.seconds
        let index = frameIndex
        frameIndex += 1
        stats.frame(pts: pts)

        var encoded = 0
        if config.record {
            if writer == nil { startWriter(first: sampleBuffer, at: time) }
            if let input = writerInput, writer?.status == .writing {
                if input.isReadyForMoreMediaData, input.append(sampleBuffer) { encoded = 1 } else { stats.writerDrop() }
            }
        }
        framesBuffer.append(Data("\(index),\(String(format: "%.6f", pts)),\(encoded)\n".utf8))
        if framesBuffer.count > 32_768 { framesLog?.write(framesBuffer); framesBuffer.removeAll(keepingCapacity: true) }

        guard index % config.detectEvery == 0, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        busyLock.lock()
        if detectBusy { busyLock.unlock(); stats.detectSkip(); return }
        detectBusy = true
        busyLock.unlock()

        // Copy the luma plane so the capture buffer is released at once.
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        let width = CVPixelBufferGetWidthOfPlane(pixels, 0), height = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        if lumaCapacity < stride * height {
            luma?.deallocate()
            lumaCapacity = stride * height
            luma = .allocate(capacity: lumaCapacity)
        }
        if let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0), let luma { memcpy(luma, base, stride * height) }
        CVPixelBufferUnlockBaseAddress(pixels, .readOnly)

        var intrinsics = fallbackIntrinsics
        if let data = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                                      attachmentModeOut: nil) as? Data, data.count >= MemoryLayout<matrix_float3x3>.size {
            let m = data.withUnsafeBytes { $0.loadUnaligned(as: matrix_float3x3.self) }
            intrinsics = Intrinsics(fx: Double(m.columns.0.x), fy: Double(m.columns.1.y),
                                    cx: Double(m.columns.2.x), cy: Double(m.columns.2.y))
        }
        detectQueue.async { [self] in
            detect(frame: index, pts: pts, width: width, height: height, stride: stride, intrinsics: intrinsics)
            busyLock.lock(); detectBusy = false; busyLock.unlock()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        stats.captureDrop()
    }

    private func startWriter(first: CMSampleBuffer, at time: CMTime) {
        guard let url = movieURL, let made = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        let settings = output.recommendedVideoSettings(forVideoCodecType: .hevc, assetWriterOutputFileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings,
                                       sourceFormatHint: CMSampleBufferGetFormatDescription(first))
        input.expectsMediaDataInRealTime = true
        made.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)  // playable after a crash
        guard made.canAdd(input) else { return }
        made.add(input)
        made.startWriting()
        made.startSession(atSourceTime: time)
        writer = made; writerInput = input
    }

    // MARK: Detection queue

    private func detect(frame: Int, pts: Double, width: Int, height: Int, stride: Int, intrinsics: Intrinsics?) {
        guard let detector, let luma else { return }
        let searched = window
        let begin = DispatchTime.now().uptimeNanoseconds
        // Full frame: decimate 2 on two threads. Tracking window: full resolution on one thread.
        let found = detector.detect(
            luma: luma, width: width, height: height, stride: stride, window: searched,
            decimate: searched == nil ? 2 : 1, threads: searched == nil ? 2 : 1,
            intrinsics: intrinsics, tagSize: config.tagSize)
        let ms = Float(DispatchTime.now().uptimeNanoseconds - begin) / 1e6
        let best = found.max { $0.decisionMargin < $1.decisionMargin }

        var row = "\(frame),\(String(format: "%.6f", pts)),\(String(format: "%.3f", ms)),\(searched == nil ? 0 : 1),"
        var description = "no tag"
        if let tag = best {
            misses = 0
            let c = tag.corners
            var edge = 0.0
            for i in 0..<4 {
                let next = c[(i + 1) % 4]
                let dx: Double = c[i].x - next.x, dy: Double = c[i].y - next.y
                edge = max(edge, (dx * dx + dy * dy).squareRoot())
            }
            // About three printed tag widths, a multiple of 4 because thresholding works in 4x4 tiles.
            let side = min(640, max(128, (Int(edge * 4) + 3) / 4 * 4))
            let w = min(side, width), h = min(side, height)
            window = SearchWindow(x: min(max(0, Int(tag.center.x) - w / 2), width - w),
                                  y: min(max(0, Int(tag.center.y) - h / 2), height - h), width: w, height: h)
            let t = tag.translation
            row += String(format: "1,%d,%.1f,%.2f,%.2f,%.4f,%.4f,%.4f", tag.id, tag.decisionMargin,
                          tag.center.x, tag.center.y, t?.x ?? .nan, t?.y ?? .nan, t?.z ?? .nan)
            description = String(format: "TAG id %d   %.2f m away   edge %.0f px", tag.id, t?.z ?? .nan, edge)
        } else {
            misses += 1
            if misses >= 6 { window = nil }  // lost: go back to searching the whole frame
            row += "0,,,,,,,"
        }
        stats.detection(ms: ms, windowed: searched != nil, found: best != nil, description: description)
        detectionsBuffer.append(Data((row + "\n").utf8))
        if detectionsBuffer.count > 32_768 {
            detectionsLog?.write(detectionsBuffer); detectionsBuffer.removeAll(keepingCapacity: true)
        }
    }
}
