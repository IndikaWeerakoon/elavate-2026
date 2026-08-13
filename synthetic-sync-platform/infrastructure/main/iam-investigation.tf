# Read-only role the OpenClaw investigation agent assumes locally.
# Kept separate from the operational lambda exec roles above — the agent
# must never hold write permissions on the pipeline it is investigating.

resource "aws_iam_role" "investigation_readonly" {
  name = "${var.name_prefix}-investigation-readonly"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "investigation_readonly" {
  name = "${var.name_prefix}-investigation-readonly"
  role = aws_iam_role.investigation_readonly.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:StartQuery",
          "logs:GetQueryResults",
          "logs:StopQuery",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.name_prefix}-*"
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:GetFunctionConfiguration", "lambda:ListFunctions"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:GetQueueAttributes", "sqs:ListQueues"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics"]
        Resource = "*"
      },
    ]
  })
}
