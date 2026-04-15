################################################################################
# Application-Level CloudWatch Alarms
# API Gateway and CloudFront alarms for the hometest-app layer
################################################################################

#------------------------------------------------------------------------------
# API Gateway Alarms
# 5XX, 4XX, latency, and integration latency per API
#------------------------------------------------------------------------------

module "api_gateway_alarms" {
  source = "../../modules/api-gateway-alarms"
  count  = var.sns_alerts_critical_topic_arn != null ? 1 : 0

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment

  api_names = toset([for prefix in local.api_prefixes : "${local.resource_prefix}-${prefix}"])

  # P1 alarms (5XX) → critical, P2 alarms (4XX, latency) → warning
  # Using critical topic for all; override per-alarm in production with tiered approach
  alarm_actions     = [var.sns_alerts_critical_topic_arn]
  enable_ok_actions = var.enable_ok_actions

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# CloudFront Alarms
# 5XX and 4XX error rates on the SPA distribution
# NOTE: CloudFront metrics are published to us-east-1 but can be read globally
#------------------------------------------------------------------------------

module "cloudfront_alarms" {
  source = "../../modules/cloudfront-alarms"
  count  = var.sns_alerts_critical_topic_arn != null ? 1 : 0

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment

  distribution_id = module.cloudfront_spa.distribution_id

  alarm_actions     = [var.sns_alerts_critical_topic_arn]
  enable_ok_actions = var.enable_ok_actions

  tags = local.common_tags
}
