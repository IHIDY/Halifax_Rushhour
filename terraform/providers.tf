terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "ca-central-1"
}

locals {
  project        = "CSCI4149-Transit"
  table_name     = "TransitScores"
  ingestor_name  = "halifax-transit-ingestor"
  api_name       = "halifax-transit-api"
  stage_name     = "v1"
  streams_name   = "halifax-transit-streams"
  build_dir      = "${path.module}/build"
}
