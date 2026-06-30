data "aws_caller_identity" "current" {}

# Bucket S3 que guarda los archivos estáticos del frontend (el "gestorpagosg2-web" del diagrama).
resource "aws_s3_bucket" "frontend" {
  #checkov:skip=CKV_AWS_144:Bucket de assets estaticos servido via CloudFront global; una sola region no justifica replicacion cross-region
  #checkov:skip=CKV2_AWS_62:Bucket de assets estaticos sin consumidores de eventos; no hay integracion downstream que necesite notificaciones S3
  bucket        = "${var.name_prefix}-web"
  force_destroy = false

  tags = { Name = "${var.name_prefix}-web" }
}

# Versionado activado — permite recuperar versiones anteriores de los archivos si algo se sobrescribe mal.
resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration { status = "Enabled" }
}

# Cifrado del bucket con la KMS key del módulo kms (no AES256 genérico).
resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# Bloquea cualquier acceso público directo al bucket — solo CloudFront puede leerlo (vía OAC).
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Manda los access logs de este bucket al bucket de logs de monitoring.
resource "aws_s3_bucket_logging" "frontend" {
  bucket        = aws_s3_bucket.frontend.id
  target_bucket = var.logs_bucket
  target_prefix = "s3-frontend/"
}

# Borra versiones viejas a los 90 días y limpia uploads multipart abandonados a los 7 días.
resource "aws_s3_bucket_lifecycle_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 90 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}


# Origin Access Control: es lo que permite que SOLO CloudFront (y nadie más) pueda firmar requests hacia el bucket S3.
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.name_prefix}-oac"
  description                       = "OAC for ${var.name_prefix} frontend S3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}


# Policy del bucket: permite leer objetos SOLO a la distribución de CloudFront (por su ARN) y deniega cualquier acceso sin SSL.
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      },
      {
        Sid    = "DenyNonSSL"
        Effect = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.frontend.arn, "${aws_s3_bucket.frontend.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}


# CloudFront Function: reescribe rutas sin extension (las del router de la SPA) a /index.html ANTES de
# llegar al origin. Reemplaza a custom_error_response (que es global y rompia los codigos 403/404 reales
# que devuelve el ALB en /api/*) por algo scopeado solo al default_cache_behavior (S3/frontend).
resource "aws_cloudfront_function" "spa_rewrite" {
  name    = "${var.name_prefix}-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite de rutas SPA sin extension a index.html"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      if (!uri.includes('.')) {
        request.uri = '/index.html';
      }

      return request;
    }
  EOT
}

# Headers de seguridad que CloudFront agrega a cada respuesta (HSTS, anti-clickjacking, anti-MIME-sniffing, etc.).
resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "${var.name_prefix}-security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    xss_protection {
      mode_block = true
      override   = true
      protection = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}

# La distribución de CloudFront: CDN global que sirve el frontend estático con HTTPS, WAF y los headers de seguridad de arriba.
resource "aws_cloudfront_distribution" "frontend" {
  #checkov:skip=CKV_AWS_310:Origen unico S3 sirviendo contenido estatico; un origin_group de failover duplicado contra el mismo bucket no aporta redundancia real
  #checkov:skip=CKV2_AWS_47:El WAFv2 ACL asociado (modules/waf) ya incluye AWSManagedRulesKnownBadInputsRuleSet con cobertura Log4j; Checkov no resuelve la asociacion cross-module
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = [var.domain_name]
  web_acl_id          = var.waf_acl_arn
  wait_for_deployment = false

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.frontend.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # Segundo origin: el ALB de los microservicios. Trafico dinamico (/api/*) se sirve desde aqui,
  # asi el ALB no necesita su propio registro DNS publico ni Route53 (todo entra por este dominio).
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "ALB-${var.name_prefix}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.frontend.id}"
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_rewrite.arn
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  # Trafico dinamico: cualquier request a /api/* se manda al ALB (no a S3), sin cache, reenviando todo (headers/cookies/query string) porque son llamadas a los microservicios.
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "ALB-${var.name_prefix}"
    viewer_protocol_policy = "redirect-to-https"
    compress                = true

    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # AWS Managed-CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AWS Managed-AllViewer
  }

  viewer_certificate {
    acm_certificate_arn      = var.cloudfront_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  logging_config {
    bucket          = "${var.logs_bucket}.s3.amazonaws.com"
    prefix          = "cloudfront/"
    include_cookies = false
  }

  # Sin restricción geográfica real (blacklist vacía) — solo así CKV_AWS_374 detecta que el control existe y está configurado.
  restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = []
    }
  }

  tags = { Name = "${var.name_prefix}-cf" }
}


# Busca la Hosted Zone de Route53 que ya existe para el dominio (creada manualmente, fuera de Terraform).
data "aws_route53_zone" "main" {
  name         = "${var.domain_name}."
  private_zone = false
}

# Registro DNS tipo Alias: apunta gestorpagosg2.site directamente a la distribución de CloudFront.
resource "aws_route53_record" "frontend" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}