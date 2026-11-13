import Foundation
import XCTest
@testable import RoughReps

final class RoughRepLogicTests: XCTestCase {
    /// Height over time for squat-like Reps: down `range` then up `range`, each a smooth half cosine.
    func squat(reps: Int, range: Double, down: Double, up: Double, pause: Double, rate: Double = 60) -> [(Double, Double)] {
        var samples: [(Double, Double)] = []
        var t = 0.0
        func hold(_ seconds: Double, at h: Double) {
            for _ in 0..<Int(seconds * rate) { samples.append((t, h)); t += 1 / rate }
        }
        func move(from a: Double, to b: Double, over seconds: Double) {
            let n = Int(seconds * rate)
            for i in 0..<n {
                let phase = Double(i) / Double(n)
                samples.append((t, a + (b - a) * (1 - cos(.pi * phase)) / 2)); t += 1 / rate
            }
        }
        hold(1, at: 1.4)
        for _ in 0..<reps {
            move(from: 1.4, to: 1.4 - range, over: down)
            move(from: 1.4 - range, to: 1.4, over: up)
            hold(pause, at: 1.4)
        }
        return samples
    }

    func testCountsRepsAndMeasuresMeanVelocity() {
        var logic = RoughRepLogic()
        var found: [RoughRep] = []
        for (t, h) in squat(reps: 5, range: 0.6, down: 1.2, up: 0.8, pause: 0.7) {
            if let rep = logic.add(time: t, height: h) { found.append(rep) }
        }
        XCTAssertEqual(found.count, 5)
        XCTAssertEqual(found.map(\.number), [1, 2, 3, 4, 5])
        for rep in found {
            // 0.6 m in 0.8 s is 0.75 m/s. The slow start and finish of the movement fall
            // outside the speed thresholds, so allow a generous margin.
            XCTAssertEqual(rep.meanVelocity, 0.75, accuracy: 0.08)
            XCTAssertEqual(rep.rangeOfMotion, 0.6, accuracy: 0.03)
            XCTAssertEqual(rep.peakVelocity, 0.6 * .pi / (2 * 0.8), accuracy: 0.06)
        }
    }

    func testIgnoresSmallMovements() {
        var logic = RoughRepLogic()
        var count = 0
        for (t, h) in squat(reps: 4, range: 0.08, down: 0.5, up: 0.5, pause: 0.5) {
            if logic.add(time: t, height: h) != nil { count += 1 }
        }
        XCTAssertEqual(count, 0)
    }

    func testReportsStillness() {
        var logic = RoughRepLogic()
        let samples = squat(reps: 1, range: 0.6, down: 1, up: 1, pause: 6)
        for (t, h) in samples { _ = logic.add(time: t, height: h) }
        XCTAssertGreaterThan(logic.stillFor(at: samples.last!.0), 5)
    }

    func testLongGapDoesNotInventARep() {
        var logic = RoughRepLogic()
        var count = 0
        for i in 0..<60 { if logic.add(time: Double(i) / 60, height: 1.0) != nil { count += 1 } }
        // Tag lost for two seconds, then found 0.5 m higher.
        for i in 0..<60 { if logic.add(time: 3 + Double(i) / 60, height: 1.5) != nil { count += 1 } }
        XCTAssertEqual(count, 0)
    }
}
