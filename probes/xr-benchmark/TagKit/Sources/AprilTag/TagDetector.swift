import CAprilTag

public enum TagFamily: String, CaseIterable, Sendable {
    case tag36h11
    case tagStandard41h12
}

/// Pinhole intrinsics in pixels, for the full frame handed to `detect`.
public struct Intrinsics: Sendable {
    public var fx, fy, cx, cy: Double
    public init(fx: Double, fy: Double, cx: Double, cy: Double) {
        self.fx = fx; self.fy = fy; self.cx = cx; self.cy = cy
    }
}

/// A rectangle of the frame to search, in full-frame pixels.
public struct SearchWindow: Sendable, Equatable {
    public var x, y, width, height: Int
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct TagDetection: Sendable {
    public var id: Int
    public var hamming: Int
    public var decisionMargin: Float
    /// Centre and corners in full-frame pixels.
    public var center: (x: Double, y: Double)
    public var corners: [(x: Double, y: Double)]
    /// Tag position in the camera frame in metres, when intrinsics were given.
    public var translation: (x: Double, y: Double, z: Double)?
    public var poseError: Double?
}

/// Owns one AprilTag detector and one family. Not thread-safe: use from one queue.
public final class TagDetector {
    public let family: TagFamily
    private let detector: UnsafeMutablePointer<apriltag_detector_t>
    private let familyPointer: UnsafeMutablePointer<apriltag_family_t>

    public init(family: TagFamily, maxHamming: Int = 1) {
        self.family = family
        detector = apriltag_detector_create()
        switch family {
        case .tag36h11: familyPointer = tag36h11_create()
        case .tagStandard41h12: familyPointer = tagStandard41h12_create()
        }
        apriltag_detector_add_family_bits(detector, familyPointer, Int32(maxHamming))
        detector.pointee.quad_sigma = 0
        detector.pointee.refine_edges = true
    }

    deinit {
        apriltag_detector_destroy(detector)
        switch family {
        case .tag36h11: tag36h11_destroy(familyPointer)
        case .tagStandard41h12: tagStandard41h12_destroy(familyPointer)
        }
    }

    /// Detect tags in an 8-bit luma plane. `decimate` must be 1, 1.5, 2, 3 or 4.
    /// With `window`, only that rectangle is searched; results are still in full-frame pixels.
    public func detect(
        luma: UnsafeMutablePointer<UInt8>, width: Int, height: Int, stride: Int,
        window: SearchWindow? = nil, decimate: Float, threads: Int = 1,
        intrinsics: Intrinsics? = nil, tagSize: Double = 0
    ) -> [TagDetection] {
        let win = window ?? SearchWindow(x: 0, y: 0, width: width, height: height)
        detector.pointee.quad_decimate = decimate
        detector.pointee.nthreads = Int32(threads)
        var image = image_u8_t(
            width: Int32(win.width), height: Int32(win.height), stride: Int32(stride),
            buf: luma + win.y * stride + win.x)
        guard let found = apriltag_detector_detect(detector, &image) else { return [] }
        defer { apriltag_detections_destroy(found) }

        var results: [TagDetection] = []
        for i in 0..<Int(vbt_detection_count(found)) {
            guard let det = vbt_detection_at(found, Int32(i)) else { continue }
            let d = det.pointee
            let ox = Double(win.x), oy = Double(win.y)
            let p = d.p
            var result = TagDetection(
                id: Int(d.id), hamming: Int(d.hamming), decisionMargin: d.decision_margin,
                center: (d.c.0 + ox, d.c.1 + oy),
                corners: [(p.0.0 + ox, p.0.1 + oy), (p.1.0 + ox, p.1.1 + oy),
                          (p.2.0 + ox, p.2.1 + oy), (p.3.0 + ox, p.3.1 + oy)],
                translation: nil, poseError: nil)
            if let k = intrinsics, tagSize > 0 {
                var t = [Double](repeating: 0, count: 3)
                // The detection is in window pixels, so shift the principal point to match.
                let err = vbt_tag_translation(det, tagSize, k.fx, k.fy, k.cx - ox, k.cy - oy, &t)
                result.translation = (t[0], t[1], t[2])
                result.poseError = err
            }
            results.append(result)
        }
        return results
    }
}
