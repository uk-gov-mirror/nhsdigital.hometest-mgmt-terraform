################################################################################
# Shared Services Infrastructure
# Contains resources shared across all environments:
# - WAF Web ACL (shared across API Gateways and CloudFront)
# - ACM Certificates (regional and global)
# - KMS Keys for encryption
# - Deployment Artifacts S3 Bucket
# - Developer IAM Role
################################################################################

terraform {
  required_version = ">= 1.14.0"

  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.37.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.8.1"
    }
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
}

# Provider for us-east-1 (required for CloudFront ACM certificates)
provider "aws" {
  alias               = "us_east_1"
  region              = "us-east-1"
  allowed_account_ids = [var.aws_account_id]
}
