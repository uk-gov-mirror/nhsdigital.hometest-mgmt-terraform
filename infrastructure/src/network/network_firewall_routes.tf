################################################################################
# Network Firewall Routes - Traffic Flow Through Firewall
################################################################################

# Update private subnet routes to go through firewall (when enabled)
resource "aws_route" "private_to_firewall" {
  count = var.enable_network_firewall ? (var.single_nat_gateway ? 1 : length(local.azs)) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.firewall_endpoint_ids[local.azs[var.single_nat_gateway ? 0 : count.index]]

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
