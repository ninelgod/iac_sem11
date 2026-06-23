data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# Llave KMS dedicada a cifrar los CloudWatch Log Groups de todo el proyecto.
resource "aws_kms_key" "cloudwatch" {
  description             = "${var.name_prefix} CloudWatch Logs encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
          "kms:GenerateDataKey*", "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# Alias legible para la llave de CloudWatch (evita usar el key_id crudo en otros módulos).
resource "aws_kms_alias" "cloudwatch" {
  name          = "alias/${var.name_prefix}-cloudwatch"
  target_key_id = aws_kms_key.cloudwatch.key_id
}

# Llave KMS para cifrar el storage y los snapshots de Aurora (RDS).
resource "aws_kms_key" "rds" {
  description             = "${var.name_prefix} Aurora RDS encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "Enable IAM User Permissions"
      Effect = "Allow"
      Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
      Action   = "kms:*"
      Resource = "*"
    }]
  })
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.name_prefix}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# Llave KMS para cifrar los secretos en Secrets Manager (credenciales de Aurora).
resource "aws_kms_key" "secrets" {
  description             = "${var.name_prefix} Secrets Manager encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Secrets Manager"
        Effect = "Allow"
        Principal = { Service = "secretsmanager.amazonaws.com" }
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
          "kms:GenerateDataKey*", "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# Llave KMS para cifrar las imágenes Docker almacenadas en ECR.
resource "aws_kms_key" "ecr" {
  description             = "${var.name_prefix} ECR encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "Enable IAM User Permissions"
      Effect = "Allow"
      Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
      Action   = "kms:*"
      Resource = "*"
    }]
  })
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/${var.name_prefix}-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}

# Llave KMS para cifrar los buckets S3 (frontend estático), usada también por CloudFront.
resource "aws_kms_key" "s3" {
  description             = "${var.name_prefix} S3 encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudFront"
        Effect = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action = [
          "kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.name_prefix}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

# Llave KMS dedicada a los buckets de logs (ALB access logs / CloudFront access logs).
resource "aws_kms_key" "alb_logs" {
  description             = "${var.name_prefix} ALB logs S3 encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "Enable IAM User Permissions"
      Effect = "Allow"
      Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
      Action   = "kms:*"
      Resource = "*"
    }]
  })
}

resource "aws_kms_alias" "alb_logs" {
  name          = "alias/${var.name_prefix}-alb-logs"
  target_key_id = aws_kms_key.alb_logs.key_id
}
