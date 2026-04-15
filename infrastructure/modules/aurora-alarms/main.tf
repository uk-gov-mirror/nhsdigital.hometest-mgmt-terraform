################################################################################
# Aurora PostgreSQL Alarms Module
# CloudWatch alarms for Aurora Serverless v2 PostgreSQL cluster
################################################################################

locals {
  resource_prefix = "${var.project_name}-${var.aws_account_shortname}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Service      = "aurora-alarms"
      ManagedBy    = "terraform"
      Module       = "aurora-alarms"
      ResourceType = "cloudwatch-alarm"
    }
  )
}

################################################################################
# CPU Utilisation Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "aurora_cpu" {
  alarm_name          = "${local.resource_prefix}-aurora-cpu-high"
  alarm_description   = "Aurora cluster CPU utilisation exceeds ${var.alarm_cpu_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-aurora-cpu-high"
  })
}

################################################################################
# Freeable Memory Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "aurora_memory" {
  alarm_name          = "${local.resource_prefix}-aurora-memory-low"
  alarm_description   = "Aurora cluster freeable memory below ${var.alarm_freeable_memory_threshold_mb}MB"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.alarm_freeable_memory_threshold_mb * 1024 * 1024 # Convert MB to bytes
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-aurora-memory-low"
  })
}

################################################################################
# Database Connections Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "aurora_connections" {
  alarm_name          = "${local.resource_prefix}-aurora-connections-high"
  alarm_description   = "Aurora cluster database connections exceed ${var.alarm_max_connections_threshold}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = var.alarm_period
  statistic           = "Maximum"
  threshold           = var.alarm_max_connections_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-aurora-connections-high"
  })
}

################################################################################
# Deadlocks Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "aurora_deadlocks" {
  alarm_name          = "${local.resource_prefix}-aurora-deadlocks"
  alarm_description   = "Aurora cluster detected deadlocks"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Deadlocks"
  namespace           = "AWS/RDS"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-aurora-deadlocks"
  })
}

################################################################################
# Aurora Replica Lag Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "aurora_replica_lag" {
  count = var.create_replica_lag_alarm ? 1 : 0

  alarm_name          = "${local.resource_prefix}-aurora-replica-lag-high"
  alarm_description   = "Aurora replica lag exceeds ${var.alarm_replica_lag_threshold_ms}ms"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "AuroraReplicaLag"
  namespace           = "AWS/RDS"
  period              = var.alarm_period
  statistic           = "Maximum"
  threshold           = var.alarm_replica_lag_threshold_ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-aurora-replica-lag-high"
  })
}

################################################################################
# Serverless Database Capacity (ACU) Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "aurora_capacity" {
  alarm_name          = "${local.resource_prefix}-aurora-capacity-high"
  alarm_description   = "Aurora Serverless capacity exceeds ${var.alarm_max_capacity_threshold} ACU"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ServerlessDatabaseCapacity"
  namespace           = "AWS/RDS"
  period              = var.alarm_period
  statistic           = "Maximum"
  threshold           = var.alarm_max_capacity_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-aurora-capacity-high"
  })
}

################################################################################
# Free Local Storage Alarm
################################################################################

resource "aws_cloudwatch_metric_alarm" "aurora_storage" {
  alarm_name          = "${local.resource_prefix}-aurora-storage-low"
  alarm_description   = "Aurora free local storage below ${var.alarm_free_storage_threshold_gb}GB"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "FreeLocalStorage"
  namespace           = "AWS/RDS"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.alarm_free_storage_threshold_gb * 1024 * 1024 * 1024 # Convert GB to bytes
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.enable_ok_actions ? var.alarm_actions : []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-aurora-storage-low"
  })
}
