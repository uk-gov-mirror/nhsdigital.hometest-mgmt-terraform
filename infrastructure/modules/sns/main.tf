################################################################################
# SNS Module
# AWS SNS topics with encryption and subscription support
################################################################################

locals {
  topic_name_suffix = coalesce(var.topic_name_suffix, "topic")

  topic_name = "${var.project_name}-${var.aws_account_shortname}-${var.environment}-${local.topic_name_suffix}"

  common_tags = merge(
    var.tags,
    {
      Name         = local.topic_name
      Service      = "sns"
      ManagedBy    = "terraform"
      Module       = "sns"
      ResourceType = "topic"
    }
  )
}

################################################################################
# SNS Topic
################################################################################

module "topic" {
  source  = "terraform-aws-modules/sns/aws"
  version = "~> 7.1.0"

  name         = local.topic_name
  display_name = var.display_name

  # FIFO configuration
  fifo_topic                  = var.fifo_topic
  content_based_deduplication = var.content_based_deduplication
  fifo_throughput_scope       = var.fifo_throughput_scope

  # Encryption
  kms_master_key_id = var.kms_master_key_id

  # Policies
  create_topic_policy         = var.create_topic_policy
  enable_default_topic_policy = var.enable_default_topic_policy
  topic_policy_statements     = var.topic_policy_statements
  topic_policy                = var.topic_policy

  # Subscriptions
  create_subscription = var.create_subscription
  subscriptions       = var.subscriptions

  # Additional configuration
  delivery_policy        = var.delivery_policy
  data_protection_policy = var.data_protection_policy
  tracing_config         = var.tracing_config
  signature_version      = var.signature_version

  tags = local.common_tags
}
