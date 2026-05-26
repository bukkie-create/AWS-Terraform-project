output "project_name" {
  value = var.project_name
}

output "aws_region" {
  value = var.aws_region
}
output "sqs_queue_url" {
  value = aws_sqs_queue.main.url
}

output "sns_topic_arn" {
  value = aws_sns_topic.main.arn
}

output "lambda_function_names" {
  value = keys(aws_lambda_function.app)
}