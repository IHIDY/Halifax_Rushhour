# ── SNS Topic for alarm notifications ────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "halifax-transit-alerts"
  tags = { Project = local.project }
}

# ── Ingestor: error rate alarm ────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "ingestor_errors" {
  alarm_name          = "ingestor-error-rate"
  alarm_description   = "Ingestor Lambda error rate > 0 for 2 consecutive minutes"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.ingestor.function_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = { Project = local.project }
}

# ── API Lambda: error rate alarm ──────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "api_errors" {
  alarm_name          = "api-error-rate"
  alarm_description   = "API Lambda error rate > 1% over 5 minutes"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.api_handler.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = { Project = local.project }
}

# ── API Lambda: p95 latency alarm ─────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "api_latency_p95" {
  alarm_name          = "api-p95-latency"
  alarm_description   = "API Lambda p95 latency > 200ms"
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  dimensions          = { FunctionName = aws_lambda_function.api_handler.function_name }
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 3
  threshold           = 200
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = { Project = local.project }
}

# ── DynamoDB: throttled requests alarm ───────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "dynamo_throttles" {
  alarm_name          = "dynamodb-throttled-requests"
  alarm_description   = "DynamoDB throttled requests > 0 — unexpected for PAY_PER_REQUEST"
  namespace           = "AWS/DynamoDB"
  metric_name         = "ThrottledRequests"
  dimensions          = { TableName = local.table_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = { Project = local.project }
}

# ── Streams Lambda: error alarm ───────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "streams_errors" {
  alarm_name          = "streams-error-rate"
  alarm_description   = "Streams Lambda error — S3 archival may be falling behind"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.streams.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = { Project = local.project }
}
