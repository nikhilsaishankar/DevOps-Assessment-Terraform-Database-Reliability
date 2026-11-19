###############################################################################
# Remote state bootstrap
#
# Applied once per AWS account, before any environment switches to the S3
# backend. Keeps its own state locally (and committed nowhere), which is the
# usual way out of the chicken-and-egg problem of storing the state of the
# thing that stores state.
#
#   cd infra/bootstrap
#   terraform init
#   terraform apply -var='buckets=["hotelbook-tfstate-dev-ap-south-1","hotelbook-tfstate-prod-ap-south-1"]'
#
# Locking uses the S3 native lock file (use_lockfile = true in backend.hcl),
# so no DynamoDB table is needed.
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "Region to create the state buckets in."
  type        = string
  default     = "ap-south-1"
}

variable "buckets" {
  description = "State bucket names, one per environment."
  type        = list(string)

  default = [
    "hotelbook-tfstate-dev-ap-south-1",
    "hotelbook-tfstate-prod-ap-south-1",
  ]
}

resource "aws_s3_bucket" "state" {
  for_each = toset(var.buckets)

  bucket = each.value

  tags = {
    Name      = each.value
    Purpose   = "terraform-remote-state"
    ManagedBy = "terraform"
  }
}

# State files contain resource attributes, including anything marked sensitive.
# Versioning is what makes a corrupted or truncated state recoverable.
resource "aws_s3_bucket_versioning" "state" {
  for_each = aws_s3_bucket.state

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  for_each = aws_s3_bucket.state

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  for_each = aws_s3_bucket.state

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  for_each = aws_s3_bucket.state

  bucket = each.value.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

output "state_buckets" {
  description = "Created state buckets - use these in each environment's backend.hcl."
  value       = [for b in aws_s3_bucket.state : b.id]
}
