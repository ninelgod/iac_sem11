data "aws_caller_identity" "current" {}

locals {
  services = {
    usuarios = { cpu = 256, memory = 512,  port = 3000 }
    pagos    = { cpu = 512, memory = 1024, port = 3001 }
    reportes = { cpu = 256, memory = 512,  port = 3002 }
  }
}

# --- ECS Cluster ---

resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.name_prefix}-cluster" }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# --- Service Connect Namespace ---

resource "aws_service_discovery_http_namespace" "main" {
  name        = "${var.name_prefix}-namespace"
  description = "ECS Service Connect namespace for ${var.name_prefix}"
  tags        = { Name = "${var.name_prefix}-namespace" }
}

# --- IAM Roles ---

resource "aws_iam_role" "execution" {
  name = "${var.name_prefix}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution_basic" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  name = "${var.name_prefix}-execution-secrets"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.secrets_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [var.kms_key_arn]
      }
    ]
  })
}

resource "aws_iam_role" "task" {
  name = "${var.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        ArnLike = {
          "aws:SourceArn" = "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "task" {
  name = "${var.name_prefix}-ecs-task-policy"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.name_prefix}/*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.secrets_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
                    "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
        Resource = "*"
      }
    ]
  })
}

# --- Task Definitions ---

resource "aws_ecs_task_definition" "service" {
  for_each = local.services

  family                   = "${var.name_prefix}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = "${var.ecr_repository_urls[each.key]}:${var.ecr_image_tag}"
      essential = true
      readonlyRootFilesystem = true

      portMappings = [{
        name          = each.key
        containerPort = each.value.port
        protocol      = "tcp"
        appProtocol   = "http"
      }]

      environment = [
        { name = "NODE_ENV",              value = "production" },
        { name = "PORT",                  value = tostring(each.value.port) },
        { name = "COGNITO_USER_POOL_ID",  value = var.cognito_user_pool_id },
        { name = "AWS_REGION",            value = var.aws_region },
        { name = "DB_NAME",               value = var.db_name },
        { name = "DB_HOST",               value = var.aurora_endpoint }
      ]

      secrets = [
        {
          name      = "DB_USERNAME"
          valueFrom = "${var.secrets_arn}:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${var.secrets_arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.name_prefix}/${each.key}"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      user = "1000"

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${each.value.port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = { Name = "${var.name_prefix}-${each.key}" }
}

# --- ECS Services ---

resource "aws_ecs_service" "service" {
  for_each = local.services

  name            = "${var.name_prefix}-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.service[each.key].arn
  desired_count   = 2

  launch_type = "FARGATE"

  enable_execute_command = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_target_group_arns[each.key]
    container_name   = each.key
    container_port   = each.value.port
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn

    service {
      port_name      = each.key
      discovery_name = each.key

      client_alias {
        port     = each.value.port
        dns_name = each.key
      }
    }

    log_configuration {
      log_driver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.name_prefix}/${each.key}"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "service-connect"
      }
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  tags = { Name = "${var.name_prefix}-${each.key}" }
}

# --- Auto Scaling ---

resource "aws_appautoscaling_target" "service" {
  for_each = local.services

  max_capacity       = 4
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.service[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each = local.services

  name               = "${var.name_prefix}-${each.key}-cpu-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.service[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.service[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.service[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 70
    scale_in_cooldown  = 60
    scale_out_cooldown = 30

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
