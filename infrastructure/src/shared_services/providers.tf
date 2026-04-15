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

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.2.1"
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
