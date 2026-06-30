data "aws_caller_identity" "current" {}
data "aws_region" "current" {}


# Topic SNS donde llegan las alarmas de CloudWatch (4xx, 5xx, latencia del ALB).
resource "aws_sns_topic" "alarms" {
  name              = "${var.name_prefix}-alarms"
  kms_master_key_id = var.kms_key_arn

  tags = { Name = "${var.name_prefix}-alarms" }
}

# Suscribe un correo al topic de alarmas (recibe el aviso cuando una alarma se dispara).
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}


# Log group del microservicio Usuarios.
resource "aws_cloudwatch_log_group" "ecs_usuarios" {
  name              = "/ecs/${var.name_prefix}/usuarios"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
  tags              = { Name = "${var.name_prefix}-ecs-usuarios-logs" }
}

# Log group del microservicio Pagos.
resource "aws_cloudwatch_log_group" "ecs_pagos" {
  name              = "/ecs/${var.name_prefix}/pagos"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
  tags              = { Name = "${var.name_prefix}-ecs-pagos-logs" }
}

# Log group del microservicio Reportes.
resource "aws_cloudwatch_log_group" "ecs_reportes" {
  name              = "/ecs/${var.name_prefix}/reportes"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
  tags              = { Name = "${var.name_prefix}-ecs-reportes-logs" }
}

# Log group de las queries de Aurora (exportadas desde el cluster). El nombre debe coincidir EXACTO con el
# que Aurora arma solo a partir de su cluster_identifier (name_prefix-aurora-cluster), si no, AWS crea su
# propio log group por separado (sin esta KMS key ni esta retencion) y este queda vacio.
resource "aws_cloudwatch_log_group" "aurora" {
  name              = "/aws/rds/cluster/${var.name_prefix}-aurora-cluster/postgresql"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
  tags              = { Name = "${var.name_prefix}-aurora-logs" }
}


# Bucket donde el ALB deposita sus access logs.
resource "aws_s3_bucket" "alb_logs" {
  #checkov:skip=CKV_AWS_144:Bucket de logs de una sola region; los logs expiran a los 365 dias, no se justifica replicacion cross-region
  #checkov:skip=CKV2_AWS_62:Bucket de logs sin consumidores de eventos; nadie procesa estos logs via notificaciones S3
  bucket        = "${var.name_prefix}-alb-access-logs"
  force_destroy = false

  tags = { Name = "${var.name_prefix}-alb-access-logs" }
}

# Access logs del bucket de logs del ALB — se cruzan con el bucket de logs de CloudFront (cada uno loguea al otro, no a sí mismo).
resource "aws_s3_bucket_logging" "alb_logs" {
  bucket        = aws_s3_bucket.alb_logs.id
  target_bucket = aws_s3_bucket.cloudfront_logs.id
  target_prefix = "s3-access/alb-logs/"
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration { status = "Enabled" }
}

# Cifrado del bucket de logs del ALB. AES256 (no KMS): ALB access logs no soporta buckets cifrados con
# SSE-KMS (limitacion del producto, no de permisos) - con aws:kms este bucket siempre falla con Access Denied.
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  #checkov:skip=CKV_AWS_145:ALB access logs no soporta buckets con cifrado SSE-KMS; AES256 es el unico modo compatible para este bucket especifico
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Borra los logs del ALB a los 365 días y limpia uploads multipart abandonados.
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    expiration { days = 365 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

# Cuenta de servicio fija que usa AWS internamente para escribir los access logs del ALB en cada región.
data "aws_elb_service_account" "main" {}

# Policy que permite específicamente a ese servicio del ALB escribir logs aquí, y bloquea cualquier acceso sin SSL.
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowELBLogging"
        Effect = "Allow"
        Principal = { AWS = data.aws_elb_service_account.main.arn }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Sid    = "DenyNonSSL"
        Effect = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.alb_logs.arn, "${aws_s3_bucket.alb_logs.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}


# Bucket donde CloudFront deposita sus access logs.
resource "aws_s3_bucket" "cloudfront_logs" {
  #checkov:skip=CKV_AWS_144:Bucket de logs de una sola region; los logs expiran a los 365 dias, no se justifica replicacion cross-region
  #checkov:skip=CKV2_AWS_62:Bucket de logs sin consumidores de eventos; nadie procesa estos logs via notificaciones S3
  bucket        = "${var.name_prefix}-cloudfront-access-logs"
  force_destroy = false

  tags = { Name = "${var.name_prefix}-cloudfront-access-logs" }
}

# CloudFront access logs (logging_config) usa el mecanismo de entrega clasico, que exige ACLs habilitadas en el
# bucket destino - con el default actual de AWS (BucketOwnerEnforced, ACLs deshabilitadas) la distribucion falla
# con "does not enable ACL access". BucketOwnerPreferred reactiva ACLs sin perder el ownership del bucket.
resource "aws_s3_bucket_ownership_controls" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Access logs del bucket de logs de CloudFront — apuntan de vuelta al bucket de logs del ALB (logging cruzado).
resource "aws_s3_bucket_logging" "cloudfront_logs" {
  bucket        = aws_s3_bucket.cloudfront_logs.id
  target_bucket = aws_s3_bucket.alb_logs.id
  target_prefix = "s3-access/cloudfront-logs/"
}

resource "aws_s3_bucket_versioning" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  versioning_configuration { status = "Enabled" }
}

# Cifrado del bucket de logs de CloudFront con KMS.
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudfront_logs" {
  bucket                  = aws_s3_bucket.cloudfront_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Borra los logs de CloudFront a los 365 días y limpia uploads multipart abandonados.
resource "aws_s3_bucket_lifecycle_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    expiration { days = 365 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

# Bloquea cualquier acceso sin SSL al bucket de logs de CloudFront.
resource "aws_s3_bucket_policy" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyNonSSL"
      Effect = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.cloudfront_logs.arn, "${aws_s3_bucket.cloudfront_logs.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}
