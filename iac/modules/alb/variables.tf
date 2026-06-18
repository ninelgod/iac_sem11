variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "certificate_arn" {
  type = string
}

variable "waf_acl_arn" {
  type = string
}

variable "logs_bucket" {
  type = string
}
