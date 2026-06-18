# --- ALB Security Group ---
resource "aws_security_group" "alb" {
  #checkov:skip=CKV_AWS_260:Puerto 80 requerido para el listener de redirect HTTP->HTTPS; no se sirve contenido de la app por este puerto
  #checkov:skip=CKV2_AWS_5:Atachado via output de modulo (module.security_groups.alb_sg_id) consumido por modules/alb; Checkov no resuelve referencias cross-module
  name        = "${var.name_prefix}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description      = "HTTP redirect only"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    description = "Traffic to ECS tasks"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.name_prefix}-alb-sg" }
}

# --- ECS Tasks Security Group ---
resource "aws_security_group" "ecs" {
  #checkov:skip=CKV2_AWS_5:Atachado via output de modulo (module.security_groups.ecs_sg_id) consumido por modules/ecs; Checkov no resuelve referencias cross-module
  name        = "${var.name_prefix}-ecs-sg"
  description = "Security group for ECS Fargate tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Traffic from ALB only"
    from_port       = 3000
    to_port         = 3002
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "HTTPS to AWS services (ECR, Cognito, Secrets Manager)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "Aurora PostgreSQL"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.aurora.id]
  }

  tags = { Name = "${var.name_prefix}-ecs-sg" }
}

# --- Aurora Security Group ---
resource "aws_security_group" "aurora" {
  #checkov:skip=CKV2_AWS_5:Atachado via output de modulo (module.security_groups.aurora_sg_id) consumido por modules/aurora; Checkov no resuelve referencias cross-module
  name        = "${var.name_prefix}-aurora-sg"
  description = "Security group for Aurora PostgreSQL cluster"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from ECS tasks only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    description = "Deny all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["127.0.0.1/32"]
  }

  tags = { Name = "${var.name_prefix}-aurora-sg" }
}
