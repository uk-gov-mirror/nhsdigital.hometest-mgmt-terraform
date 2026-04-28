################################################################################
# Public Subnets - For NAT Gateways and ALB (if needed)
################################################################################

resource "aws_subnet" "public" {
  count = length(local.public_azs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnets[count.index]
  availability_zone       = local.public_azs[count.index]
  map_public_ip_on_launch = false # Security: Don't auto-assign public IPs

  tags = merge(local.common_tags, {
    Name                     = "${local.resource_prefix}-public-${local.public_azs[count.index]}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1" # For ALB if using EKS
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Route private subnet traffic through firewall for symmetric routing.
# This can be disabled in single-AZ cost-optimised environments to keep
# ALB-to-private traffic on local VPC routing.
resource "aws_route" "public_to_firewall_private" {
  count = var.enable_network_firewall && var.route_internal_alb_traffic_through_firewall ? length(local.azs) : 0

  route_table_id         = aws_route_table.public.id
  destination_cidr_block = local.private_subnets[count.index]
  vpc_endpoint_id        = local.firewall_endpoint_ids[local.azs[count.index]]

  depends_on = [aws_networkfirewall_firewall.main]
}

resource "aws_route_table_association" "public" {
  count = length(local.public_azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
