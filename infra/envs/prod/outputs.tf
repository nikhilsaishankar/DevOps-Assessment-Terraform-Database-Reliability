output "alb_dns_name" {
  description = "Public entry point. Open http://<this value>/ once applied."
  value       = module.ecs.alb_dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = module.ecs.service_name
}

output "ecs_log_group" {
  description = "CloudWatch log group with container logs."
  value       = module.ecs.log_group_name
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets hosting the tasks and the database."
  value       = module.network.private_subnet_ids
}

output "nat_gateway_public_ips" {
  description = "Stable egress IPs of this environment, for third-party allow lists."
  value       = module.network.nat_gateway_public_ips
}

output "db_endpoint" {
  description = "Database endpoint. Resolvable only from inside the VPC."
  value       = module.rds.endpoint
}

output "db_secret_name" {
  description = "Secrets Manager secret holding the master credentials."
  value       = module.rds.master_secret_name
}

output "db_reliability_settings" {
  description = "The per-environment reliability knobs, surfaced together so the dev/prod difference is visible in `terraform output`."
  value = {
    instance_class          = var.db_instance_class
    multi_az                = module.rds.multi_az
    backup_retention_days   = module.rds.backup_retention_period
    deletion_protection     = module.rds.deletion_protection
    skip_final_snapshot     = var.db_skip_final_snapshot
    performance_insights    = var.db_performance_insights_enabled
    enhanced_monitoring_sec = var.db_monitoring_interval
  }
}
