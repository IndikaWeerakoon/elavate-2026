resource "aws_sqs_queue" "sync_dlq" {
  name                      = "${var.name_prefix}-sync-dlq"
  message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue" "sync" {
  name                       = "${var.name_prefix}-sync"
  visibility_timeout_seconds = 30

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sync_dlq.arn
    maxReceiveCount     = 3
  })
}
