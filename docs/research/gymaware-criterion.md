# GymAware as the Criterion: definitions, export, and alignment

Research for issue #4. Researched 2026-11-12. The lab's GymAware model and software version were not known when this was written, so the tethered units (PowerTool / LE / RS) and the laser-optic FLEX are covered separately wherever they differ.

Evidence labels used throughout:

- **VERIFIED**: read in a primary source (manufacturer help centre, fact sheet, API guide, or the paper itself). URL and a short quote are given.
- **INFERRED**: a conclusion drawn from verified facts; not stated by the source.
- **UNKNOWN**: not publicly documented in anything read. Listed again under "Open questions for the lab".

Source codes in square brackets (for example [H3], [P5]) refer to the Sources list at the end.

## Question

How does GymAware, the Criterion, define and compute its outputs, and how can its data be exported and aligned in time with Station Recordings? What is the Criterion's own published error against 3D motion capture?

## Short answer

1. **Rep detection thresholds are not published** (both models). GymAware documents the rules around detection (exercise-specific logic, a per-exercise minimum movement threshold, a "75% rule", a no-movement timeout that ends the Set) but no velocity or displacement threshold for concentric onset or end. The detector has also changed across app versions. Treat it as a black box that must be characterised on the lab's unit, and pin the app version.
2. **Mean velocity** is the mean of point-to-point velocities over the detected concentric phase; **peak velocity** is the highest value over an approximately 20 ms window. Same wording for tethered units and FLEX.
3. **GymAware does not document a mean propulsive velocity (MPV) output.** If MPV is a product metric, it cannot be compared with a GymAware-reported number; it could only be derived from a per-sample trace, and no per-sample export is documented.
4. **Sampling (model-dependent)**: tethered units use event-driven "variable rate sampling", down-sampled to at most 50 points per second, each point time-stamped at microsecond resolution; the manufacturer says no filtering is applied. FLEX sampling is not published by the manufacturer; one independent paper lists 50 Hz.
5. **Horizontal movement (model-dependent)**: tethered units measure tether angle and convert to vertical displacement (y = r sin θ); the angle sensor can be switched off in the app, and its range differs between PowerTool (−13° to +50°) and RS (−50° to +70°). FLEX reports vertical distance and a horizontal "bar path"; how it does so is not documented.
6. **ROM**: the closest GymAware metric is "Vertical Distance" (bottom to top of each lift, corrected for horizontal movement). "Lift Distance" is uncorrected tether travel. "Height" and "Dip" are relative to the zero point.
7. **Power** is force times velocity with force = m(a + g), averaged over the concentric phase. The system mass used for squats may include body mass; the rule is not documented.
8. **Export**: every documented per-rep export for the current software runs through GymAware Cloud (Cloud CSV "Rep Statistics Table", or the `/api/reps` endpoint). A local CSV export from the iPad is documented only for the older app. This is in tension with the local-only data handling decision; it is reported here, not resolved.
9. **Timestamps**: the documented exports carry one time per Set (`recorded`, UTC epoch seconds). No documented export carries a per-rep absolute timestamp, and the clock source is not stated (inferred: the iPad or phone clock).
10. **Recommended alignment**: match Sets by coarse wall-clock time plus the Session log, then match Reps by index within the Set, and confirm each match with the sequence of concentric durations. A shared event (bar tap) only helps if a per-sample trace export is confirmed, and it can disturb GymAware's rep detection.
11. **Criterion error (tethered)**: against 3D motion capture, mean velocity bias is typically within about ±0.05 m/s with SEE or RMSE of roughly 0.02 to 0.06 m/s in squat, bench press and deadlift; peak velocity is worse (bias up to −0.12 to +0.13 m/s). No motion-capture validation of the RS model, the front squat, or the trap-bar deadlift was found.
12. **Criterion error (FLEX)**: one motion-capture study reports typical error of the estimate 0.03 m/s (back squat) and 0.04 m/s (bench press) for mean velocity; a second reports poorer agreement, especially at high velocity (pooled SEE 0.12 m/s mean, 0.18 m/s peak).

## The devices, apps and services

**VERIFIED** unless marked.

| Item | What it is | Source |
|---|---|---|
| PowerTool "Classic" (v3 to v5) | Tethered linear position transducer; serial numbers 1 to 2694; made before November 2017 | [H10] "Manufactured prior to November 2017. Serial numbers 1-2694." |
| GymAware LE (v6+) | Same transducer with Bluetooth Low Energy; serial numbers 2695 and above | [H10] "Version 6 and above. Manufactured after November 2017." |
| GymAware RS | 2022 tethered model; serial numbers 6000 and above | [H10] "Manufactured after January 2022. Serial numbers 6000 and above" |
| FLEX | Bar-end unit using lasers and a reflective floor mat; released 2020 | [H13] "it is the only laser optic barbell tracker"; [H15] "The reflective surface of the mat allows the lasers to get the most accurate readings" |
| GymAware app (iPad) | Receives data over Bluetooth, computes and displays results; works with tethered units and FLEX | [H11] "The GymAware system is made up of several components. The RS, An Apple iPad, The GymAware Cloud (optional)"; [H13] "FLEX users can connect their FLEX device to the GymAware app for FREE" |
| FLEX Stronger app (iOS and Android) | Phone app for FLEX; can also connect an RS | [H14] "FLEX can be used with the FLEX Stronger app or the GymAware app"; [H19] "connect FLEX, GymAware RS, and ANCORE Data Plate" |
| GymAware Cloud | Web service that stores Sets, shows per-rep traces, allows rep editing, and exports CSV | [H4], [H7] |
| GymAware Cloud API | HTTP API returning Set summaries and per-rep statistics as JSON | [H11] |
| FLEX Bridge | Paid add-on that syncs FLEX data into a GymAware Cloud account | [H18] "use FLEX to collect data and have it automatically sync to your GymAware Cloud" |

Two facts that affect the project regardless of model:

- **The current GymAware app requires an account.** [H16] "Account creation is now required to use the new GymAware App." An expired account collects no data: [H16] "you will be downgraded to a Basic Account which has limited features and no data collected."
- **GymAware flags research use as a special case.** [H16] "If you are currently conducting research and using GymAware Classic, please contact sam@gymaware.com so we can support your setup".

## Findings

### 1. Rep detection: start, end, concentric onset and end thresholds

**Common to both models**

- **UNKNOWN**: the numeric criteria for concentric onset and end (velocity threshold, displacement threshold, or otherwise). No help article, fact sheet, or spec page read gives one.
- **VERIFIED**: each counted rep must be similar in size to the earlier ones. Tethered: [H6] "each subsequent rep needs to be at least 75% the size of the average of the previous reps." FLEX: [H12] "each rep needs to be within 75% of the last rep". Note the two articles word the reference differently (average of previous reps versus last rep).
- **VERIFIED**: a per-exercise minimum movement threshold decides whether a movement counts. Tethered: [H6] "Each exercise can have its own minimum movement threshold typically around 10+ inches." FLEX: [H12] "on bench press if you don't move the bar 18cm it won't trigger the minimum movement threshold".
- **VERIFIED**: the threshold gates counting, not the start of the measured phase. [H6] "does not mean that the recording of the movement does not start until after 10 inches."

**Tethered units (PowerTool / LE / RS)**

- **VERIFIED**: detection depends on the selected exercise. [H6] "if you have it set for a squat, but then perform a deadlift then it will miss the first rep every time." The squat logic expects an unrack, then a descent, then the measured ascent: [H6] "its expecting the bar to be un-racked first then lowered into the squat before the concentric phase is measured".
- **VERIFIED**: the concentric phase is not simply lowest point to highest point. [H5] "the concentric lift phase starts not at the lowest point, but where the displacement rapidly changes" (said of the squat jump); and for the clean, [H4] "the end of the rep should be where the bar position peaks prior to the catch".
- **VERIFIED**: tether angle is used by the detector. [H5] "measures the angle of lift to correct for these, in both the rep detection algorithm and in calculating final results".
- **VERIFIED**: recording is automatic and a Set ends after a period of no movement. [H7] "after 7 secs of no movement on the bar then the set itself will be deemed to be finished"; the value is adjustable ([H7] "The default value is 7 secs.").
- **VERIFIED**: stray movement before a Set can be counted as a rep and then suppress the real ones through the 75% rule. [H7] "Only the first movement of placing it up into the rack was registered as a rep."
- **VERIFIED**: rep boundaries can be edited after the fact in the Cloud, which changes the reported values. [H4] "The data will then recalculate and a corrected mean Velocity will be recorded."
- **VERIFIED**: the detector has changed between app versions. The change log lists "Updates to rep detector" at v4.1.0, v4.1.2, v4.1.4 and v4.1.6 [H20].

**FLEX**

- **VERIFIED**: only the two rules above are documented, and GymAware refers users to email for more. [H12] "This minimum movement threshold is specific to each exercise. For more information on this please contact info@flexstronger.com".
- **UNKNOWN**: whether FLEX data processed in the GymAware app uses the same detector as FLEX data processed in the FLEX Stronger app.

**What independent papers assumed.** The papers below did not use GymAware's definition for the motion-capture side; they chose their own, which is a reminder that the definition is a free parameter in every validation: Fritschi et al. used [P7] "an inclusive vertical velocity onset-threshold of 0 m/s for jumps and squats"; Chen et al. used [P9] "the lowest point of vertical displacement" to "the highest point occurring after the start".

### 2. Metric definitions

All from the manufacturer's "Parameters explained" article [H3] unless marked. That article sits in the tethered-unit section of the help centre; the FLEX wording is from [H17].

| Metric | GymAware definition | Quote |
|---|---|---|
| Mean concentric velocity ("Conc Mean Velocity") | Sum of the per-point velocities in the concentric phase divided by the number of points; each velocity is (d2 − d1)/(t2 − t1) | "summing the individual velocities for each data point and dividing by the number of data points obtained in the concentric phase" |
| Peak velocity ("Conc Peak Velocity") | Highest value in the concentric phase, over about 20 ms | "an instantaneous value, measured over a sample period of approximately 20 milliseconds" |
| Mean propulsive velocity | **Not listed.** No "propulsive" metric appears in [H3], in the Cloud export metric picker [H2], or in the FLEX metric list [H17] | (absence) |
| Displacement / ROM ("Vertical Distance") | Bottom to top of each lift, vertical component only | "from the very bottom of each lift to the very top of each lift corrected for errors due to horizontal displacement" |
| "Lift Distance" | Bottom to top, uncorrected; equals tether travel | "It is not corrected for errors due to horizontal displacement." |
| "Height" | Distance moved above the zero point set at the start | "the distance the weights were moved above the zero point" |
| "Dip" | Distance moved below the start point (squat depth) | "the distance the weights were moved below the start point of the eccentric phase" |
| Force | f = m(a + g) per point | "f = m*(a+g)" |
| Mean power ("Conc Mean Power") | Mean of per-point power, p = f × v, over the concentric phase | "summing the individual powers for each data point and dividing by the number of data points" |
| Peak power | Highest per-point power, over about 20 ms | "an instantaneous value, measured over a sample period of approximately 20 milliseconds" |
| Concentric duration ("Conc Rep Duration") | Time from concentric start to concentric finish | "t1 = time at start of concentric phase t2 = time at finish of concentric phase" |

FLEX wording [H17]: "Mean Velocity shows the mean speed of the bar across the concentric phase of every rep"; "Distance measures the vertical displacement of the bar from the lowest point of your lift to the highest."

Points that matter for the project's own metric definitions:

- **INFERRED**: because the tethered units record points at irregular intervals (see section 3), an unweighted mean of per-point velocities is not necessarily the same as displacement divided by duration. Whether GymAware weights by time is **UNKNOWN**. This could produce a small systematic difference from a Station metric computed as ROM / duration.
- **INFERRED**: reported velocity is the vertical component. The angle fact sheet says only that [F2] "power and work are always reported using vertical height values"; it does not say the same of velocity explicitly. At least one validation paper compared against resultant velocity instead: [P7] "Mean (vmean) and peak (vpeak) resultant (scalar) velocity".
- **UNKNOWN**: the mass used in the force and power equations for squats. GymAware advertises [H21] "Compensation of body mass in squats and jumps", and the change log has "Fixed body mass calculation for some exercises" [H20], but the rule (which exercises, what fraction of body mass) is not documented. Power agreement cannot be interpreted until this is known.
- **MPV**: since no MPV output is documented, MPV cannot be validated against a GymAware-reported value. Options are to drop MPV from the Criterion comparison, or to derive it from a per-sample trace if one can be exported (section 5).

### 3. Sampling rate and filtering

**Tethered units**

- **VERIFIED**: event-driven sampling, not fixed-rate. [H8] "GymAware uses a Variable Rate Sampling with Level Crossing Detection to capture data points. It then limits (downsamples) this to a maximum of 50 points per second."
- **VERIFIED**: mechanism. [F1] "Every 20 milliseconds the sensor waits for a transition on the position counter. When a transition is detected it is time-stamped and recorded." Consequence: [F1] "Data is only recorded during movement".
- **VERIFIED**: no filter is applied, per the manufacturer. [F1] "One of the key benefits of this approach is that it requires no filtering."
- **VERIFIED**: time base. [H8] "a digital optical encoder based displacement transducer with an 8Mhz quartz crystal time-base."
- **VERIFIED, model-dependent** specifications:

| Spec | PowerTool (v5) [H9] | RS [H1] |
|---|---|---|
| Position resolution | 0.3 mm | 0.8 mm |
| Base rate | 115200 Hz | not listed |
| Timer resolution | "8.6s" as printed (the help centre summary says 8.6 microseconds [H8]) | not listed |
| Down-sample rate | 50 Hz | 50 Hz |
| Angle resolution | 0.1° | 0.1° |
| Angle range | −13° to +50° | −50° to +70° |
| Max velocity | 7 m/s | 6.5 m/s |
| Bar path | not listed | "YES - 2D" |
| Link | Bluetooth Class 1 (Apple iAP) | Bluetooth LE 5.0 |

- **Discrepancy noted**: the fact sheet PDF gives the time-stamp resolution as [F1] "(35 microsecond)" and positional resolution as "600 microns", while the help centre text says 8.6 microseconds and the spec pages say 0.3 mm or 0.8 mm. These look like figures from different hardware generations. Independent papers repeat the older figures, for example [P4] "displacement >600 microns in distance are recorded at a resolution of 35 microseconds."
- **INFERRED**: with a 0.8 mm (RS) quantum and a minimum 20 ms interval, instantaneous velocity has a coarse quantisation at very low speeds, and no smoothing is applied; peak velocity is therefore expected to be noisier than mean velocity. The validity literature (section 7) is consistent with this.
- **VERIFIED**: the manufacturer's own reliability figure for the PowerTool is a technical error of measurement of 0.01 m/s for velocity on a calibration rig, from an unpublished 2009 thesis [H9] "Black, M (2009) Reliability and validity of GymAware."

**FLEX**

- **UNKNOWN from the manufacturer**: sampling rate, resolution, and any filtering. The FLEX specification article lists only size, weight, charging and app compatibility [H22].
- **VERIFIED (independent paper, not manufacturer)**: Fritschi et al. list the Flex at 50 Hz in their device table [P7]. Treat as secondary to a manufacturer statement.
- **VERIFIED**: principle. [H13] "It works on the same position/time principal as GymAware does." [H14] "gives a direct measure of distance."
- **VERIFIED**: range limit. [H15] "ultra precise lasers that have a range of 2.2 metres"; beyond it the device "will lose data points".

### 4. Horizontal bar movement and tether angle

**Tethered units**

- **VERIFIED**: each data point holds time, tether extension, and tether angle. [F2] "GymAware data points comprise of Time, Displacement and Angle."
- **VERIFIED**: vertical displacement is a polar-to-rectangular conversion. [F2] "a simple polar to rectangular coordinate conversion is done to give the y component of each data point. That is: y = r sin q".
- **VERIFIED**: it is meant for small horizontal components, not full 2D tracking. [F2] "It is not intended to give a complete 2 dimensional measurement from 0 to 90 degrees."
- **VERIFIED**: poor placement triggers an alert. [F2] "the set will trigger a suspect result alert due to poor protocol (angle changing by more than a threshold)". The threshold value is **UNKNOWN**.
- **VERIFIED**: the size of the correction in the manufacturer's own example is small. [F2] "the overall vertical displacement was corrected from 0.56m to 0.54m" (a power clean).
- **VERIFIED**: angle measurement can be turned off in the app. [H23] "You can choose to turn angle measurement off." The validation protocol should record the setting.
- **VERIFIED**: which metrics are corrected. "Vertical Distance", "Height" and "Dip" are corrected; "Lift Distance" is not [H3].
- **INFERRED**: with the unit on the floor under one end of the bar, bar tilt (one end rising faster) and bar rotation are not separable from vertical motion. Appleby et al. found that tracking location matters in heavy squats: [P10] "overestimation of displacement occurs as the tracking location moves to the barbell ends". The Station's tracked point and the tether attachment point should be recorded so the comparison is like for like.

**FLEX**

- **VERIFIED**: it reports a horizontal measure. [H17] "Bar Path displays the horizontal displacement of the bar away from your start position."
- **VERIFIED**: the mat must lie flat under the lift path. [H15] "the device only needs to be over an even surface at the time of the lift".
- **UNKNOWN**: how vertical distance is separated from horizontal movement and from bar tilt or rotation (FLEX sits on the bar end and tilts with the bar).

### 5. Export options, granularity, timestamps and clock source

**5a. GymAware Cloud CSV (tethered units; FLEX via FLEX Bridge or the GymAware app)**

- **VERIFIED**: available on paid tiers. [H2] "(Available on Cloud Premium & Standard)". Route: View > Sessions, select Sets, Export.
- **VERIFIED (read from the screenshot in the article)**: the export dialog is titled "Export Data CSV" with a Type selector showing "Rep Statistics Table", a style selector ("Columnar"), and tick boxes for "Individual Rep Statistics", "Set Averages", "Set Maximums", "Set Standard Deviation", "Set Totals", "Notes" and "Hardware Version". The metric picker includes Conc Mean Velocity, Conc Peak Velocity, Conc Mean Power, Conc Peak Power, Conc Rep Duration, Rep Duration, Dip, Height, Lift Distance, Vertical Distance, Horizontal, Time Pk Vel, and others [H2].
- **Granularity**: per-rep statistics and per-Set aggregates. **UNKNOWN**: what other values the Type selector offers, and in particular whether a per-sample (time, position, angle) export exists. The Cloud does hold the per-sample trace, because it draws it: [H4] "The blue line is the position of the bar".
- **Timestamps**: **UNKNOWN** which time columns the CSV carries. The article does not list columns.
- **VERIFIED**: getting data into the Cloud needs the iPad to be logged in and online. [H24] "This is only effective if you are logged in and have a WiFi connection."

**5b. GymAware Cloud API (tethered units; FLEX via FLEX Bridge)**

- **VERIFIED**: paid, and written for the RS. [H11] "The GymAware API is only available on subscription."; "API Access" is listed as an add-on [H16].
- **VERIFIED**: endpoints `https://cloud.gymaware.com/api/summaries` (per Set) and `https://cloud.gymaware.com/api/reps` (per Set with a list of reps). Responses are [H11] "a newline separated stream of json objects."
- **VERIFIED**: per-rep content. [H11] "REPNUM: integer: order of the reps within the set." plus one float per analysis type ("for each analysis type in the analysis endpoint there will be an additional value here").
- **VERIFIED**: timestamps. One per Set: [H11] "recorded: float: utc seconds since the epoch". No per-rep time field is documented. Whether `recorded` marks the start or the end of the Set is **UNKNOWN**.
- **VERIFIED**: no per-sample endpoint is documented in the guide.
- **VERIFIED**: query limits. [H11] "start/end need to be within 60 days of each other."

**5c. iPad app local export (tethered units, older app)**

- **VERIFIED**: the older iPad app can export locally. [H25] "Export all data as a csv and videos."
- **VERIFIED (screenshot in the article)**: the app's review list shows each Set with a date and a time to the second (for example "28/6/17 14:30:31") [H25].
- **UNKNOWN**: the columns of that CSV, whether it is per-rep, and whether the current app (v5.x, "GymAware v2") still has a local export.

**5d. FLEX Stronger app**

- **VERIFIED**: a CSV export exists. [H26] "Export data as a csv".
- **UNKNOWN**: columns, granularity, and timestamps. The only documentation is a video link.
- **VERIFIED**: sessions carry a date and time. [H27] "All sessions are time-stamped".

**Clock source (both models)**

- **UNKNOWN (not stated anywhere read)**.
- **INFERRED**: the Set time is stamped by the iPad or phone clock. The sensor's time base is described only as a crystal used to time-stamp points relative to one another [H8]; no real-time clock is listed in the PowerTool or RS specifications [H9][H1]; and the API reports Set times in UTC epoch seconds, which the app can produce from the tablet's clock. This should be confirmed on the lab's unit by changing the iPad clock and recording a Set.

**Tension with the data handling decision.** For the current app, every documented per-rep export path (5a, 5b) requires the Criterion data to be uploaded to GymAware Cloud, and the app itself requires an account [H16]. The only documented local path (5c) is for the older app. The project has decided that Criterion data stays on local machines. These two facts conflict unless the lab's app version still has a local export or GymAware offers a research arrangement. GymAware's own privacy note suggests one mitigation that the project may or may not accept: [H28] "consider employing pseudonyms or nicknames instead of disclosing personally identifiable information". A second practical conflict: the Stations, Host and iPad sit on a router with no internet route, while Cloud sync needs one.

**Recommended export path** (subject to the open questions):

- **Tethered unit**: per-rep CSV ("Rep Statistics Table" with "Individual Rep Statistics" and "Hardware Version" ticked), with at least Conc Mean Velocity, Conc Peak Velocity, Vertical Distance, Lift Distance, Dip, Conc Rep Duration, Rep Duration, Time Pk Vel, Conc Mean Power, Conc Peak Power. Take it from the iPad locally if the lab's app version allows; otherwise from the Cloud, which needs a decision on the tension above. The API returns the same per-rep values and is the better route only if exports must be automated.
- **FLEX**: connect FLEX to the GymAware app and use the same Cloud export if the lab has a Cloud licence, because that path is the documented one; otherwise the FLEX Stronger CSV, after inspecting its columns.
- In both cases, never edit rep boundaries in the Cloud for validation data without logging it, because edits change the reported values [H4].

### 6. Time alignment with a Station Recording

What the options need, checked against what the exports verifiably carry:

| Option | Needs from the Criterion export | Verifiably available? | Assessment |
|---|---|---|---|
| Rep index within a Set | Rep order per Set | Yes: `REPNUM` in the API [H11]; "Individual Rep Statistics" in the CSV [H2] | Works with every documented export. Fails silently if either system misses or adds a rep, so it needs a check |
| Wall-clock sync at rep level | Absolute time per rep, on a known clock | No: only a per-Set `recorded` time is documented; clock source unstated | Not supportable from the documented exports |
| Wall-clock sync at Set level | Absolute time per Set | Yes: `recorded` (UTC epoch seconds, float) [H11]; app list shows time to the second [H25] | Good enough to pair a Set with a stretch of a Recording, given a measured clock offset |
| Shared event (bar tap) | A per-sample trace with times | Not documented as exportable (visible in the Cloud graph only) | Cannot be used numerically unless a trace export is confirmed |

Further considerations:

- **Clock offset.** The iPad is on a network with no internet route, so its clock cannot be assumed to agree with the Host or the Stations. **INFERRED**: the offset has to be measured each Session. A simple way that needs nothing from GymAware is to show a clock with seconds on the iPad to a Station camera at the start of the Session; the Station's per-frame timestamps then give the offset to about a second, which is ample for Set-level pairing.
- **Risk in a deliberate bar movement.** GymAware records any movement once armed, and a stray movement can be counted as a rep and then suppress the real reps through the 75% rule [H7]. A tap small enough to stay under the minimum movement threshold (about 10 inches on tethered units [H6]) should not be counted, but this needs a trial on the lab's unit before it goes into the protocol.
- **Rep-count mismatches.** GymAware drops reps that fail the 75% rule or the minimum movement threshold [H6], and may add one when the bar is re-racked [H7] "additional rep gets counted at the end; because the bar was being repositioned". Index matching must expect both.

**Recommendation**

1. Pair Sets using the Session log (Participant, lift, load, Set order) and confirm with Set-level wall-clock time (`recorded` against the Recording's timeline, after applying the measured clock offset).
2. Pair Reps by index within the paired Set.
3. Verify every pairing with a signature that does not depend on any clock: the sequence of concentric durations (GymAware "Conc Rep Duration" against the Station's own concentric durations) and, as a second check, the sequence of ROM values ("Vertical Distance"). A missed or extra rep shows up as a shifted sequence; resolve it by the best-fitting shift and flag the Set.
4. Exclude, and count in the report, any Set where the rep counts differ and the signature does not resolve the shift.

Dependencies of this recommendation:

- The export includes Conc Rep Duration and Vertical Distance per rep (both are in the Cloud metric picker [H2]).
- A person logs each Set in order during the Session.
- The iPad-to-Station clock offset is measured once per Session.
- If the lab's unit turns out to export a per-sample trace, a cross-correlation of the GymAware position trace with the Station's bar trajectory would be strictly better (it gives sub-second alignment per Set and allows MPV and onset comparisons), and the bar tap becomes worth adding.

### 7. Published validity against 3D motion capture

Citations in this section come from PubMed records and, where a PMC number is given, the open full text. "Abstract only" means the full text was not accessible and only the abstract's numbers are reported.

**Check of the leads supplied with the ticket**

| Lead as given | What was found |
|---|---|
| Dorrell et al. 2019 (JSCR) | Exists, but the journal is *Journal of Sports Sciences* 2019;37(1):67-73 (online 2018). [P1] |
| Weakley et al. 2021 systematic review (Sports Med) | Confirmed. [P11] |
| Orange et al. 2020 | Confirmed, but it is a test-retest reliability study with no motion-capture comparison. [P13] A separate Orange et al. 2019 paper uses GymAware as the comparator for PUSH. |
| Thompson et al. 2020 | Confirmed. [P3] |
| Mitter et al. 2021 | Confirmed. [P2] |
| Jovanovic & Jukic 2023 (FLEX) | Not found as described. Jovanovic & Jukic 2020 (JSCR) compares two GymAware units and PUSH2 in the trap-bar deadlift; it does not involve FLEX. [P12] A 2023 Jukic et al. paper in *Scientific Reports* on GymAware, PUSH2 and Vmaxpro surfaced in a web search but was not read and is not relied on here. |
| Weakley et al. 2020 (FLEX validity) | Confirmed. [P6] |
| Banyard et al. 2017 | Confirmed, but the comparison system was four linear position transducers plus a force plate, not motion capture. [P5] |
| Askow et al. 2018 | Confirmed. [P4] |
| Wadhi et al. 2018 | Confirmed, but it concerns jump height against a force plate, not barbell velocity. [P14] |

**Validity table**

MV = mean concentric velocity; PV = peak concentric velocity. Bias sign conventions differ between papers and are given as printed.

| Study | Device | Comparison system | Lifts and loads | Metric | Error statistics | Access |
|---|---|---|---|---|---|---|
| Mitter et al. 2021 [P2] | GymAware (tethered) | 3D motion capture (Vicon per [P11]) | Squat, bench press, conventional deadlift; progressive loads to 1RM; 24 powerlifters | MV, PV | r = 0.99 to 1; standardised mean bias −0.05 to 0.1. SEE 0.017 to 0.030 m/s as tabulated in the Weakley review [P11] | Abstract only; SEE via [P11] |
| Thompson et al. 2020 [P3] | GymAware (tethered) | 12-camera Motion Analysis Raptor, 250 Hz, 6 Hz low-pass for squat | Back squat and power clean, 40 to 100% 1RM; 10 weightlifters | MV, PV | Back squat, all loads pooled: MV R² 0.99, slope 0.991 (0.979 to 1.004), intercept −0.005 (−0.014 to 0.003); PV R² 0.99, slope 0.970, intercept 0.054. Abstract gives LoA −0.03 to 0.03 m/s. Power clean MV R² falls to 0.42 at 90% 1RM | Full text (PMC7404723) |
| Askow et al. 2018 [P4] | GymAware (tethered) | 8-camera Qualisys 120 Hz and AMTI force plates 1200 Hz; 12 Hz low-pass | Back squat to failure at 75% and 90% 1RM; 9 men; 357 reps | MV, PV, force, power | MV: bias 0.03 m/s (0.01 to 0.05), ICC 0.966, SEE 0.04. PV: bias −0.12 m/s (−0.16 to −0.09), ICC 0.982, SEE 0.05; larger for fast reps (−0.16, d = −1.46). Mean power bias 75.6 W | Full text (PMC6316018) |
| Lorenzetti et al. 2017 [P8] | GymAware (tethered) | 16-camera Vicon, 100 Hz | Squat at 70% 1RM; ballistic squat at 25 kg; 9 participants | MV, PV, time to PV | 70% squat: MV r 0.958, mean difference 0.046 m/s, RMSE 0.064; PV r 0.957, mean difference 0.128, RMSE 0.163. Ballistic: MV r 0.783, RMSE 0.160; PV RMSE 0.304. No limits of agreement reported | Full text (PMC5719516) |
| Dorrell et al. 2019 [P1] | GymAware PowerTool | Motion Analysis Corp 3D, 150 Hz; Kistler force plate 1500 Hz | Back squat, bench press, deadlift at 80% 1RM; 13 participants | Displacement, MV, PV, force | R² > 0.85 for all variables except deadlift MV (R² 0.54 to 0.69). Authors advise care with the deadlift | Abstract only |
| Chen et al. 2024 [P9] | GymAware PowerTool, app 2.8 | 12-camera Vicon, 200 Hz, 6 Hz low-pass | Bulgarian split squat, 40 to 90% 1RM; 18 men | MV, PV | MV mean difference −0.02 to −0.01 m/s, MAE 0.02 to 0.03. PV mean difference 0.01 to 0.05, MAE 0.05 to 0.07. No limits of agreement reported | Full text (PMC11812161) |
| Fritschi et al. 2021 [P7] | GymAware PowerTool (firmware 16.0.1.a024, app 2.8.8) | 8-camera Vicon Vantage, 100 Hz, virtual marker at each device's attachment point | Back squat (moderate and heavy), jumps, hang power snatch; 14 participants; 724 reps | MV, PV | MV pooled r 0.99, SEE 0.06 m/s (0.01 to 0.08 by exercise); PV pooled r 0.99, SEE 0.08. Excluding the snatch, MV slope 0.98 (0.97 to 0.99), intercept 0.00. Proportional bias reported for MV and PV | Full text (PMC8472848) |
| Fritschi et al. 2021 [P7] | **FLEX** (firmware 2710, app 1.9.32) | Same | Same | MV, PV | MV pooled r 0.96, SEE 0.12 m/s (0.02 to 0.19 by exercise); PV pooled r 0.96, SEE 0.18. Excluding the snatch, MV slope 0.98, intercept 0.01. Fixed and proportional bias reported | Full text (PMC8472848) |
| Weakley et al. 2020 [P6] | **FLEX** | 3D motion capture (Vicon per [P11]) | Back squat and bench press, 20 to 100% 1RM; 18 men and women | MV only | Typical error of the estimate 0.03 (±0.004) m/s back squat; 0.04 (±0.005) m/s bench press. Inter-unit CV 3.96% on a rig | Abstract only |
| Appleby et al. 2020 [P10] | Linear position transducer (identified as GymAware in the Wannouch review [P15]) | 3D motion analysis; C7 marker as the reference | Back squat, 70 to 90% 1RM; 12 rugby players | Displacement | Typical error as CV 2.1 to 3.0%; bias 0.9 to 1.5%; r 0.96 to 0.98 | Abstract only |
| Banyard et al. 2017 [P5] | GymAware (tethered) | Four linear position transducers and a force plate (not motion capture) | Back squat, 20 to 100% 1RM; 10 men; 120 reps | MV, PV, force, power | "highly valid" for all variables except peak power at 20% and 40% 1RM; r 0.94 to 0.99 per [P11] | Abstract only |

**Related evidence that is not a motion-capture validation**

- Unit-to-unit agreement, trap-bar deadlift: two GymAware units agreed with residual standard error 0.019 to 0.021 m/s (Jovanovic & Jukic 2020 [P12], abstract only). This is the only trap-bar deadlift evidence found, and it is reproducibility, not validity.
- Test-retest reliability: Orange et al. 2020 [P13], back squat and bench press, MV ICC 0.77 to 0.87 at 40 to 90% 1RM (includes biological variation; abstract only).
- GymAware RS: no comparison with motion capture was found. The RS appears as the comparator in recent device studies, for example Kim 2026 [P16].

**Synthesis for setting pass criteria**

- **Tethered GymAware, mean velocity, squat / bench press / conventional deadlift**: mean bias against motion capture is small (about −0.02 to +0.05 m/s across studies) and random error is of the order of 0.02 to 0.06 m/s (SEE or RMSE). Only Thompson et al. report limits of agreement, and the per-load values are in figures that were not readable; the abstract range is −0.03 to 0.03 m/s.
- **Tethered GymAware, peak velocity**: clearly worse and less consistent: bias −0.12 m/s (Askow), +0.13 m/s (Lorenzetti), intercept +0.05 with slope 0.97 (Thompson). Expect the Criterion to contribute more error to any peak velocity comparison.
- **Deadlift**: the one study reporting deadlift separately found weak agreement for mean velocity (Dorrell, R² 0.54 to 0.69), while Mitter et al. report high agreement across squat, bench press and deadlift. The evidence is mixed.
- **FLEX**: two studies, with conflicting impressions. Both agree the error is small for mean velocity in slow barbell lifts and grows with velocity.
- **Gaps**: no motion-capture evidence was found for the RS model, the front squat, or the trap-bar deadlift; few studies report limits of agreement; none reports CCC.
- **INFERRED implication**: an a priori SESOI for mean velocity tighter than roughly the Criterion's own random error (a few hundredths of a m/s) cannot be defended from the literature, and a failed equivalence test near that level would not distinguish Station error from Criterion error. The systematic reviews make the general point: comparison against a device that is not motion capture [P15] "simply investigates the level of agreement or association between those devices, and not true validity."

## Open questions for the lab

Check on the physical unit:

1. Which model is it (serial number: below 2695 Classic, 2695 to 5999 LE, 6000 and above RS; or FLEX), and which firmware?
2. Which app and version is installed (older GymAware app, current v5.x "GymAware v2", or FLEX Stronger), and does it still offer a local CSV export without Cloud sync?
3. Which Cloud tier does the lab hold (Basic, Essentials, Standard, Premium), and is API access or FLEX Bridge included?
4. In the Cloud export dialog, what values does the Type selector offer besides "Rep Statistics Table"? Is there a per-sample export?
5. What time columns does the per-rep CSV contain, and at what resolution?
6. Does the Set time follow the iPad clock? (Change the iPad clock, record a Set, read the export.)
7. Is the angle sensor on, and what are the minimum movement threshold and no-movement timeout for each of the four lifts?
8. Does a small deliberate bar movement before a Set get counted as a rep or disturb the following reps?
9. Does the app run a Set with no internet route at all, and for how long before it demands a sync or login?
10. For squats, is body mass included in the power calculation, and how?

Ask GymAware (support@gymaware.com; research contact given as sam@gymaware.com):

1. The concentric onset and end criteria for squat, bench press and deadlift, and whether they differ between the tethered units and FLEX.
2. Whether mean velocity is time-weighted, and whether velocity is the vertical component.
3. Whether a per-sample (time, position, angle) export is available to researchers, and in what format.
4. Whether a research arrangement exists that keeps data off the Cloud.
5. FLEX sampling rate, and how FLEX separates vertical from horizontal movement and bar tilt.
6. Which clock stamps `recorded`, and whether it marks the start or end of the Set.
7. Whether an MPV output exists anywhere in the software.

## Could not verify

- Per-load limits of agreement in Thompson et al. (in figure images).
- Full texts of Mitter 2021, Dorrell 2019, Weakley 2020, Banyard 2017, Appleby 2020, Jovanovic & Jukic 2020, Orange 2020 (abstracts only).
- The FLEX CSV export contents (documented only by a video link).
- The 2023 Jukic et al. *Scientific Reports* paper (seen in a search listing only).
- The gymaware.com FLEX validation page (linked from the product page; not read).
- The second half of the Weakley 2021 and Wannouch 2025 review full texts (pages were truncated when read).

## Sources

Manufacturer help centre (gymaware.zendesk.com), read in a browser on 2026-11-12:

- [H1] GymAware RS Specifications. https://gymaware.zendesk.com/hc/en-us/articles/4414960013199-GymAware-RS-Specifications
- [H2] Exporting data from the GymAware Cloud (text and dialog screenshot). https://gymaware.zendesk.com/hc/en-us/articles/115001477352-Exporting-data-from-the-GymAware-Cloud
- [H3] Parameters explained - measurement metrics. https://gymaware.zendesk.com/hc/en-us/articles/333757013756-Parameters-explained-measurement-metrics
- [H4] The Clean and variations - rep detection. https://gymaware.zendesk.com/hc/en-us/articles/360000172515-The-Clean-and-variations-rep-detection
- [H5] Rep Detection (GymAware). https://gymaware.zendesk.com/hc/en-us/articles/360000067676-Rep-Detection
- [H6] Why am I missing sets and reps? https://gymaware.zendesk.com/hc/en-us/articles/360000473715-Why-am-I-missing-sets-and-reps
- [H7] Funky reps? - Rep mark up explained. https://gymaware.zendesk.com/hc/en-us/articles/360000524955-Funky-reps-Rep-mark-up-explained
- [H8] GymAware Fact sheets (index page with summaries). https://gymaware.zendesk.com/hc/en-us/articles/115001133391-GymAware-Fact-sheets
- [H9] PowerTool specifications. https://gymaware.zendesk.com/hc/en-us/articles/115005013548-PowerTool-specifications
- [H10] Identifying your GymAware Model. https://gymaware.zendesk.com/hc/en-us/articles/360001432276-Identifying-your-GymAware-Model
- [H11] API Integration (GymAware Cloud API integration guide). https://gymaware.zendesk.com/hc/en-us/articles/360001396875-API-Integration (also at https://gymaware.com/gymaware-cloud-api-integration-guide/)
- [H12] Rep Detection (FLEX). https://gymaware.zendesk.com/hc/en-us/articles/6947901584655-Rep-Detection
- [H13] FLEX Integration. https://gymaware.zendesk.com/hc/en-us/articles/4407853491983-FLEX-Integration
- [H14] FLEX is not an accelerometer. https://gymaware.zendesk.com/hc/en-us/articles/6947942755983-FLEX-is-not-an-accelerometer
- [H15] FLEX Considerations. https://gymaware.zendesk.com/hc/en-us/articles/6947901598735-FLEX-Considerations
- [H16] Some Features Have Changed - How Does This Affect Me? https://gymaware.zendesk.com/hc/en-us/articles/13392497019791-Some-Features-Have-Changed-How-Does-This-Affect-Me
- [H17] FLEX Metrics Displayed. https://gymaware.zendesk.com/hc/en-us/articles/6947872421007-FLEX-Metrics-Displayed
- [H18] FLEX Bridge. https://gymaware.zendesk.com/hc/en-us/articles/6947902764559-FLEX-Bridge
- [H19] Multi-connect. https://gymaware.zendesk.com/hc/en-us/articles/13564355263247-Multi-connect-Connect-multiple-GymAware-RS-FLEX-and-Ancore
- [H20] Change Log History. https://gymaware.zendesk.com/hc/en-us/articles/9898695339023-Change-Log-History
- [H21] How does GymAware compare to Tendo. https://gymaware.zendesk.com/hc/en-us/articles/360000067695-How-does-GymAware-compare-to-Tendo
- [H22] FLEX specifications. https://gymaware.zendesk.com/hc/en-us/articles/6947906102671-FLEX-specifications
- [H23] How do I turn the angle sensor On/Off? https://gymaware.zendesk.com/hc/en-us/articles/115001460252-How-do-I-turn-the-angle-sensor-On-Off
- [H24] Manual Sync. https://gymaware.zendesk.com/hc/en-us/articles/115001384092-Manual-Sync
- [H25] Exporting data from the iPad (text and screenshot). https://gymaware.zendesk.com/hc/en-us/articles/115001477012-Exporting-data-from-the-iPad
- [H26] Export (FLEX). https://gymaware.zendesk.com/hc/en-us/articles/6947870265103-Export
- [H27] History (FLEX). https://gymaware.zendesk.com/hc/en-us/articles/6947982801551-History
- [H28] Safeguarding Customer Privacy. https://gymaware.zendesk.com/hc/en-us/articles/8596656856591-Safeguarding-Customer-Privacy-Best-Practices-for-Protecting-Personally-Identifiable-Information-PII-Data

Manufacturer fact sheets (Kinetic Performance Technology):

- [F1] GymAware Sampling Method. https://kinetic.com.au/pdf/sample.pdf
- [F2] GymAware Angle Measurement. https://kinetic.com.au/pdf/angle.pdf

Manufacturer product pages (marketing; used only for app and platform facts):

- GymAware RS. https://gymaware.com/gymaware-rs/
- FLEX. https://gymaware.com/product/flex-barbell-tracker/

Peer-reviewed papers (records retrieved from PubMed):

- [P1] Dorrell HF, Moore JM, Smith MF, Gee TI. Validity and reliability of a linear positional transducer across commonly practised resistance training exercises. *J Sports Sci* 2019;37(1):67-73. [doi:10.1080/02640414.2018.1482588](https://doi.org/10.1080/02640414.2018.1482588)
- [P2] Mitter B, Hölbling D, Bauer P, Stöckl M, Baca A, Tschan H. Concurrent validity of field-based diagnostic technology monitoring movement velocity in powerlifting exercises. *J Strength Cond Res* 2021;35(8):2170-2178. [doi:10.1519/JSC.0000000000003143](https://doi.org/10.1519/JSC.0000000000003143)
- [P3] Thompson SW, Rogerson D, Dorrell HF, Ruddock A, Barnes A. The reliability and validity of current technologies for measuring barbell velocity in the free-weight back squat and power clean. *Sports (Basel)* 2020;8(7):94. [doi:10.3390/sports8070094](https://doi.org/10.3390/sports8070094). https://pmc.ncbi.nlm.nih.gov/articles/PMC7404723/
- [P4] Askow AT, Stone JD, Arndts DJ, et al. Validity and reliability of a commercially-available velocity and power testing device. *Sports (Basel)* 2018;6(4):170. [doi:10.3390/sports6040170](https://doi.org/10.3390/sports6040170). https://pmc.ncbi.nlm.nih.gov/articles/PMC6316018/
- [P5] Banyard HG, Nosaka K, Sato K, Haff GG. Validity of various methods for determining velocity, force, and power in the back squat. *Int J Sports Physiol Perform* 2017;12(9):1170-1176. [doi:10.1123/ijspp.2016-0627](https://doi.org/10.1123/ijspp.2016-0627)
- [P6] Weakley J, Chalkley D, Johnston R, et al. Criterion validity, and interunit and between-day reliability of the FLEX for measuring barbell velocity during commonly used resistance training exercises. *J Strength Cond Res* 2020;34(6):1519-1524. [doi:10.1519/JSC.0000000000003592](https://doi.org/10.1519/JSC.0000000000003592)
- [P7] Fritschi R, Seiler J, Gross M. Validity and effects of placement of velocity-based training devices. *Sports (Basel)* 2021;9(9):123. [doi:10.3390/sports9090123](https://doi.org/10.3390/sports9090123). https://pmc.ncbi.nlm.nih.gov/articles/PMC8472848/
- [P8] Lorenzetti S, Lamparter T, Lüthy F. Validity and reliability of simple measurement device to assess the velocity of the barbell during squats. *BMC Res Notes* 2017;10(1):707. [doi:10.1186/s13104-017-3012-z](https://doi.org/10.1186/s13104-017-3012-z). https://pmc.ncbi.nlm.nih.gov/articles/PMC5719516/
- [P9] Chen Z, Liao K, Bishop C, Bian C, Li Y. Validity of three commercial devices for recording movement velocity in the Bulgarian split squat. *J Hum Kinet* 2024;95:161-171. [doi:10.5114/jhk/189365](https://doi.org/10.5114/jhk/189365). https://pmc.ncbi.nlm.nih.gov/articles/PMC11812161/
- [P10] Appleby BB, Banyard H, Cormack SJ, Newton RU. Validity and reliability of methods to determine barbell displacement in heavy back squats. *J Strength Cond Res* 2020;34(11):3118-3123. [doi:10.1519/JSC.0000000000002803](https://doi.org/10.1519/JSC.0000000000002803)
- [P11] Weakley J, Morrison M, García-Ramos A, et al. The validity and reliability of commercially available resistance training monitoring devices: a systematic review. *Sports Med* 2021;51(3):443-502. [doi:10.1007/s40279-020-01382-w](https://doi.org/10.1007/s40279-020-01382-w). https://pmc.ncbi.nlm.nih.gov/articles/PMC7900050/
- [P12] Jovanovic M, Jukic I. Within-unit reliability and between-units agreement of the commercially available linear position transducer and barbell-mounted inertial sensor to measure movement velocity. *J Strength Cond Res* 2020 (online ahead of print). [doi:10.1519/JSC.0000000000003776](https://doi.org/10.1519/JSC.0000000000003776)
- [P13] Orange ST, Metcalfe JW, Marshall P, et al. Test-retest reliability of a commercial linear position transducer (GymAware PowerTool) to measure velocity and power in the back squat and bench press. *J Strength Cond Res* 2020;34(3):728-737. [doi:10.1519/JSC.0000000000002715](https://doi.org/10.1519/JSC.0000000000002715)
- [P14] Wadhi T, Rauch JT, Tamulevicius N, Andersen JC, De Souza EO. Validity and reliability of the GymAware linear position transducer for squat jump and counter-movement jump height. *Sports (Basel)* 2018;6(4):177. [doi:10.3390/sports6040177](https://doi.org/10.3390/sports6040177)
- [P15] Wannouch YJ, Leahey SR, Ramírez-Campillo R, et al. A systematic review using a multi-layered criteria framework for assessing the validity and reliability of velocity monitoring devices in resistance training. *PLoS One* 2025;20(9):e0324606. [doi:10.1371/journal.pone.0324606](https://doi.org/10.1371/journal.pone.0324606). https://pmc.ncbi.nlm.nih.gov/articles/PMC12416690/
- [P16] Kim A. Comparing repetition-velocity output from a motor-integrated magnetic sensing system with that of a linear position transducer across resistance exercises and loads. *Sensors (Basel)* 2026;26(20):6466. [doi:10.3390/s26206466](https://doi.org/10.3390/s26206466) (abstract only; cited only to show the RS used as a comparator)
