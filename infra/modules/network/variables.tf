variable "project" {
  description = "Project name, used as a prefix for every resource name."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, ...)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, e.g. 10.20.0.0/16."
  }
}

variable "availability_zones" {
  description = <<-EOT
    Explicit list of AZs to spread subnets across. Passed in rather than looked up
    with the aws_availability_zones data source so that `terraform plan` works
    without AWS credentials (see README, "Plan-only configuration").
  EOT
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two availability zones are required: both the ALB and the RDS subnet group need multi-AZ coverage."
  }
}

variable "subnet_newbits" {
  description = "Number of bits to add to the VPC prefix when carving subnets. 4 on a /16 yields /20 subnets."
  type        = number
  default     = 4
}

variable "enable_nat_gateway" {
  description = "Create NAT gateways so that private subnets have outbound internet access (needed for ECR image pulls, CloudWatch Logs and Secrets Manager)."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ. Cheaper, but a single AZ failure takes out egress for every private subnet. Intended for dev only."
  type        = bool
  default     = false
}

variable "alb_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the ALB listener."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "alb_listener_port" {
  description = "Port the ALB listens on."
  type        = number
  default     = 80
}

variable "container_port" {
  description = "Port the application container listens on. The ALB security group is allowed to reach the ECS tasks only on this port."
  type        = number
  default     = 80
}

variable "db_port" {
  description = "Port the RDS instance listens on. Only the ECS task security group is allowed to reach it."
  type        = number
  default     = 5432
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs to CloudWatch Logs."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "Retention for the VPC flow log group."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags applied to resources in this module."
  type        = map(string)
  default     = {}
}
