################################################################################
# AWS Cognito User Pool
################################################################################

resource "aws_cognito_user_pool" "main" {
  count = var.enable_cognito ? 1 : 0

  name = "${local.resource_prefix}-user-pool"

  # Account recovery settings
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Admin create user settings
  admin_create_user_config {
    allow_admin_create_user_only = var.cognito_allow_admin_create_user_only

    invite_message_template {
      email_subject = var.cognito_invite_email_subject
      email_message = var.cognito_invite_email_message
      sms_message   = var.cognito_invite_sms_message
    }
  }

  # Auto-verified attributes
  auto_verified_attributes = var.cognito_auto_verified_attributes

  # Deletion protection
  deletion_protection = var.cognito_deletion_protection ? "ACTIVE" : "INACTIVE"

  # Device configuration
  device_configuration {
    challenge_required_on_new_device      = var.cognito_device_challenge_required
    device_only_remembered_on_user_prompt = var.cognito_device_remember_on_prompt
  }

  # Email configuration
  email_configuration {
    email_sending_account = var.cognito_email_sending_account
    source_arn            = var.cognito_ses_email_identity_arn
    from_email_address    = var.cognito_from_email_address
  }

  # MFA configuration
  mfa_configuration = var.cognito_mfa_configuration

  dynamic "software_token_mfa_configuration" {
    for_each = var.cognito_mfa_configuration != "OFF" ? [1] : []
    content {
      enabled = true
    }
  }

  # Password policy
  password_policy {
    minimum_length                   = var.cognito_password_minimum_length
    require_lowercase                = var.cognito_password_require_lowercase
    require_numbers                  = var.cognito_password_require_numbers
    require_symbols                  = var.cognito_password_require_symbols
    require_uppercase                = var.cognito_password_require_uppercase
    temporary_password_validity_days = var.cognito_temporary_password_validity_days
  }

  # Schema attributes
  dynamic "schema" {
    for_each = var.cognito_custom_attributes
    content {
      name                     = schema.value.name
      attribute_data_type      = schema.value.attribute_data_type
      developer_only_attribute = lookup(schema.value, "developer_only_attribute", false)
      mutable                  = lookup(schema.value, "mutable", true)
      required                 = lookup(schema.value, "required", false)

      dynamic "string_attribute_constraints" {
        for_each = schema.value.attribute_data_type == "String" ? [1] : []
        content {
          min_length = lookup(schema.value, "min_length", 0)
          max_length = lookup(schema.value, "max_length", 2048)
        }
      }

      dynamic "number_attribute_constraints" {
        for_each = schema.value.attribute_data_type == "Number" ? [1] : []
        content {
          min_value = lookup(schema.value, "min_value", null)
          max_value = lookup(schema.value, "max_value", null)
        }
      }
    }
  }

  # Username configuration
  username_configuration {
    case_sensitive = var.cognito_username_case_sensitive
  }

  # User attribute update settings
  user_attribute_update_settings {
    attributes_require_verification_before_update = var.cognito_attributes_require_verification
  }

  # Verification message template
  verification_message_template {
    default_email_option  = var.cognito_verification_email_option
    email_subject         = var.cognito_verification_email_subject
    email_message         = var.cognito_verification_email_message
    email_subject_by_link = var.cognito_verification_email_subject_by_link
    email_message_by_link = var.cognito_verification_email_message_by_link
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-user-pool"
  })
}

################################################################################
# Cognito User Pool Domain
################################################################################

resource "aws_cognito_user_pool_domain" "main" {
  count = var.enable_cognito ? 1 : 0

  domain       = var.cognito_custom_domain != "" ? var.cognito_custom_domain : "${var.project_name}-${var.aws_account_shortname}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main[0].id

  # Custom domain requires a certificate
  certificate_arn = var.cognito_custom_domain != "" ? var.cognito_domain_certificate_arn : null
}

################################################################################
# Cognito User Pool Client
################################################################################

resource "aws_cognito_user_pool_client" "main" {
  count = var.enable_cognito ? 1 : 0

  name         = "${local.resource_prefix}-client"
  user_pool_id = aws_cognito_user_pool.main[0].id

  # Token validity
  access_token_validity  = var.cognito_access_token_validity
  id_token_validity      = var.cognito_id_token_validity
  refresh_token_validity = var.cognito_refresh_token_validity

  token_validity_units {
    access_token  = var.cognito_access_token_validity_units
    id_token      = var.cognito_id_token_validity_units
    refresh_token = var.cognito_refresh_token_validity_units
  }

  # OAuth settings
  allowed_oauth_flows                  = var.cognito_allowed_oauth_flows
  allowed_oauth_flows_user_pool_client = var.cognito_allowed_oauth_flows_user_pool_client
  allowed_oauth_scopes                 = var.cognito_allowed_oauth_scopes
  callback_urls                        = var.cognito_callback_urls
  logout_urls                          = var.cognito_logout_urls
  supported_identity_providers         = var.cognito_supported_identity_providers

  # Security settings
  generate_secret                               = var.cognito_generate_client_secret
  prevent_user_existence_errors                 = var.cognito_prevent_user_existence_errors
  enable_token_revocation                       = var.cognito_enable_token_revocation
  enable_propagate_additional_user_context_data = var.cognito_enable_propagate_user_context

  # Auth flows
  explicit_auth_flows = var.cognito_explicit_auth_flows

  # Read/Write attributes
  read_attributes  = var.cognito_read_attributes
  write_attributes = var.cognito_write_attributes

}

################################################################################
# Cognito Resource Server (for custom scopes)
################################################################################

resource "aws_cognito_resource_server" "main" {
  count = var.enable_cognito && length(var.cognito_resource_server_scopes) > 0 ? 1 : 0

  identifier   = var.cognito_resource_server_identifier != "" ? var.cognito_resource_server_identifier : "https://${var.domain_name}"
  name         = "${local.resource_prefix}-resource-server"
  user_pool_id = aws_cognito_user_pool.main[0].id

  dynamic "scope" {
    for_each = var.cognito_resource_server_scopes
    content {
      scope_name        = scope.value.name
      scope_description = scope.value.description
    }
  }
}

################################################################################
# Cognito Identity Pool (for federated identities)
################################################################################

resource "aws_cognito_identity_pool" "main" {
  count = var.enable_cognito && var.enable_cognito_identity_pool ? 1 : 0

  identity_pool_name               = "${local.resource_prefix}-identity-pool"
  allow_unauthenticated_identities = var.cognito_allow_unauthenticated_identities
  allow_classic_flow               = var.cognito_allow_classic_flow

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.main[0].id
    provider_name           = aws_cognito_user_pool.main[0].endpoint
    server_side_token_check = var.cognito_server_side_token_check
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-identity-pool"
  })
}

################################################################################
# IAM Roles for Identity Pool
################################################################################

data "aws_iam_policy_document" "cognito_identity_assume_role" {
  count = var.enable_cognito && var.enable_cognito_identity_pool ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["cognito-identity.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "cognito-identity.amazonaws.com:aud"
      values   = [aws_cognito_identity_pool.main[0].id]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "cognito-identity.amazonaws.com:amr"
      values   = ["authenticated"]
    }
  }
}

resource "aws_iam_role" "cognito_authenticated" {
  count = var.enable_cognito && var.enable_cognito_identity_pool ? 1 : 0

  name               = "${local.resource_prefix}-cognito-authenticated"
  assume_role_policy = data.aws_iam_policy_document.cognito_identity_assume_role[0].json

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-cognito-authenticated"
  })
}

resource "aws_iam_role_policy" "cognito_authenticated" {
  count = var.enable_cognito && var.enable_cognito_identity_pool ? 1 : 0

  name = "${local.resource_prefix}-cognito-authenticated-policy"
  role = aws_iam_role.cognito_authenticated[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "mobileanalytics:PutEvents",
          "cognito-sync:*",
          "cognito-identity:*"
        ]
        Resource = "*"
      }
    ]
  })
}

data "aws_iam_policy_document" "cognito_identity_unauthenticated_assume_role" {
  count = var.enable_cognito && var.enable_cognito_identity_pool && var.cognito_allow_unauthenticated_identities ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["cognito-identity.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "cognito-identity.amazonaws.com:aud"
      values   = [aws_cognito_identity_pool.main[0].id]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "cognito-identity.amazonaws.com:amr"
      values   = ["unauthenticated"]
    }
  }
}

resource "aws_iam_role" "cognito_unauthenticated" {
  count = var.enable_cognito && var.enable_cognito_identity_pool && var.cognito_allow_unauthenticated_identities ? 1 : 0

  name               = "${local.resource_prefix}-cognito-unauthenticated"
  assume_role_policy = data.aws_iam_policy_document.cognito_identity_unauthenticated_assume_role[0].json

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-cognito-unauthenticated"
  })
}

resource "aws_iam_role_policy" "cognito_unauthenticated" {
  count = var.enable_cognito && var.enable_cognito_identity_pool && var.cognito_allow_unauthenticated_identities ? 1 : 0

  name = "${local.resource_prefix}-cognito-unauthenticated-policy"
  role = aws_iam_role.cognito_unauthenticated[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "mobileanalytics:PutEvents",
          "cognito-sync:*"
        ]
        Resource = "*"
      }
    ]
  })
}

################################################################################
# Identity Pool Role Attachment
################################################################################

resource "aws_cognito_identity_pool_roles_attachment" "main" {
  count = var.enable_cognito && var.enable_cognito_identity_pool ? 1 : 0

  identity_pool_id = aws_cognito_identity_pool.main[0].id

  roles = merge(
    {
      "authenticated" = aws_iam_role.cognito_authenticated[0].arn
    },
    var.cognito_allow_unauthenticated_identities ? {
      "unauthenticated" = aws_iam_role.cognito_unauthenticated[0].arn
    } : {}
  )
}

################################################################################
# M2M Resource Servers
################################################################################

resource "aws_cognito_resource_server" "results" {
  count = var.enable_cognito ? 1 : 0

  identifier   = "results"
  name         = "${local.resource_prefix}-results"
  user_pool_id = aws_cognito_user_pool.main[0].id

  scope {
    scope_name        = "write"
    scope_description = "Write access to Test Results"
  }
}

resource "aws_cognito_resource_server" "orders" {
  count = var.enable_cognito ? 1 : 0

  identifier   = "orders"
  name         = "${local.resource_prefix}-orders"
  user_pool_id = aws_cognito_user_pool.main[0].id

  scope {
    scope_name        = "write"
    scope_description = "Write access to Test Orders"
  }
}

################################################################################
# M2M App Clients
################################################################################

resource "aws_cognito_user_pool_client" "internal_test_client_m2m" {
  count = var.enable_cognito ? 1 : 0

  name         = "${local.resource_prefix}-internal-test-client-m2m"
  user_pool_id = aws_cognito_user_pool.main[0].id

  # Generate client secret for M2M
  generate_secret = true

  # Token validity
  access_token_validity = 60 # 60 minutes

  token_validity_units {
    access_token = "minutes"
  }

  # OAuth settings for client credentials flow (M2M)
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = [
    "${aws_cognito_resource_server.results[0].identifier}/write",
    "${aws_cognito_resource_server.orders[0].identifier}/write",
  ]

  # Disable user-based auth flows
  explicit_auth_flows = []

  # Security settings
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  depends_on = [
    aws_cognito_resource_server.results,
    aws_cognito_resource_server.orders
  ]
}

resource "aws_cognito_user_pool_client" "preventex_m2m" {
  count = var.enable_cognito ? 1 : 0

  name         = "${local.resource_prefix}-preventex-m2m"
  user_pool_id = aws_cognito_user_pool.main[0].id

  # Generate client secret for M2M
  generate_secret = true

  # Token validity
  access_token_validity = 60 # 60 minutes

  token_validity_units {
    access_token = "minutes"
  }

  # OAuth settings for client credentials flow (M2M)
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = [
    "${aws_cognito_resource_server.results[0].identifier}/write",
    "${aws_cognito_resource_server.orders[0].identifier}/write",
  ]

  # Disable user-based auth flows
  explicit_auth_flows = []

  # Security settings
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  depends_on = [
    aws_cognito_resource_server.results,
    aws_cognito_resource_server.orders
  ]
}

resource "aws_cognito_user_pool_client" "sh24_m2m" {
  count = var.enable_cognito ? 1 : 0

  name         = "${local.resource_prefix}-sh24-m2m"
  user_pool_id = aws_cognito_user_pool.main[0].id

  # Generate client secret for M2M
  generate_secret = true

  # Token validity
  access_token_validity = 60 # 60 minutes

  token_validity_units {
    access_token = "minutes"
  }

  # OAuth settings for client credentials flow (M2M)
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = [
    "${aws_cognito_resource_server.results[0].identifier}/write",
    "${aws_cognito_resource_server.orders[0].identifier}/write",
  ]

  # Disable user-based auth flows
  explicit_auth_flows = []

  # Security settings
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  depends_on = [
    aws_cognito_resource_server.results,
    aws_cognito_resource_server.orders
  ]
}
