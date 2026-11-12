# Data model and storage

Type: grilling
Status: open
Blocked by: 01, 05

## Question

What schema and storage layout does v1 use?

Decide:

- The schema for Participant, Session, Set, Rep, Recording, Station, and Criterion data.
- How future jump, IMU, and mocap Recordings fit without a migration.
- Algorithm version on every derived value.
- Raw data kept: video, timestamp sidecar, tag tracks.
- File layout on the Host's disk.
- Retention and deletion rules for exploratory Sessions versus Sessions under the IRB.
- Participant identifiers: pseudonymous IDs, and where the mapping to identities lives.

Output: schema and storage layout ready for the spec.
