################################################################################
# Data/Database Subnets - Isolated (No Internet Access)
################################################################################

resource "aws_subnet" "data" {
  count = length(local.data_azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.data_subnets[count.index]
  availability_zone = local.data_azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-data-${local.azs[count.index]}"
    Tier = "data"
  })
}

resource "aws_route_table" "data" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-data-rt"
  })
}

resource "aws_route_table_association" "data" {
  count = length(local.data_azs)

  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

################################################################################
# DB Subnet Group (for RDS if needed)
################################################################################

resource "aws_db_subnet_group" "main" {
  count = var.create_db_subnet_group ? 1 : 0

  name        = "${local.resource_prefix}-db-subnet-group"
  description = "Database subnet group for ${local.resource_prefix}"
  subnet_ids  = aws_subnet.data[*].id

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-db-subnet-group"
  })
}
