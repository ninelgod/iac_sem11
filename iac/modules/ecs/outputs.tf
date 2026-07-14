output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  value = aws_ecs_cluster.main.arn
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "service_names" {
  value = { for k, v in aws_ecs_service.service : k => v.name }
}

output "service_connect_namespace_arn" {
  value = aws_service_discovery_http_namespace.main.arn
}
