const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand } = require("@aws-sdk/lib-dynamodb");

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const SOURCE_TABLE = process.env.SOURCE_TABLE || "incident-agent-poc-source";

async function main() {
  const record = {
    id: "record-100",
    tenantId: "tenant-demo-001",
    correlationId: "corr-demo-7821",
    status: "PENDING",
    payload: {
      legacyRecordId: "legacy-100",
      description: "Synthetic demonstration record",
    },
  };

  await ddb.send(new PutCommand({ TableName: SOURCE_TABLE, Item: record }));
  console.log(`Seeded ${record.id} into ${SOURCE_TABLE}. Dispatcher/sync-worker will pick it up via the DynamoDB stream.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
