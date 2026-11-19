output "alb_dns_name" {
  description = "Public DNS name of the ALB - the entry point of the stack."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB, for a Route 53 alias record."
  value       = aws_lb.this.zone_id
}

output "alb_arn" {
  description = "ARN of the ALB."
  value       = aws_lb.this.arn
}

output "target_group_arn" {
  description = "ARN of the target group."
  value       = aws_lb_target_group.this.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "ARN of the task definition revision currently referenced by the service."
  value       = aws_ecs_task_definition.this.arn
}

output "task_execution_role_arn" {
  description = "ARN of the ECS execution role."
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "ARN of the application task role."
  value       = aws_iam_role.task.arn
}

output "log_group_name" {
  description = "CloudWatch log group receiving container logs."
  value       = aws_cloudwatch_log_group.app.name
}
