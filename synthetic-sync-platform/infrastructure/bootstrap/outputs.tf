output "tfstate_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}

output "tfstate_lock_table" {
  value = aws_dynamodb_table.tfstate_lock.name
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}
