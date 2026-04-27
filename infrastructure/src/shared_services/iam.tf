################################################################################
# Developer IAM Role (Shared across environments)
################################################################################

resource "aws_iam_role" "developer" {
  name = "${local.resource_prefix}-developer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.developer_account_arns
        }
        Action = "sts:AssumeRole"
        Condition = var.require_mfa ? {
          Bool = {
            "aws:MultiFactorAuthPresent" = "true"
          }
        } : {}
      }
    ]
  })

  max_session_duration = 3600

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-developer-role"
  })
}

resource "aws_iam_role_policy" "developer_lambda" {
  name = "lambda-deployment"
  role = aws_iam_role.developer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaDeployment"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:PublishVersion",
          "lambda:CreateAlias",
          "lambda:UpdateAlias"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.project_name}-*"
      },
      # {
      #   Sid    = "S3ArtifactAccess"
      #   Effect = "Allow"
      #   Action = [
      #     "s3:GetObject",
      #     "s3:PutObject",
      #     "s3:ListBucket"
      #   ]
      #   Resource = [
      #     aws_s3_bucket.deployment_artifacts.arn,
      #     "${aws_s3_bucket.deployment_artifacts.arn}/*"
      #   ]
      # },
      {
        Sid    = "CloudFrontInvalidation"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation",
          "cloudfront:GetInvalidation",
          "cloudfront:ListInvalidations"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:ResourceTag/Project" = var.project_name
          }
        }
      },
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.project_name}/*"
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.main.arn,
          aws_kms_key.pii_data.arn
        ]
      }
    ]
  })
}

################################################################################
# Developer Deployment Policy (Part 1 - Compute & API)
# Customer-managed policy for SSO Permission Set attachment
# Covers: IAM, Lambda, API Gateway, SQS, CloudFront, S3, Route53, TF state
################################################################################

resource "aws_iam_policy" "developer_deployment" {
  name        = "${local.resource_prefix}-developer-deployment"
  description = "Deployment permissions for HomeTest developers via SSO"
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "IAMRoleMgmt"
        Effect   = "Allow"
        Action   = ["iam:*Role*"]
        Resource = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-*"
      },
      {
        Sid    = "IAMPolicyMgmt"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:TagPolicy",
          "iam:UntagPolicy"
        ]
        Resource = "arn:aws:iam::${var.aws_account_id}:policy/${var.project_name}-*"
      },
      {
        Sid      = "LambdaMgmt"
        Effect   = "Allow"
        Action   = ["lambda:*"]
        Resource = "arn:aws:lambda:*:${var.aws_account_id}:function:${var.project_name}-*"
      },
      {
        Sid    = "LambdaESM"
        Effect = "Allow"
        Action = [
          "lambda:CreateEventSourceMapping",
          "lambda:UpdateEventSourceMapping",
          "lambda:DeleteEventSourceMapping",
          "lambda:GetEventSourceMapping",
          "lambda:ListEventSourceMappings",
          "Lambda:CreateFunction"
        ]
        Resource = "*"
      },
      {
        Sid    = "APIGatewayMgmt"
        Effect = "Allow"
        Action = [
          "apigateway:GET",
          "apigateway:POST",
          "apigateway:PUT",
          "apigateway:PATCH",
          "apigateway:DELETE",
          "apigateway:SetWebACL"
        ]
        Resource = [
          "arn:aws:apigateway:*::/restapis",
          "arn:aws:apigateway:*::/restapis/*",
          "arn:aws:apigateway:*::/domainnames",
          "arn:aws:apigateway:*::/domainnames/*",
          "arn:aws:apigateway:*::/tags/*"
        ]
      },
      {
        Sid      = "APIGatewayAcct"
        Effect   = "Allow"
        Action   = ["apigateway:GET", "apigateway:PATCH"]
        Resource = "arn:aws:apigateway:*::/account"
      },
      {
        Sid      = "SQSMgmt"
        Effect   = "Allow"
        Action   = ["sqs:*"]
        Resource = "arn:aws:sqs:*:${var.aws_account_id}:${var.project_name}-*"
      },
      {
        Sid      = "CloudFrontMgmt"
        Effect   = "Allow"
        Action   = ["cloudfront:*"]
        Resource = "*"
      },
      {
        Sid    = "S3Mgmt"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          "arn:aws:s3:::${var.project_name}-*",
          "arn:aws:s3:::${var.project_name}-*/*"
        ]
      },
      {
        Sid    = "Route53Mgmt"
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:GetChange",
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets"
        ]
        Resource = [
          "arn:aws:route53:::hostedzone/*",
          "arn:aws:route53:::change/*"
        ]
      },
      {
        Sid    = "TFStateAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.project_name}-*-s3-tfstate",
          "arn:aws:s3:::${var.project_name}-*-s3-tfstate/*"
        ]
      },
      {
        Sid      = "RDSQueryEditor"
        Effect   = "Allow"
        Action   = ["dbqms:*", "rds-data:*"]
        Resource = "*"
      },
      {
        Sid    = "SecretsManagerMgmt"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:PutResourcePolicy",
          "secretsmanager:DeleteResourcePolicy"
        ]
        Resource = "arn:aws:secretsmanager:*:${var.aws_account_id}:secret:${var.project_name}/*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-developer-deployment"
  })
}

################################################################################
# Developer Deployment Policy (Part 2 - Infrastructure & Networking)
# Customer-managed policy for SSO Permission Set attachment
# Covers: CloudWatch, KMS, EC2, WAF, ACM, ELB, Service Discovery, SNS
################################################################################

resource "aws_iam_policy" "developer_deployment_infra" {
  name        = "${local.resource_prefix}-developer-deployment-infra"
  description = "Infrastructure permissions for HomeTest developers via SSO (networking & monitoring)"
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CWLogsMgmt"
        Effect = "Allow"
        Action = ["logs:*"]
        Resource = [
          "arn:aws:logs:*:${var.aws_account_id}:log-group:/aws/lambda/${var.project_name}-*",
          "arn:aws:logs:*:${var.aws_account_id}:log-group:/aws/lambda/${var.project_name}-*:*",
          "arn:aws:logs:*:${var.aws_account_id}:log-group:/aws/apigateway/${var.project_name}-*",
          "arn:aws:logs:*:${var.aws_account_id}:log-group:/aws/apigateway/${var.project_name}-*:*",
          "arn:aws:logs:*:${var.aws_account_id}:log-group:/ecs/${var.project_name}-*",
          "arn:aws:logs:*:${var.aws_account_id}:log-group:/ecs/${var.project_name}-*:*"
        ]
      },
      {
        Sid      = "CWAlarmsMgmt"
        Effect   = "Allow"
        Action   = ["cloudwatch:*Alarm*", "cloudwatch:*Tag*"]
        Resource = "arn:aws:cloudwatch:*:${var.aws_account_id}:alarm:${var.project_name}-*"
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:ListGrants"
        ]
        Resource = "arn:aws:kms:*:${var.aws_account_id}:key/*"
        Condition = {
          "ForAnyValue:StringLike" = {
            "kms:ResourceAliases" = "alias/${var.project_name}-*"
          }
        }
      },
      {
        Sid      = "ResourceGroupMgmt"
        Effect   = "Allow"
        Action   = ["resource-groups:*"]
        Resource = "arn:aws:resource-groups:*:${var.aws_account_id}:group/${var.project_name}-*"
      },
      {
        Sid      = "EC2Describe"
        Effect   = "Allow"
        Action   = ["ec2:DescribeVpcs", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeNetworkInterfaces"]
        Resource = "*"
      },
      {
        Sid    = "EC2SecurityGroupMgmt"
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/Name" = ["${var.project_name}-*"]
          }
        }
      },
      {
        Sid    = "EC2SecurityGroupMgmtByTag"
        Effect = "Allow"
        Action = [
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/Name" = ["${var.project_name}-*"]
          }
        }
      },
      {
        Sid      = "WAFAssoc"
        Effect   = "Allow"
        Action   = ["wafv2:AssociateWebACL", "wafv2:DisassociateWebACL", "wafv2:GetWebACLForResource", "wafv2:GetWebACL"]
        Resource = "*"
      },
      {
        Sid    = "ACMMgmt"
        Effect = "Allow"
        Action = [
          "acm:DescribeCertificate",
          "acm:ListTagsForCertificate",
          "acm:RequestCertificate",
          "acm:DeleteCertificate",
          "acm:AddTagsToCertificate",
          "acm:RemoveTagsFromCertificate",
          "acm:GetCertificate",
          "acm:ListCertificates"
        ]
        Resource = "*"
      },
      {
        Sid    = "ELBMgmt"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "ServiceDiscoveryMgmt"
        Effect = "Allow"
        Action = [
          "servicediscovery:CreateService",
          "servicediscovery:DeleteService",
          "servicediscovery:GetService",
          "servicediscovery:UpdateService",
          "servicediscovery:ListServices",
          "servicediscovery:GetNamespace",
          "servicediscovery:ListNamespaces",
          "servicediscovery:TagResource",
          "servicediscovery:UntagResource",
          "servicediscovery:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid      = "SNSRead"
        Effect   = "Allow"
        Action   = ["sns:GetTopicAttributes", "sns:ListTagsForResource"]
        Resource = "arn:aws:sns:*:${var.aws_account_id}:${var.project_name}-*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-developer-deployment-infra"
  })
}

################################################################################
# ReadOnly Terraform State Access Policy
# Customer-managed policy for SSO ReadOnly Permission Set attachment
# Allows read-only users to decrypt terraform state files
################################################################################

resource "aws_iam_policy" "tfstate_readonly" {
  name        = "${local.resource_prefix}-tfstate-readonly" #Change name
  description = "Read-only access to Terraform state for SSO ReadOnly users"
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 Terraform state read access
      {
        Sid    = "S3TerraformStateReadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-*-s3-tfstate",
          "arn:aws:s3:::${var.project_name}-*-s3-tfstate/*"
        ]
      },
      # KMS decryption for state files (encrypted with the shared-services KMS key)
      {
        Sid    = "KMSDecryptTerraformState"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = "arn:aws:kms:*:${var.aws_account_id}:key/*"
        Condition = {
          "ForAnyValue:StringLike" = {
            "kms:ResourceAliases" = "alias/${var.project_name}-*-kms-tfstate-key"
          }
        }
      },
      # KMS used for Lambda encryption
      {
        Sid    = "KMSSharedServicesKey"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey",
          "kms:Encrypt",
          "kms:CreateGrant"
        ]
        Resource = "arn:aws:kms:*:${var.aws_account_id}:key/*"
        Condition = {
          "ForAnyValue:StringLike" = {
            "kms:ResourceAliases" = "alias/${var.project_name}-*-kms-shared-services-key"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-tfstate-readonly"
  })
}
