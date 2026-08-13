const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand, UpdateCommand } = require("@aws-sdk/lib-dynamodb");

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const SOURCE_TABLE = process.env.SOURCE_TABLE;
const DESTINATION_TABLE = process.env.DESTINATION_TABLE;

// CloudRecordInput = { cloudRecordId, tenantId, description }
// The source payload only carries legacyRecordId — never mapped to
// cloudRecordId — so this write fails validation on every record.
async function writeDestination(record) {
  const input = {
    cloudRecordId: record.payload.cloudRecordId,
    tenantId: record.tenantId,
    description: record.payload.description,
  };

  if (!input.cloudRecordId) {
    throw new Error("cloudRecordId is required");
  }

  await ddb.send(new PutCommand({ TableName: DESTINATION_TABLE, Item: input }));
}

async function updateSourceStatus(id, status) {
  await ddb.send(
    new UpdateCommand({
      TableName: SOURCE_TABLE,
      Key: { id },
      UpdateExpression: "SET #status = :status",
      ExpressionAttributeNames: { "#status": "status" },
      ExpressionAttributeValues: { ":status": status },
    })
  );
}

exports.handler = async (event) => {
  for (const message of event.Records) {
    const record = JSON.parse(message.body);

    try {
      await writeDestination(record);
    } catch (error) {
      console.error(
        JSON.stringify({
          event: "DESTINATION_WRITE_FAILED",
          correlationId: record.correlationId,
          recordId: record.id,
          reason: error instanceof Error ? error.message : "Unknown error",
        })
      );
    }

    await updateSourceStatus(record.id, "SYNCED");

    console.log(
      JSON.stringify({
        event: "SOURCE_MARKED_SYNCED",
        correlationId: record.correlationId,
        recordId: record.id,
      })
    );
  }
};
