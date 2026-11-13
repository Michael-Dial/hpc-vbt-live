/// Provisional Rep detection for the Station feedback prototype. Not the v1 rep logic:
/// the rules and thresholds here are first guesses, to be replaced once
/// "Metric definitions per lift" is decided.
///
/// Streaming, as ADR 0001 requires: one height sample in, at most one Rep out.
public struct RoughRep: Sendable, Equatable {
    public let number: Int
    public let meanVelocity: Double   // m/s over the upward phase
    public let peakVelocity: Double   // m/s
    public let rangeOfMotion: Double  // m
    public let duration: Double       // s
    public let endTime: Double        // capture clock, s
}

public struct RoughRepLogic: Sendable {
    public static let version = "prototype-0"

    /// An upward movement counts as a Rep only if it rises at least this far.
    public var minimumRange = 0.15
    /// Upward phase starts above this speed and ends at or below `endSpeed`.
    public var startSpeed = 0.05
    public var endSpeed = 0.0
    /// The bar counts as still below this speed.
    public var stillSpeed = 0.03
    /// A gap longer than this resets the logic instead of being bridged.
    public var longestGap = 0.5

    public private(set) var velocity = 0.0
    public private(set) var repCount = 0
    public private(set) var lastMovementTime: Double?

    private var history: [(time: Double, height: Double)] = []
    private var rising = false
    private var startTime = 0.0, startHeight = 0.0
    private var topTime = 0.0, topHeight = 0.0
    private var peak = 0.0

    public init() {}

    /// Seconds the bar has been still, as of `time`.
    public func stillFor(at time: Double) -> Double {
        lastMovementTime.map { time - $0 } ?? 0
    }

    /// Feed one sample: capture-clock time in seconds and bar height in metres (up is positive).
    public mutating func add(time: Double, height: Double) -> RoughRep? {
        if let last = history.last, time - last.time > longestGap {
            history.removeAll(); rising = false
        }
        history.append((time, height))
        if history.count > 5 { history.removeFirst() }
        if lastMovementTime == nil { lastMovementTime = time }
        guard history.count == 5, let oldest = history.first, time > oldest.time else { return nil }

        // Velocity over the last four sample intervals (about 67 ms at 60 samples a second).
        velocity = (height - oldest.height) / (time - oldest.time)
        if abs(velocity) > stillSpeed { lastMovementTime = time }

        if !rising {
            if velocity > startSpeed {
                rising = true
                startTime = oldest.time; startHeight = oldest.height
                topTime = time; topHeight = height
                peak = velocity
            }
            return nil
        }
        peak = max(peak, velocity)
        if height > topHeight { topHeight = height; topTime = time }
        guard velocity <= endSpeed else { return nil }

        rising = false
        let range = topHeight - startHeight, duration = topTime - startTime
        guard range >= minimumRange, duration > 0.1 else { return nil }
        repCount += 1
        return RoughRep(number: repCount, meanVelocity: range / duration, peakVelocity: peak,
                        rangeOfMotion: range, duration: duration, endTime: time)
    }
}
