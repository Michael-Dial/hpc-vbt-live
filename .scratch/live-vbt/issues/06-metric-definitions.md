# Metric definitions per lift

Type: grilling
Status: open
Blocked by: 03

## Question

For back squat, front squat, bench press, and deadlift (straight bar and trap bar), what exactly does v1 compute for each Rep?

Decide:

- Concentric start and end, and the eccentric phase where it exists.
- MCV, MPV (and its propulsive-phase definition), peak velocity, and ROM.
- Velocity loss within a Set, and whether the reference Rep is the first or the fastest.
- Power: which mass counts (bar load only, or including body mass), and whether v1 reports it at all.
- Dead-stop versus touch-and-go deadlifts, pauses, partial Reps, and ghost Reps (unracking and reracking).
- Where definitions should match GymAware's so validation is interpretable, and where they deliberately differ.

Output: definitions precise enough to implement and to test against the Reference Dataset.
