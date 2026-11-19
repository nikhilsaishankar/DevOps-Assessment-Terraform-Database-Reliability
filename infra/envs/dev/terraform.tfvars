###############################################################################
# dev - small, cheap, disposable
#
# Deliberate choices:
#   * one NAT gateway shared by both AZs      -> ~50% of the prod NAT bill
#   * backup retention 1 day                  -> enough to undo a bad migration
#   * deletion_protection = false              -> the environment can be torn down
#   * skip_final_snapshot = true               -> destroy does not leave artefacts
#   * ECS Exec enabled                         -> debugging without a bastion
###############################################################################

environment = "dev"
region      = "ap-south-1"
owner       = "platform"
cost_center = "engineering-dev"

# --- network ---
vpc_cidr           = "10.20.0.0/16"
availability_zones = ["ap-south-1a", "ap-south-1b"]
single_nat_gateway = true
alb_ingress_cidrs  = ["0.0.0.0/0"]
enable_flow_logs   = false

# --- ecs ---
container_image         = "public.ecr.aws/nginx/nginx:1.27-alpine"
container_port          = 80
task_cpu                = 256
task_memory             = 512
desired_count           = 1
container_insights      = false
enable_execute_command  = true
alb_deletion_protection = false
log_retention_days      = 7

# --- rds ---
db_engine                       = "postgres"
db_engine_version               = "16"
db_parameter_group_family       = "postgres16"
db_port                         = 5432
db_name                         = "hotels"
db_instance_class               = "db.t4g.micro"
db_allocated_storage            = 20
db_max_allocated_storage        = 50
db_multi_az                     = false
db_backup_retention_period      = 1
db_deletion_protection          = false
db_skip_final_snapshot          = true
db_apply_immediately            = true
db_performance_insights_enabled = false
db_monitoring_interval          = 0
db_cloudwatch_logs_exports      = []
db_secret_recovery_window_days  = 0
