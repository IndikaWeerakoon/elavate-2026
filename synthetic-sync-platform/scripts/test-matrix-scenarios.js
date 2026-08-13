// Each category is a real, reachable code path in src/dispatcher and
// src/sync-worker (not a fabricated error) - see the comment on each for
// exactly which lines it exercises. Every generated item becomes a ground
// truth row in expectations.json so seed-test-matrix.js's output can later
// be scored against what the incident-triage skill actually reports.

const TENANT = "tenant-demo-001";

function items(count, make) {
  return Array.from({ length: count }, (_, i) => make(i + 1));
}

const CATEGORIES = {
  // A - the deployed bug: writeDestination() maps payload.cloudRecordId,
  // but the source only ever sends payload.legacyRecordId. Guard throws
  // "cloudRecordId is required", caught, never rethrown -> SYNCED anyway.
  classic_mapping_bug: {
    count: 38,
    expected: {
      dispatched: true,
      destinationWriteFails: true,
      failureReasonContains: "cloudRecordId is required",
      finalSourceStatus: "SYNCED",
      destinationHasRecord: false,
    },
    generate: () =>
      items(38, (n) => ({
        id: `record-a-${n}`,
        tenantId: TENANT,
        correlationId: `corr-a-${n}`,
        status: "PENDING",
        payload: { legacyRecordId: `legacy-a-${n}`, description: `Classic mapping bug case ${n}` },
      })),
  },

  // B - record.payload absent entirely. `record.payload.cloudRecordId`
  // throws a TypeError *before* the intentional guard is even reached -
  // still caught by the same try/catch, still ends in SYNCED. Different
  // failure reason string, same silent-failure symptom as A.
  payload_missing: {
    count: 10,
    expected: {
      dispatched: true,
      destinationWriteFails: true,
      failureReasonContains: "Cannot read properties of undefined",
      finalSourceStatus: "SYNCED",
      destinationHasRecord: false,
    },
    generate: () =>
      items(10, (n) => ({
        id: `record-b-${n}`,
        tenantId: TENANT,
        correlationId: `corr-b-${n}`,
        status: "PENDING",
        // no `payload` key at all
      })),
  },

  // C - cloudRecordId IS present (the guard passes) but tenantId is
  // missing. Measured live: the doc client's default marshaller silently
  // *drops* the undefined attribute rather than throwing - the write
  // SUCCEEDS, producing a destination record with tenantId missing and
  // zero error log. Worse than the other bugs: there's no failure signal
  // at all, just quietly incomplete data.
  marshalling_bug: {
    count: 10,
    expected: {
      dispatched: true,
      destinationWriteFails: false,
      failureReasonContains: null,
      finalSourceStatus: "SYNCED",
      destinationHasRecord: true,
      destinationRecordMissingField: "tenantId",
    },
    generate: () =>
      items(10, (n) => ({
        id: `record-c-${n}`,
        // no `tenantId` key at all
        correlationId: `corr-c-${n}`,
        status: "PENDING",
        payload: { cloudRecordId: `cloud-c-${n}`, description: `Marshalling bug case ${n}` },
      })),
  },

  // D - correlationId missing. Dispatcher's RECORD_DISPATCHED log drops the
  // key (JSON.stringify skips undefined), so a correlation-ID log filter
  // finds nothing - the skill must fall back to searching by recordId.
  missing_correlation_id: {
    count: 7,
    expected: {
      dispatched: true,
      destinationWriteFails: true,
      failureReasonContains: "cloudRecordId is required",
      finalSourceStatus: "SYNCED",
      destinationHasRecord: false,
      correlationIdAbsentFromLogs: true,
    },
    generate: () =>
      items(7, (n) => ({
        id: `record-d-${n}`,
        tenantId: TENANT,
        // no `correlationId` key at all
        status: "PENDING",
        payload: { legacyRecordId: `legacy-d-${n}`, description: `Missing correlationId case ${n}` },
      })),
  },

  // E - dispatcher's `item.status !== "PENDING"` is a strict, case-sensitive
  // equality check. Anything else - missing, wrong case, pre-set to
  // SYNCED - gets silently skipped: zero RECORD_DISPATCHED log, zero
  // sync-worker invocation, zero trace at all. The "black hole" case.
  never_dispatched: {
    count: 14,
    expected: {
      dispatched: false,
      destinationWriteFails: null, // sync-worker never runs
      failureReasonContains: null,
      finalSourceStatus: null, // stays whatever it was seeded as
      destinationHasRecord: false,
      noLogsAtAll: true,
    },
    generate: () => {
      const variants = [undefined, "pending", "Pending", "PENDING ", "SYNCED"];
      return items(14, (n) => {
        const status = variants[(n - 1) % variants.length];
        const item = {
          id: `record-e-${n}`,
          tenantId: TENANT,
          correlationId: `corr-e-${n}`,
          payload: { legacyRecordId: `legacy-e-${n}`, description: `Never-dispatched case ${n} (status=${JSON.stringify(status)})` },
        };
        if (status !== undefined) item.status = status;
        return item;
      });
    },
  },

  // F - control group. payload.cloudRecordId, tenantId, and description
  // are ALL present and well-formed - the write actually succeeds. Tests
  // that the skill doesn't cry wolf on a healthy record.
  healthy_control: {
    count: 15,
    expected: {
      dispatched: true,
      destinationWriteFails: false,
      failureReasonContains: null,
      finalSourceStatus: "SYNCED",
      destinationHasRecord: true,
    },
    generate: () =>
      items(15, (n) => ({
        id: `record-f-${n}`,
        tenantId: TENANT,
        correlationId: `corr-f-${n}`,
        status: "PENDING",
        payload: { cloudRecordId: `record-f-${n}`, description: `Healthy control case ${n}` },
      })),
  },

  // G - duplicate/race scenario. The same id is PutItem'd twice in quick
  // succession while still PENDING, which can produce two independent
  // stream events (INSERT then MODIFY) before the worker's first run
  // flips status to SYNCED - two SQS messages, two worker invocations,
  // two DESTINATION_WRITE_FAILED + two SOURCE_MARKED_SYNCED log lines for
  // the same correlationId. Timing-dependent - occasionally collapses to
  // a single run, which is fine; the manifest only asserts the eventual
  // end state, not the exact log-line count.
  duplicate_processing: {
    count: 6,
    isDuplicatePair: true,
    expected: {
      dispatched: true,
      destinationWriteFails: true,
      failureReasonContains: "cloudRecordId is required",
      finalSourceStatus: "SYNCED",
      destinationHasRecord: false,
      possibleDuplicateLogLines: true,
    },
    generate: () =>
      items(6, (n) => ({
        id: `record-g-${n}`,
        tenantId: TENANT,
        correlationId: `corr-g-${n}`,
        status: "PENDING",
        payload: { legacyRecordId: `legacy-g-${n}`, description: `Duplicate-processing case ${n}` },
      })),
  },
};

module.exports = { CATEGORIES };
