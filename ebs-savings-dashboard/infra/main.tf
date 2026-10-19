module "kms" {
  source     = "./modules/kms"
  prefix     = local.prefix
  account_id = local.account_id
  region     = var.aws_region
}

module "cur" {
  source                = "./modules/cur"
  prefix                = local.prefix
  account_id            = local.account_id
  region                = var.aws_region
  kms_key_arn           = module.kms.cur_key_arn
  management_account_id = local.account_id

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

module "athena" {
  source           = "./modules/athena"
  prefix           = local.prefix
  cur_bucket_name  = module.cur.bucket_name
  cur_bucket_arn   = module.cur.bucket_arn
  kms_key_arn      = module.kms.athena_key_arn
  scan_limit_bytes = var.athena_scan_limit_bytes
}

module "lambda" {
  source                = "./modules/lambda"
  prefix                = local.prefix
  region                = var.aws_region
  account_id            = local.account_id
  org_id                = var.org_id
  athena_workgroup_name = module.athena.workgroup_name
  athena_workgroup_arn  = module.athena.workgroup_arn
  athena_database       = module.athena.database_name
  results_bucket_name   = module.athena.results_bucket_name
  results_bucket_arn    = module.athena.results_bucket_arn
  cur_bucket_arn        = module.cur.bucket_arn
  kms_key_arn           = module.kms.lambda_key_arn
  cur_kms_key_arn       = module.kms.cur_key_arn
  athena_kms_key_arn    = module.kms.athena_key_arn
  vpc_id                = var.vpc_id
  private_subnet_ids    = var.private_subnet_ids
  use_vpc               = local.use_vpc
}

module "api_gateway" {
  source                = "./modules/api_gateway"
  prefix                = local.prefix
  lambda_function_arn   = module.lambda.function_arn
  lambda_function_name  = module.lambda.function_name
  cognito_user_pool_id  = var.cognito_user_pool_id
  cognito_app_client_id = var.cognito_app_client_id
  use_cognito           = local.use_cognito
  region                = var.aws_region
  allowed_origin        = local.use_custom_domain ? "https://${var.domain_name}" : "*"
}

module "frontend" {
  source              = "./modules/frontend"
  prefix              = local.prefix
  api_invoke_url      = module.api_gateway.invoke_url
  domain_name         = var.domain_name
  acm_certificate_arn = var.acm_certificate_arn
  use_custom_domain   = local.use_custom_domain

  providers = {
    aws     = aws
    aws.waf = aws.waf
  }
}

# Cross-account read role — deployed into each member account
# Requires separate provider aliases per account.
# For testing with a single account, member_account_ids = [] skips this.
# See cross_account_role/README.md for multi-account setup.
