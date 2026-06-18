output "alb_arn" {
  value = aws_lb.main.arn
}

output "alb_arn_suffix" {
  value = aws_lb.main.arn_suffix
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "alb_zone_id" {
  value = aws_lb.main.zone_id
}

output "https_listener_arn" {
  value = aws_lb_listener.https.arn
}

output "target_group_arns" {
  description = "Map of service name to target group ARN"
  value = {
    usuarios = aws_lb_target_group.usuarios.arn
    pagos    = aws_lb_target_group.pagos.arn
    reportes = aws_lb_target_group.reportes.arn
  }
}
