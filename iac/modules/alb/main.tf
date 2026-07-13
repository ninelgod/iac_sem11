# El Application Load Balancer público: punto de entrada para el tráfico dinámico/API de los microservicios.
resource "aws_lb" "main" {
  #checkov:skip=CKV2_AWS_76:El WAFv2 ACL asociado (modules/waf) ya incluye AWSManagedRulesKnownBadInputsRuleSet con cobertura Log4j; Checkov no resuelve la asociacion cross-module
  #checkov:skip=CKV_AWS_150:Deletion protection deshabilitada para permitir terraform destroy en entorno academico sin intervencion manual previa
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  drop_invalid_header_fields = true
  enable_cross_zone_load_balancing = true

  access_logs {
    bucket  = var.logs_bucket
    prefix  = "alb"
    enabled = true
  }

  tags = { Name = "${var.name_prefix}-alb" }
}

# Conecta el WAF (modules/waf) con este ALB para que filtre el tráfico antes de llegar a los listeners.
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = var.waf_acl_arn
}

# --- HTTP → HTTPS redirect ---

# Listener en el puerto 80 que solo redirige a HTTPS (301) — nunca sirve contenido por HTTP.
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# --- HTTPS Listener ---

# Listener principal en el puerto 443 (TLS 1.3). Por defecto responde 404; el ruteo real lo hacen las listener rules de abajo.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"not found\"}"
      status_code  = "404"
    }
  }
}

# --- Target Groups ---

# Target Group del microservicio Usuarios (registra las tareas Fargate por IP, healthcheck en /health).
resource "aws_lb_target_group" "usuarios" {
  #checkov:skip=CKV_AWS_378:Trafico de backend confinado a subnets privadas y solo alcanzable desde la SG del ALB; el edge publico ya fuerza HTTPS/TLS1.3 en el listener
  name        = "${var.name_prefix}-usuarios-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    path                = "/health"
    matcher             = "200"
  }

  tags = { Name = "${var.name_prefix}-usuarios-tg" }
}

# Target Group del microservicio Pagos.
resource "aws_lb_target_group" "pagos" {
  #checkov:skip=CKV_AWS_378:Trafico de backend confinado a subnets privadas y solo alcanzable desde la SG del ALB; el edge publico ya fuerza HTTPS/TLS1.3 en el listener
  name        = "${var.name_prefix}-pagos-tg"
  port        = 3001
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    path                = "/health"
    matcher             = "200"
  }

  tags = { Name = "${var.name_prefix}-pagos-tg" }
}

# Target Group del microservicio Reportes.
resource "aws_lb_target_group" "reportes" {
  #checkov:skip=CKV_AWS_378:Trafico de backend confinado a subnets privadas y solo alcanzable desde la SG del ALB; el edge publico ya fuerza HTTPS/TLS1.3 en el listener
  name        = "${var.name_prefix}-reportes-tg"
  port        = 3002
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    path                = "/health"
    matcher             = "200"
  }

  tags = { Name = "${var.name_prefix}-reportes-tg" }
}

# --- Path-based Routing Rules ---

# Si la URL empieza con /api/usuarios/ o /api/auth/, el ALB manda el tráfico al Target Group de Usuarios.
resource "aws_lb_listener_rule" "usuarios" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  condition {
    path_pattern { values = ["/api/usuarios/*", "/api/auth/*"] }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.usuarios.arn
  }
}

# Si la URL empieza con /api/pagos/, el ALB manda el tráfico al Target Group de Pagos.
resource "aws_lb_listener_rule" "pagos" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 200

  condition {
    path_pattern { values = ["/api/pagos/*"] }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pagos.arn
  }
}

# Si la URL empieza con /api/reportes/, el ALB manda el tráfico al Target Group de Reportes.
resource "aws_lb_listener_rule" "reportes" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 300

  condition {
    path_pattern { values = ["/api/reportes/*"] }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.reportes.arn
  }
}

# --- Reglas HTTP para el origin de CloudFront ---
# CloudFront llega a este ALB como origin "custom" por HTTP (no HTTPS): el certificado del listener 443
# es para el dominio publico (gestorpagosg2.site), no para el hostname *.elb.amazonaws.com del ALB, asi
# que TLS fallaria por mismatch de hostname. El tramo CloudFront->ALB queda dentro de la red de AWS;
# el viewer (usuario final) siempre habla HTTPS con CloudFront. Cualquier otra ruta en el puerto 80
# sigue redirigiendo a HTTPS (default_action de aws_lb_listener.http_redirect, sin cambios).

resource "aws_lb_listener_rule" "usuarios_http" {
  listener_arn = aws_lb_listener.http_redirect.arn
  priority     = 100

  condition {
    path_pattern { values = ["/api/usuarios/*", "/api/auth/*"] }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.usuarios.arn
  }
}

resource "aws_lb_listener_rule" "pagos_http" {
  listener_arn = aws_lb_listener.http_redirect.arn
  priority     = 200

  condition {
    path_pattern { values = ["/api/pagos/*"] }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pagos.arn
  }
}

resource "aws_lb_listener_rule" "reportes_http" {
  listener_arn = aws_lb_listener.http_redirect.arn
  priority     = 300

  condition {
    path_pattern { values = ["/api/reportes/*"] }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.reportes.arn
  }
}
