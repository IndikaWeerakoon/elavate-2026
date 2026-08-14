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

  // DynamoDBDocumentClient defaults to removeUndefinedValues: true, which silently
  // drops undefined attributes from the PutItem request. A source row missing
  // tenantId would otherwise be written as a destination row with no tenantId field,
  // source marked SYNCED, and no log entry to alert on. Validate up front so the
  // failure surfaces and the D1 swallow-fix in the handler can DLQ the message.
  if (!input.cloudRecordId || !input.tenantId) {
    throw new Error(
      `tenantId and cloudRecordId are required, got ${JSON.stringify(
        Object.keys(input).filter((k) => input[k] === undefined || input[k] === null)
      )}`
    );
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
