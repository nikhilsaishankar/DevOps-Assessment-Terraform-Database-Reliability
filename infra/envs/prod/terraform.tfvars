###############################################################################
# prod - sized and protected
#
# Deliberate choices:
#   * one NAT gateway per AZ                   -> an AZ outage does not remove egress
#   * Multi-AZ RDS                             -> automatic failover to the standby
#   * backup retention 30 days                 -> 30 days of point-in-time recovery
#   * deletion_protection = true                -> destroy fails on purpose
#   * skip_final_snapshot = false               -> a snapshot survives a deletion
#   * ECS Exec disabled                         -> no interactive shells in prod
#   * changes wait for the maintenance window
###############################################################################

environment = "prod"
region      = "ap-south-1"
owner       = "platform"
cost_center = "engineering-prod"

# --- network ---
vpc_cidr           = "10.30.0.0/16"
availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
single_nat_gateway = false
alb_ingress_cidrs  = ["0.0.0.0/0"]
enable_flow_logs   = true

# --- ecs ---
container_image         = "public.ecr.aws/nginx/nginx:1.27-alpine"
container_port          = 80
task_cpu                = 1024
task_memory             = 2048
desired_count           = 3
container_insights      = true
enable_execute_command  = false
alb_deletion_protection = true
log_retention_days      = 90

# --- rds ---
db_engine                       = "postgres"
db_engine_version               = "16"
db_parameter_group_family       = "postgres16"
db_port                         = 5432
db_name                         = "hotels"
db_instance_class               = "db.m6g.large"
db_allocated_storage            = 100
db_max_allocated_storage        = 500
db_multi_az                     = true
db_backup_retention_period      = 30
db_deletion_protection          = true
db_skip_final_snapshot          = false
db_apply_immediately            = false
db_performance_insights_enabled = true
db_monitoring_interval          = 60
db_cloudwatch_logs_exports      = ["postgresql", "upgrade"]
db_secret_recovery_window_days  = 30
