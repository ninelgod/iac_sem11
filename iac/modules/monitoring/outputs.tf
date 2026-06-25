output "alb_logs_bucket" {
  description = "S3 bucket name for ALB access logs"
  value       = aws_s3_bucket.alb_logs.bucket
  depends_on  = [aws_s3_bucket_policy.alb_logs]
}

output "cloudfront_logs_bucket" {
  description = "S3 bucket name for CloudFront access logs"
  value       = aws_s3_bucket.cloudfront_logs.bucket
}

output "aurora_log_group_name" {
  description = "CloudWatch log group name for Aurora"
  value       = aws_cloudwatch_log_group.aurora.name
}

output "ecs_log_groups" {
  description = "CloudWatch log group names per ECS service"
  value = {
    usuarios = aws_cloudwatch_log_group.ecs_usuarios.name
    pagos    = aws_cloudwatch_log_group.ecs_pagos.name
    reportes = aws_cloudwatch_log_group.ecs_reportes.name
  }
}

output "alarm_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  value       = aws_sns_topic.alarms.arn
}

output "name_prefix" {
  description = "Name prefix for use in root-level alarm resources"
  value       = var.name_prefix
}
