data "aws_caller_identity" "current" {}

# ── S3 Data Lake ──────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "data_lake" {
  bucket = "halifax-transit-scores-${data.aws_caller_identity.current.account_id}"
  tags   = { Project = local.project }
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Suspended"   # not needed for append-only time-series
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket                  = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Lifecycle — 4-tier cost optimisation ─────────────────────────────────────
resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "transit-score-tiering"
    status = "Enabled"

    filter { prefix = "scores/" }

    # Day 0-30: S3 Standard — hot data, frequent dashboard queries
    transition {
      days          = 30
      storage_class = "STANDARD_IA"    # -58% vs Standard
    }

    # Day 30-90: Standard-IA — weekly reporting queries
    transition {
      days          = 90
      storage_class = "GLACIER_IR"     # -68% vs Standard-IA, <ms retrieval
    }

    # Day 90-365: Glacier Instant Retrieval — monthly compliance checks
    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"   # -75% vs Glacier IR, rarely accessed
    }

    # Day 365+: Deep Archive — cold storage, regulatory retention
  }
}

output "data_lake_bucket" {
  value = aws_s3_bucket.data_lake.bucket
}
