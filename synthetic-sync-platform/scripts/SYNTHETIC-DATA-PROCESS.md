# Synthetic data generation — process & continuation prompt

This document exists so that generating more synthetic incidents for
`synthetic-sync-platform` can continue correctly even if the terminal
session that built it is lost. It is written as a prompt: read it top to
bottom before writing or seeding any new synthetic data, and follow it as
instructions.

## What this data is for

`synthetic-sync-platform` is a clean-room synthetic AWS pipeline (source
table → DynamoDB Stream → dispatcher Lambda → SQS → sync-worker Lambda →
destination table) that intentionally contains a real, reachable
silent-failure bug. The synthetic data seeded into it exists to **demonstrate
the `incident-triage` OpenClaw skill's analysis ability** — every record
seeded should be traceable to a specific, real code path in
`src/dispatcher/index.js` or `src/sync-worker/index.js`, not an arbitrary or
fabricated error. If you can't point to the exact line that causes a
scenario, don't seed it as if it were a distinct failure mode.

## Before doing anything: check what already exists

Do not assume a fresh state. Before seeding more data:

1. Read `git log --oneline -- synthetic-sync-platform/scripts` in the repo
   to see what's already been built and committed.
2. Read `scripts/test-matrix-expectations.json` — the ground-truth manifest
   for the 100-record instant batch (categories, ids, expected outcomes).
3. Read `scripts/live-sync-batches.jsonl` — the append-only log of the
   time-spread batches (one JSON object per line: tick, timestamp, id,
   category, correlationId).
4. Cross-check actual AWS state before trusting either file is fully
   representative of reality — a killed process, an expired AWS SSO
   session, or a manual `aws dynamodb` call could have changed things
   since the file was last written. Ground truth is always:
   ```
   aws dynamodb scan --table-name incident-agent-poc-source
   aws dynamodb scan --table-name incident-agent-poc-destination
   ```

## The two generation mechanisms that already exist

Don't build a third one without a clear reason — extend these first.

### 1. Instant batch — `seed-test-matrix.js` + `test-matrix-scenarios.js`

Seeds a fixed set of records across named categories all at once, then
`verify-test-matrix.js` checks the real end state against a written
expectation. As of the last run: **100 records across 7 categories**, all
verified 100/100.

### 2. Time-spread batch — `seed-sync-batch.js` + `run-live-sync-batches.sh`

Seeds 10 records per "tick" (cycling through 6 of the 7 category shapes,
skipping `duplicate_processing`), on a real 5-minute cadence, for a
configurable number of ticks. As of the last run: **14 ticks × 10 = 140
records**, ticks numbered 1–14.

If asked to generate more live data, **continue the tick numbering from 15
onward** — do not restart at 1, or ids will collide (`record-live-t1-1`
already exists and means something specific).

## The 7 failure categories — do not invent an 8th casually

Each is defined in `scripts/test-matrix-scenarios.js` with a comment citing
the exact code path. Reproduce this table from that file if it drifts;
don't hand-copy stale numbers into new work:

| Category | What's missing/wrong in the seeded item | Real code path | Actual outcome |
|---|---|---|---|
| `classic_mapping_bug` | `payload.legacyRecordId` present, no `cloudRecordId` | `writeDestination()`'s guard throws `"cloudRecordId is required"` | caught, not rethrown → source `SYNCED`, destination empty |
| `payload_missing` | no `payload` key at all | `record.payload.cloudRecordId` throws TypeError *before* the guard | same silent outcome, different reason string |
| `marshalling_bug` | `cloudRecordId` present, no `tenantId` | doc client **silently drops** the undefined field | write **succeeds** with an incomplete record, **zero error log** — found live, this was originally assumed to throw and didn't; verify actual behavior before trusting an assumption about AWS SDK defaults |
| `missing_correlation_id` | no `correlationId` key | dispatcher's `RECORD_DISPATCHED` log drops the key (JSON.stringify skips undefined) | same as classic_mapping_bug, but correlation-ID log search finds nothing |
| `never_dispatched` | `status` missing, wrong case, or pre-set to `SYNCED` | dispatcher's `item.status !== "PENDING"` is strict equality | silently skipped — zero downstream trace of any kind |
| `healthy_control` | fully valid: `cloudRecordId`, `tenantId`, `description` all present | nothing — the write actually succeeds | destination record correctly created (false-positive check for the skill) |
| `duplicate_processing` | same id PUT twice while still `PENDING` | two stream events before the worker's first run flips status | timing-dependent; may produce 1 or 2 processing runs, both fine |

If you add a genuinely new category, you must: (1) trace it to a specific
line in the actual deployed Lambda code, (2) seed it and check the *actual*
AWS result before writing down what you expect it to do — don't assume,
verify (see the `marshalling_bug` lesson above), (3) add it to this table
and to `test-matrix-scenarios.js` together, so the doc and the code never
drift apart.

## Naming conventions already in use — don't collide with these

| Source | ID pattern | Correlation ID pattern |
|---|---|---|
| Original single incident | `record-100` | `corr-demo-7821` |
| Instant batch, category A–G | `record-a-1`…`record-a-38`, `record-b-1`…`record-b-10`, `record-c-*`, `record-d-*`, `record-e-*`, `record-f-*`, `record-g-1`…`record-g-6` | `corr-a-1`, `corr-b-1`, etc. (category D omits it entirely, by design) |
| Time-spread batch | `record-live-t{tick}-{1..10}` for tick 1–14 so far | `corr-record-live-t{tick}-{n}` (except the `missing_correlation_id` slot each tick, which omits it — `never_dispatched` still gets one, it only omits `status`) |

New data should use a naming scheme that's obviously distinct from all of
the above at a glance — e.g. a new date-stamped or purpose-stamped prefix —
so a human scanning the source table can tell which generation run any
given record came from.

## Known operational hazards (hit these already — expect them again)

- **AWS SSO session expiry mid-run.** A long-running seed script (e.g. the
  70-minute time-spread batch) can outlive the SSO token. `set -e` in
  `run-live-sync-batches.sh` means the whole run dies on the first failed
  write. Before starting a long run, confirm the session is fresh with
  `aws sts get-caller-identity`; after a failure, check `.jsonl`/manifest
  output to see exactly how far it got before resuming (resuming from the
  right tick, not restarting from zero, unless you've confirmed restarting
  is harmless — PutItem is idempotent per id, so it usually is, but check).
- **Background processes can be killed by session/environment recycling**
  (observed: a run was killed overnight, unrelated to any script bug).
  Always check `wc -l` on the output log against the expected count before
  declaring a run complete.
- **Don't trust a verification script's printed claims — check its
  asserts.** The `marshalling_bug` discovery happened because an early
  version of `verify-test-matrix.js` *printed* "expected 15 destination
  records" without actually failing when reality was 25. If you write a
  new verifier, make every stated expectation an actual assertion.

## How to verify after seeding

```bash
cd synthetic-sync-platform/scripts
npm run verify-matrix     # for the instant batch
```

For time-spread or new ad-hoc data, check directly:

```bash
aws dynamodb get-item --table-name incident-agent-poc-source --key '{"id":{"S":"<id>"}}'
aws dynamodb scan --table-name incident-agent-poc-destination
aws logs filter-log-events --log-group-name /aws/lambda/incident-agent-poc-sync-worker --filter-pattern "<correlationId>"
```

## If you are a fresh session picking this up cold

1. Read this file fully before writing or running anything.
2. Read the "before doing anything" section above and actually run those
   checks — don't assume the repo state matches this document's examples
   forever; they'll go stale as more data is added.
3. Reuse `test-matrix-scenarios.js`'s `GENERATORS`/`CATEGORIES` shapes
   rather than re-deriving the bug mechanics from scratch — they're already
   traced to real code and already validated.
4. Whatever you seed, update `test-matrix-expectations.json` or
   `live-sync-batches.jsonl` (or both, or a clearly-named new manifest) so
   the *next* session has the same record you're relying on right now.
5. Commit and push whatever you add, with a commit message that states
   what was seeded and why — the commit history is itself part of this
   process's memory.
