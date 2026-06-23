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

variable "alb_dns_name" {
  description = "DNS name del ALB, usado como segundo origin de CloudFront para trafico dinamico /api/*"
  type        = string
}
