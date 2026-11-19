output "identifier" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.identifier
}

output "address" {
  description = "Hostname of the instance. Resolvable only inside the VPC."
  value       = aws_db_instance.this.address
}

output "endpoint" {
  description = "host:port of the instance."
  value       = aws_db_instance.this.endpoint
}

output "port" {
  description = "Port the instance listens on."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.this.db_name
}

output "master_username" {
  description = "Master username."
  value       = aws_db_instance.this.username
}

output "master_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the master credentials. Passed to the ECS module so the task can read it."
  value       = aws_secretsmanager_secret.master.arn
}

output "master_secret_name" {
  description = "Name of the Secrets Manager secret, for `aws secretsmanager get-secret-value`."
  value       = aws_secretsmanager_secret.master.name
}

output "backup_retention_period" {
  description = "Effective automated backup retention in days - echoed so the per-environment difference is visible in `terraform output`."
  value       = aws_db_instance.this.backup_retention_period
}

output "deletion_protection" {
  description = "Effective deletion protection setting."
  value       = aws_db_instance.this.deletion_protection
}

output "multi_az" {
  description = "Whether a standby is running in a second AZ."
  value       = aws_db_instance.this.multi_az
}
