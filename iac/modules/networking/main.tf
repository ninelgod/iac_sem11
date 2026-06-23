data "aws_caller_identity" "current" {}

# La VPC principal donde vive toda la infraestructura del proyecto.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

# --- Public Subnets ---

# Subnets públicas (una por AZ) donde viven el ALB y los NAT Gateways.
resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = { Name = "${var.name_prefix}-public-${var.availability_zones[count.index]}" }
}

# --- Private Subnets (ECS) ---

# Subnets privadas (una por AZ) donde corren las tareas Fargate de ECS, sin IP pública.
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = { Name = "${var.name_prefix}-private-${var.availability_zones[count.index]}" }
}

# --- Private DB Subnets (Aurora) ---

# Subnets privadas dedicadas a la base de datos (una por AZ), aisladas incluso de las subnets de ECS.
resource "aws_subnet" "private_db" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_db_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = { Name = "${var.name_prefix}-private-db-${var.availability_zones[count.index]}" }
}

# --- Internet Gateway ---

# Puerta de salida/entrada a internet para las subnets públicas.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

# --- NAT Gateways (one per AZ for HA) ---

# IP elástica fija para cada NAT Gateway (una por AZ).
resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-nat-eip-${count.index}" }
}

# NAT Gateway por AZ: permite que las subnets privadas salgan a internet (ej. para llamar a KMS) sin recibir tráfico entrante.
resource "aws_nat_gateway" "main" {
  count         = length(var.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = { Name = "${var.name_prefix}-nat-${var.availability_zones[count.index]}" }
  depends_on = [aws_internet_gateway.main]
}

# --- Route Tables ---

# Tabla de rutas para las subnets públicas.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-rt-public" }
}

# Ruta default (0.0.0.0/0) de las subnets públicas hacia el Internet Gateway.
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Asocia cada subnet pública con la tabla de rutas pública.
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Una tabla de rutas privada por AZ (para que cada subnet privada salga por SU propio NAT Gateway).
resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-rt-private-${var.availability_zones[count.index]}" }
}

# Ruta default de cada subnet privada hacia su NAT Gateway correspondiente.
resource "aws_route" "private_nat" {
  count                  = length(var.availability_zones)
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
}

# Asocia cada subnet privada (ECS) con su tabla de rutas privada.
resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Tabla de rutas para las subnets de base de datos (sin ruta a internet — Aurora no necesita salir).
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-rt-private-db" }
}

# Asocia las subnets de DB con su tabla de rutas (aislada, sin salida a internet).
resource "aws_route_table_association" "private_db" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}

# --- VPC Endpoints ---

# Security Group de los VPC Endpoints: solo acepta HTTPS desde las subnets privadas/DB.
resource "aws_security_group" "vpc_endpoint" {
  name        = "${var.name_prefix}-vpce-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from private subnets"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = concat(var.private_subnet_cidrs, var.private_db_subnet_cidrs)
  }

  egress {
    description = "No outbound needed for interface endpoints"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["127.0.0.1/32"]
  }

  tags = { Name = "${var.name_prefix}-vpce-sg" }
}

# Endpoint privado a la API de ECR (autenticación) — evita salir a internet para hablar con ECR.
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-vpce-ecr-api" }
}

# Endpoint privado al registro Docker de ECR (pull de imágenes de los contenedores).
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-vpce-ecr-dkr" }
}

# Endpoint privado a CloudWatch Logs (los contenedores mandan logs sin pasar por el NAT/internet).
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-vpce-logs" }
}

# Endpoint privado a Secrets Manager (los servicios leen las credenciales de Aurora sin salir a internet).
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-vpce-secretsmanager" }
}

# Endpoint Gateway (gratis) a S3 — usado por ECS/CloudFront para acceder a buckets sin salir a internet.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = { Name = "${var.name_prefix}-vpce-s3" }
}

data "aws_region" "current" {}

# --- VPC Flow Logs ---

# Log group donde se guardan los Flow Logs (registro de todo el tráfico de red de la VPC).
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.name_prefix}/flow-logs"
  retention_in_days = 365
  kms_key_id        = var.kms_key_id

  tags = { Name = "${var.name_prefix}-flow-logs" }
}

# Rol que asume el servicio de VPC Flow Logs para poder escribir en CloudWatch.
resource "aws_iam_role" "flow_logs" {
  name = "${var.name_prefix}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Permisos del rol de Flow Logs: solo puede escribir en su propio log group.
resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.name_prefix}-vpc-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
    }]
  })
}

# Activa el registro de Flow Logs (todo el tráfico, ACCEPT y REJECT) para toda la VPC.
resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = { Name = "${var.name_prefix}-flow-log" }
}

# Bloquea el Security Group "default" que AWS crea automáticamente con la VPC (sin reglas = no permite ningún tráfico).
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-default-sg-lockdown" }
}
