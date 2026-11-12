# XR benchmark

Type: task
Status: open
Blocked by: 01, 02, 13

## Question

Can an iPhone XR run the recommended capture pipeline plus live AprilTag detection for a full Session?

The agent builds a minimal probe app from the answers to "iOS capture pipeline" and "AprilTag on iOS". The user runs it on one XR mounted at a rack, plugged into power, with a tagged bar.

Measure:

- Which formats are actually exposed (1080p at 120 and 240 fps).
- Detection time per frame (median and 95th percentile) at 1080p, searching a region around the last detection.
- Dropped frames.
- Thermal state across 60 minutes of continuous Recording.
- Storage used per minute.
- Regularity of frame timestamps.

Decision rule, agreed in advance: at 120 fps the budget is 8.3 ms per frame. If the 95th percentile exceeds about 8 ms, or frames drop, test live processing at 60 fps while still recording at 120 fps, and report both.

Output: the measurements and a recommendation: live at 120 fps, live at 60 fps, or the XRs are unsuitable as Stations.
