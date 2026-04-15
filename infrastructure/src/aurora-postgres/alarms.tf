################################################################################
# Aurora PostgreSQL CloudWatch Alarms
# Monitors CPU, memory, connections, deadlocks, capacity, and storage
################################################################################

module "aurora_alarms" {
  source = "../../modules/aurora-alarms"
  count  = var.sns_alerts_critical_topic_arn != null ? 1 : 0

  project_name          = var.project_name
  aws_account_shortname = var.aws_account_shortname
  environment           = var.environment

  cluster_identifier = module.aurora_postgres.cluster_id

  # Capacity threshold based on configured max ACU
  alarm_max_capacity_threshold = var.serverlessv2_max_capacity * 0.8

  alarm_actions     = [var.sns_alerts_critical_topic_arn]
  enable_ok_actions = var.enable_ok_actions

  tags = merge(local.common_tags, {
    Component = "aurora-alarms"
  })
}
