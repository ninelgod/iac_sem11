data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- SNS Topic for Alarms ---

resource "aws_sns_topic" "alarms" {
  name              = "${var.name_prefix}-alarms"
  kms_master_key_id = var.kms_key_arn

  tags = { Name = "${var.name_prefix}-alarms" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# --- CloudWatch Log Groups ---

resource "aws_cloudwatch_log_group" "ecs_usuarios" {
  name              = "/ecs/${var.name_prefix}/usuarios"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
  tags              = { Name = "${var.name_prefix}-ecs-usuarios-logs" }
}

resource "aws_cloudwatch_log_group" "ecs_pagos" {
  name              = "/ecs/${var.name_prefix}/pagos"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
  tags              = { Name = "${var.name_prefix}-ecs-pagos-logs" }
}

resource "aws_cloudwatch_log_group" "ecs_reportes" {
  name              = "/ecs/${var.name_prefix}/reportes"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
  tags              = { Name = "${var.name_prefix}-ecs-reportes-logs" }
}

resource "aws_cloudwatch_log_group" "aurora" {
  name              = "/aws/rds/cluster/${var.name_prefix}/postgresql"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
  tags              = { Name = "${var.name_prefix}-aurora-logs" }
}

# --- S3 Bucket for ALB Access Logs ---

resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.name_prefix}-alb-access-logs"
  force_destroy = false

  tags = { Name = "${var.name_prefix}-alb-access-logs" }
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
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

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    expiration { days = 365 }
  }
}

# ALB access logging policy — AWS ELB service account needs write access
data "aws_elb_service_account" "main" {}

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

# --- S3 Bucket for CloudFront Logs ---

resource "aws_s3_bucket" "cloudfront_logs" {
  bucket        = "${var.name_prefix}-cloudfront-access-logs"
  force_destroy = false

  tags = { Name = "${var.name_prefix}-cloudfront-access-logs" }
}

resource "aws_s3_bucket_versioning" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
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

resource "aws_s3_bucket_lifecycle_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    expiration { days = 365 }
  }
}

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

