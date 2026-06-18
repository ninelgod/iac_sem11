variable "name_prefix" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "cloudfront_certificate_arn" {
  type = string
}

variable "waf_acl_arn" {
  type = string
}

variable "logs_bucket" {
  type = string
}

variable "kms_key_arn" {
  type = string
}
