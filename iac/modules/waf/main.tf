# --- WAF for ALB (REGIONAL) ---

# Web ACL regional asociado al ALB: filtra requests maliciosos antes de que lleguen a ECS.
resource "aws_wafv2_web_acl" "alb" {
  name  = "${var.name_prefix}-alb-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # Regla administrada de AWS: bloquea ataques web comunes (OWASP Top 10 genérico).
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-CRS"
      sampled_requests_enabled   = true
    }
  }

  # Regla administrada: bloquea patrones de entradas maliciosas conocidas (incluye cobertura para Log4j/Log4Shell).
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-KBI"
      sampled_requests_enabled   = true
    }
  }

  # Regla administrada: bloquea intentos de inyección SQL.
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-SQLi"
      sampled_requests_enabled   = true
    }
  }

  # Regla propia: bloquea una IP si supera 2000 requests en la ventana de evaluación (anti fuerza bruta/DoS básico).
  rule {
    name     = "RateLimitRule"
    priority = 4
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-alb-waf"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${var.name_prefix}-alb-waf" }
}

# Manda los logs de las decisiones del WAF (qué bloqueó, qué dejó pasar) a CloudWatch, redactando el header Authorization.
resource "aws_wafv2_web_acl_logging_configuration" "alb" {
  log_destination_configs = [aws_cloudwatch_log_group.waf_alb.arn]
  resource_arn            = aws_wafv2_web_acl.alb.arn

  redacted_fields {
    single_header { name = "authorization" }
  }
}

# Log group donde caen los logs del WAF del ALB.
resource "aws_cloudwatch_log_group" "waf_alb" {
  name              = "aws-waf-logs-${var.name_prefix}-alb"
  retention_in_days = 365
}

# --- WAF for CloudFront (CLOUDFRONT must be us-east-1) ---
# NOTE: CloudFront WAF must be created in us-east-1 via a separate provider alias.
# Here we output a placeholder ARN; teams should deploy waf/cloudfront in a us-east-1 stack.
# See: modules/waf/cloudfront_waf/main.tf for the us-east-1 WAF resource.

# Web ACL global (scope CLOUDFRONT) asociado a la distribución de CloudFront. AWS exige que viva en us-east-1 sí o sí.
resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us_east_1
  name     = "${var.name_prefix}-cf-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Misma regla de ataques web comunes, aplicada al tráfico que entra por CloudFront.
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-cf-CRS"
      sampled_requests_enabled   = true
    }
  }

  # Misma regla de inputs maliciosos conocidos (cobertura Log4j) pero del lado de CloudFront.
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-cf-KBI"
      sampled_requests_enabled   = true
    }
  }

  # Rate limiting propio para el tráfico del frontend (límite más alto que el del ALB porque es contenido estático cacheado).
  rule {
    name     = "RateLimitCF"
    priority = 3
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 3000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-cf-RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-cf-waf"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${var.name_prefix}-cf-waf" }
}
