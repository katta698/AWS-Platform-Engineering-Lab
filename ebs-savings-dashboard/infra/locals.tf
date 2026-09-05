data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Prefix for every named resource — keeps names unique and identifiable
  prefix = "${var.org_name}-ebs-dash-${var.environment}"

  # Use Cognito JWT auth when pool ID is provided, otherwise IAM
  use_cognito = var.cognito_user_pool_id != ""

  # Use VPC for Lambda when vpc_id is provided
  use_vpc = var.vpc_id != ""

  # Use custom domain for CloudFront when provided
  use_custom_domain = var.domain_name != ""
}
