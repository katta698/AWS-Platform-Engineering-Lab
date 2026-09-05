# Remote state — comment out during first-time bootstrap.
# Run `terraform init` locally first, then uncomment and run
# `terraform init -migrate-state` to move state into S3.
#
# Requires Terraform >= 1.10 and AWS provider >= 5.40.
# S3 native locking (use_lockfile = true) uses S3 conditional writes —
# no DynamoDB table needed.

# terraform {
#   backend "s3" {
#     bucket       = "<your-org>-terraform-state-<mgmt-account-id>"
#     key          = "ebs-savings-dashboard/terraform.tfstate"
#     region       = "us-east-1"
#     encrypt      = true
#     kms_key_id   = "<state-bucket-kms-key-arn>"
#     use_lockfile = true   # S3-native locking — no DynamoDB required
#   }
# }

# Bootstrap: create the state bucket once, then enable the backend block above.
resource "aws_s3_bucket" "tfstate" {
  count  = var.bootstrap_state_bucket ? 1 : 0
  bucket = "${var.org_name}-terraform-state-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  count  = var.bootstrap_state_bucket ? 1 : 0
  bucket = aws_s3_bucket.tfstate[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  count  = var.bootstrap_state_bucket ? 1 : 0
  bucket = aws_s3_bucket.tfstate[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  count                   = var.bootstrap_state_bucket ? 1 : 0
  bucket                  = aws_s3_bucket.tfstate[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3-native locking writes a .tflock file alongside the state object.
# The bucket just needs versioning + object ownership — no extra resources.
resource "aws_s3_bucket_object_lock_configuration" "tfstate" {
  count  = var.bootstrap_state_bucket ? 1 : 0
  bucket = aws_s3_bucket.tfstate[0].id
  # Object Lock is optional — use_lockfile works without it.
  # Enabling it adds a hard compliance layer on top of the soft lock.
  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 1
    }
  }
}
