################################################################################
# Network Firewall Policy
################################################################################

resource "aws_networkfirewall_firewall_policy" "main" {
  count = var.enable_network_firewall ? 1 : 0

  name = "${local.resource_prefix}-firewall-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    stateful_default_actions           = ["aws:drop_established_app_layer"]

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    stateful_rule_group_reference {
      priority     = 100
      resource_arn = aws_networkfirewall_rule_group.allow_aws_services[0].arn
    }

    dynamic "stateful_rule_group_reference" {
      for_each = length(var.allowed_egress_domains) > 0 ? [1] : []
      content {
        priority     = 110
        resource_arn = aws_networkfirewall_rule_group.egress_domain_filter[0].arn
      }
    }

    dynamic "stateful_rule_group_reference" {
      for_each = length(var.allowed_ingress_ips) > 0 ? [1] : []
      content {
        priority     = 150
        resource_arn = aws_networkfirewall_rule_group.ingress_ip_filter[0].arn
      }
    }

    dynamic "stateful_rule_group_reference" {
      for_each = length(var.allowed_egress_ips) > 0 ? [1] : []
      content {
        priority     = 200
        resource_arn = aws_networkfirewall_rule_group.egress_ip_filter[0].arn
      }
    }

    dynamic "stateful_rule_group_reference" {
      for_each = var.firewall_default_deny ? [1] : []
      content {
        priority     = 65535
        resource_arn = aws_networkfirewall_rule_group.drop_all[0].arn
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-firewall-policy"
  })
}
