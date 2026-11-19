###############################################################################
# Environment root
#
# Wires the three modules together:
#
#   network -> (subnets + the three security groups)
#     rds   -> consumes rds_security_group_id, publishes its secret ARN
#     ecs   -> consumes alb/ecs security group ids and the RDS secret ARN
#
# Because the security groups are owned by the network module, the rds -> ecs
# edge is the only cross-module dependency between the two, and the module
# graph stays acyclic.
###############################################################################

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = "terraform"
    Repository  = "devops-assessment-terraform-db"
  }
}

module "network" {
  source = "../../modules/network"

  project     = var.project
  environment = var.environment

  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  alb_ingress_cidrs = var.alb_ingress_cidrs
  alb_listener_port = 80
  container_port    = var.container_port
  db_port           = var.db_port

  enable_flow_logs        = var.enable_flow_logs
  flow_log_retention_days = var.log_retention_days

  tags = local.common_tags
}

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  private_subnet_ids    = module.network.private_subnet_ids
  rds_security_group_id = module.network.rds_security_group_id

  engine                 = var.db_engine
  engine_version         = var.db_engine_version
  parameter_group_family = var.db_parameter_group_family
  port                   = var.db_port
  db_name                = var.db_name

  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  multi_az              = var.db_multi_az

  backup_retention_period = var.db_backup_retention_period
  deletion_protection     = var.db_deletion_protection
  skip_final_snapshot     = var.db_skip_final_snapshot
  apply_immediately       = var.db_apply_immediately

  performance_insights_enabled    = var.db_performance_insights_enabled
  monitoring_interval             = var.db_monitoring_interval
  enabled_cloudwatch_logs_exports = var.db_cloudwatch_logs_exports
  secret_recovery_window_days     = var.db_secret_recovery_window_days

  tags = local.common_tags
}

module "ecs" {
  source = "../../modules/ecs"

  project     = var.project
  environment = var.environment
  region      = var.region

  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.network.alb_security_group_id
  ecs_security_group_id = module.network.ecs_security_group_id

  listener_port              = 80
  enable_deletion_protection = var.alb_deletion_protection
  health_check_path          = "/"

  container_image = var.container_image
  container_port  = var.container_port
  task_cpu        = var.task_cpu
  task_memory     = var.task_memory
  desired_count   = var.desired_count

  container_insights     = var.container_insights
  enable_execute_command = var.enable_execute_command
  log_retention_days     = var.log_retention_days

  # Connection details the application needs. The password is not here - the
  # task reads it from the secret below.
  container_environment = {
    DB_HOST = module.rds.address
    DB_PORT = tostring(module.rds.port)
    DB_NAME = module.rds.db_name
    DB_USER = module.rds.master_username
  }

  db_secret_arn    = module.rds.master_secret_arn
  inject_db_secret = true

  tags = local.common_tags
}
