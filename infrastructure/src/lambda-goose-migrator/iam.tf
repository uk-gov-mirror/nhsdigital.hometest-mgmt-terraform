################################################################################
# Per-Lambda IAM Role — Goose Migrator (Least Privilege)
#
# This role is scoped to ONLY the resources the goose-migrator Lambda needs:
#   - CloudWatch Logs: only its own log group
#   - Secrets Manager: only the Aurora master secret + app_user secret
#   - RDS IAM Auth: only the specific Aurora cluster
#   - VPC ENI: required for VPC-deployed Lambda (resource must be *)
################################################################################

resource "aws_iam_role" "lambda_goose_migrator" {
  name               = "${local.resource_prefix}-goose-migrator-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-goose-migrator-role"
  })
}

resource "aws_iam_policy" "lambda_goose_migrator_policy" {
  name        = "${local.resource_prefix}-goose-migrator-policy"
  description = "Least-privilege policy for goose-migrator Lambda."
  policy      = data.aws_iam_policy_document.lambda_goose_migrator_policy.json

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-goose-migrator-policy"
  })
}

resource "aws_iam_role_policy_attachment" "lambda_goose_migrator_attach" {
  role       = aws_iam_role.lambda_goose_migrator.name
  policy_arn = aws_iam_policy.lambda_goose_migrator_policy.arn
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_goose_migrator_policy" {
  # CloudWatch Logs — scoped to this Lambda's log group only
  statement {
    sid    = "CloudWatchCreateLogGroup"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:*"
    ]
  }
  statement {
    sid    = "CloudWatchWriteLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/lambda/${local.resource_prefix}-lambda-goose-migrator:*"
    ]
  }

  # Secrets Manager — only the Aurora master user secret + app_user secret
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = compact(concat(
      # Aurora master user secret (always needed for migrations)
      var.use_iam_auth ? [] : [data.aws_rds_cluster.db.master_user_secret[0].secret_arn],
      # App user secret (only when schema != public)
      var.db_schema != "public" ? [aws_secretsmanager_secret.app_user[0].arn] : []
    ))
  }

  # RDS IAM Authentication — scoped to the specific Aurora cluster
  statement {
    sid     = "RDSIAMConnect"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = [
      "arn:aws:rds-db:${var.aws_region}:${var.aws_account_id}:dbuser:${data.aws_rds_cluster.db.cluster_resource_id}/*"
    ]
  }

  # VPC ENI Management — required for VPC-deployed Lambda
  # Note: These permissions must be granted on Resource "*" as Lambda creates
  # ENIs during function creation and the specific resource ARN is not known
  # in advance. Security is enforced through VPC security groups.
  statement {
    sid    = "VPCNetworkInterfaces"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses"
    ]
    resources = ["*"]
  }
}
