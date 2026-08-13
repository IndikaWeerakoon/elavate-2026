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

## IAM design

Three separate roles, least privilege each:

| Role | Used by | Access |
|---|---|---|
| `incident-agent-poc-github-deploy` | GitHub Actions (OIDC) | create/destroy POC resources only |
| `incident-agent-poc-dispatcher` / `-sync-worker` | Lambda exec roles | scoped to their own table/queue |
| `incident-agent-poc-investigation-readonly` | OpenClaw agent (local) | read-only: logs, DynamoDB read, Lambda/SQS describe, CloudWatch metrics |

The investigation role has zero write permissions on the pipeline it inspects.
