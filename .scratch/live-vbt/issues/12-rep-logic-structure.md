# Rep-logic structure and regression testing

Type: grilling
Status: open
Blocked by: 02

## Question

How is the rep logic structured and tested?

Decide:

- The boundary of the rep-logic Swift package: input is timestamped tag poses; output is Reps and their metrics.
- How the macOS replay CLI feeds Recordings through the same package.
- Where regression on the Reference Dataset runs: a local Mac, or a GitLab CI macOS runner on repo.service.osu.edu (research whether one is available).
- What a regression report shows, such as the change in bias and limits of agreement against GymAware, and the thresholds that fail a change.

Constraint: the live value is the stored value. Reprocessing flags disagreements; it never overwrites.
