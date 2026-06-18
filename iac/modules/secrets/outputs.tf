output "db_secret_arn" {
  description = "ARN of the DB credentials secret"
  value       = aws_secretsmanager_secret.db.arn
}

output "db_master_password" {
  description = "Generated DB master password"
  value       = random_password.db_master.result
  sensitive   = true
}
