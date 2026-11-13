import AVFoundation
import Combine
import CoreMotion
import RoughReps
import UIKit

enum Lift: String, CaseIterable, Identifiable {
    case backSquat = "Back squat", frontSquat = "Front squat", bench = "Bench press", deadlift = "Deadlift"
    var id: String { rawValue }
}

struct ClosedSet: Identifiable {
    let id: Int
    let lift: Lift
    let load: Double
    let unit: String
    let participant: String
    let startTime, endTime: Double   // capture clock, seconds
    let startedAt: Date
    let endedAutomatically: Bool
    let reps: [RoughRep]

    var summary: String {
        guard let best = reps.map(\.meanVelocity).max(), let last = reps.last else {
            return "Set \(id): \(lift.rawValue), no Reps"
        }
        let loss = best > 0 ? 100 * (best - last.meanVelocity) / best : 0
        return String(format: "Set %d: %@ %g %@, %d Reps, best %.2f, last %.2f (loss %.0f%%)",
                      id, lift.rawValue, load, unit, reps.count, best, last.meanVelocity, loss)
    }

    var json: [String: Any] {
        ["set": id, "lift": lift.rawValue, "load": load, "unit": unit, "participant": participant,
         "start_pts_s": startTime, "end_pts_s": endTime,
         "started_at": ISO8601DateFormatter().string(from: startedAt),
         "ended_automatically": endedAutomatically, "algorithm_version": RoughRepLogic.version,
         "reps": reps.map { ["rep": $0.number, "mean_velocity_m_s": $0.meanVelocity, "peak_velocity_m_s": $0.peakVelocity,
                             "range_of_motion_m": $0.rangeOfMotion, "duration_s": $0.duration, "end_pts_s": $0.endTime] }]
    }
}

/// One Session on one Station: a continuous Recording, with Sets opened and closed inside it.
final class SessionModel: ObservableObject {
    static let stillSecondsToEndSet = 8.0
    let controller = CaptureController()
    let participants = ["Unassigned", "P1", "P2", "P3", "P4", "P5", "P6"]

    @Published var sessionRunning = false
    @Published var setOpen = false
    @Published var lift = Lift.backSquat
    @Published var load = 135.0
    @Published var useKilograms = false
    @Published var participant = "Unassigned"
    @Published var speakVelocity = true
    @Published var reps: [RoughRep] = []
    @Published var closedSets: [ClosedSet] = []
    @Published var tagFound = false
    @Published var heightChange = 0.0     // metres since the Session started
    @Published var stillFor = 0.0
    @Published var diagnostics = ""
    @Published var message = ""

    var unit: String { useKilograms ? "kg" : "lb" }
    var bestVelocity: Double? { reps.map(\.meanVelocity).max() }
    var velocityLoss: Double? {
        guard let best = bestVelocity, let last = reps.last, best > 0 else { return nil }
        return 100 * (best - last.meanVelocity) / best
    }

    private let motion = CMMotionManager()
    private let speech = AVSpeechSynthesizer()
    private var setStartedAt = Date()

    // Shared with the detection queue, guarded by lock.
    private let lock = NSLock()
    private var logic = RoughRepLogic()
    private var gravity: (x: Double, y: Double, z: Double)?
    private var open = false
    private var lastTime = 0.0, setStartTime = 0.0
    private var lastHeight: Double?, firstHeight: Double?
    private var lastFound = false

    func startSession() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { [self] in
                do {
                    guard granted else { throw BenchError.cameraDenied }
                    UIDevice.current.isBatteryMonitoringEnabled = true
                    try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
                    lock.lock(); firstHeight = nil; lastHeight = nil; open = false; lock.unlock()
                    controller.onSample = { [weak self] time, position in self?.sample(time: time, position: position) }
                    try controller.start(BenchConfig())
                    motion.deviceMotionUpdateInterval = 0.1
                    motion.startDeviceMotionUpdates(to: OperationQueue()) { [weak self] data, _ in
                        guard let self, let g = data?.gravity else { return }
                        self.lock.lock(); self.gravity = (g.x, g.y, g.z); self.lock.unlock()
                    }
                    UIApplication.shared.isIdleTimerDisabled = true
                    closedSets = []; reps = []
                    sessionRunning = true
                    message = ""
                } catch {
                    message = error.localizedDescription
                }
            }
        }
    }

    func endSession() {
        if setOpen { endSet(automatic: false) }
        sessionRunning = false
        motion.stopDeviceMotionUpdates()
        UIApplication.shared.isIdleTimerDisabled = false
        message = "Saving..."
        controller.stop { [self] folder in
            message = "Saved \(folder?.lastPathComponent ?? "nothing"), \(closedSets.count) Sets."
        }
    }

    func startSet() {
        lock.lock()
        logic = RoughRepLogic(); open = true; setStartTime = lastTime
        lock.unlock()
        reps = []
        setStartedAt = Date()
        setOpen = true
    }

    func endSet(automatic: Bool) {
        guard setOpen else { return }
        lock.lock()
        open = false
        let end = lastTime, start = setStartTime
        lock.unlock()
        closedSets.append(ClosedSet(id: closedSets.count + 1, lift: lift, load: load, unit: unit, participant: participant,
                                    startTime: start, endTime: end, startedAt: setStartedAt,
                                    endedAutomatically: automatic, reps: reps))
        setOpen = false
        saveSets()
    }

    /// Called twice a second from the screen.
    func refresh() {
        guard sessionRunning else { return }
        controller.stats.noteDeviceState()
        lock.lock()
        tagFound = lastFound
        if let h = lastHeight, let first = firstHeight { heightChange = h - first }
        stillFor = open ? logic.stillFor(at: lastTime) : 0
        lock.unlock()
        diagnostics = controller.stats.screen(fileBytes: CaptureController.size(controller.movieURL)).text
    }

    // MARK: Detection queue

    private func sample(time: Double, position: (x: Double, y: Double, z: Double)?) {
        lock.lock()
        lastTime = time
        guard let p = position, let g = gravity else {
            lastFound = false
            lock.unlock()
            return
        }
        lastFound = true
        // Gravity arrives in device axes (x right, y up, z out of the screen). The camera frame the
        // tag position uses is x right, y down, z forward in the landscape buffer: (x, y, z) = (-y, -x, -z).
        // Height is the tag's position against gravity, so up is positive whichever way the phone is turned.
        let height = -(p.x * -g.y + p.y * -g.x + p.z * -g.z)
        lastHeight = height
        if firstHeight == nil { firstHeight = height }
        var rep: RoughRep?
        var autoEnd = false
        if open {
            rep = logic.add(time: time, height: height)
            autoEnd = logic.repCount > 0 && logic.stillFor(at: time) > Self.stillSecondsToEndSet
        }
        lock.unlock()

        if let rep {
            DispatchQueue.main.async { [self] in
                guard setOpen else { return }
                reps.append(rep)
                if speakVelocity {
                    speech.speak(AVSpeechUtterance(string: String(format: "%.0f", rep.meanVelocity * 100)))
                }
            }
        }
        if autoEnd { DispatchQueue.main.async { [self] in endSet(automatic: true) } }
    }

    private func saveSets() {
        guard let dir = controller.runDirectory,
              let data = try? JSONSerialization.data(withJSONObject: closedSets.map(\.json),
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: dir.appendingPathComponent("sets.json"))
    }
}
