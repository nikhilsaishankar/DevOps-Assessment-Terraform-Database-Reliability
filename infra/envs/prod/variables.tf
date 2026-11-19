variable "project" {
  description = "Project name, used as a prefix for every resource name."
  type        = string
  default     = "hotelbook"
}

variable "environment" {
  description = "Environment name. Set per environment directory; do not override."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "owner" {
  description = "Team or individual responsible for this environment. Applied as a tag."
  type        = string
  default     = "platform"
}

variable "cost_center" {
  description = "Cost allocation tag value."
  type        = string
  default     = "engineering"
}

# --- Network ------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Non-overlapping across environments so the two can be peered later."
  type        = string
}

variable "availability_zones" {
  description = "AZs to spread subnets across. Listed explicitly so plan works without AWS credentials."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway across all private subnets."
  type        = bool
}

variable "alb_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs."
  type        = bool
  default     = false
}

# --- ECS ----------------------------------------------------------------------

variable "container_image" {
  description = "Image for the placeholder application container."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.27-alpine"
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "Fargate task CPU units."
  type        = number
}

variable "task_memory" {
  description = "Fargate task memory in MiB."
  type        = number
}

variable "desired_count" {
  description = "Number of tasks to run."
  type        = number
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights."
  type        = bool
  default     = false
}

variable "enable_execute_command" {
  description = "Allow ECS Exec into running tasks."
  type        = bool
  default     = false
}

variable "alb_deletion_protection" {
  description = "Prevent the ALB from being deleted."
  type        = bool
}

variable "log_retention_days" {
  description = "Retention for the container log group."
  type        = number
}

# --- RDS ----------------------------------------------------------------------

variable "db_engine" {
  description = "RDS engine (postgres or mysql)."
  type        = string
  default     = "postgres"
}

variable "db_engine_version" {
  description = "Major engine version."
  type        = string
  default     = "16"
}

variable "db_parameter_group_family" {
  description = "Parameter group family, must match db_engine_version."
  type        = string
  default     = "postgres16"
}

variable "db_port" {
  description = "Port the database listens on."
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Name of the initial database."
  type        = string
  default     = "hotels"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "db_allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
}

variable "db_max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB."
  type        = number
}

variable "db_multi_az" {
  description = "Run a standby in a second AZ."
  type        = bool
}

variable "db_backup_retention_period" {
  description = "Days of automated backups to keep."
  type        = number
}

variable "db_deletion_protection" {
  description = "Refuse to delete the instance."
  type        = bool
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot on destroy."
  type        = bool
}

variable "db_apply_immediately" {
  description = "Apply changes immediately instead of in the maintenance window."
  type        = bool
}

variable "db_performance_insights_enabled" {
  description = "Enable Performance Insights."
  type        = bool
}

variable "db_monitoring_interval" {
  description = "Enhanced monitoring interval in seconds. 0 disables."
  type        = number
}

variable "db_cloudwatch_logs_exports" {
  description = "Engine log types to ship to CloudWatch Logs."
  type        = list(string)
  default     = []
}

variable "db_secret_recovery_window_days" {
  description = "Secrets Manager recovery window for the master secret."
  type        = number
}

# --- Plan-only escape hatch ---------------------------------------------------

variable "plan_only" {
  description = <<-EOT
    Skip the AWS provider's credential preflight (STS GetCallerIdentity, account
    id lookup, EC2 metadata probe) so that `terraform plan` runs without an AWS
    account.

    Defaults to TRUE so that the review commands work verbatim:

      terraform init && terraform validate && terraform plan -refresh=false

    Without it the AWS provider v6 calls sts:GetCallerIdentity while configuring
    itself and the plan dies with InvalidClientTokenId before evaluating a single
    resource. Since this repository is reviewed rather than deployed, a plan that
    works with no credentials is the useful default.

    Set it to false for a real apply, so the provider validates its credentials
    up front instead of failing part-way through:

      terraform apply -var plan_only=false
  EOT
  type        = bool
  default     = true
}
