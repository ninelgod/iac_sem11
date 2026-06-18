data "aws_region" "current" {}

resource "aws_cognito_user_pool" "main" {
  name = "${var.name_prefix}-user-pool"

  # MFA configuration
  mfa_configuration = "OPTIONAL"
  software_token_mfa_configuration {
    enabled = true
  }

  # Password policy
  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Attributes
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Schema
  schema {
    attribute_data_type      = "String"
    name                     = "email"
    required                 = true
    mutable                  = true
    string_attribute_constraints {
      min_length = 5
      max_length = 256
    }
  }

  # Advanced security
  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }

  # Deletion protection
  deletion_protection = "ACTIVE"

  # CloudWatch logs
  lambda_config {}

  tags = { Name = "${var.name_prefix}-user-pool" }
}

resource "aws_cognito_user_pool_client" "api" {
  name         = "${var.name_prefix}-api-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  allowed_oauth_flows_user_pool_client = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # Token validity
  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.name_prefix
  user_pool_id = aws_cognito_user_pool.main.id
}
