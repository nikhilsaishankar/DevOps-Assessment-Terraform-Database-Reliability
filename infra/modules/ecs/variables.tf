variable "project" {
  description = "Project name, used as a prefix for every resource name."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, ...)."
  type        = string
}

variable "region" {
  description = "AWS region. Needed explicitly for the awslogs driver configuration."
  type        = string
}

variable "vpc_id" {
  description = "VPC the target group is created in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for the Fargate tasks. Tasks get no public IP."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group for the ALB (created by the network module)."
  type        = string
}

variable "ecs_security_group_id" {
  description = "Security group for the Fargate tasks (created by the network module)."
  type        = string
}

# --- Load balancer ------------------------------------------------------------

variable "listener_port" {
  description = "Port the ALB listens on."
  type        = number
  default     = 80
}

variable "enable_deletion_protection" {
  description = "Prevent the ALB from being deleted. True in prod."
  type        = bool
  default     = false
}

variable "enable_access_logs" {
  description = "Write ALB access logs to S3. Requires access_logs_bucket."
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "Existing S3 bucket for ALB access logs."
  type        = string
  default     = ""
}

variable "health_check_path" {
  description = "Path the target group health check requests."
  type        = string
  default     = "/"
}

variable "health_check_matcher" {
  description = "HTTP status codes treated as healthy."
  type        = string
  default     = "200-399"
}

variable "idle_timeout" {
  description = "ALB idle timeout in seconds."
  type        = number
  default     = 60
}

# --- Task and service ---------------------------------------------------------

variable "container_name" {
  description = "Name of the container in the task definition."
  type        = string
  default     = "app"
}

variable "container_image" {
  description = <<-EOT
    Container image for the placeholder application. The brief allows any simple
    image; nginx is used so that the ALB health check succeeds with no app code.
    Replace with an ECR image reference for a real service.
  EOT
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.27-alpine"
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB. Must be a valid pairing with task_cpu."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to run."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count >= 1
    error_message = "desired_count must be at least 1."
  }
}

variable "deployment_minimum_healthy_percent" {
  description = "Lower bound, as a percentage of desired_count, on healthy tasks during a deployment."
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "Upper bound, as a percentage of desired_count, on running tasks during a deployment."
  type        = number
  default     = 200
}

variable "enable_execute_command" {
  description = "Allow `aws ecs execute-command` into running tasks. Convenient in dev, audited access in prod."
  type        = bool
  default     = false
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights on the cluster."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention for the task log group."
  type        = number
  default     = 30
}

variable "container_environment" {
  description = "Plain environment variables for the container. Never put secrets here - they are visible in the task definition."
  type        = map(string)
  default     = {}
}

variable "db_secret_arn" {
  description = <<-EOT
    ARN of the Secrets Manager secret holding the database credentials. It is
    injected into the container as the DB_SECRET environment variable by the ECS
    agent at start-up, and the execution role is granted read access to exactly
    that one secret. Only read when inject_db_secret is true.
  EOT
  type        = string
  default     = ""
}

variable "inject_db_secret" {
  description = <<-EOT
    Whether to wire db_secret_arn into the task definition and grant the
    execution role read access to it.

    This is a separate boolean rather than a `db_secret_arn != ""` test on
    purpose. The ARN is produced by the rds module, so its value is unknown
    until apply, and Terraform cannot evaluate `count` from an unknown value -
    it fails with "Invalid count argument" before planning anything. A plain
    bool supplied by the caller is known at plan time, so the conditional
    resources plan cleanly on a first run against an empty state.
  EOT
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags applied to resources in this module."
  type        = map(string)
  default     = {}
}
