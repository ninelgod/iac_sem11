locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

module "kms" {
  source      = "./modules/kms"
  name_prefix = local.name_prefix
  aws_region  = var.aws_region
}

module "networking" {
  source                  = "./modules/networking"
  name_prefix             = local.name_prefix
  vpc_cidr                = var.vpc_cidr
  availability_zones      = var.availability_zones
  public_subnet_cidrs     = var.public_subnet_cidrs
  private_subnet_cidrs    = var.private_subnet_cidrs
  private_db_subnet_cidrs = var.private_db_subnet_cidrs
  kms_key_id              = module.kms.cloudwatch_key_arn
}

module "security_groups" {
  source      = "./modules/security_groups"
  name_prefix = local.name_prefix
  vpc_id      = module.networking.vpc_id
  vpc_cidr    = var.vpc_cidr
}

module "ecr" {
  source      = "./modules/ecr"
  name_prefix = local.name_prefix
  kms_key_arn = module.kms.ecr_key_arn
  services    = ["usuarios", "pagos", "reportes"]
}

module "secrets" {
  source              = "./modules/secrets"
  name_prefix         = local.name_prefix
  kms_key_arn         = module.kms.secrets_key_arn
  db_name             = var.db_name
  db_master_username  = var.db_master_username
  vpc_id              = module.networking.vpc_id
  subnet_ids          = module.networking.private_subnet_ids
}

module "waf" {
  source      = "./modules/waf"
  name_prefix = local.name_prefix

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

module "alb" {
  source            = "./modules/alb"
  name_prefix       = local.name_prefix
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  security_group_id = module.security_groups.alb_sg_id
  certificate_arn   = var.certificate_arn
  waf_acl_arn       = module.waf.alb_waf_acl_arn
  logs_bucket       = module.monitoring.alb_logs_bucket
}

module "cognito" {
  source      = "./modules/cognito"
  name_prefix = local.name_prefix
}

module "aurora" {
  source               = "./modules/aurora"
  name_prefix          = local.name_prefix
  db_subnet_ids        = module.networking.private_db_subnet_ids
  security_group_id    = module.security_groups.aurora_sg_id
  db_name              = var.db_name
  db_master_username   = var.db_master_username
  db_master_password   = module.secrets.db_master_password
  kms_key_arn          = module.kms.rds_key_arn
  cloudwatch_log_group = module.monitoring.aurora_log_group_name
}

module "ecs" {
  source             = "./modules/ecs"
  name_prefix        = local.name_prefix
  aws_region         = var.aws_region
  private_subnet_ids = module.networking.private_subnet_ids
  security_group_id     = module.security_groups.ecs_sg_id
  alb_target_group_arns = module.alb.target_group_arns
  ecr_repository_urls   = module.ecr.repository_urls
  ecr_image_tag         = var.ecr_image_tag
  kms_key_arn           = module.kms.cloudwatch_key_arn
  secrets_arn           = module.secrets.db_secret_arn
  cognito_user_pool_id  = module.cognito.user_pool_id
  aurora_endpoint       = module.aurora.cluster_endpoint
  db_name               = var.db_name
}

module "frontend" {
  source                     = "./modules/frontend"
  name_prefix                = local.name_prefix
  domain_name                = var.domain_name
  cloudfront_certificate_arn = var.cloudfront_certificate_arn
  waf_acl_arn                = module.waf.cloudfront_waf_acl_arn
  logs_bucket                = module.monitoring.cloudfront_logs_bucket
  kms_key_arn                = module.kms.s3_key_arn
}

module "monitoring" {
  source      = "./modules/monitoring"
  name_prefix = local.name_prefix
  kms_key_arn = module.kms.cloudwatch_key_arn
  alarm_email = var.alarm_email
}

# --- CloudWatch Alarms (standalone para evitar ciclo alb <-> monitoring) ---

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name_prefix}-alb-5xxErrorRate"
  alarm_description   = "ALB 5xx error rate exceeds 1%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 1
  treat_missing_data  = "notBreaching"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  dimensions          = { LoadBalancer = module.alb.alb_arn_suffix }
  alarm_actions       = [module.monitoring.alarm_topic_arn]
  ok_actions          = [module.monitoring.alarm_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_4xx" {
  alarm_name          = "${local.name_prefix}-alb-4xxErrorRate"
  alarm_description   = "ALB 4xx error rate exceeds 5%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 5
  treat_missing_data  = "notBreaching"
  metric_name         = "HTTPCode_ELB_4XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  dimensions          = { LoadBalancer = module.alb.alb_arn_suffix }
  alarm_actions       = [module.monitoring.alarm_topic_arn]
  ok_actions          = [module.monitoring.alarm_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "${local.name_prefix}-alb-OriginLatency"
  alarm_description   = "ALB target response time (p95) exceeds 2 seconds"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 2
  treat_missing_data  = "notBreaching"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p95"
  dimensions          = { LoadBalancer = module.alb.alb_arn_suffix }
  alarm_actions       = [module.monitoring.alarm_topic_arn]
  ok_actions          = [module.monitoring.alarm_topic_arn]
}
