// Seeds 20 records per tick, ALL failure-shaped (no healthy_control this
// time) - for a dense, all-error stress run. Uses the same code-traced
// failure shapes as test-matrix-scenarios.js / seed-sync-batch.js. See
// SYNTHETIC-DATA-PROCESS.md before extending this.
const fs = require("fs");
const path = require("path");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand } = require("@aws-sdk/lib-dynamodb");

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const SOURCE_TABLE = process.env.SOURCE_TABLE || "incident-agent-poc-source";
const TENANT = "tenant-demo-001";

const GENERATORS = {
  classic_mapping_bug: (id) => ({
    id,
    tenantId: TENANT,
    correlationId: `corr-${id}`,
    status: "PENDING",
    payload: { legacyRecordId: `legacy-${id}`, description: `Failure batch: classic mapping bug (${id})` },
  }),
  payload_missing: (id) => ({
    id,
    tenantId: TENANT,
    correlationId: `corr-${id}`,
    status: "PENDING",
  }),
  marshalling_bug: (id) => ({
    id,
    correlationId: `corr-${id}`,
    status: "PENDING",
    payload: { cloudRecordId: `cloud-${id}`, description: `Failure batch: marshalling bug, missing tenantId (${id})` },
  }),
  missing_correlation_id: (id) => ({
    id,
    tenantId: TENANT,
    status: "PENDING",
    payload: { legacyRecordId: `legacy-${id}`, description: `Failure batch: missing correlationId (${id})` },
  }),
  never_dispatched: (id) => ({
    id,
    tenantId: TENANT,
    correlationId: `corr-${id}`,
    // no `status` key - dispatcher's strict equality check skips it forever
    payload: { legacyRecordId: `legacy-${id}`, description: `Failure batch: never dispatched, no status (${id})` },
  }),
};

// 20 slots per tick: 4 of each of the 5 failure categories
const CATEGORY_NAMES = Object.keys(GENERATORS);
const CYCLE = [];
for (let round = 0; round < 4; round++) CYCLE.push(...CATEGORY_NAMES);

async function main() {
  const tick = process.argv[2];
  if (!tick) {
    console.error("Usage: node seed-failure-batch.js <tick-number>");
    process.exit(1);
  }

  const logPath = path.join(__dirname, "failure-batches.jsonl");
  const timestamp = new Date().toISOString();

  const writes = CYCLE.map((category, i) => {
    const id = `record-fail-t${tick}-${i + 1}`;
    const item = GENERATORS[category](id);
    return { id, category, item };
  });

  await Promise.all(
    writes.map(({ item }) => ddb.send(new PutCommand({ TableName: SOURCE_TABLE, Item: item })))
  );

  const lines = writes
    .map(({ id, category, item }) =>
      JSON.stringify({ tick: Number(tick), timestamp, id, category, correlationId: item.correlationId ?? null })
    )
    .join("\n") + "\n";
  fs.appendFileSync(logPath, lines);

  console.log(`[tick ${tick}] seeded ${writes.length} failure records`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
