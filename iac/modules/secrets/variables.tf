variable "name_prefix" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_master_username" {
  type      = string
  sensitive = true
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}
