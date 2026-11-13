# xr-benchmark

Throwaway probe for the map ticket "XR benchmark": can an iPhone XR record 1080p at 120 fps and
detect the bar-end AprilTag live for a full Session?

- `TagKit/`: a Swift package. `CAprilTag` is the AprilTag C library, vendored unmodified at commit
  `b7c0ebe` (BSD-2-Clause, see `TagKit/Sources/CAprilTag/apriltag/LICENSE.md`). `AprilTag` is a thin
  Swift wrapper. `swift test` in `TagKit/` checks detection and pose on a synthetic frame.
- `App/`: the benchmark app. One capture session feeds an HEVC `AVAssetWriter` and the detector.
  The detector searches a window around the last detection, and the whole frame when the tag is lost.

## Build and install

    xcodegen generate
    xcodebuild -project XRBench.xcodeproj -scheme XRBench -configuration Release \
      -destination "id=<device UDID>" -derivedDataPath build \
      -allowProvisioningUpdates DEVELOPMENT_TEAM=<team ID> build
    xcrun devicectl device install app --device <device UDID> build/Build/Products/Release-iphoneos/XRBench.app

## Run

1. Mount the XR 2.0 to 2.5 m from the bar end, looking along the bar, plugged into power.
2. Open XR Bench, allow the camera, pick the tag family, 120 fps, detect every frame, Record on.
3. Press Start. The badge shows TAG FOUND or NO TAG; the readout shows timings, drops, and heat.
4. Press Stop and save. Each run writes a folder in the app's Documents:
   `recording.mov`, `frames.csv`, `detections.csv`, `summary.json`.

The Recording may show people. Copy run folders only to `data/` on a local machine; never commit them.
