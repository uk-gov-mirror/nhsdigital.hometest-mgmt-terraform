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
# Network Firewall Rule Group - Stateful IP Filtering (Egress)
################################################################################

resource "aws_networkfirewall_rule_group" "egress_ip_filter" {
  count = var.enable_network_firewall ? 1 : 0

  capacity = 100
  name     = "${local.resource_prefix}-egress-ip-filter"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      dynamic "stateful_rule" {
        for_each = var.allowed_egress_ips
        content {
          action = "PASS"
          header {
            destination      = stateful_rule.value.ip
            destination_port = stateful_rule.value.port
            direction        = "FORWARD"
            protocol         = upper(stateful_rule.value.protocol)
            source           = var.vpc_cidr
            source_port      = "ANY"
          }
          rule_option {
            keyword  = "sid"
            settings = [stateful_rule.key + 1]
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
# Network Firewall Rule Group - Stateful IP Filtering (Ingress)
################################################################################

resource "aws_networkfirewall_rule_group" "ingress_ip_filter" {
  count = var.enable_network_firewall && length(var.allowed_ingress_ips) > 0 ? 1 : 0

  capacity = 100
  name     = "${local.resource_prefix}-ingress-ip-filter"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      dynamic "stateful_rule" {
        for_each = var.allowed_ingress_ips
        content {
          action = "PASS"
          header {
            destination      = var.vpc_cidr
            destination_port = stateful_rule.value.port
            direction        = "FORWARD"
            protocol         = upper(stateful_rule.value.protocol)
            source           = stateful_rule.value.ip
            source_port      = "ANY"
          }
          rule_option {
            keyword  = "sid"
            settings = [stateful_rule.key + 10001]
          }
        }
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-ingress-ip-filter"
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

################################################################################
# Network Firewall Rule Group - Drop All Other Traffic (Default Deny)
################################################################################

resource "aws_networkfirewall_rule_group" "drop_all" {
  count = var.enable_network_firewall && var.firewall_default_deny ? 1 : 0

  capacity = 10
  name     = "${local.resource_prefix}-drop-all"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      stateful_rule {
        action = "DROP"
        header {
          destination      = "ANY"
          destination_port = "ANY"
          direction        = "FORWARD"
          protocol         = "IP"
          source           = var.vpc_cidr
          source_port      = "ANY"
        }
        rule_option {
          keyword  = "sid"
          settings = ["999999"]
        }
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-drop-all"
  })
}
