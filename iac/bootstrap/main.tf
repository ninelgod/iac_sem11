# Bootstrap: crea el bucket S3 y la tabla DynamoDB para el backend remoto.
# Ejecutar UNA SOLA VEZ antes de `terraform init` en el directorio raíz de iac/.
#
# Uso:
#   cd iac/bootstrap
#   terraform init
#   terraform apply
#   cd ..
#   terraform init   ← ahora sí apunta al backend remoto

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Este módulo usa backend local intencionalmente
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "project_name" {
  type    = string
  default = "gestorpagosg2"
}

data "aws_caller_identity" "current" {}

# --- KMS key para cifrar el tfstate ---
resource "aws_kms_key" "tfstate" {
  description             = "KMS key for Terraform state S3 bucket"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "Enable IAM User Permissions"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })

  tags = { Name = "${var.project_name}-tfstate-kms" }
}

resource "aws_kms_alias" "tfstate" {
  name          = "alias/${var.project_name}-tfstate"
  target_key_id = aws_kms_key.tfstate.key_id
}

# --- S3 Bucket para los access logs del tfstate ---
resource "aws_s3_bucket" "tfstate_access_logs" {
  #checkov:skip=CKV_AWS_18:Bucket destino de access logs; habilitarle logging propio crearia un ciclo
  #checkov:skip=CKV_AWS_144:Bucket de logs de soporte de una sola region; no se justifica replicacion cross-region
  #checkov:skip=CKV2_AWS_62:Bucket de logs sin consumidores de eventos
  bucket        = "${var.project_name}-tfstate-access-logs"
  force_destroy = false

  tags = { Name = "${var.project_name}-tfstate-access-logs" }
}

resource "aws_s3_bucket_versioning" "tfstate_access_logs" {
  bucket = aws_s3_bucket.tfstate_access_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate_access_logs" {
  bucket = aws_s3_bucket.tfstate_access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tfstate.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate_access_logs" {
  bucket                  = aws_s3_bucket.tfstate_access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate_access_logs" {
  bucket = aws_s3_bucket.tfstate_access_logs.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    expiration { days = 365 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

# --- S3 Bucket para el tfstate ---
resource "aws_s3_bucket" "tfstate" {
  #checkov:skip=CKV_AWS_144:Bucket de estado de Terraform de una sola region; la replicacion cross-region no aplica a este stack de bootstrap
  #checkov:skip=CKV2_AWS_62:Bucket de estado sin consumidores de eventos; no hay integracion downstream que necesite notificaciones S3
  bucket        = "${var.project_name}-tfstate"
  force_destroy = false

  tags = { Name = "${var.project_name}-tfstate" }
}

resource "aws_s3_bucket_logging" "tfstate" {
  bucket        = aws_s3_bucket.tfstate.id
  target_bucket = aws_s3_bucket.tfstate_access_logs.id
  target_prefix = "tfstate-access-logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tfstate.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyNonSSL"
        Effect = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid    = "DenyNonEncrypted"
        Effect = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.tfstate.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# --- DynamoDB para el lock del tfstate ---
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "${var.project_name}-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.tfstate.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "${var.project_name}-tfstate-lock" }
}

output "s3_bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.tfstate_lock.name
}
