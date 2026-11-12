# AprilTag on iOS

Type: research
Status: open
Blocked by:

## Question

How should AprilTag 3 (https://github.com/AprilRobotics/apriltag, a C library under BSD-2) be integrated into a Swift iOS app, and what tag setup gives a reliable 3D pose of the bar end at 1080p?

Cover:

- Building the C library and exposing it to Swift as a package.
- Tag family: tagStandard41h12 versus tag36h11 versus the ArUco-compatible families, judged on detection speed, false-positive rate, and minimum size in pixels.
- Physical tag size relative to a 50 mm Olympic sleeve, and mounting: an end-cap mount, rigidity, and keeping plates from blocking the view.
- Camera distance and lateral offset for each lift, so plates and rack uprights don't hide the tag.
- Detector parameters (`quad_decimate`, decode sharpening, thread count) and their speed versus accuracy trade-offs.
- Searching only a region around the last detection to save time per frame.
- Pose estimation with `estimate_tag_pose` using per-device camera intrinsics, and how pose error behaves along the camera axis versus in the image plane.
- Any published per-frame cost on A12-class or similar mobile hardware.

Output: a recommended tag family, tag size, mount concept, and detector settings to take into the XR benchmark.
