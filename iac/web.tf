# --- ALB: Target Group y listener rule para la app Next.js ---

resource "aws_lb_target_group" "web" {
  #checkov:skip=CKV_AWS_378:Trafico de backend confinado a subnets privadas y solo alcanzable desde la SG del ALB
  name        = "${local.name_prefix}-web-tg"
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
    path                = "/"
    matcher             = "200-404"
  }

  tags = { Name = "${local.name_prefix}-web-tg" }
}

# Rutas /api/auth/* exclusivas de Next.js (reset de contraseña): se resuelven ANTES de que
# la regla de microservicio usuarios (priority 100) las intercepte.
resource "aws_lb_listener_rule" "web_auth_https" {
  listener_arn = module.alb.https_listener_arn
  priority     = 50

  condition {
    path_pattern {
      values = [
        "/api/auth/verify-reset-code",
        "/api/auth/request-password-reset",
        "/api/auth/change-password",
      ]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_listener_rule" "web_auth_http" {
  listener_arn = module.alb.http_listener_arn
  priority     = 50

  condition {
    path_pattern {
      values = [
        "/api/auth/verify-reset-code",
        "/api/auth/request-password-reset",
        "/api/auth/change-password",
      ]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# Regla catch-all HTTPS (prioridad 50000): páginas y APIs de Next.js no capturadas por microservicios.
resource "aws_lb_listener_rule" "web" {
  listener_arn = module.alb.https_listener_arn
  priority     = 50000

  condition {
    path_pattern { values = ["/*"] }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# Regla catch-all HTTP (prioridad 50000): CloudFront conecta al ALB por HTTP (origin_protocol_policy
# = http-only), así que el routing de páginas también necesita existir en el listener HTTP.
resource "aws_lb_listener_rule" "web_http" {
  listener_arn = module.alb.http_listener_arn
  priority     = 50000

  condition {
    path_pattern { values = ["/*"] }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# --- Secrets Manager: variables de entorno de la app Next.js ---

resource "aws_secretsmanager_secret" "web" {
  #checkov:skip=CKV2_AWS_57:RESEND_API_KEY es una API key de tercero (Resend); la rotacion automatica via Lambda no aplica para credenciales externas administradas por el proveedor
  name                    = "${local.name_prefix}/web/app-secrets"
  description             = "Environment variables for the Next.js web app (RESEND_API_KEY)"
  kms_key_id              = module.kms.secrets_key_arn
  recovery_window_in_days = 7

  tags = { Name = "${local.name_prefix}-web-secrets" }
}

resource "aws_secretsmanager_secret_version" "web" {
  secret_id = aws_secretsmanager_secret.web.id

  secret_string = jsonencode({
    RESEND_API_KEY = var.resend_api_key
  })
}

# --- IAM: rol de ejecución exclusivo para la tarea web ---
# La app Next.js accede tanto al secret de Aurora (credenciales DB) como al secret propio
# (RESEND_API_KEY), por lo que necesita su propio execution role con la política correcta.

resource "aws_iam_role" "web_execution" {
  name = "${local.name_prefix}-web-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "web_execution_basic" {
  role       = aws_iam_role.web_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "web_execution_secrets" {
  name = "${local.name_prefix}-web-execution-secrets"
  role = aws_iam_role.web_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [
          aws_secretsmanager_secret.web.arn,
          module.secrets.db_secret_arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [module.kms.secrets_key_arn]
      }
    ]
  })
}

# --- CloudWatch Logs ---

resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${local.name_prefix}/web"
  retention_in_days = 365
  kms_key_id        = module.kms.cloudwatch_key_arn
  tags              = { Name = "${local.name_prefix}-web-logs" }
}

# --- ECS Task Definition ---

resource "aws_ecs_task_definition" "web" {
  family                   = "${local.name_prefix}-web"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.web_execution.arn
  task_role_arn            = module.ecs.task_role_arn

  container_definitions = jsonencode([{
    name      = "web"
    image     = "${module.ecr.repository_urls["web"]}:${var.ecr_image_tag}"
    essential = true

    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]

    environment = [
      { name = "NODE_ENV",              value = "production" },
      { name = "PORT",                  value = "3000" },
      { name = "HOSTNAME",              value = "0.0.0.0" },
      { name = "DB_HOST",               value = module.aurora.cluster_endpoint },
      { name = "DB_NAME",               value = var.db_name },
      { name = "AWS_REGION",            value = var.aws_region },
      { name = "COGNITO_USER_POOL_ID",  value = module.cognito.user_pool_id },
      { name = "COGNITO_CLIENT_ID",     value = module.cognito.client_id },
      { name = "USUARIOS_SERVICE_URL",  value = "http://${module.alb.alb_dns_name}" },
    ]

    secrets = [
      { name = "DB_USERNAME",    valueFrom = "${module.secrets.db_secret_arn}:username::" },
      { name = "DB_PASSWORD",    valueFrom = "${module.secrets.db_secret_arn}:password::" },
      { name = "RESEND_API_KEY", valueFrom = "${aws_secretsmanager_secret.web.arn}:RESEND_API_KEY::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.web.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:3000/ || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = { Name = "${local.name_prefix}-web" }
}

# --- ECS Service ---

resource "aws_ecs_service" "web" {
  name            = "${local.name_prefix}-web"
  cluster         = module.ecs.cluster_arn
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.networking.private_subnet_ids
    security_groups  = [module.security_groups.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = 3000
  }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  depends_on = [aws_iam_role_policy_attachment.web_execution_basic]

  tags = { Name = "${local.name_prefix}-web" }
}
