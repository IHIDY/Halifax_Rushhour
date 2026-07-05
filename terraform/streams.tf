# ── CloudWatch Log Group ──────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "streams" {
  name              = "/aws/lambda/${local.streams_name}"
  retention_in_days = 7
  tags              = { Project = local.project }
}

# ── IAM Role: S3 PutObject only ───────────────────────────────────────────────
resource "aws_iam_role" "streams" {
  name               = "${local.streams_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = { Project = local.project }
}

resource "aws_iam_role_policy" "streams_s3" {
  name = "s3-put-only"
  role = aws_iam_role.streams.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PutObjectOnly"
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.data_lake.arn}/scores/*"
    }]
  })
}

resource "aws_iam_role_policy" "streams_dynamo_read" {
  name = "dynamo-stream-read"
  role = aws_iam_role.streams.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadStream"
      Effect = "Allow"
      Action = [
        "dynamodb:GetRecords",
        "dynamodb:GetShardIterator",
        "dynamodb:DescribeStream",
        "dynamodb:ListStreams"
      ]
      Resource = aws_dynamodb_table.transit_scores.stream_arn
    }]
  })
}

resource "aws_iam_role_policy" "streams_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.streams.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.streams.arn}:*"
    }]
  })
}

# ── Lambda ────────────────────────────────────────────────────────────────────
data "archive_file" "streams_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/streams"
  output_path = "${local.build_dir}/streams.zip"
}

resource "aws_lambda_function" "streams" {
  function_name    = local.streams_name
  role             = aws_iam_role.streams.arn
  runtime          = "python3.12"
  handler          = "streams_lambda.handler"
  filename         = data.archive_file.streams_zip.output_path
  source_code_hash = data.archive_file.streams_zip.output_base64sha256
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      DATA_LAKE_BUCKET = aws_s3_bucket.data_lake.bucket
    }
  }

  depends_on = [aws_cloudwatch_log_group.streams]
  tags       = { Project = local.project }
}

# ── Event Source Mapping: DynamoDB Stream → Lambda ───────────────────────────
resource "aws_lambda_event_source_mapping" "dynamo_stream" {
  event_source_arn  = aws_dynamodb_table.transit_scores.stream_arn
  function_name     = aws_lambda_function.streams.arn
  starting_position = "LATEST"
  batch_size        = 100          # process up to 100 records per invocation
  bisect_batch_on_function_error = true
}
