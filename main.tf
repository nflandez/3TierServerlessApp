data "aws_caller_identity" "current" {}

locals {
  # S3 bucket names and Cognito domains must be globally unique, so add the account ID
  unique = "${var.name}-${data.aws_caller_identity.current.account_id}"
}

# Tier 3: data
module "data" {
  source = "./modules/data"

  name = var.name
}

# Presentation tier: S3 + CloudFront (the site URL is needed by Cognito and CORS)
module "frontend" {
  source = "./modules/frontend"

  name           = var.name
  bucket_name    = "${local.unique}-site"
  api_url        = module.api.api_url
  cognito_domain = module.auth.hosted_ui_domain
  client_id      = module.auth.client_id
}

# Authentication
module "auth" {
  source = "./modules/auth"

  name          = var.name
  domain_prefix = local.unique
  site_url      = module.frontend.site_url
}

# Tier 2: application logic
module "api" {
  source = "./modules/api"

  name               = var.name
  table_name         = module.data.table_name
  table_arn          = module.data.table_arn
  user_pool_issuer   = module.auth.issuer
  client_id          = module.auth.client_id
  allowed_origin     = module.frontend.site_url
  log_retention_days = var.log_retention_days
}

# Monitoring across all tiers
module "monitoring" {
  source = "./modules/monitoring"

  name               = var.name
  region             = var.region
  alert_email        = var.alert_email
  function_name      = module.api.function_name
  lambda_log_group   = module.api.lambda_log_group
  api_id             = module.api.api_id
  table_name         = module.data.table_name
  cloudfront_dist_id = module.frontend.distribution_id
}
