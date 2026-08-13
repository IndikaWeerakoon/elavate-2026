# synthetic-sync-platform

Clean-room synthetic AWS pipeline. Reproduces a silent-failure distributed-system
bug — no client code, data, or account involved. All resources prefixed
`incident-agent-poc-*`, region `us-east-1`, account `927676118813`.

## Architecture

```
DynamoDB (source) --stream--> dispatcher Lambda --SQS--> sync-worker Lambda --> DynamoDB (destination)
                                                                |
                                                                +--> marks source SYNCED (even on write failure)
```

The sync-worker's `writeDestination` maps the wrong contract field
(`legacyRecordId` instead of `cloudRecordId`), the write throws, the error is
caught and logged, but never rethrown — so the source status flips to
`SYNCED` regardless. See `src/sync-worker/index.js`.

## One-time bootstrap (run locally, not in CI)

Creates the Terraform state bucket/lock table and the GitHub OIDC deploy role.
Requires an AWS identity with IAM/S3/DynamoDB admin rights (your SSO profile).

```
cd infrastructure/bootstrap
terraform init
terraform apply
terraform output github_deploy_role_arn
```

Then set the output as a GitHub Actions repository variable:

```
gh variable set AWS_DEPLOY_ROLE_ARN --body "<role arn from output above>"
```

## CI-managed lifecycle

- **Create/update**: push to `main` touching `synthetic-sync-platform/infrastructure/main/**`
  or `src/**`, or run the `synthetic-infra-apply` workflow manually.
- **Destroy**: run the `synthetic-infra-destroy` workflow manually, typing
  `destroy` to confirm.

Both assume the bootstrap-created OIDC role — no long-lived AWS keys in GitHub.

## Seed the incident and verify

```
cd scripts
npm install
SOURCE_TABLE=incident-agent-poc-source npm run seed
# wait a few seconds for the stream -> dispatcher -> SQS -> sync-worker chain
npm run verify
```

`verify-incident.js` confirms: source record is `SYNCED`, destination table
is empty — the silent-failure signature an investigation agent must detect
from CloudWatch logs plus DynamoDB state plus the repository code.

## 100-record test matrix (varied failure modes)

Beyond the single `record-100` incident, `scripts/test-matrix-scenarios.js`
defines 7 categories of real, code-reachable failure modes in
`src/dispatcher` and `src/sync-worker` (not fabricated — each is traced to
a specific line):

| Category | Count | Root cause |
|---|---|---|
| `classic_mapping_bug` | 38 | `cloudRecordId` never mapped from `legacyRecordId` (the main bug) |
| `payload_missing` | 10 | `record.payload` absent entirely — TypeError before the guard, same silent-SYNCED outcome |
| `marshalling_bug` | 10 | `tenantId` missing — doc client **silently drops** the undefined field and the write *succeeds* with incomplete data, zero error log (found live while building this matrix; worse than a loud failure) |
| `missing_correlation_id` | 7 | `correlationId` absent — breaks correlation-ID log search, must fall back to recordId |
| `never_dispatched` | 14 | `status` missing/wrong-case/pre-set — dispatcher's strict equality check silently skips it, zero trace at all |
| `healthy_control` | 15 | Fully valid payload — write actually succeeds, tests that the agent doesn't cry wolf |
| `duplicate_processing` | 6 | Same record PUT twice while still PENDING — race for duplicate stream events |

Run it:

```
cd scripts
npm run seed-matrix    # or: node seed-test-matrix.js
# wait ~45s for the pipeline to process all 100
npm run verify-matrix  # or: node verify-test-matrix.js
```

`seed-test-matrix.js` writes `scripts/test-matrix-expectations.json` — a
ground-truth manifest (category, seeded item, expected end state) checked
into the repo. `verify-test-matrix.js` re-derives the deterministic
infra-level outcome (source status, destination presence, field-level
correctness) per record and per category; last run was 100/100. This
validates the *pipeline's* behavior — validating whether the
`incident-triage` OpenClaw skill correctly diagnoses each category is a
separate, manual step (`openclaw agent --message "..."` per record).

## Live sync simulation (spread over time, not all at once)

`scripts/seed-sync-batch.js` + `scripts/run-live-sync-batches.sh` reproduce
the same 6 single-item failure/success shapes as the test matrix (skips
`duplicate_processing`, which needs paired writes), but spread over real
time instead of firing all 100 at once — useful for demoing a live
dashboard or a scheduled `openclaw` scan picking up incidents as they occur.

```
cd scripts
npm run live-sync   # or: ./run-live-sync-batches.sh
```

Seeds 10 records every 5 minutes for 1h10m (14 ticks × 10 = 140 records).
Each tick cycles through: 2× `classic_mapping_bug`, 2× `payload_missing`,
2× `marshalling_bug`, 1× `missing_correlation_id`, 1× `never_dispatched`,
2× `healthy_control`. Appends to `scripts/live-sync-batches.jsonl`
(tick, timestamp, id, category, correlationId) as it goes — safe to `tail -f`
during a demo, and safe to re-run (PutItem is idempotent per id).

## IAM design

Three separate roles, least privilege each:

| Role | Used by | Access |
|---|---|---|
| `incident-agent-poc-github-deploy` | GitHub Actions (OIDC) | create/destroy POC resources only |
| `incident-agent-poc-dispatcher` / `-sync-worker` | Lambda exec roles | scoped to their own table/queue |
| `incident-agent-poc-investigation-readonly` | OpenClaw agent (local) | read-only: logs, DynamoDB read, Lambda/SQS describe, CloudWatch metrics |

The investigation role has zero write permissions on the pipeline it inspects.
