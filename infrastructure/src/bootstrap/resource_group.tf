################################################################################
# Resource Group for Bootstrap Resources
# Allows viewing all bootstrap resources in AWS Console
################################################################################

locals {
  rg_name = "${local.resource_prefix}-rg"
}

resource "aws_resourcegroups_group" "all" {
  for_each = toset(var.aws_allowed_regions)

  name        = "${local.rg_name}-all-${each.key}"
  description = "Resource group containing all Terraform infrastructure"

  region = each.key

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        {
          Key    = "Project"
          Values = [var.project_name]
        },
        {
          Key    = "ManagedBy"
          Values = ["terraform"]
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.rg_name}-all"
  })
}

resource "aws_resourcegroups_group" "bootstrap" {
  for_each = toset(var.aws_allowed_regions)

  name        = "${local.rg_name}-bootstrap-${each.key}"
  description = "Resource group containing bootstrap Terraform infrastructure"

  region = each.key

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        {
          Key    = "Project"
          Values = [var.project_name]
        },
        {
          Key    = "ManagedBy"
          Values = ["terraform"]
        },
        {
          Key    = "Component"
          Values = ["bootstrap"]
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.rg_name}-bootstrap"
  })
}
