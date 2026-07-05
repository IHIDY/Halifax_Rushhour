output "api_endpoint" {
  description = "Base URL — replace {route_id} with a real Halifax route ID (e.g. 1, 2, 10)"
  value       = "https://${aws_api_gateway_rest_api.transit_api.id}.execute-api.ca-central-1.amazonaws.com/${local.stage_name}/routes/{route_id}"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.transit_scores.name
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.transit_scores.arn
}

output "ingestor_lambda_arn" {
  value = aws_lambda_function.ingestor.arn
}

output "api_lambda_arn" {
  value = aws_lambda_function.api_handler.arn
}
