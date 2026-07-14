variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
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
  default     = "gestorpagosg2.site"
}

variable "certificate_arn" {
  description = "ARN de un certificado ACM ya emitido en us-east-2 para el listener HTTPS del ALB. Terraform no crea este certificado."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:acm:us-east-2:[0-9]{12}:certificate/.+", var.certificate_arn))
    error_message = "certificate_arn debe ser un ARN válido de ACM en us-east-2 y debe existir antes de ejecutar terraform apply."
  }
}

variable "cloudfront_certificate_arn" {
  description = "ARN de un certificado ACM ya emitido en us-east-1 para CloudFront HTTPS. Terraform no crea este certificado."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:acm:us-east-1:[0-9]{12}:certificate/.+", var.cloudfront_certificate_arn))
    error_message = "cloudfront_certificate_arn debe ser un ARN válido de ACM en us-east-1, requerido por CloudFront."
  }
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

variable "resend_api_key" {
  description = "Resend API key for email notifications in the Next.js web app"
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Grafana admin panel password"
  type        = string
  sensitive   = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on Aurora destroy. Set to true for dev/test to avoid snapshot name conflicts on repeated destroys"
  type        = bool
  default     = false
}
