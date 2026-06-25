variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "Environment must be prod, staging, or dev."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "gestorpagosg2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to deploy into"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (ALB + NAT gateways)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private subnets (ECS Fargate)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDRs for private DB subnets (Aurora)"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "domain_name" {
  description = "Root domain name"
  type        = string
  default     = "gestorpagosg2.com"
}

variable "certificate_arn" {
  description = "ACM certificate ARN (us-east-2) for ALB HTTPS listener"
  type        = string
}

variable "cloudfront_certificate_arn" {
  description = "ACM certificate ARN (us-east-1) for CloudFront HTTPS"
  type        = string
}

variable "db_name" {
  description = "Aurora database name"
  type        = string
  default     = "gestorpagosg2db"
}

variable "db_master_username" {
  description = "Aurora master username"
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "alarm_email" {
  description = "Email for CloudWatch alarm SNS notifications"
  type        = string
}

variable "ecr_image_tag" {
  description = "Container image tag to deploy"
  type        = string
  default     = "latest"
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on Aurora destroy. Set to true for dev/test to avoid snapshot name conflicts on repeated destroys"
  type        = bool
  default     = false
}
