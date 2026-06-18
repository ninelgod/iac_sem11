output "cloudwatch_key_arn" {
  description = "KMS key ARN for CloudWatch Logs"
  value       = aws_kms_key.cloudwatch.arn
}

output "rds_key_arn" {
  description = "KMS key ARN for RDS/Aurora"
  value       = aws_kms_key.rds.arn
}

output "secrets_key_arn" {
  description = "KMS key ARN for Secrets Manager"
  value       = aws_kms_key.secrets.arn
}

output "ecr_key_arn" {
  description = "KMS key ARN for ECR"
  value       = aws_kms_key.ecr.arn
}

output "s3_key_arn" {
  description = "KMS key ARN for S3"
  value       = aws_kms_key.s3.arn
}

output "alb_logs_key_arn" {
  description = "KMS key ARN for ALB logs bucket"
  value       = aws_kms_key.alb_logs.arn
}
