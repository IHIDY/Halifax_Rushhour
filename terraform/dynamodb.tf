resource "aws_dynamodb_table" "transit_scores" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "route_id"
  range_key    = "timestamp"

  attribute {
    name = "route_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  ttl {
    attribute_name = "ttl_epoch"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"   # only new record needed for S3 archival

  server_side_encryption {
    enabled = true   # AES-256 via AWS-owned KMS key
  }

  tags = { Project = local.project }
}
