// CloudRecordInput — what the destination system (CloudNext) expects.
// {
//   cloudRecordId: string
//   tenantId: string
//   description: string
// }
//
// The sync-worker never maps legacyRecordId -> cloudRecordId, so every
// write to CloudNext fails validation. See src/sync-worker/index.js.
module.exports = {};
