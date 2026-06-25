variable "name_prefix" {
  type = string
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_master_username" {
  type      = string
  sensitive = true
}

variable "db_master_password" {
  type      = string
  sensitive = true
}

variable "kms_key_arn" {
  type = string
}

variable "cloudwatch_log_group" {
  type = string
}

variable "skip_final_snapshot" {
  type        = bool
  default     = false
  description = "Skip final snapshot on destroy. Set to true for dev/test environments to avoid snapshot name conflicts on repeated destroys"
}
