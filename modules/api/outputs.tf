output "api_url" {
  value = aws_apigatewayv2_api.this.api_endpoint
}

output "api_id" {
  value = aws_apigatewayv2_api.this.id
}

output "function_name" {
  value = aws_lambda_function.api.function_name
}

output "lambda_log_group" {
  value = aws_cloudwatch_log_group.lambda.name
}
