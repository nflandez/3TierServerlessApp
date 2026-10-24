# ---------- Alarm notifications (optional) ----------

resource "aws_sns_topic" "alerts" {
  count = var.alert_email == "" ? 0 : 1
  name  = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  alarm_actions = var.alert_email == "" ? [] : [aws_sns_topic.alerts[0].arn]
}

# ---------- Alarms ----------

# Any unhandled error in the Lambda function
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name}-lambda-errors"
  alarm_description   = "The API Lambda function returned errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# Server-side failures seen by API Gateway
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.name}-api-5xx"
  alarm_description   = "API Gateway returned 5xx errors"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = var.api_id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# Security signal: lots of rejected requests (missing, expired or forged tokens)
resource "aws_cloudwatch_metric_alarm" "api_4xx" {
  alarm_name          = "${var.name}-api-unauthorized-spike"
  alarm_description   = "Many 4xx responses in 5 minutes, possibly someone calling the API without a valid token"
  namespace           = "AWS/ApiGateway"
  metric_name         = "4xx"
  dimensions          = { ApiId = var.api_id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ---------- Dashboard: one page for all three tiers ----------

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type       = "metric"
        x          = 0
        y          = 0
        width      = 12
        height     = 6
        properties = {
          title   = "API Gateway requests and errors"
          region  = var.region
          view    = "timeSeries"
          stat    = "Sum"
          period  = 60
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", var.api_id, { label = "Requests" }],
            ["AWS/ApiGateway", "4xx", "ApiId", var.api_id, { label = "4xx (client / auth errors)" }],
            ["AWS/ApiGateway", "5xx", "ApiId", var.api_id, { label = "5xx (server errors)" }],
          ]
        }
      },
      {
        type       = "metric"
        x          = 12
        y          = 0
        width      = 12
        height     = 6
        properties = {
          title   = "API Gateway latency (ms)"
          region  = var.region
          view    = "timeSeries"
          period  = 60
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiId", var.api_id, { stat = "Average", label = "Average" }],
            ["AWS/ApiGateway", "Latency", "ApiId", var.api_id, { stat = "p90", label = "p90" }],
          ]
        }
      },
      {
        type       = "metric"
        x          = 0
        y          = 6
        width      = 12
        height     = 6
        properties = {
          title   = "Lambda invocations and errors"
          region  = var.region
          view    = "timeSeries"
          stat    = "Sum"
          period  = 60
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", var.function_name],
            ["AWS/Lambda", "Throttles", "FunctionName", var.function_name],
          ]
        }
      },
      {
        type       = "metric"
        x          = 12
        y          = 6
        width      = 12
        height     = 6
        properties = {
          title   = "Lambda duration (ms)"
          region  = var.region
          view    = "timeSeries"
          period  = 60
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.function_name, { stat = "Average", label = "Average" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.function_name, { stat = "Maximum", label = "Max (includes cold starts)" }],
          ]
        }
      },
      {
        type       = "metric"
        x          = 0
        y          = 12
        width      = 12
        height     = 6
        properties = {
          title   = "DynamoDB capacity used"
          region  = var.region
          view    = "timeSeries"
          stat    = "Sum"
          period  = 60
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.table_name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.table_name],
          ]
        }
      },
      {
        type       = "metric"
        x          = 12
        y          = 12
        width      = 12
        height     = 6
        properties = {
          title   = "CloudFront requests (global)"
          region  = "us-east-1" # CloudFront is global and always reports metrics in us-east-1
          view    = "timeSeries"
          stat    = "Sum"
          period  = 300
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", var.cloudfront_dist_id, "Region", "Global"],
          ]
        }
      },
      {
        type       = "log"
        x          = 0
        y          = 18
        width      = 24
        height     = 6
        properties = {
          title  = "Recent Lambda log lines"
          region = var.region
          view   = "table"
          query  = "SOURCE '${var.lambda_log_group}' | fields @timestamp, @message | sort @timestamp desc | limit 20"
        }
      },
    ]
  })
}
