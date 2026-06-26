# Agrupa las 2 subnets privadas de base de datos (una por AZ) — Aurora exige al menos 2 AZ en el subnet group.
resource "aws_db_subnet_group" "main" {
  name        = "${var.name_prefix}-db-subnet-group"
  description = "Aurora DB subnet group"
  subnet_ids  = var.db_subnet_ids

  tags = { Name = "${var.name_prefix}-db-subnet-group" }
}

# Parámetros custom del motor PostgreSQL: log de todas las queries, log de queries lentas (>1s) y SSL obligatorio.
resource "aws_rds_cluster_parameter_group" "main" {
  name        = "${var.name_prefix}-cluster-params"
  family      = "aurora-postgresql16"
  description = "Aurora PostgreSQL 16 cluster parameters"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = { Name = "${var.name_prefix}-cluster-params" }
}

# El cluster de Aurora Serverless v2 (PostgreSQL): cifrado con KMS, backups de 7 días, snapshot final y deletion protection.
resource "aws_rds_cluster" "main" {
  #checkov:skip=CKV2_AWS_8:El cluster ya tiene backups nativos automaticos (backup_retention_period=7, snapshot final, deletion_protection); un AWS Backup plan seria redundante
  cluster_identifier = "${var.name_prefix}-aurora-cluster"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "16.4"
  database_name      = var.db_name

  master_username = var.db_master_username
  master_password = var.db_master_password

  db_subnet_group_name            = aws_db_subnet_group.main.name
  vpc_security_group_ids          = [var.security_group_id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  # Serverless v2 scaling
  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 2
  }

  # Backups
  backup_retention_period   = 7
  preferred_backup_window   = "03:00-04:00"
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-final-snapshot"
  deletion_protection       = true

  iam_database_authentication_enabled = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  preferred_maintenance_window = "sun:05:00-sun:06:00"

  tags = { Name = "${var.name_prefix}-aurora-cluster" }
}

# Instancia primaria de Aurora, en la AZ A (us-east-2a) — la que normalmente atiende las queries.
resource "aws_rds_cluster_instance" "primary" {
  identifier           = "${var.name_prefix}-aurora-primary"
  cluster_identifier   = aws_rds_cluster.main.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.main.engine
  engine_version       = aws_rds_cluster.main.engine_version
  availability_zone    = "us-east-2a"
  publicly_accessible  = false
  monitoring_interval  = 60
  monitoring_role_arn  = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn
  auto_minor_version_upgrade      = true

  tags = { Name = "${var.name_prefix}-aurora-primary" }
}

# Instancia secundaria (reader/failover), en la AZ B (us-east-2b) — es el "Multi-AZ" que pidió el ingeniero, listo para tomar el rol de primary si la AZ A falla.
resource "aws_rds_cluster_instance" "secondary" {
  identifier           = "${var.name_prefix}-aurora-secondary"
  cluster_identifier   = aws_rds_cluster.main.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.main.engine
  engine_version       = aws_rds_cluster.main.engine_version
  availability_zone    = "us-east-2b"
  publicly_accessible  = false
  monitoring_interval  = 60
  monitoring_role_arn  = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn
  auto_minor_version_upgrade      = true

  tags = { Name = "${var.name_prefix}-aurora-secondary" }
}


# Rol que usa RDS para escribir las métricas de Enhanced Monitoring (CPU, I/O, memoria al detalle) a CloudWatch.
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.name_prefix}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Política administrada de AWS que habilita el Enhanced Monitoring para el rol de arriba.
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
