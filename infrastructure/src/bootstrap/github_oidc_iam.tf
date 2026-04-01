################################################################################
# GitHub OIDC Provider (Account-level, create once)
################################################################################
# Build the list of allowed subjects for the trust policy
locals {
  # Allow all branches wildcard
  all_branches_subject = ["repo:${var.github_repo}:*"]

  # Allow specific branches
  branch_subjects = [for branch in var.github_branches : "repo:${var.github_repo}:ref:refs/heads/${branch}"]

  # Allow specific environments
  environment_subjects = [for env in var.github_environments : "repo:${var.github_repo}:environment:${env}"]

  # Allow pull requests (for plan only - consider separate role for PRs)
  # pr_subjects = ["repo:${var.github_repo}:pull_request"]

  # Combine all allowed subjects based on flag
  # If github_allow_all_branches is true, allow all branches from the repo
  # Otherwise, restrict to specific branches and environments
  all_allowed_subjects = var.github_allow_all_branches ? local.all_branches_subject : concat(
    local.branch_subjects,
    local.environment_subjects
  )

  gha_iam_role_name = "${local.resource_prefix}-iam-role-gha-terraform"
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  # GitHub OIDC thumbprints
  # https://github.blog/changelog/2023-06-27-github-actions-update-on-oidc-integration-with-aws/
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-iam-oidc-provider-github"
  })
}

################################################################################
# IAM Role for GitHub Actions (with strict OIDC conditions)
################################################################################
resource "aws_iam_role" "gha_oidc_role" {
  name        = local.gha_iam_role_name
  description = "IAM role for GitHub Actions to run Terraform/Terragrunt"

  # Maximum session duration (1 hour for security)
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitHubActionsOIDC"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.all_allowed_subjects
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = local.gha_iam_role_name
  })
}
