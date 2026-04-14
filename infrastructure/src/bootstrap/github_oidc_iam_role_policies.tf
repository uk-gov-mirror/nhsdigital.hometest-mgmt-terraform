################################################################################
# IAM Policy for Terraform State Management (Least Privilege)
################################################################################

resource "aws_iam_role_policy" "gha_tfstate" {
  name   = "${local.gha_iam_role_name}-policy-tfstate-access"
  role   = aws_iam_role.gha_oidc_role.id
  policy = data.aws_iam_policy_document.tfstate_policy.json
}

data "aws_iam_policy_document" "tfstate_policy" {
  # S3 State Bucket - Full access for state management
  statement {
    sid    = "S3StateBucketAccess"
    effect = "Allow"
    actions = [
      "s3:*"
    ]
    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*"
    ]
  }

  # KMS Key for State Encryption
  statement {
    sid    = "KMSStateEncryption"
    effect = "Allow"
    actions = [
      "kms:*"
    ]
    resources = [aws_kms_key.tfstate.arn]
  }
}

################################################################################
# IAM Policy for Terraform Infrastructure Management (POC - Simplified)
# Note: This is a permissive policy for POC environments
# For production, implement least-privilege access
################################################################################

resource "aws_iam_role_policy" "gha_infrastructure" {
  name   = "${local.gha_iam_role_name}-policy-infrastructure-access"
  role   = aws_iam_role.gha_oidc_role.id
  policy = data.aws_iam_policy_document.infrastructure_policy.json
}

data "aws_iam_policy_document" "infrastructure_policy" {
  # Full access to common AWS services for POC deployment
  statement {
    sid    = "POCFullAccess"
    effect = "Allow"
    actions = [
      # Networking
      "ec2:*",
      "vpc:*",
      "network-firewall:*",

      # Compute
      "lambda:*",
      "ecr:*",
      "ecs:*",

      # Load Balancing
      "elasticloadbalancing:*",

      # Service Discovery (Cloud Map)
      "servicediscovery:*",

      # WAF
      "wafv2:*",

      # Storage
      "s3:*",
      "dynamodb:*",

      # Security & Encryption
      "kms:*",
      "secretsmanager:*",
      "ssm:*",

      # API & Messaging
      "apigateway:*",
      "sns:*",
      "sqs:*",

      # DNS & CDN
      "route53:*",
      "cloudfront:*",
      "acm:*",

      # Monitoring
      "logs:*",
      "cloudwatch:*",
      "chatbot:*",

      # Resource Management
      "resource-groups:*",
      "tag:*",

      # Identity
      "cognito-idp:*",
      "cognito-identity:*",

      # Data Streaming
      "firehose:*",
      "kinesis:*",

      # Database
      "rds:*",

      # Auto Scaling (ECS, etc.)
      "application-autoscaling:*",

      # Account management (region opt-in/out)
      "account:*",

      # STS
      "sts:GetCallerIdentity",
      "sts:AssumeRole"
    ]
    resources = ["*"]
  }

  # IAM permissions scoped to project resources
  statement {
    sid    = "IAMProjectAccess"
    effect = "Allow"
    actions = [
      "iam:*"
    ]
    resources = [
      "arn:aws:iam::*:role/${var.project_name}-*",
      "arn:aws:iam::*:policy/${var.project_name}-*",
      "arn:aws:iam::*:role/aws-service-role/*"
    ]
  }

  # IAM read access for all resources
  statement {
    sid    = "IAMReadAccess"
    effect = "Allow"
    actions = [
      "iam:Get*",
      "iam:List*",
      "iam:PassRole"
    ]
    resources = ["*"]
  }

  # Allow creating service-linked roles
  statement {
    sid    = "IAMServiceLinkedRoles"
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole",
      "iam:DeleteServiceLinkedRole",
      "iam:GetServiceLinkedRoleDeletionStatus"
    ]
    resources = ["*"]
  }
}

################################################################################
# Optional: Attach Additional Managed Policies
################################################################################

resource "aws_iam_role_policy_attachment" "additional_policies" {
  for_each   = toset(var.additional_iam_policy_arns)
  role       = aws_iam_role.gha_oidc_role.name
  policy_arn = each.value
}

################################################################################
# Permissions Boundary (Optional but Recommended)
# Prevents privilege escalation - even for POC
################################################################################

resource "aws_iam_policy" "gha_permissions_boundary" {
  name        = "${local.gha_iam_role_name}-policy-gha-permissions-boundary"
  description = "Permissions boundary for GitHub Actions role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowedServices"
        Effect = "Allow"
        Action = [
          "s3:*",
          "dynamodb:*",
          "lambda:*",
          "logs:*",
          "ec2:*",
          "network-firewall:*",
          "iam:*",
          "ssm:*",
          "secretsmanager:*",
          "kms:*",
          "sns:*",
          "sqs:*",
          "apigateway:*",
          "route53:*",
          "acm:*",
          "cloudfront:*",
          "cloudwatch:*",
          "ecr:*",
          "ecs:*",
          "elasticloadbalancing:*",
          "servicediscovery:*",
          "wafv2:*",
          "resource-groups:*",
          "tag:*",
          "sts:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyIAMUserManagement"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:DeleteUser",
          "iam:CreateAccessKey",
          "iam:DeleteAccessKey",
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
          "iam:PutUserPolicy",
          "iam:DeleteUserPolicy",
          "iam:CreateGroup",
          "iam:DeleteGroup",
          "iam:UpdateLoginProfile",
          "iam:CreateLoginProfile",
          "iam:DeleteLoginProfile"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyOrganizationsActions"
        Effect = "Deny"
        Action = [
          "organizations:*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.gha_iam_role_name}-policy-gha-permissions-boundary"
  })
}

# Uncomment to apply the permissions boundary
# resource "aws_iam_role" "gha_oidc_role" {
#   ...
#   permissions_boundary = aws_iam_policy.gha_permissions_boundary.arn
# }
