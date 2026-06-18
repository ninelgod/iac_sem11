variable "name_prefix" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "alb_target_group_arns" {
  description = "Map of service → target group ARN"
  type        = map(string)
}

variable "ecr_repository_urls" {
  description = "Map of service → ECR URL"
  type        = map(string)
}

variable "ecr_image_tag" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "secrets_arn" {
  description = "ARN of the DB credentials secret"
  type        = string
}

variable "cognito_user_pool_id" {
  type = string
}

variable "aurora_endpoint" {
  type      = string
  sensitive = true
}

variable "db_name" {
  type = string
}

