################################################################################
# Terraform and Provider Configuration
################################################################################

terraform {
  required_version = ">= 1.14.0"

  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.37.0"
    }
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
}

# Provider for us-east-1 (required for Route 53 query logging CloudWatch logs)
provider "aws" {
  alias               = "us_east_1"
  region              = "us-east-1"
  allowed_account_ids = [var.aws_account_id]
}
