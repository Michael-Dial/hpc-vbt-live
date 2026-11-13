import XCTest
@testable import AprilTag

final class DetectorTests: XCTestCase {
    // tag36h11 ID 0, one character per cell, including its white outer ring.
    static let tag36h11ID0 = [
        "..........", ".########.", ".#..#.#.#.", ".##...#.#.", ".##..####.",
        ".#.#.####.", ".##.#..##.", ".####.###.", ".########.", "..........",
    ]

    /// A 1920x1080 mid-grey frame with the tag drawn `cell` pixels per cell at (x, y).
    func frame(cell: Int, x: Int, y: Int) -> [UInt8] {
        var luma = [UInt8](repeating: 128, count: 1920 * 1080)
        for (r, row) in Self.tag36h11ID0.enumerated() {
            for (c, ch) in row.enumerated() {
                let value: UInt8 = ch == "#" ? 20 : 235
                for py in 0..<cell {
                    for px in 0..<cell {
                        luma[(y + r * cell + py) * 1920 + x + c * cell + px] = value
                    }
                }
            }
        }
        return luma
    }

    let k = Intrinsics(fx: 1442, fy: 1442, cx: 960, cy: 540)

    func testFullFrameDetectionAndPose() throws {
        var luma = frame(cell: 8, x: 900, y: 500)
        let detector = TagDetector(family: .tag36h11)
        let found = luma.withUnsafeMutableBufferPointer {
            detector.detect(luma: $0.baseAddress!, width: 1920, height: 1080, stride: 1920,
                            decimate: 2, intrinsics: k, tagSize: 0.072)
        }
        XCTAssertEqual(found.count, 1)
        let tag = try XCTUnwrap(found.first)
        XCTAssertEqual(tag.id, 0)
        XCTAssertEqual(tag.center.x, 940, accuracy: 1)
        XCTAssertEqual(tag.center.y, 540, accuracy: 1)
        // 72 mm edge spanning 64 px at fx 1442 px is 1442 * 0.072 / 64 = 1.622 m away.
        let t = try XCTUnwrap(tag.translation)
        XCTAssertEqual(t.z, 1.622, accuracy: 0.05)
    }

    func testWindowGivesSameResultInFullFramePixels() throws {
        var luma = frame(cell: 8, x: 900, y: 500)
        let detector = TagDetector(family: .tag36h11)
        let window = SearchWindow(x: 748, y: 348, width: 384, height: 384)
        let found = luma.withUnsafeMutableBufferPointer {
            detector.detect(luma: $0.baseAddress!, width: 1920, height: 1080, stride: 1920,
                            window: window, decimate: 1, intrinsics: k, tagSize: 0.072)
        }
        let tag = try XCTUnwrap(found.first)
        XCTAssertEqual(tag.id, 0)
        XCTAssertEqual(tag.center.x, 940, accuracy: 1)
        XCTAssertEqual(tag.center.y, 540, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(tag.translation).z, 1.622, accuracy: 0.05)
    }

    func testWrongFamilyFindsNothing() {
        var luma = frame(cell: 8, x: 900, y: 500)
        let detector = TagDetector(family: .tagStandard41h12)
        let found = luma.withUnsafeMutableBufferPointer {
            detector.detect(luma: $0.baseAddress!, width: 1920, height: 1080, stride: 1920, decimate: 2)
        }
        XCTAssertTrue(found.isEmpty)
    }
}
