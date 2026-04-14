################################################################################
# API Gateway Account Settings (for CloudWatch logging)
# This is a REGIONAL SINGLETON — only one per AWS account/region.
# Must live in shared_services (not per-environment) to avoid environments
# fighting over the same resource.
################################################################################

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn

  depends_on = [aws_iam_role_policy.api_gateway_cloudwatch]
}

resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "${local.resource_prefix}-apigw-cloudwatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-apigw-cloudwatch-role"
  })
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch" {
  name = "${local.resource_prefix}-apigw-cloudwatch-policy"
  role = aws_iam_role.api_gateway_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:*"
      }
    ]
  })
}
