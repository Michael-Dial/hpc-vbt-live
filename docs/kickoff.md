# Kickoff: hpc-vbt-live

This repo builds live rep-by-rep barbell VBT from phone cameras. Work runs in two stages. First, a wayfinder map turns open questions into decisions. Then those decisions become a v1 build spec, and the build follows the spec.

Sources of truth, read before acting:

- `CONTEXT.md`: the vocabulary. Use its terms in code, issues, and commits.
- The wayfinder map (`.scratch/live-vbt/map.md`, or the `wayfinder:map` issue after migration): destination, standing decisions, hardware, methods, and data handling.

## Standing rules

- **Map before build.** Product code starts once the map is clear and the spec is published. Until then, any code is a probe: throwaway, kept under `probes/`, and written to serve a task ticket.
- **One ticket per session.** Research tickets are the exception; they run in parallel as subagents.
- **Human-in-the-loop tickets** (grilling, prototype, and any task the agent can't finish alone) resolve in conversation with the user. Put each decision to the user and wait for their answer.
- **Data handling.** Before touching video, Recordings, or GymAware exports, read "Data handling" in the map's Notes. Participant data lives under `data/`, which git ignores.
- **Where sessions run.** Anything that builds, signs, or installs the Station app runs locally on the user's Mac with an XR connected. Research tickets and Host backend work can run in cloud sessions.

## Session 1: set up the repo

1. Check that `.gitignore`, `CONTEXT.md`, `docs/kickoff.md`, `.scratch/live-vbt/map.md`, and the 13 files in `.scratch/live-vbt/issues/` are committed and pushed. If any are missing, ask the user for the path to `live-vbt-wayfinder.zip`, run `unzip -o` on it at the repo root, then commit and push.
2. Run the setup-matt-pocock-skills skill. At the issue-tracker question, recommend GitHub Issues, because parallel sessions would conflict while editing a markdown map. The user decides.
3. If the user chose GitHub Issues, migrate the map:
   - Create the map issue, labelled `wayfinder:map`, from `map.md`.
   - Create each ticket as a sub-issue of the map: title from the file's heading, body from its Question, label `wayfinder:<type>` from its `Type:` line.
   - Turn each `Blocked by:` line into a native issue dependency, following the "Wayfinding operations" section of the tracker doc.
   - Rewrite the links in the map so they point at the new issues.
   - Delete `.scratch/live-vbt/` in its own commit.

Done when everything above is pushed and a frontier query returns exactly these six tickets: iOS capture pipeline; AprilTag on iOS; GymAware definitions, export, and alignment; Set entry at the Station; Host and network; Apple developer setup and installing on the XRs.

## Session 2: research

Charting stopped before its final step, which is firing the research subagents. Do that now: run each of the three research tickets as a parallel subagent using the research skill, and resolve each one as the wayfinder skill describes (answer recorded, ticket closed, gist added to Decisions so far).

Done when all three research tickets are closed with answers, and any fog they made specifiable has graduated into new tickets.

## Sessions 3 onward: work the map

Run the wayfinder skill on the map. It takes the first frontier ticket unless the user names one. Suggest "Apple developer setup and installing on the XRs" early, because the XR benchmark is blocked on it.

Done when no open tickets remain and "Not yet specified" is empty, every patch either graduated into tickets that were resolved, or ruled out of scope.

## After the map: build

1. Run the to-spec skill to write the v1 build spec from the map's Decisions so far. This spec is the map's destination. It orders delivery as Phase 1 (one Station, no Host) and then Phase 2, with Phase 2 starting only after Phase 1 passes the gate defined in "Validation protocol and pass criteria".
2. Run the to-tickets skill to split the spec into tracer-bullet tickets with blocking edges.
3. Add an `## Agent skills` note to `CLAUDE.md`: implement tickets with the tdd or implement skill, and use the codebase-design skill when drawing module boundaries, starting with the rep-logic package. Then delete `docs/kickoff.md`; the spec, tickets, and `CLAUDE.md` carry the build from here.
