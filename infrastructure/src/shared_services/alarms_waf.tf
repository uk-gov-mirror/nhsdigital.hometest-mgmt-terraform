################################################################################
# WAF Alarms
# CloudWatch alarms for WAFv2 Web ACLs (Regional and CloudFront)
################################################################################

#------------------------------------------------------------------------------
# Regional WAF Alarms (API Gateway)
#------------------------------------------------------------------------------

module "waf_alarms_regional" {
  source = "../../modules/waf-alarms"

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment
  aws_region            = var.aws_region

  web_acl_name    = aws_wafv2_web_acl.regional.name
  waf_name_suffix = "regional"

  rate_limit_metric_name = "${local.resource_prefix}-rate-limit"
  sqli_metric_name       = "${local.resource_prefix}-sqli"

  alarm_actions     = [module.sns_alerts_security.topic_arn]
  enable_ok_actions = var.enable_ok_actions

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# CloudFront WAF Alarms
# NOTE: CloudFront WAF metrics use region "us-east-1"
#------------------------------------------------------------------------------

module "waf_alarms_cloudfront" {
  source = "../../modules/waf-alarms"

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment
  aws_region            = "us-east-1"

  web_acl_name    = aws_wafv2_web_acl.cloudfront.name
  waf_name_suffix = "cloudfront"

  rate_limit_metric_name = "${local.resource_prefix}-cf-rate-limit"

  alarm_actions     = [module.sns_alerts_security.topic_arn]
  enable_ok_actions = var.enable_ok_actions

  tags = local.common_tags
}
