variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private subnets (ECS)"
  type        = list(string)
}

variable "private_db_subnet_cidrs" {
  description = "CIDRs for private DB subnets (Aurora)"
  type        = list(string)
}

variable "kms_key_id" {
  description = "KMS key ARN for VPC flow logs encryption"
  type        = string
}
