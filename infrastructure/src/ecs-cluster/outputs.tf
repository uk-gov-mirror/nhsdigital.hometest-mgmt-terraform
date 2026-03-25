################################################################################
# ECS Cluster Outputs
################################################################################

output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "service_discovery_namespace_id" {
  description = "ID of the Cloud Map service discovery namespace"
  value       = aws_service_discovery_private_dns_namespace.main.id
}

output "service_discovery_namespace_arn" {
  description = "ARN of the Cloud Map service discovery namespace"
  value       = aws_service_discovery_private_dns_namespace.main.arn
}

output "service_discovery_namespace_name" {
  description = "Name of the Cloud Map service discovery namespace"
  value       = aws_service_discovery_private_dns_namespace.main.name
}

output "ecs_tasks_security_group_id" {
  description = "ID of the shared ECS tasks baseline security group"
  value       = aws_security_group.ecs_tasks.id
}

output "ecs_tasks_log_group_name" {
  description = "Name of the CloudWatch log group for ECS tasks"
  value       = aws_cloudwatch_log_group.ecs_tasks.name
}

output "ecs_tasks_log_group_arn" {
  description = "ARN of the CloudWatch log group for ECS tasks"
  value       = aws_cloudwatch_log_group.ecs_tasks.arn
}
