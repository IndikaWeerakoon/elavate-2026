const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand, ScanCommand } = require("@aws-sdk/lib-dynamodb");

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const SOURCE_TABLE = process.env.SOURCE_TABLE || "incident-agent-poc-source";
const DESTINATION_TABLE = process.env.DESTINATION_TABLE || "incident-agent-poc-destination";
const RECORD_ID = process.env.RECORD_ID || "record-100";

async function main() {
  const source = await ddb.send(new GetCommand({ TableName: SOURCE_TABLE, Key: { id: RECORD_ID } }));
  const destination = await ddb.send(new ScanCommand({ TableName: DESTINATION_TABLE }));

  console.log("source item:", source.Item);
  console.log("destination table item count:", destination.Items?.length ?? 0);

  const sourceSynced = source.Item?.status === "SYNCED";
  const destinationMissing = (destination.Items?.length ?? 0) === 0;

  if (sourceSynced && destinationMissing) {
    console.log("PASS: silent failure reproduced — source SYNCED, destination record missing.");
  } else {
    console.log("FAIL: incident not reproduced as expected.");
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
