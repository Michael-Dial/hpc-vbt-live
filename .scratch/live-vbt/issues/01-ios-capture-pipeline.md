# iOS capture pipeline

Type: research
Status: open
Blocked by:

## Question

On an iPhone XR (A12, 3 GB RAM, iOS 18 as its final OS), which AVFoundation pipeline can do all of the following for 60+ minutes without interruption?

- Capture 1080p at 120 fps. Also establish whether the 240 fps formats are exposed to third-party apps.
- Encode every frame to a file: one continuous Recording per Session.
- Deliver every frame to app code for live tag detection.
- Keep the hardware presentation timestamp for every frame.

Cover:

- AVAssetWriter fed from AVCaptureVideoDataOutput, versus AVCaptureMovieFileOutput running alongside a data output. Is that combination supported on iOS 18?
- Locking frame rate, exposure, and focus; turning off video stabilization; whether OIS can be disabled for video.
- Writing a per-frame timestamp sidecar.
- Detecting and logging dropped frames.
- Monitoring thermal and system pressure state, and degrading gracefully (for example, dropping live processing to 60 fps while still recording at 120 fps).
- Expected storage per minute at 1080p120 in HEVC and H.264.
- Anything in the above that requires iOS 26-only APIs, which the XRs can't use.

Output: a recommended pipeline with links to Apple documentation, plus a list of what only the XR benchmark can settle.
