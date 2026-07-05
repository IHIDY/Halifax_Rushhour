resource "aws_api_gateway_rest_api" "transit_api" {
  name        = "Halifax-Transit-API"
  description = "CSCI 4149 — GTFS Realtime Delay Score API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = { Project = local.project }
}

# /routes
resource "aws_api_gateway_resource" "routes" {
  rest_api_id = aws_api_gateway_rest_api.transit_api.id
  parent_id   = aws_api_gateway_rest_api.transit_api.root_resource_id
  path_part   = "routes"
}

# /routes/{route_id}
resource "aws_api_gateway_resource" "route_id" {
  rest_api_id = aws_api_gateway_rest_api.transit_api.id
  parent_id   = aws_api_gateway_resource.routes.id
  path_part   = "{route_id}"
}

resource "aws_api_gateway_method" "get_route" {
  rest_api_id      = aws_api_gateway_rest_api.transit_api.id
  resource_id      = aws_api_gateway_resource.route_id.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = false
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.transit_api.id
  resource_id             = aws_api_gateway_resource.route_id.id
  http_method             = aws_api_gateway_method.get_route.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_alias.api_live.invoke_arn
}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  qualifier     = aws_lambda_alias.api_live.name   # permission scoped to alias, not $LATEST
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.transit_api.execution_arn}/*/*"
}

# ── /health ───────────────────────────────────────────────────────────────────
resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.transit_api.id
  parent_id   = aws_api_gateway_rest_api.transit_api.root_resource_id
  path_part   = "health"
}

resource "aws_api_gateway_method" "get_health" {
  rest_api_id   = aws_api_gateway_rest_api.transit_api.id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "health_integration" {
  rest_api_id             = aws_api_gateway_rest_api.transit_api.id
  resource_id             = aws_api_gateway_resource.health.id
  http_method             = aws_api_gateway_method.get_health.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_alias.api_live.invoke_arn
}

# ── Deployment ────────────────────────────────────────────────────────────────
resource "aws_api_gateway_deployment" "v1" {
  rest_api_id = aws_api_gateway_rest_api.transit_api.id

  # Force redeploy when API definition changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.route_id.id,
      aws_api_gateway_method.get_route.id,
      aws_api_gateway_integration.lambda_integration.id,
      aws_api_gateway_resource.health.id,
      aws_api_gateway_method.get_health.id,
      aws_api_gateway_integration.health_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_integration.lambda_integration]
}

# ── Stage: 15s cache + throttling ────────────────────────────────────────────
resource "aws_api_gateway_stage" "v1" {
  deployment_id         = aws_api_gateway_deployment.v1.id
  rest_api_id           = aws_api_gateway_rest_api.transit_api.id
  stage_name            = local.stage_name
  cache_cluster_enabled = true
  cache_cluster_size    = "0.5"
  xray_tracing_enabled  = true

  tags = { Project = local.project }
}

# aws provider v5.x: method_settings moved to a standalone resource
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.transit_api.id
  stage_name  = aws_api_gateway_stage.v1.stage_name
  method_path = "*/*"

  settings {
    caching_enabled        = true
    cache_ttl_in_seconds   = 15
    throttling_burst_limit = 300
    throttling_rate_limit  = 150
  }
}
