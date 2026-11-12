# AprilTag on iOS

Research note for the wayfinder ticket "AprilTag on iOS" (issue #3). Researched 2026-11-12.

Every claim carries one of three labels:

- **[V]** Verified: read in a primary source, cited with a URL and a short quote.
- **[I]** Inferred or computed: the arithmetic and assumptions are shown.
- **[U]** Unknown: only the XR benchmark (or a named follow-up) can settle it.

A fourth label, **[P]**, marks results from a throwaway probe built for this note: the AprilTag sources compiled as a Swift package and run on synthetic 1920x1080 frames on an Apple M2 Pro Mac. The probe proves that things build and behave as described. Its timings are not XR timings.

Source links into the AprilTag repository are pinned to commit `b7c0ebe9aa20f82ec7a828579004f9e706bfecd9` (master, 2026-08-07), written below as `{AT}` = `https://github.com/AprilRobotics/apriltag/blob/b7c0ebe9aa20f82ec7a828579004f9e706bfecd9`.

## Question

How should the AprilTag 3 C library be integrated into the Swift Station app (and the macOS replay CLI), and what tag setup gives a reliable 3D pose of the bar end at 1080p?

## Short answer

- **Packaging.** Vendor the AprilTag C sources (pinned commit) into a C target `CAprilTag` in the shared Swift package, with a one-file umbrella header, and put a thin Swift wrapper target on top. It needs no dependencies beyond libc, libm and pthreads, and the probe built it unmodified for macOS and for iOS arm64. Do not adopt a third-party wrapper; the existing ones are days-old or unmaintained.
- **Tag family: `tag36h11`** to carry into the benchmark, with `tagStandard41h12` as the comparison arm. For a fixed printed footprint, 36h11's detection square is 80% of the printed width against 56% for 41h12, so it gives a 44% longer baseline for pose. The project needs a handful of IDs, so 41h12's larger ID count buys nothing. This departs from the README's general advice and the benchmark should confirm it.
- **Tag size: 90 mm printed `tag36h11`** (9 mm cells, 72 mm detection edge, the value passed as `tagsize`), on a 100 mm rigid square carrier. At 2.0 m this is about 52 px across the detection edge and 6.5 px per cell, if the XR's 1080p format uses the full sensor width (unverified).
- **Mount concept:** a removable end cap that seats on the sleeve end, centred on the bar axis, with the flat carrier perpendicular to the axis. It goes on after the plates and collar, like a collar. Centring matters because any offset from the axis turns sleeve rotation into position error. A tag small enough to stay inside the 50 mm sleeve footprint (35 mm printed) is the fallback and is roughly 2.6 times worse in depth precision.
- **Station placement:** on or near the bar axis, 2.0 to 2.5 m from the bar end, portrait, lens at about the mid-height of the lift's bar travel, with a small lateral offset (5 to 15 degrees) allowed. Plates sit behind the tag and cannot hide it; people standing at the bar end can.
- **Detector settings to benchmark first:** one family (`tag36h11`), 1 bit of error correction, `quad_decimate = 2.0` for full-frame search and `1.0` inside a tracking window, `quad_sigma = 0`, `refine_edges = true`, `decode_sharpening = 0.25` (default), `nthreads = 1` in the tracking window and `2` for full-frame search.
- **Use only decimation values 1, 1.5, 2, 3, 4.** Other non-integer values are truncated for the image but not for the corner rescale, which silently corrupts corner positions.
- **Search a window around the last detection.** The library has no region-of-interest option, but its image header takes a pointer and a stride, so a window into the luma plane costs nothing. Shift `cx, cy` by the window origin for pose. In the Mac probe a 384 px window cut a cluttered frame from 18.9 ms to 1.2 ms. A full-frame search is unlikely to fit the 8.3 ms budget on the XR in a cluttered gym; the window is what makes 120 fps plausible.
- **Pose.** Call `estimate_tag_pose` with per-device `fx, fy, cx, cy` and `tagsize = 0.072`. It assumes a pinhole model, so correct lens distortion on the four corners first if calibration shows it matters. Use the translation; treat the rotation as unreliable for a near-frontal tag.
- **Error shape.** For the same pixel error, depth error is larger than in-plane error by the factor distance / tag edge (about 28 at 2 m with a 72 mm edge). Vertical bar motion lies in the image plane, which is the well-measured direction. Depth should be smoothed over a Rep or Set, not trusted frame by frame.
- **No published A12-class per-frame timing exists** that this research could find. The nearest numbers are desktop CPUs (below). The XR benchmark has to measure it.

## Findings

### 1. Building the C library and exposing it to Swift

**Licence and version**

- **[V]** The licence is BSD 2-Clause. `{AT}/LICENSE.md` line 1: "BSD 2-Clause License", copyright "The Regents of The University of Michigan". Binary redistribution must reproduce the notice: "Redistributions in binary form must reproduce the above copyright notice". The Station app therefore needs the licence text in its acknowledgements.
- **[V]** The latest release is v3.4.5, published 2025-08-29 (`https://api.github.com/repos/AprilRobotics/apriltag/releases/latest`, `"tag_name": "v3.4.5"`). `{AT}/CMakeLists.txt` line 2: "project(apriltag VERSION 3.4.5 LANGUAGES C)".
- **[V]** Master is 57 commits ahead of v3.4.5 (`https://api.github.com/repos/AprilRobotics/apriltag/compare/v3.4.5...master`, "ahead 57"). Those commits include union-find speedups, a new decode lookup table ("refactor: implement pigeonhole based lookup table"), deep-copy helpers, a minimum-image-size check and the ArUco families ("Add support for ArUco tag families (4x4 to 7x7 and MIP)"). The `aruco/` directory does not exist at tag v3.4.5.
- **[I]** Pin a specific commit instead of a release tag. `tag36h11` and `tagStandard41h12` exist in both; master has the performance work. The commit used throughout this note is a reasonable pin.

**Dependencies and platform fit**

- **[V]** `{AT}/README.md` line 3: "AprilTag consists of a small C library with minimal dependencies." Line 142: "Note that this library has no external dependencies."
- **[V]** `{AT}/README.md` line 41: "Officially only Linux operating systems are supported". Apple platforms are not officially supported, so the project owns any breakage.
- **[V]** It needs pthreads and libm. `{AT}/CMakeLists.txt` lines 89-94: "find_package(Threads REQUIRED)" and "target_link_libraries(${PROJECT_NAME} PUBLIC m)". `{AT}/common/pthreads_cross.h` lines 29-31 include `<pthread.h>` and `<sched.h>` on non-Windows builds. Both are part of the iOS and macOS SDKs, so nothing extra is linked.
- **[V]** The language standard is C99: `{AT}/CMakeLists.txt` line 99, "set_property(TARGET ${PROJECT_NAME} PROPERTY C_STANDARD 99)".
- **[V]** The library sources are `apriltag.c`, `apriltag_pose.c`, `apriltag_quad_thresh.c`, everything in `common/`, and the `tag*.c` family files (`{AT}/CMakeLists.txt` lines 74-79). `apriltag_pywrap.c` includes `<Python.h>` and must be excluded, as must `example/` and `test/`.
- **[P]** With those exclusions the sources compiled without modification under Xcode's clang for `arm64-apple-macos` (`swift build -c release`) and for iOS arm64 (`xcodebuild -destination generic/platform=iOS`, "BUILD SUCCEEDED"). There were a handful of compiler warnings and no errors.

**Swift Package Manager layout**

- **[V]** SwiftPM builds C targets and generates the module map. Swift.org documentation, "Creating C language targets" (`https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/CreatingCLanguageTargets.md`): "If `include/Foo.h` exists and `include` contains no other subdirectory, then Swift package manager uses `include/Foo.h` as the umbrella header for the module map."
- **[V]** Same page: "In case of complicated `include` layouts or headers that are not compatible with modules, provide a `module.modulemap` in the `include` directory."
- **[V]** `publicHeadersPath` (`https://developer.apple.com/documentation/packagedescription/target/publicheaderspath`): "The path to the directory that contains public headers of a C-family target. If this is nil, the directory is set to include."
- **[V]** The upstream sources include headers both as `"common/zarray.h"` from the root and as bare `"workerpool.h"` from inside `common/` (`{AT}/common/workerpool.c` lines 31 and 42). The root directory must therefore be a header search path.
- **[P]** The layout that worked:

  ```
  Sources/CAprilTag/
    apriltag/            <- upstream tree, vendored at the pinned commit
    include/CAprilTag.h  <- umbrella: #include "../apriltag/apriltag.h",
                            "../apriltag/apriltag_pose.h", "../apriltag/tag36h11.h", ...
  ```

  with the target declared as `path: "Sources/CAprilTag"`, `publicHeadersPath: "include"`, `cSettings: [.headerSearchPath("apriltag")]`, and `exclude:` listing `apriltag/apriltag_pywrap.c`, `apriltag/example`, `apriltag/test`, `apriltag/CMake`, the non-source files, and the family files that are not used.
- **[I]** Exclude unused families. `tagStandard52h13.c` alone is 1.2 MB of source (measured in the clone) and the ArUco directory adds 17 more families. Only `tag36h11.c` and `tagStandard41h12.c` are needed.
- **[I]** Keep the Swift wrapper in the same package as a second target (`AprilTag`, depending on `CAprilTag`), so the Station app and the macOS replay CLI share it. The wrapper should own the detector and family lifetimes, expose a `detect(luma:width:height:stride:window:)` call that takes a raw pointer, and return plain Swift value types. The C API returns heap objects the caller must free (`{AT}/apriltag.h` lines 264-268: "The caller is responsible for freeing the result").
- **[V]** A detector is not shared between threads safely by design, and a family instance belongs to one detector. `{AT}/apriltag.h` line 237: "a single instance should only be provided to one apriltag detector instance."

**Passing a CVPixelBuffer without copying**

- **[V]** The image type is a header over caller memory. `{AT}/common/image_types.h` lines 37-44 declare `width`, `height`, `stride` and `uint8_t *buf`. `{AT}/README.md` lines 150-151: "Image data in a cv::Mat object can be passed to AprilTag without creating a deep copy."
- **[I]** The luma plane of a 420 bi-planar buffer is 8-bit grayscale with its own bytes-per-row. Lock the buffer, read the plane-0 base address and bytes-per-row, and fill `image_u8_t` with those. The plane's bytes-per-row can exceed the width, which is exactly what `stride` is for.
- **[P]** The probe passed `stride = 1920` with a smaller `width` and `height` and an offset `buf` pointer, and detection and pose were identical to the full-frame result.

**Existing Swift wrappers (leads only, secondary)**

- `https://github.com/keyqcloud/SwiftAprilTag`: MIT wrapper with vendored C sources, a `CVPixelBuffer` luma path and pose. Created 2026-05-08, last pushed 2026-05-09, 1 star (GitHub API, read 2026-11-12). Two days of history is not a maintenance record. Useful as a reference for the package manifest, which uses the same `CAprilTag` plus wrapper split.
- `BuildMonumental/AprilTags-Swift` (pushed 2026-06-17, 0 stars, wraps a fork), `bouk/AprilTags` (1 star), `dadgarki/apriltag_swift`, `AmirAliAminiAghdam/AprilTag3_in_iOS` (last pushed 2024-12). None is established.
- **[I]** Writing the wrapper in-repo is about a hundred lines and removes a dependency on an unproven package. That is the recommendation.

### 2. Tag family

**Geometry and code strength, read from the family source files**

| Family | Data bits | Min. Hamming | IDs | Detection edge / printed width (cells) | Border |
|---|---|---|---|---|---|
| `tag36h11` | 36 | 11 | 587 | 8 / 10 | black outside, needs white margin |
| `tagStandard41h12` | 41 | 12 | 2115 | 5 / 9 | white outside black, data ring outside |
| `tagCircle21h7` | 21 | 7 | 38 | 5 / 9 | as 41h12, corners unused |
| `tagAruco6x6_250` | 36 | 11 | 250 | 8 / 10 | as 36h11 |
| `tagArucoMIP36h12` | 36 | 12 | 250 | 8 / 10 | as 36h11 |
| `tagAruco4x4_50` | 16 | 4 | 50 | 6 / 8 | as 36h11 |
| `tagAruco5x5_100` | 25 | 7 | 100 | 7 / 9 | as 36h11 |

- **[V]** Values are the `h`, `ncodes`, `nbits`, `width_at_border`, `total_width` and `reversed_border` fields: `{AT}/tag36h11.c` lines 624-704, `{AT}/tagStandard41h12.c` lines 2152-2242, `{AT}/tagCircle21h7.c` lines 75-125, `{AT}/aruco/tagArucoMIP36h12.c` lines 304-384, and the matching lines in the other `aruco/` files.
- **[V]** The upstream default advice is 41h12. `{AT}/README.md` line 69: "For the vast majority of applications, the tagStandard41h12 family will be the correct choice."
- **[V]** The ArUco families are in master only, and are offered for compatibility: `{AT}/README.md` line 75, "If you need ArUco support, use the native ArUco families".

**False positives**

- **[V]** Krogius, Haggenmiller and Olson 2019, Table I (`https://april.eecs.umich.edu/media/pdfs/krogius2019iros.pdf`): for 41h12 over 6,090,028 candidate quads from 207,920 LabelMe images, the Ising-energy family gave 0, 0, 4 and 44 false positives at 0, 1, 2 and 3 bits corrected.
- **[V]** Wang and Olson 2016, Table I (`https://april.eecs.umich.edu/media/pdfs/wang2016iros.pdf`): for 36h11 with up to 2 bits corrected, 6 false detections in 13,623,725 candidate quads, "0.000044%".
- **[V]** Small codes are much worse. Krogius 2019, Table II: the 21h7 circular family gave 85 false positives at 0 bits corrected and 22,266 at 2 bits on the same dataset.
- **[V]** Error correction raises the false-positive rate. `{AT}/apriltag.h` lines 204-205: "accepting large numbers of corrected errors leads to greatly increased false positive rates."
- **[I]** For this project both 36h11 and 41h12 are far below any rate that matters, because the wrapper can also reject every ID that is not one of the few tags the lab printed (cutting the rate by roughly IDs-used / IDs-in-family) and can reject detections outside the tracking window. The low-Hamming ArUco dictionaries (4x4, 5x5) and 21h7 should not be used. No published false-positive measurement was found for the ArUco families as implemented in this library **[U]**.

**Speed**

- **[V]** Decoding cost does not grow with family size. Wang 2016, section III-E: the lookup makes decoding "O(1), where n is the size of the tag family."
- **[V]** Krogius 2019, section IV-C: "When tuned for maximum recall, the new detector has roughly equivalent performance using either family." And: "when tuned for greater speed (high decimation factor), the recall of the 41h12 tag family is less than that of the 36h11 tag family." The authors add that this "may be an artifact" of their white backgrounds.
- **[P]** In the Mac probe, 36h11 and 41h12 at the same size took the same time (1.8 ms against 1.9 ms full frame, clean background, decimate 2).

**Minimum size in pixels**

- **[V]** The detector's hard floors come from the quad stage. `{AT}/apriltag_quad_thresh.c` lines 1818-1833: the minimum quad width is the family's `width_at_border` divided by `quad_decimate`, floored at 3 px, and line 961 rejects quads with "area < 0.95*tag_width*tag_width". Line 1078 rejects clusters smaller than `min_cluster_pixels`, which defaults to 24 (`{AT}/apriltag.c` line 381).
- **[V]** Krogius 2019, section IV-A: "If printed at the same physical size, the 9x9 tag would have a larger bit pitch, which improves its detection range." Section III-A, on moving the border inward: "the smaller border potentially reduces pose accuracy and detection distance".
- **[V]** Olson 2011, section V-B (`https://april.eecs.umich.edu/media/pdfs/olson2011tags.pdf`): going from 36-bit to 16-bit tags gains little range, "only a 25% improvement in detection range can be expected".
- **[P]** On noise-free synthetic frames the probe detected 36h11 at 20 px printed width (2 px per cell) at decimate 1 and 2, and 41h12 at 18 px printed width at decimate 1 but not at decimate 2. This is a best case with perfect focus, contrast and no blur.
- **[U]** No primary source states a minimum pixels-per-cell for real images. The papers report range in metres for cameras whose focal length in pixels is not given. The design target used in this note, at least 5 px per cell and at least 40 px across the detection edge, is an engineering margin, not a published figure. The benchmark should find the real floor under gym lighting and motion blur.

**Why 36h11 for this project**

- **[I]** Pose uses only the four corners of the detection square. For a printed width W, that square is 0.8 W for 36h11 and 0.556 W for 41h12 (table above). Depth error scales with 1 / edge (section 7), so at equal footprint 36h11 has 0.8 / 0.556 = 1.44 times less depth error. The footprint is the binding constraint on a bar end.
- **[I]** 41h12's advantages are more IDs (2115 against 587) and one more unit of Hamming distance. The project needs perhaps one ID per Station. 36h11's cost is a slightly smaller cell for the same print (W/10 against W/9), which matters only near the detection floor, and the recommended tag is well above it.
- **[I]** `tagArucoMIP36h12` has the same geometry as 36h11 with Hamming distance 12, but exists only on unreleased master and has no published false-positive data in this detector. It is not worth the risk.

### 3. Tag size and mounting on a 50 mm sleeve

**Equipment dimensions**

- **[V]** IPF Technical Rulebook, effective 2026-03-01, section 2.3 (`https://www.powerlifting.sport/fileadmin/ipf/data/rules/technical-rules/english/2026_IPF_Technical_Rulebook__effective_01_March_2026__v3.pdf`, page 8): "Diameter of the sleeve not to exceed 52 mm or be less than 50 mm."
- **[V]** Same section: "The diameter of the largest discs shall not be more than 45 cm", "The hole size in the middle of the disc must not exceed 53 mm or be less than 52 mm", "Total overall length not to exceed 2.2 m" and "Distance between the collar faces is not to exceed 1.32 m or be less than 1.31 m."
- **[I]** Each sleeve side therefore has at most (2.2 - 1.31) / 2 = 0.445 m from collar face to bar end.
- **[U]** The IWF Technical and Competition Rules could not be read (the IWF download link returned HTTP 403). The 50 mm IWF sleeve diameter is widely reported in secondary sources but is not verified here.
- **[U]** Whether the lab's bars have a flat, steel end face, a recessed end cap, or a hollow sleeve bore, and what a trap bar's sleeve end looks like, has to be checked on the actual equipment. Trap-bar sleeves vary by maker and no specification governs them.

**Sizes** (computed with fx = 1442 px; see section 4 for that assumption)

| Printed tag | Detection edge (`tagsize`) | Cell | At 1.5 m: edge, px per cell | At 2.0 m | At 2.5 m |
|---|---|---|---|---|---|
| 36h11, 90 mm | 72 mm | 9 mm | 69 px, 8.7 | 52 px, 6.5 | 42 px, 5.2 |
| 41h12, 90 mm | 50 mm | 10 mm | 48 px, 9.6 | 36 px, 7.2 | 29 px, 5.8 |
| 36h11, 60 mm | 48 mm | 6 mm | 46 px, 5.8 | 35 px, 4.3 | 28 px, 3.5 |
| 36h11, 35 mm | 28 mm | 3.5 mm | 27 px, 3.4 | 20 px, 2.5 | 16 px, 2.0 |

- **[I]** Pixels = fx x size / distance. Example: 1442 x 0.072 / 2.0 = 51.9 px.
- **[I]** A square that stays inside the 50 mm sleeve circle has a side of at most 50 / sqrt(2) = 35.4 mm. That is the 35 mm row: plates could slide over it, so it could stay on the bar permanently, but it falls below the 5 px per cell target beyond about 1 m and has 72 / 28 = 2.6 times the depth error of the 90 mm tag.
- **[I]** A 90 mm tag is wider than the 52 to 53 mm disc hole, so its carrier must come off to change plates. That sets the mount concept.

**Mount concept**

- **[I]** A removable end cap: a cup or plug that seats on the end of the sleeve and carries a rigid, flat 100 mm square plate, with the tag centre on the bar axis and the plate perpendicular to it. It goes on last, after plates and collar, and comes off first. Seating options to prototype are a cup with a 50 to 52 mm bore and a thumbscrew or over-centre clamp, or a magnetic base if the sleeve end is flat steel. Which one works depends on the unknown end-face geometry above.
- **[I]** Centre the tag on the axis. A tag centre displaced e from the axis traces a circle of radius e when the sleeve turns, which appears as a spurious position oscillation of amplitude e. Olympic bar sleeves are built to turn on the shaft (general knowledge, not verified against a primary source), and plates roll on the floor in a deadlift. A centred tag only spins in place, and AprilTag codes are rotation-safe: Olson 2011, section V-A, guarantees the Hamming distance "for all four rotations of each tag".
- **[I]** Rigidity and flatness. Pose assumes a planar tag of exactly known size. Olson 2011, section VI-B, lists "tag non-planarity" among the things that degrade real-world accuracy. Print on a rigid, matte substrate (not paper taped to a curved or flexing surface), measure the printed detection edge with calipers, and store that measured value as `tagsize`.
- **[V]** What `tagsize` means. `{AT}/README.md` line 196: "The tag size should not be measured from the outside of the tag. The tag size is defined as the distance between the detection corners".
- **[I]** Keep a white margin. For 36h11 the outermost of the 10 cells is the white ring that forms the detected border edge, so the full 90 mm must be printed and kept clean. Add a few millimetres of white beyond that on the 100 mm carrier so a dark plate behind does not merge with the edge under blur.
- **[V]** Tag images come from `https://github.com/AprilRobotics/apriltag-imgs` (BSD-2-Clause), which holds "Images of all tags from all the pre-generated" families at one pixel per cell and a `tag_to_svg.py` script with a `--size` option for printing at a set physical size.
- **[I]** Plates blocking the view. Viewed along the bar axis, the plates and collar are behind the end-cap tag, so they cannot occlude it. They only form its background. The practical occluders are people and objects between the Station and the bar end (section 4).
- **[U]** Whether an end cap survives dropped deadlifts and repeated handling, and how repeatably it re-seats on centre, needs a physical prototype.

### 4. Station distance and lateral offset for each lift

**Field of view, the assumption everything here rests on**

- **[V]** Apple's iPhone XR specifications (`https://support.apple.com/en-us/111868`): "12MP Wide camera", "Optical image stabilization", and "Slo-mo video support for 1080p at 120 fps or 240 fps". The page gives no focal length.
- **[I]** The map gives a 26 mm equivalent lens. For a 4:3 sensor, the 35 mm-equivalent diagonal of 43.27 mm corresponds to a half-width of 43.27 x 0.8 / 2 = 17.31 mm, so the horizontal field of view is 2 x atan(17.31 / 26) = 67.3 degrees. If a 1920-px-wide video format spans the full sensor width, fx = 960 / tan(33.65 degrees) = 1442 px.
- **[U]** Whether the XR's 1080p 120 fps format uses the full sensor width, a centre crop, or binning is not documented by Apple and was not found in any primary source. A crop raises fx and every pixel count above in proportion, and narrows the coverage figures below by the same factor. The Station can read this directly: `AVCaptureDevice.Format.videoFieldOfView` "Indicates the format's horizontal field of view in degrees" (`https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/videofieldofview`). The capture-pipeline note lists the same unknown.

**Coverage** (portrait, fx = 1442 px assumed)

| Distance | Vertical coverage (1920 px) | Horizontal coverage (1080 px) |
|---|---|---|
| 1.5 m | 2.00 m | 1.12 m |
| 2.0 m | 2.66 m | 1.50 m |
| 2.5 m | 3.33 m | 1.87 m |

- **[I]** Coverage = pixels x distance / fx.

**Placement per lift**

All of the following is **[I]**: geometry worked from the equipment dimensions above and typical bar heights, to be confirmed at the rack.

- **Common to all lifts.** The Station looks along the bar axis at the end cap, in portrait, 2.0 to 2.5 m from the bar end. Rack uprights sit inboard of the plates, so they are behind the tag from this viewpoint and cannot hide it. Set the lens height near the middle of the bar's vertical travel, so the tag stays close to the image centre. This keeps the viewing angle small and limits how much depth noise leaks into height (section 7).
- **Lateral offset.** Exact alignment with the bar axis is not required. An offset of 5 to 15 degrees (0.2 to 0.5 m sideways at 2 m) costs under 4% of tag width in foreshortening (cos 15 degrees = 0.966) and can be used to keep the Station out of the walkway. Olson 2011, Fig. 9, and Wang 2016, Fig. 6, show detection and orientation accuracy holding until the tag is turned far from frontal. Avoid large offsets: beyond about 20 degrees the plate rim or collar can start to cut into the view of a tag that sits close to the plate face.
- **Back squat and front squat.** Bar height runs from roughly 0.8 m at the bottom to 1.6 m standing (IPF racks adjust from "1.00 m in the lowest position" to "at least 1.70 m"). Lens at about 1.2 m. The walkout moves the bar horizontally in the image, perpendicular to the bar axis, by up to about a metre, so use 2.5 m, or aim the Station at the squatting position and accept that the racked position is near the image edge.
- **Bench press.** Bar height runs from about 0.7 m at the chest to about 1.2 m at lockout (IPF bench height is "not less than 42 cm and not exceeding 45 cm", bar rests "75 cm to a maximum of 110 cm"). Lens at about 1.0 m, 2.0 m away.
- **Deadlift, straight bar.** The bar starts at half a plate diameter, about 0.225 m above the floor (from the 45 cm disc), and finishes around 0.7 to 0.9 m. Lens at about 0.5 m, 2.0 m away. A low mount is the constraint here; a Station at squat height looks down at 15 to 20 degrees, which is acceptable but puts the tag off-centre.
- **Deadlift, trap bar.** Same heights. The sleeve geometry is unknown (section 3).
- **Occluders.** The real risk is a person standing at the bar end: side spotters on squat and bench, and anyone loading plates. Keep the 2 m corridor between Station and bar end clear during a Set. Plate storage horns, adjacent racks and a second bar are fixed and can be checked once at setup.
- **Background.** The plate face behind the tag is a large, mostly uniform disc, which is a benign background. Printed lettering on bumper plates adds candidate quads but they are rejected at decode.

### 5. Detector parameters

Defaults, from `apriltag_detector_create` (`{AT}/apriltag.c` lines 372-404): `nthreads = 1`, `quad_decimate = 2.0`, `quad_sigma = 0.0`, `refine_edges = true`, `decode_sharpening = 0.25`, `min_cluster_pixels = 24`, `min_white_black_diff = 5`. **[V]**

**`quad_decimate`**

- **[V]** `{AT}/apriltag.h` lines 135-138: "detection of quads can be done on a lower-resolution image, improving speed at a cost of pose accuracy and a slight decrease in detection rate. Decoding the binary payload is still done at full resolution."
- **[V]** `{AT}/README.md` line 165: "Increasing the quad_decimate parameter will increase the speed of the detector at the cost of detection distance."
- **[V]** Decimation is point sampling. Krogius 2019, section III-C-1: "The value of the output pixel is set to the value of a single pixel from the input image."
- **[V]** Wang 2016, section IV-B, on decimating by 2: the new detector works "without noticeably affecting localization accuracy vs. non-decimated images", on ray-traced images.
- **[V]** Only 1.5 and integers are implemented. `{AT}/common/image_u8.c` line 443 has a special case "if (ffactor == 1.5)"; otherwise line 489 does "int factor = (int) ffactor". But the corners are scaled back by the unrounded float (`{AT}/apriltag.c` lines 1143-1144: "q->p[j][0] *= td->quad_decimate"). **[I]** A value such as 2.5 therefore decimates by 2 and rescales by 2.5, which misplaces every corner. Restrict the setting to 1, 1.5, 2, 3, 4.
- **[P]** Mac probe, full 1080p frame, one thread, cluttered background: 54 ms at 1, 31 ms at 1.5, 19 ms at 2, 10 ms at 3, 6.9 ms at 4. Clean background: 7.0, 3.7, 2.0, 0.95, 0.60 ms. Cost falls roughly with the square of the factor and depends heavily on scene clutter.

**`refine_edges`**

- **[V]** `{AT}/apriltag.h` lines 147-150: edges are adjusted to "snap to" strong gradients nearby; "Generally recommended to be on (true)." Wang 2016, section III-F: "the edge refinement step improves localization accuracy when tags are used for pose estimation."
- **[V]** The header comment says "Option is ignored if quad_decimate = 1", but the current code applies it regardless: `{AT}/apriltag.c` lines 948-950 have the decimate condition commented out and run `if (td->refine_edges)`. Leave it on.

**`decode_sharpening`**

- **[V]** `{AT}/apriltag.h` lines 156-160: "This can help decode small tags but may or may not help in odd lighting conditions or low light conditions. The default value is 0.25." Krogius 2019, section III-D: the sharpening "should help to counteract the blurring that occurs in very small images of tags."
- **[I]** It acts on the sampled bit grid only, not on corner positions, so it affects whether a tag decodes and not the pose. With 5 or more pixels per cell it should be irrelevant. Keep the default; sweep it only if decodes fail under motion blur.

**`quad_sigma`**

- **[V]** `{AT}/apriltag.h` lines 141-144: "Very noisy images benefit from non-zero values (e.g. 0.8)." `{AT}/README.md` line 165: "If your image is somewhat noisy, increasing the quad_sigma parameter can increase speed."
- **[I]** Start at 0. Short exposures at 120 fps under gym lighting may be noisy enough for 0.8 to help; that is a benchmark sweep.

**`nthreads`**

- **[V]** `{AT}/README.md` line 165: "If you have extra cpu cores to throw at the problem then you can increase nthreads." Threads are plain pthreads created once per detector (`{AT}/common/workerpool.c` lines 104-112) and only when `nthreads > 1`.
- **[P]** Mac probe, cluttered full frame, decimate 2: 18.9 ms with one thread, 10.9 ms with two.
- **[I]** The A12 has two performance cores, and capture, encoding and the UI also need CPU. Use 1 thread inside the tracking window, where there is too little work to split, and 2 for full-frame search. Whether the library's worker threads land on performance cores under iOS scheduling is **[U]**.

**Error correction bits**

- **[V]** `{AT}/apriltag.h` lines 240-246: `apriltag_detector_add_family` uses 2 bits; `apriltag_detector_add_family_bits` sets it explicitly. Lines 206-207: "the detector cannot detect tags with a hamming distance greater than 2."
- **[I]** Use 1. A large, clean, close tag should decode with 0 errors; 1 gives tolerance for a speck of chalk. Log `hamming` and `decision_margin` per detection during the benchmark and tighten if they are always 0 and high.

**Built-in timing**

- **[V]** The detector records per-stage timings for the last frame in `td->tp` (`{AT}/apriltag.h` lines 171-172, "Statistics relating to last processed frame"), printable with `timeprofile_display` (`{AT}/common/timeprofile.h` line 87). The benchmark can use this to see which stage dominates on the XR.

### 6. Searching only a region around the last detection

- **[V]** The library has no region-of-interest parameter. The public detector fields are those listed in `{AT}/apriltag.h` lines 127-191 and none restricts the search area.
- **[V]** The image header carries its own stride and base pointer (`{AT}/common/image_types.h` lines 37-44), and every pixel access in the pipeline indexes with `stride` (for example `{AT}/common/image_u8.c` line 498).
- **[I]** A window is therefore free: set `buf` to the address of the window's top-left pixel in the luma plane, `width` and `height` to the window size, and `stride` to the plane's bytes-per-row. No copy is made.
- **[I]** Detections come back in window coordinates. For pose, the simplest exact correction is to shift the principal point: pass `cx - x0` and `cy - y0` to `estimate_tag_pose`. This is exact because the pose code uses only `(p - c) / f` and the homography in the same coordinates (`{AT}/apriltag_pose.c` line 506, line 458). For reporting, add `(x0, y0)` to the corners and centre.
- **[P]** The probe confirmed this: the window result matched the full-frame centre to 0.01 px and the pose depth exactly (0.7500 m both ways).
- **[P]** Mac probe, cluttered frame, one thread: full frame at decimate 2 took 18.9 ms; a 384 x 384 window took 1.2 ms at decimate 2 and 3.8 ms at decimate 1. On a clean background the window took 0.30 ms and 0.73 ms.
- **[V]** Minimum window size: the detector returns nothing for images under 8 px on a side (`{AT}/apriltag.c`, "if (im_orig->width < 8 || im_orig->height < 8)").
- **[I]** Window sizing. At 120 fps a bar moving 2 m/s travels 16.7 mm per frame, which is 12 px at 2 m (1442 x 0.0167 / 2). The tag moves very little between frames, so the window is set by the tag, not by motion: about three times the printed tag width, for example 256 px for a 65 px tag, leaves a full tag-width of margin on each side. Make the side a multiple of 4, because thresholding works in 4 x 4 tiles (`{AT}/apriltag_quad_thresh.c`, "const int tilesz = 4").
- **[I]** Acquisition and loss. Start with a full-frame search at decimate 2 or 3 (two threads). Once found, track in the window at decimate 1. After a few consecutive misses, widen the window, then fall back to full frame. A full-frame search that overruns one frame period only delays re-acquisition; it does not need to fit 8.3 ms.
- **[I]** Decimate 1 inside the window is recommended because the header itself says decimation costs pose accuracy, and the window makes full resolution cheap.

### 7. Pose estimation and how its error behaves

**API**

- **[V]** `{AT}/apriltag_pose.h` lines 11-18: the input struct holds the detection, "tagsize; // In meters" and "fx", "fy", "cx", "cy" each "In pixels". Lines 25-28: the output is a 3x3 rotation `R` and 3x1 translation `t`, "the position of the tag within the camera frame."
- **[V]** `{AT}/README.md` line 201: "The z-axis points from the camera center out the camera lens. The x-axis is to the right in the image taken by the camera, and y is down."
- **[V]** Method, `{AT}/apriltag_pose.h` lines 42-45: "This uses the homography method described in [1] for the initial estimate. Then Orthogonal Iteration [2] is used to refine this estimate. Then [3] is used to find a potential second local minima".
- **[V]** `estimate_tag_pose` runs 50 iterations and returns whichever of the two candidates has the lower object-space error (`{AT}/apriltag_pose.c` lines 528-546). The caller must free `pose.R` and `pose.t` with `matd_destroy`.
- **[V]** The README offers an alternative: "alternately use OpenCv's Pnp solver with SOLVEPNP_IPPE_SQUARE" (`{AT}/README.md` line 173). Not needed here.

**Intrinsics**

- **[V]** The pose code assumes an undistorted pinhole model: it converts each corner with `(p - cx) / fx` and `(p - cy) / fy` and nothing else (`{AT}/apriltag_pose.c` line 506).
- **[V]** iOS can deliver intrinsics per frame. Apple (`https://developer.apple.com/documentation/avfoundation/avcaptureconnection/iscameraintrinsicmatrixdeliveryenabled`): "Camera intrinsics describe the current imaging parameters of a capture device in ways that you can use to render overlays or perform computer vision tasks." The attachment is "a 3x3 camera intrinsic matrix to apply to the current sample buffer" (`https://developer.apple.com/documentation/coremedia/kcmsamplebufferattachmentkey_cameraintrinsicmatrix`).
- **[U]** Whether the XR supports intrinsic delivery on its 1080p 120 fps format, how accurate the delivered values are, whether they move with focus and optical stabilisation, and how large the lens distortion is at the image edges. Per-device calibration with a checkerboard or tag grid, at the capture format and a locked focus, is the decided route; the delivered matrix is a cross-check.
- **[I]** If the Station rotates frames to portrait, the intrinsics must be expressed in the same orientation as the buffer handed to the detector. Swapping fx with fy and cx with cy is easy to get wrong; a unit test with a synthetic frame catches it.
- **[I]** If distortion matters, undistort only the four corner points before calling `estimate_tag_pose`. That is four point evaluations, not an image remap.

**Error along the camera axis versus in the image plane**

- **[I]** Pinhole model, tag edge s, distance Z, focal length f in pixels, tag edge in the image p = f s / Z. Then Z = f s / p, and a pixel error dp in the measured edge gives dZ = (Z^2 / (f s)) dp. A pixel error du in the tag centre gives a lateral error dX = (Z / f) du. For equal pixel errors the ratio is dZ / dX = Z / s.
- **[I]** Numbers for the 72 mm edge at fx = 1442 px, per 0.1 px of error:

  | Distance | In-plane (X or Y) | Depth (Z) | Ratio |
  |---|---|---|---|
  | 1.5 m | 0.10 mm | 2.2 mm | 21 |
  | 2.0 m | 0.14 mm | 3.9 mm | 28 |
  | 2.5 m | 0.17 mm | 6.0 mm | 35 |

  Example: 2000^2 / (1442 x 72) x 0.1 = 3.85 mm depth; 2000 / 1442 x 0.1 = 0.139 mm in-plane.
- **[V]** The corner estimates are sub-pixel. Olson 2011, section III-B: "Because the lines are fit using data from many pixels, these corner estimates are accurate to a small fraction of a pixel." No primary source gives a number for the current detector on real images, so 0.1 px is a unit for scaling, not a claim **[U]**.
- **[V]** The same shape appears in the published evaluations. Olson 2011, section VI-B: "The main factor in localization accuracy is the size of the target, which is affected by both the distance and orientation of the tag." Wang 2016, Fig. 5, plots position error growing with distance.
- **[V]** According to PubMed, Abbas et al. 2019, "Analysis and Improvements in AprilTag Based State Estimation", Sensors 19(24):5480 ([DOI](https://doi.org/10.3390/s19245480)), a peer-reviewed evaluation against motion capture, found that "the angular rotation of the camera (yaw angle) about its vertical axis is the primary source of error", with "the distance and viewing angle of the camera from the AprilTag" as the other factors. **[I]** This supports keeping the tag near the image centre and the Station roughly square to it. The paper's per-axis figures could not be extracted from the retrieved text and are not quoted here.
- **[I]** What this means for bar velocity. The Station looks along the bar axis, so vertical bar motion is in the image plane, the precise direction. Depth is the bar-axis direction, which the lift barely uses; depth matters only as the scale that turns pixels into millimetres. Height is computed as Y = Z (v - cy) / fy, so depth noise leaks into height in proportion to how far the tag is from the image centre: a tag 300 px off-centre carries 300 / 1442 = 0.21 of the depth noise into Y. Two consequences for the spec: keep the tag near the centre row (lens at mid-travel height), and low-pass the depth across a Rep or Set, or fix it per Set, instead of using each frame's raw Z.
- **[V]** Rotation is ambiguous for planar targets. The pose code looks for "a potential second local minima" (`{AT}/apriltag_pose.h` line 44, citing Schweighofer and Pinz 2006, "Robust Pose Estimation from a Planar Target"). **[I]** A small tag viewed nearly head-on is the classic case where the two candidate rotations are close in error and the chosen one can flip between frames. Translation is much less affected. The rep logic should use `t` only, and should not derive anything from `R` without checking for flips. How often flips happen with this setup is **[U]**.
- **[I]** Motion blur is the other error source and is set by exposure, not by the detector. At 2 m, 1 m/s is 721 px/s (1442 / 2). An exposure of 1/1000 s smears edges by 0.7 px; 1/240 s smears them by 3 px. Vertical blur shifts the top and bottom edges together, so it biases apparent tag height more than tag centre. Exposure limits belong to the capture pipeline note.

### 8. Published per-frame cost on A12-class hardware

- **[U]** No published per-frame timing for AprilTag 3 on an A12, or any iPhone, was found in the repository, its wiki, its release notes, or the three papers.
- **[V]** The closest statement about phones is qualitative. Wang 2016, section IV-C: "The detector performance is good enough to run on the relatively lower-powered iPhone and similar smartphone processors". No figure accompanies it, and it refers to AprilTag 2.
- **[V]** AprilTag 2, one thread of an Intel Xeon E5-2640 at 2.5 GHz, natural images (Wang 2016, section IV-C): "about 0.254 microseconds per pixel", and with decimation by 2 "0.072 microseconds per pixel, or about 22 ms for a 640 x 480 image." The paper warns: "The absolute times are not meant to be representative". **[I]** Scaled to 1920 x 1080 (2,073,600 px) that is about 149 ms per frame at decimate 2.
- **[V]** AprilTag 3, Intel Core i7-7600U at 2.80 GHz, 1296 x 964 images (Krogius 2019, section III-E and Fig. 7): a speed-versus-recall sweep whose x-axis runs from 0 to 1200 frames per second. **[I]** Read from the plot, the high-recall end of the AprilTag 3 curves sits well under 100 frames per second and the fast end near 1000; exact values are not tabulated.
- **[V]** `{AT}/README.md` line 3 claims AprilTag 3 has "a faster (>2x) detector" than AprilTag 2.
- **[P]** This note's Mac probe (Apple M2 Pro, release build, synthetic 1080p frames, pinned commit): full frame, one thread, decimate 2 took 2.0 ms on a clean background and 18.9 ms on a blocky high-contrast background; a 384 px window took 0.3 to 1.2 ms. An M2 Pro performance core is substantially faster than an A12 core; the ratio was not verified here, so these are not converted into XR estimates.
- **[I]** The takeaway is qualitative: per-frame cost is dominated by image area and scene clutter, full-frame search at 1080p is in the tens of milliseconds on desktop-class cores in cluttered scenes, and the tracking window brings it down by an order of magnitude. Whether the window fits inside 8.3 ms on the XR alongside capture and encoding is the benchmark's question.

## What only the XR benchmark can settle

1. Per-frame detection and pose cost on the XR at 1080p: full frame at decimate 2, 3 and 4 with 1 and 2 threads, and the tracking window at decimate 1 and 2, in a real gym scene. Use `td->tp` to see which stage dominates.
2. The field of view (and so fx) of the 1080p 120 fps format, and whether it is cropped or binned. This rescales every pixel count in this note.
3. Whether `tag36h11` or `tagStandard41h12` gives the steadier pose at equal printed size on real footage. This note predicts 36h11.
4. The real minimum pixels per cell under gym lighting, 120 fps exposure and bar motion, and whether `quad_sigma = 0.8` or a different `decode_sharpening` helps.
5. Frame-to-frame noise in `t` (in-plane and depth) with the bar stationary, and how often the rotation estimate flips.
6. Whether decimate 1 in the window measurably improves pose over decimate 2 with `refine_edges` on.
7. How many frames are lost to motion blur at peak bar speed for the exposure the capture pipeline can hold.
8. Whether the detector's worker threads run on performance cores, and what two threads do to capture and encoding headroom and to thermals over a Session.
9. Whether per-frame intrinsic delivery is available on that format and how it compares to the calibrated values; how much lens distortion there is where the tag travels.

Not benchmark items, but open and physical: the end-face geometry of the lab's straight bars and trap bar; a prototype end cap's centring repeatability and durability; the IWF sleeve specification (not read).

## Sources

Primary, read for this note:

- AprilRobotics/apriltag at commit `b7c0ebe9aa20f82ec7a828579004f9e706bfecd9`: `README.md`, `LICENSE.md`, `CMakeLists.txt`, `apriltag.h`, `apriltag.c`, `apriltag_quad_thresh.c`, `apriltag_pose.h`, `apriltag_pose.c`, `common/image_types.h`, `common/image_u8.c`, `common/workerpool.c`, `common/pthreads_cross.h`, `common/timeprofile.h`, `tag36h11.c`, `tagStandard41h12.c`, `tagCircle21h7.c`, `aruco/*.c`. https://github.com/AprilRobotics/apriltag/tree/b7c0ebe9aa20f82ec7a828579004f9e706bfecd9
- AprilRobotics/apriltag releases and compare API: https://api.github.com/repos/AprilRobotics/apriltag/releases/latest and https://api.github.com/repos/AprilRobotics/apriltag/compare/v3.4.5...master
- AprilRobotics/apriltag-imgs README: https://github.com/AprilRobotics/apriltag-imgs
- E. Olson, "AprilTag: A robust and flexible visual fiducial system", ICRA 2011: https://april.eecs.umich.edu/media/pdfs/olson2011tags.pdf
- J. Wang and E. Olson, "AprilTag 2: Efficient and robust fiducial detection", IROS 2016: https://april.eecs.umich.edu/media/pdfs/wang2016iros.pdf
- M. Krogius, A. Haggenmiller and E. Olson, "Flexible Layouts for Fiducial Tags", IROS 2019: https://april.eecs.umich.edu/media/pdfs/krogius2019iros.pdf
- S. M. Abbas, S. Aslam, K. Berns and A. Muhammad, "Analysis and Improvements in AprilTag Based State Estimation", Sensors 19(24):5480, 2019 (retrieved through PubMed, PMC6960891): https://doi.org/10.3390/s19245480
- Swift Package Manager documentation, "Creating C language targets": https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/CreatingCLanguageTargets.md
- Apple, PackageDescription `publicHeadersPath`: https://developer.apple.com/documentation/packagedescription/target/publicheaderspath
- Apple, iPhone XR Technical Specifications: https://support.apple.com/en-us/111868
- Apple, `isCameraIntrinsicMatrixDeliveryEnabled`: https://developer.apple.com/documentation/avfoundation/avcaptureconnection/iscameraintrinsicmatrixdeliveryenabled
- Apple, `kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix`: https://developer.apple.com/documentation/coremedia/kcmsamplebufferattachmentkey_cameraintrinsicmatrix
- Apple, `AVCaptureDevice.Format.videoFieldOfView`: https://developer.apple.com/documentation/avfoundation/avcapturedevice/format/videofieldofview
- IPF Technical Rulebook, effective 2026-03-01, sections 2.3 to 2.6: https://www.powerlifting.sport/fileadmin/ipf/data/rules/technical-rules/english/2026_IPF_Technical_Rulebook__effective_01_March_2026__v3.pdf

Secondary, used as leads only:

- keyqcloud/SwiftAprilTag: https://github.com/keyqcloud/SwiftAprilTag
- GitHub repository search for Swift AprilTag wrappers: https://api.github.com/search/repositories?q=apriltag+language:swift

Not read (attempted, failed): IWF Technical and Competition Rules and Regulations (HTTP 403 from iwf.sport).

Probe: a throwaway SwiftPM package (C target plus a Swift executable) built outside the repository on 2026-11-12 with Xcode's Swift 6.4.2 toolchain, on an Apple M2 Pro. It is not checked in. If the numbers marked [P] are wanted as a repeatable artifact, the XR benchmark ticket should recreate it under `probes/`.
