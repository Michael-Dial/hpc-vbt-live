# Rep logic is streaming only, with one code path for live and Replay

The rep logic sees one bar sample at a time and emits each Rep when it ends. Replay pushes the same samples through the same code in the same order; there is no separate batch algorithm that looks at a whole Set at once.

We chose this because the live value is the stored value: what the Participant saw on the Station is what the study analyses. With one code path, a Replay of a Recording's Bar Track under the same Algorithm Version must reproduce the live values to within floating-point tolerance, which gives a cheap and strict regression check.

## Considered options

- **Batch algorithm for Replay.** Smoothing and Rep boundaries could use the whole Set, which would likely agree better with the Criterion. Rejected: replayed values would differ from live values by design, so every disagreement would need explaining and the stored value would no longer be the best available one.
- **Both, with batch as a "research" output.** Rejected for v1: two sets of values per Rep to version, validate, and keep apart.

## Consequences

- Filters must be causal, so any smoothing adds latency or is limited to what a short look-back allows.
- A Rep cannot be revised after it is emitted. Improvements arrive as a new Algorithm Version, and Replay flags where it disagrees with stored values; it never overwrites them.
