variable "name_prefix" {
  type = string
}

variable "kms_key_arn" {
  description = "ARN de la KMS key (us-east-2) usada para cifrar el log group del WAF del ALB"
  type        = string
}
