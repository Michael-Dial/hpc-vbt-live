# Wayfinder map: Live VBT v1

Label: wayfinder:map

## Destination

A v1 build spec, ready to hand to an implementing agent, for live rep-by-rep barbell VBT: XR Stations that track the bar and give feedback on the phone, a local Host with an iPad web UI, and a validation protocol with pass criteria against GymAware, backed by a collected Reference Dataset. The data model leaves room for future jump, IMU, and mocap Recordings.

## Notes

**Domain.** Exploratory R&D at the OSU Human Performance Collaborative. Not under an IRB, except that any Session comparing against the Criterion (GymAware) falls under the lab's existing IRB approval for validation research. Vocabulary is in `CONTEXT.md`; use its terms.

**Skills.** Grilling tickets: call the grilling and domain-modeling skills, and update `CONTEXT.md` as terms resolve. Research tickets: the research skill, fired as subagents. Prototype tickets: the prototype skill. Task tickets: drive alone where possible, otherwise hand the user a precise checklist.

**Hardware.**
- Several iPhone XR: A12, 3 GB RAM, single 12 MP wide camera with OIS, 1080p slo-mo formats at 120 and 240 fps. iOS 18 is their last OS, so iOS 26-only APIs (locked frame duration, genlock) are unavailable.
- One iPhone 17 Pro: the reference camera. Never develop or benchmark Station software against it; it hides XR performance problems.
- One iPad: opens the Host's web UI.
- GymAware: the Criterion.
- Samsung S10 and S22: not used in v1.
- Apple: the user's personal Apple Developer account.

**Lifts.** Back squat, front squat, bench press, deadlift (straight bar or trap bar).

**Decided before the map** (don't reopen without new evidence):
- Native Swift Station app, deployment target iOS 18.
- AprilTag 3 (C library, BSD-2) on the bar end for tracking, with full pose from per-device intrinsics.
- Rep logic lives in a pure Swift package shared by the app and a macOS replay CLI.
- The live value is the stored value. Reprocessing flags disagreements; it never overwrites what the Participant saw. Every derived value records its algorithm version.
- Raw data is never discarded: video, per-frame timestamps, device ID, calibration version.
- Session model: one Recording per Station per Session. Each Set carries its Participant, load, Station, and start and end time within that Recording.
- Host stack mirrors `hpc-open-wearables`: FastAPI, Postgres, Celery/Redis, React web UI served to the iPad.
- Stations, Host, and iPad sit on an isolated router with no internet route. Live feedback never depends on the network.
- Capture target 1080p at 120 fps, pending the XR benchmark.
- Delivery phases: Phase 0 groundwork, Phase 1 one Station with no Host, Phase 2 Host plus several Stations.

**Methods.** Agreement analyses use repeated-measures Bland-Altman limits of agreement, CCC, MAE/RMSE, proportional bias, and TOST equivalence against an a priori SESOI. Never correlation alone.

**Data handling.** Participant video and Criterion data stay on local machines. Never commit them to git and never upload them to cloud services, including cloud coding sessions.

## Decisions so far

<!-- one line per resolved ticket: [ticket title](issues/NN-slug.md): one-line gist -->

## Not yet specified

- **iPad UI and team view.** What coaches and researchers see and do on the iPad during a Session. Waits on [Set entry at the Station](issues/05-set-entry.md), [Host and network](issues/10-host-and-network.md), and [Data model and storage](issues/11-data-model.md).
- **Multi-Station load testing.** How to prove several Stations can run a full Session concurrently with no lost Reps. Waits on [Host and network](issues/10-host-and-network.md).
- **Station hardware.** Mounts, cabling, power, and lighting at each rack. Waits on [XR benchmark](issues/04-xr-benchmark.md), which sets the thermal and power constraints.
- **Analytics.** Load-velocity profiles, velocity-loss summaries, and exports to the lab's analysis pipeline. Waits on [Metric definitions per lift](issues/06-metric-definitions.md) and [Data model and storage](issues/11-data-model.md).
- **Container Services sync.** Pushing data from the Host to OSU Container Services. In scope, but only after v1 works fully self-hosted, and it needs its own decision on participant video.

## Out of scope

- Countermovement jumps and any jump module: a later map.
- Polar IMU on the bar: a later map.
- Multi-view markerless mocap (Pose2Sim, OpenSim): a later map.
- Android Stations.
- Olympic lifts, jump squats, dumbbell and kettlebell work.
- Hardware frame sync (genlock).
- Running the formal validation study. The map decides the protocol and pass criteria; the study runs after the build.
