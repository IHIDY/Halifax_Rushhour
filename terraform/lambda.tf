# ── CloudWatch Log Groups (created before Lambda to avoid race condition) ─────
resource "aws_cloudwatch_log_group" "ingestor" {
  name              = "/aws/lambda/${local.ingestor_name}"
  retention_in_days = 7
  tags              = { Project = local.project }
}

resource "aws_cloudwatch_log_group" "api_handler" {
  name              = "/aws/lambda/${local.api_name}"
  retention_in_days = 7
  tags              = { Project = local.project }
}

# ── Ingestor Lambda ───────────────────────────────────────────────────────────
data "archive_file" "ingestor_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/ingestor"
  output_path = "${local.build_dir}/ingestor.zip"
}

resource "aws_lambda_function" "ingestor" {
  function_name    = local.ingestor_name
  role             = aws_iam_role.ingestor.arn
  runtime          = "python3.12"
  handler          = "ingestor_lambda.handler"
  filename         = data.archive_file.ingestor_zip.output_path
  source_code_hash = data.archive_file.ingestor_zip.output_base64sha256
  timeout          = 30
  memory_size      = 256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME  = local.table_name
      GTFS_URL    = "https://gtfs.halifax.ca/realtime/TripUpdate/TripUpdates.pb"
      SCORE_TTL_H = "24"
    }
  }

  depends_on = [aws_cloudwatch_log_group.ingestor]
  tags       = { Project = local.project }
}

# ── API Handler Lambda ────────────────────────────────────────────────────────
data "archive_file" "api_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/api"
  output_path = "${local.build_dir}/api.zip"
}

resource "aws_lambda_function" "api_handler" {
  function_name    = local.api_name
  role             = aws_iam_role.api_handler.arn
  runtime          = "python3.12"
  handler          = "api_lambda.handler"
  filename         = data.archive_file.api_zip.output_path
  source_code_hash = data.archive_file.api_zip.output_base64sha256
  timeout          = 10
  memory_size      = 128
  publish          = true   # required: Provisioned Concurrency needs a versioned alias

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = local.table_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.api_handler]
  tags       = { Project = local.project }
}

resource "aws_lambda_alias" "api_live" {
  name             = "live"
  function_name    = aws_lambda_function.api_handler.function_name
  function_version = aws_lambda_function.api_handler.version
}

resource "aws_lambda_provisioned_concurrency_config" "api_handler" {
  function_name                     = aws_lambda_function.api_handler.function_name
  qualifier                         = aws_lambda_alias.api_live.name
  provisioned_concurrent_executions = 1
}

