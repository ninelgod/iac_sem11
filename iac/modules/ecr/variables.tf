variable "name_prefix" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "services" {
  description = "List of microservice names to create ECR repos for"
  type        = list(string)
  default     = ["usuarios", "pagos", "reportes"]
}
