const fs = require("fs");
const path = require("path");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { CATEGORIES } = require("./test-matrix-scenarios");

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const SOURCE_TABLE = process.env.SOURCE_TABLE || "incident-agent-poc-source";

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function putWithRetry(item, attempt = 1) {
  try {
    await ddb.send(new PutCommand({ TableName: SOURCE_TABLE, Item: item }));
  } catch (err) {
    if (attempt >= 3) throw err;
    await sleep(200 * attempt);
    return putWithRetry(item, attempt + 1);
  }
}

// Fires PutItems in small concurrent batches so 100 writes don't hammer
// on-demand DynamoDB in one instant, without needing real throttling logic
// for a table this small.
async function putAllBatched(items, batchSize = 10) {
  for (let i = 0; i < items.length; i += batchSize) {
    const batch = items.slice(i, i + batchSize);
    await Promise.all(batch.map((item) => putWithRetry(item)));
  }
}

async function main() {
  const manifest = [];

  for (const [categoryName, category] of Object.entries(CATEGORIES)) {
    const generatedItems = category.generate();
    console.log(`Seeding ${generatedItems.length} items for category "${categoryName}"...`);

    await putAllBatched(generatedItems);

    if (category.isDuplicatePair) {
      // Re-put the same items shortly after, still PENDING, to try to
      // trigger a second independent stream event before the worker's
      // first run flips status to SYNCED.
      await sleep(300);
      await putAllBatched(generatedItems);
    }

    for (const item of generatedItems) {
      manifest.push({
        category: categoryName,
        id: item.id,
        correlationId: item.correlationId ?? null,
        seededItem: item,
        expected: category.expected,
      });
    }
  }

  const outputPath = path.join(__dirname, "test-matrix-expectations.json");
  fs.writeFileSync(outputPath, JSON.stringify(manifest, null, 2));

  console.log(`\nSeeded ${manifest.length} records across ${Object.keys(CATEGORIES).length} categories.`);
  console.log(`Ground-truth manifest written to ${outputPath}`);
  console.log("Wait ~30-60s for the stream -> dispatcher -> SQS -> sync-worker chain, then run verify-test-matrix.js");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
