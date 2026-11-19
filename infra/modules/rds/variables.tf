variable "project" {
  description = "Project name, used as a prefix for every resource name."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, ...)."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the DB subnet group. At least two, in different AZs."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "RDS requires a subnet group spanning at least two availability zones."
  }
}

variable "rds_security_group_id" {
  description = "Security group for the instance (created by the network module). Ingress from the ECS tasks only."
  type        = string
}

# --- Engine -------------------------------------------------------------------

variable "engine" {
  description = "RDS engine. The local Docker Compose stack and the SQL in db/ target PostgreSQL."
  type        = string
  default     = "postgres"

  validation {
    condition     = contains(["postgres", "mysql"], var.engine)
    error_message = "engine must be postgres or mysql."
  }
}

variable "engine_version" {
  description = "Major engine version. Given as a major version only so that RDS selects the current minor release and auto_minor_version_upgrade does not produce permanent drift."
  type        = string
  default     = "16"
}

variable "parameter_group_family" {
  description = "Parameter group family, must match engine_version (e.g. postgres16, mysql8.0)."
  type        = string
  default     = "postgres16"
}

variable "port" {
  description = "Port the instance listens on."
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Name of the initial database."
  type        = string
  default     = "hotels"
}

variable "master_username" {
  description = "Master username. The password is generated, never set by hand."
  type        = string
  default     = "hotels_admin"
}

# --- Sizing -------------------------------------------------------------------

variable "instance_class" {
  description = "Instance class. Sized per environment."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper bound for storage autoscaling in GiB. Set equal to allocated_storage to disable."
  type        = number
  default     = 100
}

variable "storage_type" {
  description = "EBS volume type for the instance."
  type        = string
  default     = "gp3"
}

variable "multi_az" {
  description = "Run a synchronous standby in a second AZ. True in prod."
  type        = bool
  default     = false
}

# --- Reliability --------------------------------------------------------------

variable "backup_retention_period" {
  description = "Days of automated backups to keep. 0 disables them, which also disables point-in-time recovery."
  type        = number
  default     = 1

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 0 and 35 days."
  }
}

variable "backup_window" {
  description = "Daily UTC window for automated backups. Chosen off-peak for IST traffic."
  type        = string
  default     = "18:00-19:00"
}

variable "maintenance_window" {
  description = "Weekly UTC maintenance window. Must not overlap backup_window."
  type        = string
  default     = "sun:19:30-sun:20:30"
}

variable "deletion_protection" {
  description = "Refuse to delete the instance. True in prod."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. True in dev so the environment can be torn down cleanly."
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply changes at once instead of in the next maintenance window. True in dev."
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights."
  type        = bool
  default     = false
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention in days. 7 is the free tier; otherwise 31-month multiples (93, 186, 341, 589, 731)."
  type        = number
  default     = 7
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0, 1, 5, 10, 15, 30, 60). 0 disables it and skips the monitoring role."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "enabled_cloudwatch_logs_exports" {
  description = "Engine log types to ship to CloudWatch Logs (postgres: postgresql, upgrade)."
  type        = list(string)
  default     = []
}

variable "kms_key_id" {
  description = "Customer managed KMS key for storage encryption. Empty uses the AWS managed aws/rds key."
  type        = string
  default     = ""
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window. 0 deletes the secret immediately, which is what makes repeated dev teardown possible."
  type        = number
  default     = 0
}

variable "log_min_duration_statement" {
  description = "Log statements slower than this many milliseconds. -1 disables. Feeds the slow-query review the index work in db/ is based on."
  type        = number
  default     = 1000
}

variable "tags" {
  description = "Additional tags applied to resources in this module."
  type        = map(string)
  default     = {}
}
