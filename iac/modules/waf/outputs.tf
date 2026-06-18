output "alb_waf_acl_arn" {
  description = "WAF WebACL ARN for ALB (REGIONAL)"
  value       = aws_wafv2_web_acl.alb.arn
}

output "cloudfront_waf_acl_arn" {
  description = "WAF WebACL ARN for CloudFront (CLOUDFRONT scope, us-east-1)"
  value       = aws_wafv2_web_acl.cloudfront.arn
}
