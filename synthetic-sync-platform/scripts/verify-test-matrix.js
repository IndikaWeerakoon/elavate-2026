const fs = require("fs");
const path = require("path");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand, ScanCommand } = require("@aws-sdk/lib-dynamodb");

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const SOURCE_TABLE = process.env.SOURCE_TABLE || "incident-agent-poc-source";
const DESTINATION_TABLE = process.env.DESTINATION_TABLE || "incident-agent-poc-destination";

async function main() {
  const manifestPath = path.join(__dirname, "test-matrix-expectations.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

  const destinationScan = await ddb.send(new ScanCommand({ TableName: DESTINATION_TABLE }));
  const destinationById = new Map((destinationScan.Items || []).map((i) => [i.cloudRecordId, i]));

  const results = { pass: 0, fail: 0, failures: [] };
  const byCategory = {};

  for (const row of manifest) {
    const source = await ddb.send(new GetCommand({ TableName: SOURCE_TABLE, Key: { id: row.id } }));
    const currentStatus = source.Item?.status;

    let ok = true;
    const reasons = [];

    if (row.expected.finalSourceStatus === null) {
      // never_dispatched: status must be exactly what we seeded (unchanged)
      const seededStatus = row.seededItem.status;
      if (currentStatus !== seededStatus) {
        ok = false;
        reasons.push(`expected status to stay ${JSON.stringify(seededStatus)}, got ${JSON.stringify(currentStatus)}`);
      }
    } else if (currentStatus !== row.expected.finalSourceStatus) {
      ok = false;
      reasons.push(`expected status ${row.expected.finalSourceStatus}, got ${JSON.stringify(currentStatus)}`);
    }

    const expectedCloudRecordId = row.seededItem.payload?.cloudRecordId;
    const destinationItem = expectedCloudRecordId ? destinationById.get(expectedCloudRecordId) : undefined;

    if (row.expected.destinationHasRecord === true) {
      if (!destinationItem) {
        ok = false;
        reasons.push(`expected destination to contain ${expectedCloudRecordId}, not found`);
      } else if (row.expected.destinationRecordMissingField) {
        const field = row.expected.destinationRecordMissingField;
        if (destinationItem[field] !== undefined) {
          ok = false;
          reasons.push(`expected destination record to be missing "${field}", but it was present`);
        }
      }
    } else if (destinationItem) {
      ok = false;
      reasons.push(`expected no destination record, but found one for ${expectedCloudRecordId}`);
    }

    byCategory[row.category] ??= { pass: 0, fail: 0 };
    byCategory[row.category][ok ? "pass" : "fail"] += 1;

    if (ok) {
      results.pass += 1;
    } else {
      results.fail += 1;
      results.failures.push({ id: row.id, category: row.category, reasons });
    }
  }

  const expectedDestinationCount = manifest.filter((r) => r.expected.destinationHasRecord === true).length;

  console.log("=== Per-category results ===");
  for (const [category, counts] of Object.entries(byCategory)) {
    console.log(`  ${category}: ${counts.pass} pass, ${counts.fail} fail`);
  }

  console.log(`\n=== Overall: ${results.pass}/${manifest.length} passed ===`);
  console.log(`Destination table contains ${destinationById.size} record(s), expected exactly ${expectedDestinationCount}.`);
  if (destinationById.size !== expectedDestinationCount) {
    results.failures.push({ id: "(aggregate)", category: "(aggregate)", reasons: ["destination table count mismatch"] });
  }

  if (results.failures.length) {
    console.log("\n=== Failures ===");
    for (const f of results.failures) {
      console.log(`  [${f.category}] ${f.id}: ${f.reasons.join("; ")}`);
    }
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
