################################################################################
# Network Alarms
# CloudWatch alarms for NAT Gateways and Network Firewall
# Placed in shared_services because network deploys before shared_services,
# and alarms require SNS topics that are created here.
################################################################################

module "network_alarms" {
  source = "../../modules/network-alarms"
  count  = length(var.nat_gateway_ids) > 0 || var.network_firewall_name != null ? 1 : 0

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment

  nat_gateway_ids = {
    for idx, gw_id in var.nat_gateway_ids : "az${idx + 1}" => gw_id
  }

  firewall_name = var.network_firewall_name

  alarm_actions     = [module.sns_alerts_warning.topic_arn]
  enable_ok_actions = var.enable_ok_actions

  tags = local.common_tags
}
