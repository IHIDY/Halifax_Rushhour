resource "aws_cloudwatch_event_rule" "every_minute" {
  name                = "transit-ingest-every-minute"
  schedule_expression = "rate(1 minute)"
  description         = "Triggers Halifax Transit ingestor Lambda every 60 seconds"
  tags                = { Project = local.project }
}

resource "aws_cloudwatch_event_target" "ingestor_target" {
  rule = aws_cloudwatch_event_rule.every_minute.name
  arn  = aws_lambda_function.ingestor.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_minute.arn
}
