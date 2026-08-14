const { SQSClient, SendMessageCommand } = require("@aws-sdk/client-sqs");
const { unmarshall } = require("@aws-sdk/util-dynamodb");

const sqs = new SQSClient({});
const QUEUE_URL = process.env.SYNC_QUEUE_URL;

// Dispatches PENDING source records onto the sync queue.
// Skips records already SYNCED so the stream trigger fired by the
// sync-worker's own status update does not cause a re-dispatch loop.
exports.handler = async (event) => {
  for (const record of event.Records) {
    if (record.eventName !== "INSERT" && record.eventName !== "MODIFY") continue;
    if (!record.dynamodb.NewImage) continue;

    const item = unmarshall(record.dynamodb.NewImage);
    if (item.status !== "PENDING") {
      console.log(
        JSON.stringify({
          event: "RECORD_SKIPPED",
          reason: "STATUS_NOT_PENDING",
          correlationId: item.correlationId,
          recordId: item.id,
          actualStatus: item.status,
        })
      );
      continue;
    }

    await sqs.send(
      new SendMessageCommand({
        QueueUrl: QUEUE_URL,
        MessageBody: JSON.stringify(item),
      })
    );

    console.log(
      JSON.stringify({
        event: "RECORD_DISPATCHED",
        correlationId: item.correlationId,
        recordId: item.id,
      })
    );
  }
};
