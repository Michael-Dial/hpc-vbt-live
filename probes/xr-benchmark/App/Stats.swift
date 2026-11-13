import Foundation
import UIKit

/// Everything the benchmark measures. Written from the capture and detection queues, read by the UI.
final class BenchStats {
    private let lock = NSLock()
    private var started = Date()
    private var nominal = 1.0 / 120

    private var frames = 0
    private var captureDrops = 0          // frames AVFoundation reported as dropped
    private var writerDrops = 0           // frames the encoder was not ready for
    private var detectSkipped = 0         // frames where the detector was still busy
    private var detectRuns = 0
    private var detectFound = 0
    private var windowMs: [Float] = []
    private var fullMs: [Float] = []

    private var lastPTS: Double?
    private var intervalSum = 0.0, intervalSumSq = 0.0, intervalMax = 0.0
    private var intervalCount = 0
    private var lateIntervals = 0         // longer than 1.5x nominal
    private var missingFrames = 0         // estimated from late intervals
    private var frameGapRuns: [Int] = []  // length of each run of missing frames

    private var everFound = false
    private var missRun = 0
    private var missRuns: [Int] = []      // consecutive detection attempts with no tag

    private var thermal: [(seconds: Double, state: String)] = []
    private var battery: [(seconds: Double, level: Float)] = []
    private var last = "no tag yet"
    private var lastFx = Double.nan, lastEdge = Double.nan
    private var lastFound = false
    private(set) var formatLine = ""
    private(set) var formats: [String] = []
    private var settings: [String: Any] = [:]

    func reset(nominalInterval: Double, formatLine: String, formats: [String], settings: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        started = Date(); nominal = nominalInterval
        frames = 0; captureDrops = 0; writerDrops = 0; detectSkipped = 0; detectRuns = 0; detectFound = 0
        windowMs = []; fullMs = []
        lastPTS = nil; intervalSum = 0; intervalSumSq = 0; intervalMax = 0; intervalCount = 0
        lateIntervals = 0; missingFrames = 0; frameGapRuns = []
        everFound = false; missRun = 0; missRuns = []
        thermal = []; battery = []; last = "no tag yet"; lastFound = false
        self.formatLine = formatLine; self.formats = formats; self.settings = settings
    }

    func frame(pts: Double) {
        lock.lock(); defer { lock.unlock() }
        frames += 1
        if let prev = lastPTS {
            let d = pts - prev
            intervalSum += d; intervalSumSq += d * d; intervalCount += 1
            intervalMax = max(intervalMax, d)
            if d > 1.5 * nominal {
                lateIntervals += 1
                let missing = max(1, Int((d / nominal).rounded()) - 1)
                missingFrames += missing
                frameGapRuns.append(missing)
            }
        }
        lastPTS = pts
    }

    func note(fx: Double, edgePixels: Double) { lock.lock(); lastFx = fx; lastEdge = edgePixels; lock.unlock() }
    func captureDrop() { lock.lock(); captureDrops += 1; lock.unlock() }
    func writerDrop() { lock.lock(); writerDrops += 1; lock.unlock() }
    func detectSkip() { lock.lock(); detectSkipped += 1; lock.unlock() }

    func detection(ms: Float, windowed: Bool, found: Bool, description: String) {
        lock.lock(); defer { lock.unlock() }
        detectRuns += 1
        if windowed { windowMs.append(ms) } else { fullMs.append(ms) }
        lastFound = found
        if found {
            detectFound += 1; everFound = true; last = description
            if missRun > 0 { missRuns.append(missRun); missRun = 0 }
        } else if everFound {
            missRun += 1
        }
    }

    func noteDeviceState() {
        let state: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: state = "nominal"
        case .fair: state = "fair"
        case .serious: state = "serious"
        case .critical: state = "critical"
        @unknown default: state = "unknown"
        }
        let level = UIDevice.current.batteryLevel
        lock.lock(); defer { lock.unlock() }
        let t = Date().timeIntervalSince(started)
        if thermal.last?.state != state { thermal.append((t, state)) }
        if battery.last.map({ t - $0.seconds >= 60 }) ?? true { battery.append((t, level)) }
    }

    private static func percentile(_ sorted: [Float], _ p: Double) -> Float {
        guard !sorted.isEmpty else { return .nan }
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
    }

    private static func timing(_ values: [Float]) -> [String: Any] {
        let s = values.sorted()
        func r(_ v: Float) -> Any { v.isNaN ? NSNull() : (Double(v) * 100).rounded() / 100 }
        return ["count": s.count, "median_ms": r(percentile(s, 0.5)), "p95_ms": r(percentile(s, 0.95)),
                "p99_ms": r(percentile(s, 0.99)), "max_ms": r(s.last ?? .nan)]
    }

    private static func histogram(_ runs: [Int]) -> [String: Int] {
        var h: [String: Int] = [:]
        for r in runs {
            let key = r <= 5 ? "\(r)" : r <= 10 ? "6-10" : r <= 30 ? "11-30" : r <= 120 ? "31-120" : ">120"
            h[key, default: 0] += 1
        }
        return h
    }

    /// Lines for the on-screen readout.
    func screen(fileBytes: Int64) -> (found: Bool, text: String) {
        lock.lock(); defer { lock.unlock() }
        let elapsed = Date().timeIntervalSince(started)
        let w = windowMs.suffix(1200).sorted(), f = fullMs.suffix(1200).sorted()
        let fps = elapsed > 0 ? Double(frames) / elapsed : 0
        let mbPerMin = elapsed > 5 ? Double(fileBytes) / 1e6 / (elapsed / 60) : 0
        let foundPct = detectRuns > 0 ? 100 * Double(detectFound) / Double(detectRuns) : 0
        let lines = [
            String(format: "elapsed %02d:%02d   thermal %@", Int(elapsed) / 60, Int(elapsed) % 60,
                   thermal.last?.state ?? "?"),
            String(format: "frames %d   %.1f fps", frames, fps),
            String(format: "missing %d   reported drops %d   encoder drops %d", missingFrames, captureDrops, writerDrops),
            String(format: "detect window  med %.1f  p95 %.1f ms", Self.percentile(w, 0.5), Self.percentile(w, 0.95)),
            String(format: "detect full    med %.1f  p95 %.1f ms", Self.percentile(f, 0.5), Self.percentile(f, 0.95)),
            String(format: "detector busy, skipped %d   found %.0f%%", detectSkipped, foundPct),
            String(format: "recording %.0f MB/min", mbPerMin),
            last,
        ]
        return (lastFound, lines.joined(separator: "\n"))
    }

    func summary(fileBytes: Int64) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        let elapsed = Date().timeIntervalSince(started)
        let mean = intervalCount > 0 ? intervalSum / Double(intervalCount) : 0
        let variance = intervalCount > 1 ? max(0, intervalSumSq / Double(intervalCount) - mean * mean) : 0
        var device = utsname(); uname(&device)
        let model = withUnsafeBytes(of: &device.machine) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        return [
            "device_model": model,
            "ios": UIDevice.current.systemVersion,
            "started": ISO8601DateFormatter().string(from: started),
            "elapsed_s": (elapsed * 10).rounded() / 10,
            "settings": settings,
            "active_format": formatLine,
            "last_fx_px": lastFx.isNaN ? NSNull() : lastFx as Any,
            "last_tag_edge_px": lastEdge.isNaN ? NSNull() : lastEdge as Any,
            "formats_1080p": formats,
            "frames": frames,
            "mean_fps": elapsed > 0 ? (Double(frames) / elapsed * 100).rounded() / 100 : 0,
            "frame_interval": [
                "nominal_ms": nominal * 1000, "mean_ms": mean * 1000, "sd_ms": variance.squareRoot() * 1000,
                "max_ms": intervalMax * 1000, "late_intervals": lateIntervals,
                "estimated_missing_frames": missingFrames, "missing_run_lengths": Self.histogram(frameGapRuns),
            ],
            "reported_capture_drops": captureDrops,
            "encoder_not_ready_drops": writerDrops,
            "detection": [
                "attempts": detectRuns, "found": detectFound, "skipped_detector_busy": detectSkipped,
                "window": Self.timing(windowMs), "full_frame": Self.timing(fullMs),
                "no_tag_run_lengths_in_attempts": Self.histogram(missRuns),
            ],
            "recording_bytes": fileBytes,
            "recording_mb_per_min": elapsed > 0 ? (Double(fileBytes) / 1e6 / (elapsed / 60) * 10).rounded() / 10 : 0,
            "thermal_timeline": thermal.map { ["t_s": ($0.seconds * 10).rounded() / 10, "state": $0.state] },
            "battery_timeline": battery.map { ["t_s": $0.seconds.rounded(), "level": $0.level] },
        ]
    }
}
