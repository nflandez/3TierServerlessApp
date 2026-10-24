output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "issuer" {
  description = "Token issuer URL that API Gateway checks every JWT against"
  value       = "https://${aws_cognito_user_pool.this.endpoint}"
}

output "hosted_ui_domain" {
  value = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}
