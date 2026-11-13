// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TagKit",
    platforms: [.iOS("18.0"), .macOS(.v14)],
    products: [.library(name: "AprilTag", targets: ["AprilTag"])],
    targets: [
        .target(
            name: "CAprilTag",
            path: "Sources/CAprilTag",
            exclude: ["apriltag/LICENSE.md", "apriltag/VENDORED.txt"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("apriltag"), .unsafeFlags(["-w"])]
        ),
        .target(name: "AprilTag", dependencies: ["CAprilTag"]),
        .testTarget(name: "AprilTagTests", dependencies: ["AprilTag"]),
    ]
)
