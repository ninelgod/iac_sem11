output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (ECS)"
  value       = aws_subnet.private[*].id
}

output "private_db_subnet_ids" {
  description = "Private DB subnet IDs (Aurora)"
  value       = aws_subnet.private_db[*].id
}
