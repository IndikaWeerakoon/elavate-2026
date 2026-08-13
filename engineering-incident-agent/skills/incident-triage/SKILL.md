---
name: incident-triage
description: Investigates data-sync incidents in the synthetic-sync-platform pipeline (source marked SYNCED but destination record missing, or similar silent failures) by cross-referencing DynamoDB state, CloudWatch logs, and the pipeline's own source code. Use when asked to investigate a record, correlation ID, or "why is X not showing up" in the synthetic-sync-platform system.
---

# Incident triage: synthetic-sync-platform

You investigate cross-service data-sync failures. Never guess or speculate —
every claim in your report must cite a specific piece of evidence (a log
line, a DynamoDB item, or a file:line in the source).

All scripts below are read-only. The instance's AWS identity has no write
permissions on this pipeline — do not attempt writes.

## Evidence-gathering procedure

Given a record ID, correlation ID, or a vague "record X missing" report:

1. **Resolve the service.** If you know the Lambda function name or log
   group involved, run `{baseDir}/scripts/resolve-service.sh <name>` to get
   its log group, source/destination tables, and repo path. If you don't
   know which service is involved yet, start from the source table (see
   `config/services.json` for the default: `incident-agent-poc-source`).

2. **Check source state.**
   `{baseDir}/scripts/read-item.sh <sourceTable> '{"id":{"S":"<record-id>"}}'`
   Note the `status` field and the `correlationId`.

3. **Check destination state.**
   `{baseDir}/scripts/scan-table.sh <destinationTable>`
   If the record's expected key isn't present, that's the core symptom:
   source thinks it's done, destination disagrees.

4. **Pull the logs.** Use the correlation ID as the filter substring:
   `{baseDir}/scripts/query-logs.sh <logGroup> <correlationId>`
   Look for anything logged as an ERROR-level event (e.g.
   `DESTINATION_WRITE_FAILED`) followed by a success-looking event (e.g.
   `SOURCE_MARKED_SYNCED`) for the same correlation ID — that combination is
   the signature of a swallowed exception: the write failed, was caught, and
   the pipeline proceeded as if it hadn't.

5. **Find the root cause in code.** Take the event name or error reason
   string from step 4 and search the repo:
   `{baseDir}/scripts/search-repo.sh "<exact string from the log>" ~/repos/synthetic-sync-platform`
   Read enough surrounding code to explain *why* the write failed (e.g. a
   contract/field-name mismatch) and confirm the catch block doesn't
   rethrow — that's what let the pipeline mark the record synced anyway.

6. **Report.** State, in order: what the source/destination state shows,
   the exact log lines (with timestamps) that show the failure and the
   false-success marker, the file:line where the exception is swallowed,
   and the one-sentence root cause. If any step didn't turn up evidence,
   say so explicitly rather than filling the gap with a guess.

## Scope

This skill only has visibility into `incident-agent-poc-*` resources
(scoped by IAM) and the repos cloned under `~/repos/`. If asked about
something outside that scope, say you don't have visibility into it rather
than fabricating an answer.
