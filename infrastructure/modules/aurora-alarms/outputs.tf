################################################################################
# Aurora PostgreSQL Alarms Module Outputs
################################################################################

output "alarm_cpu_arn" {
  description = "ARN of the CPU utilisation alarm"
  value       = aws_cloudwatch_metric_alarm.aurora_cpu.arn
}

output "alarm_memory_arn" {
  description = "ARN of the freeable memory alarm"
  value       = aws_cloudwatch_metric_alarm.aurora_memory.arn
}

output "alarm_connections_arn" {
  description = "ARN of the database connections alarm"
  value       = aws_cloudwatch_metric_alarm.aurora_connections.arn
}

output "alarm_deadlocks_arn" {
  description = "ARN of the deadlocks alarm"
  value       = aws_cloudwatch_metric_alarm.aurora_deadlocks.arn
}

output "alarm_replica_lag_arn" {
  description = "ARN of the replica lag alarm (if created)"
  value       = try(aws_cloudwatch_metric_alarm.aurora_replica_lag[0].arn, null)
}

output "alarm_capacity_arn" {
  description = "ARN of the serverless capacity alarm"
  value       = aws_cloudwatch_metric_alarm.aurora_capacity.arn
}

output "alarm_storage_arn" {
  description = "ARN of the free local storage alarm"
  value       = aws_cloudwatch_metric_alarm.aurora_storage.arn
}
