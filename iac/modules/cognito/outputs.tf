output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "client_id" {
  value = aws_cognito_user_pool_client.api.id
}

output "jwks_uri" {
  description = "JWKS endpoint used by each microservice to validate JWTs"
  value       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/jwks.json"
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.main.arn
}
