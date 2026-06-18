data "archive_file" "rotation_lambda" {
  type        = "zip"
  source_file = "${path.module}/rotation.py"
  output_path = "${path.module}/rotation.zip"
}

resource "random_password" "db_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name_prefix}/aurora/db-credentials"
  description             = "Aurora PostgreSQL master credentials"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 30

  tags = { Name = "${var.name_prefix}-db-secret" }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.db_master.result
    dbname   = var.db_name
    engine   = "aurora-postgresql"
  })
}

resource "aws_secretsmanager_secret_rotation" "db" {
  secret_id           = aws_secretsmanager_secret.db.id
  rotation_lambda_arn = aws_lambda_function.rotate_secret.arn

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [aws_lambda_permission.secrets_manager]
}

# --- Lambda for secret rotation ---

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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

resource "aws_iam_role_policy_attachment" "rotation_lambda_basic" {
  role       = aws_iam_role.rotation_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

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

resource "aws_cloudwatch_log_group" "rotation_lambda" {
  name              = "/aws/lambda/${var.name_prefix}-secret-rotation"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn
}

resource "aws_lambda_function" "rotate_secret" {
  function_name = "${var.name_prefix}-secret-rotation"
  role          = aws_iam_role.rotation_lambda.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  filename         = data.archive_file.rotation_lambda.output_path
  source_code_hash = data.archive_file.rotation_lambda.output_base64sha256

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${data.aws_region.current.name}.amazonaws.com"
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.rotation_lambda]
}

resource "aws_lambda_permission" "secrets_manager" {
  statement_id  = "AllowSecretsManagerInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotate_secret.function_name
  principal     = "secretsmanager.amazonaws.com"
}
