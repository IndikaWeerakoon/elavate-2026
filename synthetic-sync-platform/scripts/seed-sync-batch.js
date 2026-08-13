// Seeds one batch of 10 records mixing success + varied error scenarios,
// for the "live sync" demo: run repeatedly over time (see
// run-live-sync-batches.sh) rather than all at once like test-matrix.
// Reuses the same code-reachable failure shapes as test-matrix-scenarios.js
// but generates one item per category call instead of a fixed count.
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
    payload: { legacyRecordId: `legacy-${id}`, description: `Live batch: classic mapping bug (${id})` },
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
    payload: { cloudRecordId: `cloud-${id}`, description: `Live batch: marshalling bug, missing tenantId (${id})` },
  }),
  missing_correlation_id: (id) => ({
    id,
    tenantId: TENANT,
    status: "PENDING",
    payload: { legacyRecordId: `legacy-${id}`, description: `Live batch: missing correlationId (${id})` },
  }),
  never_dispatched: (id) => ({
    id,
    tenantId: TENANT,
    correlationId: `corr-${id}`,
    // no `status` key - dispatcher's strict equality check skips it forever
    payload: { legacyRecordId: `legacy-${id}`, description: `Live batch: never dispatched, no status (${id})` },
  }),
  healthy_control: (id) => ({
    id,
    tenantId: TENANT,
    correlationId: `corr-${id}`,
    status: "PENDING",
    payload: { cloudRecordId: id, description: `Live batch: healthy control, should sync fine (${id})` },
  }),
};

// 10 slots per tick: mix of every error category plus 2 successes
const CYCLE = [
  "classic_mapping_bug",
  "payload_missing",
  "marshalling_bug",
  "missing_correlation_id",
  "never_dispatched",
  "healthy_control",
  "classic_mapping_bug",
  "payload_missing",
  "marshalling_bug",
  "healthy_control",
];

async function main() {
  const tick = process.argv[2];
  if (!tick) {
    console.error("Usage: node seed-sync-batch.js <tick-number>");
    process.exit(1);
  }

  const logPath = path.join(__dirname, "live-sync-batches.jsonl");
  const timestamp = new Date().toISOString();

  for (let i = 0; i < CYCLE.length; i++) {
    const category = CYCLE[i];
    const id = `record-live-t${tick}-${i + 1}`;
    const item = GENERATORS[category](id);

    await ddb.send(new PutCommand({ TableName: SOURCE_TABLE, Item: item }));

    fs.appendFileSync(
      logPath,
      JSON.stringify({ tick: Number(tick), timestamp, id, category, correlationId: item.correlationId ?? null }) + "\n"
    );

    console.log(`[tick ${tick}] seeded ${id} (${category})`);
  }

  console.log(`Tick ${tick}: seeded ${CYCLE.length} records.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
