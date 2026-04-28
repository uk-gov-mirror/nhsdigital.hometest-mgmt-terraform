################################################################################
# Network Firewall Rule Group - Allow Internal VPC Traffic (scoped)
# Only permits the specific ports required for internal service communication:
#   - TCP 8080: ALB/Lambda → ECS container port
#   - TCP 443:  Internal HTTPS (service-to-service)
#   - TCP 5432: Lambda/ECS → Aurora PostgreSQL
# All other internal traffic is subject to the default deny action.
# Security groups remain the primary access control for internal traffic.
################################################################################

resource "aws_networkfirewall_rule_group" "allow_internal" {
  count = var.enable_network_firewall && var.enable_ecs_internal_rules ? 1 : 0

  capacity = var.firewall_rule_group_capacities.internal
  name     = "${local.resource_prefix}-allow-internal"
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
      rules_string = join("\n", [
        "pass tcp $HOME_NET any -> $HOME_NET 8080 (msg:\"Allow ALB/Lambda to ECS container port\"; sid:1; rev:1;)",
        "pass tcp $HOME_NET any -> $HOME_NET 443 (msg:\"Allow internal HTTPS\"; sid:2; rev:1;)",
        "pass tcp $HOME_NET any -> $HOME_NET 5432 (msg:\"Allow internal PostgreSQL (Aurora)\"; sid:3; rev:1;)",
      ])
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-allow-internal"
  })
}

################################################################################
# Network Firewall Rule Group - Allow AWS Services (Required for Lambda)
################################################################################

resource "aws_networkfirewall_rule_group" "allow_aws_services" {
  count = var.enable_network_firewall ? 1 : 0

  capacity = var.firewall_rule_group_capacities.aws_services
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

  capacity = var.firewall_rule_group_capacities.egress_ip
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
      rules_string = join("\n", [
        for idx, rule in var.allowed_egress_ips :
        "pass ${lower(rule.protocol)} $HOME_NET any -> ${rule.ip} ${upper(rule.port) == "ANY" ? "any" : rule.port} (msg:\"${rule.description}\"; sid:${idx + 20001}; rev:1;)"
      ])
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

  capacity = var.firewall_rule_group_capacities.egress_domain
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
# Network Firewall Rule Group - Default Deny All
################################################################################

resource "aws_networkfirewall_rule_group" "drop_all" {
  count = var.enable_network_firewall && var.firewall_default_deny ? 1 : 0

  capacity = var.firewall_rule_group_capacities.drop_all
  name     = "${local.resource_prefix}-drop-all"
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
      rules_string = join("\n", [
        "drop tcp any any -> any any (flow:established,to_server; msg:\"Default deny all established TCP traffic\"; sid:999999; rev:1;)",
        "drop udp any any -> any any (msg:\"Default deny all UDP traffic\"; sid:999998; rev:1;)",
      ])
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-drop-all"
  })
}

################################################################################
# Network Firewall Rule Group - Stateful IP Filtering (Ingress)
################################################################################

resource "aws_networkfirewall_rule_group" "ingress_ip_filter" {
  count = var.enable_network_firewall && length(var.allowed_ingress_ips) > 0 ? 1 : 0

  capacity = var.firewall_rule_group_capacities.ingress_ip
  name     = "${local.resource_prefix}-ingress-ip-filter"
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
      rules_string = join("\n", [
        for idx, rule in var.allowed_ingress_ips :
        "pass ${lower(rule.protocol)} ${rule.ip} any -> $HOME_NET ${lower(rule.port) == "any" ? "any" : rule.port} (msg:\"${rule.description}\"; sid:${idx + 10001}; rev:1;)"
      ])
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-ingress-ip-filter"
  })
}
