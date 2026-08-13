data "archive_file" "dispatcher" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/dispatcher"
  output_path = "${path.module}/../../.build/dispatcher.zip"
}

data "archive_file" "sync_worker" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/sync-worker"
  output_path = "${path.module}/../../.build/sync-worker.zip"
}

# --- dispatcher ---

resource "aws_iam_role" "dispatcher" {
  name = "${var.name_prefix}-dispatcher"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "dispatcher" {
  name = "${var.name_prefix}-dispatcher"
  role = aws_iam_role.dispatcher.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.dispatcher.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams",
        ]
        Resource = "${aws_dynamodb_table.source.arn}/stream/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.sync.arn
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "dispatcher" {
  name              = "/aws/lambda/${var.name_prefix}-dispatcher"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "dispatcher" {
  function_name    = "${var.name_prefix}-dispatcher"
  role             = aws_iam_role.dispatcher.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = 15
  memory_size      = 128
  filename         = data.archive_file.dispatcher.output_path
  source_code_hash = data.archive_file.dispatcher.output_base64sha256

  environment {
    variables = {
      SYNC_QUEUE_URL = aws_sqs_queue.sync.url
    }
  }

  depends_on = [aws_cloudwatch_log_group.dispatcher]
}

resource "aws_lambda_event_source_mapping" "dispatcher_stream" {
  event_source_arn  = aws_dynamodb_table.source.stream_arn
  function_name     = aws_lambda_function.dispatcher.arn
  starting_position = "LATEST"
  batch_size        = 10
}

# --- sync-worker ---

resource "aws_iam_role" "sync_worker" {
  name = "${var.name_prefix}-sync-worker"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "sync_worker" {
  name = "${var.name_prefix}-sync-worker"
  role = aws_iam_role.sync_worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.sync_worker.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
        ]
        Resource = aws_sqs_queue.sync.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.destination.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.source.arn
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "sync_worker" {
  name              = "/aws/lambda/${var.name_prefix}-sync-worker"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "sync_worker" {
  function_name    = "${var.name_prefix}-sync-worker"
  role             = aws_iam_role.sync_worker.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = 15
  memory_size      = 128
  filename         = data.archive_file.sync_worker.output_path
  source_code_hash = data.archive_file.sync_worker.output_base64sha256

  environment {
    variables = {
      SOURCE_TABLE      = aws_dynamodb_table.source.name
      DESTINATION_TABLE = aws_dynamodb_table.destination.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.sync_worker]
}

resource "aws_lambda_event_source_mapping" "sync_worker_queue" {
  event_source_arn = aws_sqs_queue.sync.arn
  function_name    = aws_lambda_function.sync_worker.arn
  batch_size       = 5
}
