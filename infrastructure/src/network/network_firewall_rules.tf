################################################################################
# Network Firewall Rule Group - Allow AWS Services (Required for Lambda)
################################################################################

resource "aws_networkfirewall_rule_group" "allow_aws_services" {
  count = var.enable_network_firewall ? 1 : 0

  capacity = 50
  name     = "${local.resource_prefix}-allow-aws-services"
  type     = "STATEFUL"

  rule_group {
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set {
          definition = [var.vpc_cidr]
        }
      }
    }

    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["TLS_SNI", "HTTP_HOST"]
        targets = [
          ".amazonaws.com",
          ".aws.amazon.com"
        ]
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-allow-aws-services"
  })
}

################################################################################
# Network Firewall Rule Group - IP Address Filtering
################################################################################

resource "aws_networkfirewall_rule_group" "egress_ip_filter" {
  count = var.enable_network_firewall && length(var.allowed_egress_ips) > 0 ? 1 : 0

  capacity = 100
  name     = "${local.resource_prefix}-egress-ip-filter"
  type     = "STATEFUL"

  rule_group {
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set {
          definition = [var.vpc_cidr]
        }
      }
    }

    rules_source {
      stateful_rule {
        action = "PASS"
        header {
          destination      = "$EXTERNAL_NET"
          destination_port = "ANY"
          direction        = "FORWARD"
          protocol         = "IP"
          source           = "$HOME_NET"
          source_port      = "ANY"
        }
        rule_option {
          keyword = "sid:1"
        }
      }

      dynamic "stateful_rule" {
        for_each = var.allowed_egress_ips
        content {
          action = "PASS"
          header {
            destination      = stateful_rule.value.ip
            destination_port = stateful_rule.value.port
            direction        = "FORWARD"
            protocol         = stateful_rule.value.protocol
            source           = "$HOME_NET"
            source_port      = "ANY"
          }
          rule_option {
            keyword = "sid:${stateful_rule.key + 2}"
          }
          rule_option {
            keyword  = "msg"
            settings = ["\"${stateful_rule.value.description}\""]
          }
        }
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-egress-ip-filter"
  })
}

################################################################################
# Network Firewall Rule Group - Domain Filtering (HTTPS/TLS)
################################################################################

resource "aws_networkfirewall_rule_group" "egress_domain_filter" {
  count = var.enable_network_firewall && length(var.allowed_egress_domains) > 0 ? 1 : 0

  capacity = 100
  name     = "${local.resource_prefix}-egress-domain-filter"
  type     = "STATEFUL"

  rule_group {
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set {
          definition = [var.vpc_cidr]
        }
      }
    }

    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["TLS_SNI", "HTTP_HOST"]
        targets              = var.allowed_egress_domains
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-egress-domain-filter"
  })
}
