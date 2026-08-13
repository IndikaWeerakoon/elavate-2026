terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project      = "EngineeringIncidentAgent"
      Environment  = "POC"
      Owner        = "Hasitha"
      ExpiresAfter = "2026-08-20"
      ManagedBy    = "terraform-bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

# --- Terraform remote state backend for the main POC stack ---

resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.name_prefix}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "${var.name_prefix}-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# --- GitHub Actions OIDC deploy role (reuses existing account OIDC provider) ---

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_deploy_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.name_prefix}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_deploy_trust.json
}

data "aws_iam_policy_document" "github_deploy_permissions" {
  # Terraform state backend access
  statement {
    sid     = "TFStateBucket"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
    ]
  }

  statement {
    sid       = "TFStateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.tfstate_lock.arn]
  }

  # POC resource lifecycle — scoped to the incident-agent-poc-* prefix only
  statement {
    sid    = "PocDynamoDB"
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable",
      "dynamodb:DescribeTable",
      "dynamodb:UpdateTable",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:ListTagsOfResource",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:DescribeStream",
      "dynamodb:GetShardIterator",
      "dynamodb:GetRecords",
      "dynamodb:ListStreams",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.name_prefix}-*",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.name_prefix}-*/stream/*",
    ]
  }

  statement {
    sid    = "PocSQS"
    effect = "Allow"
    actions = [
      "sqs:CreateQueue",
      "sqs:DeleteQueue",
      "sqs:GetQueueAttributes",
      "sqs:SetQueueAttributes",
      "sqs:TagQueue",
      "sqs:UntagQueue",
      "sqs:ListQueueTags",
    ]
    resources = ["arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.name_prefix}-*"]
  }

  statement {
    sid    = "PocLambda"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:ListVersionsByFunction",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:ListTags",
      "lambda:CreateEventSourceMapping",
      "lambda:DeleteEventSourceMapping",
      "lambda:GetEventSourceMapping",
      "lambda:UpdateEventSourceMapping",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:GetPolicy",
    ]
    resources = ["arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.name_prefix}-*"]
  }

  statement {
    sid    = "PocLambdaEventSourceMapping"
    effect = "Allow"
    actions = [
      "lambda:CreateEventSourceMapping",
      "lambda:DeleteEventSourceMapping",
      "lambda:GetEventSourceMapping",
      "lambda:UpdateEventSourceMapping",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:ListTags",
    ]
    resources = ["*"]
  }

  statement {
    # DescribeLogGroups does not support resource-level scoping.
    sid       = "PocLogsDescribe"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid    = "PocLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:ListTagsForResource",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name_prefix}-*"]
  }

  # IAM roles for the Lambda functions themselves — scoped to the poc prefix
  statement {
    sid    = "PocIamRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PassRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name_prefix}-*"]
  }

  # instance-profile is a distinct IAM resource type from role, needs its own ARN pattern
  statement {
    sid    = "PocIamInstanceProfiles"
    effect = "Allow"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.name_prefix}-*"]
  }

  # EC2 describe/create actions mostly don't support resource-level ARNs.
  # Destructive actions are guarded by the Project tag instead.
  statement {
    sid    = "Ec2ReadAndCreate"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceAttribute",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeKeyPairs",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeVolumes",
      "ec2:DescribeAddresses",
      "ec2:DescribeTags",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeIamInstanceProfileAssociations",
      "ec2:RunInstances",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:AllocateAddress",
      "ec2:AssociateAddress",
      "ec2:AssociateIamInstanceProfile",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Ec2DestructiveTagGuarded"
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances",
      "ec2:StopInstances",
      "ec2:DeleteSecurityGroup",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:DisassociateIamInstanceProfile",
      "ec2:ReleaseAddress",
      "ec2:DisassociateAddress",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["EngineeringIncidentAgent"]
    }
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "${var.name_prefix}-github-deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy_permissions.json
}
