################################################################################
# ECS Cluster Outputs
################################################################################

output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = module.ecs_cluster.id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs_cluster.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_cluster.name
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

################################################################################
# Shared ALB Outputs
################################################################################

output "alb_arn" {
  description = "ARN of the shared ECS ALB"
  value       = try(module.ecs_alb[0].arn, null)
}

output "alb_dns_name" {
  description = "DNS name of the shared ECS ALB"
  value       = try(module.ecs_alb[0].dns_name, null)
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID of the shared ECS ALB (for Route53 alias)"
  value       = try(module.ecs_alb[0].zone_id, null)
}

output "alb_security_group_id" {
  description = "Security group ID of the shared ECS ALB"
  value       = try(module.ecs_alb[0].security_group_id, null)
}

output "alb_https_listener_arn" {
  description = "ARN of the HTTPS listener on the shared ALB"
  value       = try(module.ecs_alb[0].listeners["https"].arn, null)
}
