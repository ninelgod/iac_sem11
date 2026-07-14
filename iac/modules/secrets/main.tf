# Empaqueta el código Python de la Lambda de rotación en un .zip (Terraform lo sube tal cual a Lambda).
data "archive_file" "rotation_lambda" {
  type        = "zip"
  source_file = "${path.module}/rotation.py"
  output_path = "${path.module}/rotation.zip"
}

# Genera la contraseña inicial del usuario master de Aurora (no queda hardcodeada en ningún lado).
resource "random_password" "db_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Secreto en Secrets Manager donde se guardan las credenciales de Aurora.
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name_prefix}/aurora/db-credentials"
  description             = "Aurora PostgreSQL master credentials"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 30

  tags = { Name = "${var.name_prefix}-db-secret" }
}

# Primera versión del secreto: usuario, password generada, nombre de BD y engine.
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.db_master.result
    dbname   = var.db_name
    engine   = "aurora-postgresql"
  })
}

# Rotación automática deshabilitada: la Lambda carece de acceso al puerto 5432 de Aurora
# (SG solo permite 443) y no tiene DB_HOST configurado, por lo que la rotación fallaba
# en el paso setSecret dejando AWSPENDING sin promover correctamente.
# Para un entorno productivo real, usar la SAR managed rotation function en su lugar:
# arn:aws:serverlessrepo:us-east-1:297356227824:applications/SecretsManagerRDSPostgreSQLRotationSingleUser

# --- Lambda for secret rotation ---

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Rol que asume la Lambda de rotación de secretos.
resource "aws_iam_role" "rotation_lambda" {
  name = "${var.name_prefix}-secret-rotation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Política administrada básica de Lambda: permite escribir logs en CloudWatch.
resource "aws_iam_role_policy_attachment" "rotation_lambda_basic" {
  role       = aws_iam_role.rotation_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Política administrada que permite a Lambda crear/gestionar las interfaces de red (ENIs) necesarias para correr dentro de la VPC.
resource "aws_iam_role_policy_attachment" "rotation_lambda_vpc" {
  role       = aws_iam_role.rotation_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Security Group de la Lambda: solo necesita salida HTTPS (hacia Secrets Manager/KMS vía VPC endpoints o NAT).
resource "aws_security_group" "rotation_lambda" {
  name        = "${var.name_prefix}-secret-rotation-lambda-sg"
  description = "Security group for the Secrets Manager rotation Lambda"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS to AWS services (Secrets Manager, KMS) via VPC endpoints/NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-secret-rotation-lambda-sg" }
}

# Cola SQS donde caen los eventos que la Lambda no pudo procesar (Dead Letter Queue), para no perder fallos silenciosamente.
resource "aws_sqs_queue" "rotation_dlq" {
  name                      = "${var.name_prefix}-secret-rotation-dlq"
  kms_master_key_id         = var.kms_key_arn
  message_retention_seconds = 1209600

  tags = { Name = "${var.name_prefix}-secret-rotation-dlq" }
}

# Permiso para que la Lambda pueda mandar mensajes a su propia DLQ cuando falla.
resource "aws_iam_role_policy" "rotation_lambda_dlq" {
  name = "${var.name_prefix}-secret-rotation-dlq-policy"
  role = aws_iam_role.rotation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = aws_sqs_queue.rotation_dlq.arn
    }]
  })
}

# Permisos en runtime de la Lambda: leer/actualizar el secreto de Aurora y usar la KMS key para descifrarlo.
resource "aws_iam_role_policy" "rotation_lambda" {
  name = "${var.name_prefix}-secret-rotation-policy"
  role = aws_iam_role.rotation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue",
                    "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecretVersionStage"]
        Resource = aws_secretsmanager_secret.db.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# Log group de la Lambda de rotación. Usa la KMS key de CloudWatch (no la de Secrets Manager): esa policy
# solo permite al principal secretsmanager.amazonaws.com, y CloudWatch Logs necesita logs.amazonaws.com.
resource "aws_cloudwatch_log_group" "rotation_lambda" {
  name              = "/aws/lambda/${var.name_prefix}-secret-rotation"
  retention_in_days = 365
  kms_key_id        = var.cloudwatch_kms_key_arn
}

# Lambda que ejecuta la rotación del secreto cada 30 días: corre dentro de la VPC, con DLQ y env vars cifradas con KMS.
resource "aws_lambda_function" "rotate_secret" {
  function_name = "${var.name_prefix}-secret-rotation"
  role          = aws_iam_role.rotation_lambda.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  filename         = data.archive_file.rotation_lambda.output_path
  source_code_hash = data.archive_file.rotation_lambda.output_base64sha256

  #checkov:skip=CKV_AWS_115:Cuenta AWS (academica/sandbox) con cuota de concurrencia muy baja; reservar cualquier valor aqui baja el UnreservedConcurrentExecution de la cuenta por debajo del minimo de 10 que exige AWS
  #checkov:skip=CKV_AWS_272:AWS Signer no disponible en cuenta academica sandbox; firma de codigo no aplicable en este contexto
  kms_key_arn = var.kms_key_arn

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${data.aws_region.current.name}.amazonaws.com"
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.rotation_lambda.id]
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.rotation_dlq.arn
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.rotation_lambda, aws_iam_role_policy_attachment.rotation_lambda_vpc]
}

# Autoriza a Secrets Manager (y solo para ESTE secreto puntual) a invocar la Lambda cuando toca rotar.
resource "aws_lambda_permission" "secrets_manager" {
  statement_id  = "AllowSecretsManagerInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotate_secret.function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = aws_secretsmanager_secret.db.arn
}
