# EC2 instance role for the OpenClaw investigation agent — read-only.
# Mirrors synthetic-sync-platform's investigation-readonly role, but as a
# native instance profile since the agent runs directly on this box.

resource "aws_iam_role" "openclaw_ec2" {
  name = "${var.name_prefix}-ec2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "openclaw_investigation_readonly" {
  name = "${var.name_prefix}-investigation-readonly"
  role = aws_iam_role.openclaw_ec2.id
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
          "logs:FilterLogEvents",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/incident-agent-poc-*"
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

resource "aws_iam_instance_profile" "openclaw_ec2" {
  name = "${var.name_prefix}-ec2"
  role = aws_iam_role.openclaw_ec2.name
}
