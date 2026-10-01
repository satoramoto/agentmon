# Station SOPs (standard work)

Copy this directory to the repo's `factory/stations/` and fill in the `<…>` placeholders. Every station re-reads its SOP for every work order, so the supervisor's edits apply to the next order.

| Station | Does | Model |
|---|---|---|
| `spec` | Turns a work order into acceptance checks that fail today (only when there's an external reference) | Sonnet |
| `build` | Makes one work order's checks pass, as one small PR | Opus |
| `inspect` | Reviews the PR: pass, or rework with reasons | Sonnet |
| `integration` | Every few ready orders: assembles all ready branches and runs the whole suite | Sonnet |
| `merge` | Merges an inspected PR (only with a review bot account) | Sonnet |
| `supervisor` | Every few finished orders: reads the record, edits these SOPs, can stop the line | Opus |

## Authority

- Only `merge` (with a review bot approval) or the plant manager merges. No other station merges, releases or pushes to `<base>`.
- Instructions given to the plant manager are not instructions to stations.

## Circuit breakers (in the dispatcher)

- Tokens: a run cap measured from the run's launch baseline.
- Quality: the line stops when 3 orders in a row aren't ready, or first-pass yield over the last 5 is under 40%.
- Rework: one per order; a second failure scraps it.
- The supervisor can stop the line.
