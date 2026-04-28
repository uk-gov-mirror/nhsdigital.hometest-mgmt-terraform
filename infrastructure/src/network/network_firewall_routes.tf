################################################################################
# Network Firewall Routes - Traffic Flow Through Firewall
################################################################################

# Update private subnet routes to go through firewall (when enabled)
resource "aws_route" "private_to_firewall" {
  count = var.enable_network_firewall ? length(local.azs) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.firewall_endpoint_ids[local.azs[count.index]]

  depends_on = [aws_networkfirewall_firewall.main]
}

# Route return traffic from private subnets to public subnets through firewall (symmetric routing)
# Without this, ALB->task goes through firewall but task->ALB bypasses it, breaking stateful inspection
locals {
  private_to_public_routes = var.enable_network_firewall ? flatten([
    for pi in range(length(local.azs)) : [
      for pui in range(length(local.public_azs)) : {
        key               = "${pi}-${pui}"
        route_table_id    = aws_route_table.private[pi].id
        destination_cidr  = local.public_subnets[pui]
        firewall_endpoint = local.firewall_endpoint_ids[local.azs[pi]]
      }
    ]
  ]) : []
}

resource "aws_route" "private_to_firewall_public" {
  for_each = { for r in local.private_to_public_routes : r.key => r }

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.destination_cidr
  vpc_endpoint_id        = each.value.firewall_endpoint

  depends_on = [aws_networkfirewall_firewall.main]
}

################################################################################
# IGW Route Table - Return Traffic Through Firewall
################################################################################

resource "aws_route_table" "igw" {
  count = var.enable_network_firewall ? 1 : 0

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-igw-rt"
  })
}

# Route inbound traffic from IGW through firewall for inspection
resource "aws_route" "igw_to_firewall" {
  count = var.enable_network_firewall ? length(local.azs) : 0

  route_table_id         = aws_route_table.igw[0].id
  destination_cidr_block = aws_subnet.private[count.index].cidr_block
  vpc_endpoint_id        = local.firewall_endpoint_ids[local.azs[count.index]]

  depends_on = [aws_networkfirewall_firewall.main]
}

resource "aws_route_table_association" "igw" {
  count = var.enable_network_firewall ? 1 : 0

  gateway_id     = aws_internet_gateway.main.id
  route_table_id = aws_route_table.igw[0].id
}
