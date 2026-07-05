# ── Shared assume-role policy ────────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ── Ingestor role: PutItem only ──────────────────────────────────────────────
resource "aws_iam_role" "ingestor" {
  name               = "${local.ingestor_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = { Project = local.project }
}

resource "aws_iam_role_policy" "ingestor_dynamo" {
  name = "dynamo-put-only"
  role = aws_iam_role.ingestor.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PutItemOnly"
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem"]
      Resource = aws_dynamodb_table.transit_scores.arn
    }]
  })
}

resource "aws_iam_role_policy" "ingestor_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.ingestor.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "WriteLogs"
      Effect = "Allow"
      Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.ingestor.arn}:*"
    }]
  })
}

resource "aws_iam_role_policy" "ingestor_xray" {
  name = "xray-put"
  role = aws_iam_role.ingestor.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "XRayWrite"
      Effect = "Allow"
      Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
      Resource = "*"
    }]
  })
}

# ── API Handler role: Query only ─────────────────────────────────────────────
resource "aws_iam_role" "api_handler" {
  name               = "${local.api_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = { Project = local.project }
}

resource "aws_iam_role_policy" "api_dynamo" {
  name = "dynamo-query-only"
  role = aws_iam_role.api_handler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "QueryOnly"
      Effect   = "Allow"
      Action   = ["dynamodb:Query"]
      Resource = aws_dynamodb_table.transit_scores.arn
    }]
  })
}

resource "aws_iam_role_policy" "api_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.api_handler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "WriteLogs"
      Effect = "Allow"
      Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.api_handler.arn}:*"
    }]
  })
}

resource "aws_iam_role_policy" "api_xray" {
  name = "xray-put"
  role = aws_iam_role.api_handler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "XRayWrite"
      Effect = "Allow"
      Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
      Resource = "*"
    }]
  })
}
