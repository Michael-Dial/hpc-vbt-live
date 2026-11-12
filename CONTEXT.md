# Live VBT

Live rep-by-rep velocity feedback for barbell lifts, captured by phones mounted at racks, for exploratory R&D and validation research at the OSU Human Performance Collaborative.

## Language

### People and time

**Participant**:
A person whose lifts are recorded.
_Avoid_: Athlete, lifter, subject, user

**Session**:
One block of gym time. Participants may rotate through Stations within it.
_Avoid_: Workout, block, practice

**Set**:
A run of Reps by one Participant at one load at one Station, located inside that Station's Recording by its start and end time.
_Avoid_: Bout, attempt

**Rep**:
One repetition of a lift within a Set.
_Avoid_: Repetition, lift, movement

### Capture

**Station**:
A phone mounted at a rack that tracks the bar and gives live feedback.
_Avoid_: Rack node, edge device, camera, client

**Recording**:
One Station's continuous raw capture for a whole Session: video plus a timestamp for every frame.
_Avoid_: Video, clip, capture, file

**Bar Track**:
The per-frame samples of bar position a Station logs within a Recording, including frames where the bar was not found.
_Avoid_: Trajectory, path, pose log, trace

**Host**:
The gym machine that runs a Session and receives Reps and Recordings from Stations.
_Avoid_: Server, hub, base station, backend

### Validation

**Criterion**:
The reference device a validation compares against (GymAware for v1).
_Avoid_: Gold standard, ground truth, reference device

**Reference Dataset**:
Recordings paired with Criterion data, used for development and regression testing.
_Avoid_: Golden dataset, test set, training data

### Processing

**Algorithm Version**:
The identifier stamped on every derived value, naming the exact logic and tuning that produced it.
_Avoid_: Build, release, model version

**Replay**:
Running a Recording, or its Bar Track, through the rep logic away from the Station.
_Avoid_: Reprocessing, offline analysis, batch run

**Regression Run**:
One Replay of the whole Reference Dataset that reports what changed and how agreement with the Criterion moved.
_Avoid_: Test run, benchmark, validation
