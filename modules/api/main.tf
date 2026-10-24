# ---------- Lambda function ----------

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/build/handler.zip"
}

# Created before the function so logs get a retention period
# (otherwise Lambda auto-creates a log group that keeps logs forever)
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name}-api"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name_prefix        = "${var.name}-lambda-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Least privilege: only the three DynamoDB actions the code uses, on one table,
# plus writing to its own log group
data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid       = "TasksTable"
    actions   = ["dynamodb:Query", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [var.table_arn]
  }

  statement {
    sid       = "OwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "tasks-api"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_lambda_function" "api" {
  function_name    = "${var.name}-api"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = "handler.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  memory_size      = 256
  timeout          = 10

  environment {
    variables = {
      TABLE_NAME = var.table_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy.lambda]
}

# ---------- API Gateway (HTTP API) ----------

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name}-api"
  protocol_type = "HTTP"

  # Browsers may only call the API from the CloudFront site
  cors_configuration {
    allow_origins = [var.allowed_origin]
    allow_methods = ["GET", "POST", "DELETE", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 300
  }
}

# Every route requires a valid Cognito token. API Gateway checks the signature,
# issuer, audience and expiry before Lambda is ever invoked.
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  name             = "cognito"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = var.user_pool_issuer
    audience = [var.client_id]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "routes" {
  for_each = toset(["GET /tasks", "POST /tasks", "DELETE /tasks/{taskId}"])

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${var.name}-api"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  # Basic protection against abuse and runaway costs
  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }

  # One JSON line per request, including who called and why auth failed
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format          = jsonencode({
      requestId   = "$context.requestId"
      time        = "$context.requestTime"
      ip          = "$context.identity.sourceIp"
      route       = "$context.routeKey"
      status      = "$context.status"
      latencyMs   = "$context.responseLatency"
      user        = "$context.authorizer.claims.sub"
      authError   = "$context.authorizer.error"
      lambdaError = "$context.integrationErrorMessage"
    })
  }
}

# Allow this API (and only this API) to invoke the function
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
