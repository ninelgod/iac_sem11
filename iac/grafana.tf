# --- ALB: Target Group y listener rules para Grafana ---

resource "aws_lb_target_group" "grafana" {
  #checkov:skip=CKV_AWS_378:Trafico de backend confinado a subnets privadas y solo alcanzable desde la SG del ALB
  name        = "${local.name_prefix}-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = module.networking.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    path                = "/grafana/api/health"
    matcher             = "200"
  }

  tags = { Name = "${local.name_prefix}-grafana-tg" }
}

resource "aws_lb_listener_rule" "grafana_https" {
  listener_arn = module.alb.https_listener_arn
  priority     = 70

  condition {
    path_pattern { values = ["/grafana", "/grafana/*"] }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}

resource "aws_lb_listener_rule" "grafana_http" {
  listener_arn = module.alb.http_listener_arn
  priority     = 70

  condition {
    path_pattern { values = ["/grafana", "/grafana/*"] }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}

# --- Secrets Manager ---

resource "aws_secretsmanager_secret" "grafana" {
  #checkov:skip=CKV2_AWS_57:Credencial administrativa de Grafana; rotacion manual gestionada por el equipo de operaciones
  name                    = "${local.name_prefix}/grafana/credentials"
  description             = "Grafana admin password"
  kms_key_id              = module.kms.secrets_key_arn
  recovery_window_in_days = 7

  tags = { Name = "${local.name_prefix}-grafana-secrets" }
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id = aws_secretsmanager_secret.grafana.id
  secret_string = jsonencode({
    admin_password = var.grafana_admin_password
  })
}

# --- IAM: Execution Role (pull imagen ECR + leer secret) ---

resource "aws_iam_role" "grafana_execution" {
  name = "${local.name_prefix}-grafana-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_execution_basic" {
  role       = aws_iam_role.grafana_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "grafana_execution_secrets" {
  name = "${local.name_prefix}-grafana-execution-secrets"
  role = aws_iam_role.grafana_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.grafana.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [module.kms.secrets_key_arn]
      }
    ]
  })
}

# --- IAM: Task Role (acceso de lectura a CloudWatch y Logs Insights) ---

resource "aws_iam_role" "grafana_task" {
  name = "${local.name_prefix}-grafana-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "grafana_cloudwatch" {
  #checkov:skip=CKV_AWS_355:CloudWatch metrics, Logs Insights y EC2 Describe requieren Resource=* porque no tienen ARN por recurso individual en estas acciones de consulta
  #checkov:skip=CKV_AWS_356:CloudWatch metrics, Logs Insights y EC2 Describe requieren Resource=* porque no tienen ARN por recurso individual en estas acciones de consulta
  name = "${local.name_prefix}-grafana-cloudwatch"
  role = aws_iam_role.grafana_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetInsightRuleReport"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- CloudWatch Logs (logs del propio Grafana) ---

resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/${local.name_prefix}/grafana"
  retention_in_days = 365
  kms_key_id        = module.kms.cloudwatch_key_arn
  tags              = { Name = "${local.name_prefix}-grafana-logs" }
}

# --- ECS Task Definition ---

resource "aws_ecs_task_definition" "grafana" {
  family                   = "${local.name_prefix}-grafana"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.grafana_execution.arn
  task_role_arn            = aws_iam_role.grafana_task.arn

  container_definitions = jsonencode([{
    name      = "grafana"
    image     = "${module.ecr.repository_urls["grafana"]}:${var.ecr_image_tag}"
    essential = true

    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]

    environment = [
      { name = "GF_SERVER_ROOT_URL",            value = "https://${var.domain_name}/grafana/" },
      { name = "GF_SERVER_SERVE_FROM_SUB_PATH", value = "true" },
      { name = "GF_AUTH_ANONYMOUS_ENABLED",     value = "false" },
      { name = "GF_SECURITY_ADMIN_USER",        value = "admin" },
    ]

    secrets = [
      { name = "GF_SECURITY_ADMIN_PASSWORD", valueFrom = "${aws_secretsmanager_secret.grafana.arn}:admin_password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.grafana.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:3000/grafana/api/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = { Name = "${local.name_prefix}-grafana" }
}

# --- ECS Service ---

resource "aws_ecs_service" "grafana" {
  name            = "${local.name_prefix}-grafana"
  cluster         = module.ecs.cluster_arn
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.networking.private_subnet_ids
    security_groups  = [module.security_groups.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "grafana"
    container_port   = 3000
  }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  depends_on = [aws_iam_role_policy_attachment.grafana_execution_basic]

  tags = { Name = "${local.name_prefix}-grafana" }
}
