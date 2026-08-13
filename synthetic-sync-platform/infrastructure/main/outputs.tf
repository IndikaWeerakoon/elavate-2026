output "source_table_name" {
  value = aws_dynamodb_table.source.name
}

output "destination_table_name" {
  value = aws_dynamodb_table.destination.name
}

output "sync_queue_url" {
  value = aws_sqs_queue.sync.url
}

output "sync_dlq_url" {
  value = aws_sqs_queue.sync_dlq.url
}

output "dispatcher_function_name" {
  value = aws_lambda_function.dispatcher.function_name
}

output "sync_worker_function_name" {
  value = aws_lambda_function.sync_worker.function_name
}

output "sync_worker_log_group" {
  value = aws_cloudwatch_log_group.sync_worker.name
}

output "investigation_role_arn" {
  value = aws_iam_role.investigation_readonly.arn
}
