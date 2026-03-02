resource "aws_iam_role" "lambda_goose_migrator" {
  name               = "${local.resource_prefix}-goose-migrator-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-goose-migrator-role"
  })
}

resource "aws_iam_policy" "lambda_goose_migrator_policy" {
  name        = "${local.resource_prefix}-goose-migrator-policy"
  description = "Allow Lambda to connect to RDS and fetch secrets."
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
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:CreateSecret",
      "secretsmanager:DescribeSecret"
    ]
    resources = ["*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeNetworkInterfaces",
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeInstances",
      "ec2:AttachNetworkInterface"
    ]
    resources = ["*"]
  }
}
