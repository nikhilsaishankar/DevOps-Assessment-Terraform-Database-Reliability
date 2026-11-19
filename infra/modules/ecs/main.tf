###############################################################################
# ECS / Fargate module
#
# Internet -> ALB (public subnets) -> Fargate tasks (private subnets)
#
# The tasks run with assign_public_ip = false. Their only route to the internet
# is the NAT gateway created by the network module, which is what lets the
# image pull and the CloudWatch Logs / Secrets Manager calls succeed without
# the tasks ever being reachable from outside the VPC.
###############################################################################

locals {
  name = "${var.project}-${var.environment}"

  tags = merge(var.tags, {
    Module = "ecs"
  })

  # Environment variables the container always gets, merged with whatever the
  # caller passes in (database host, port, name, ...).
  base_environment = {
    APP_ENV = var.environment
  }

  container_environment = merge(local.base_environment, var.container_environment)
}

resource "aws_ecs_cluster" "this" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }

  tags = merge(local.tags, {
    Name = local.name
  })
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days

  tags = local.tags
}

resource "aws_ecs_task_definition" "this" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        for key, value in local.container_environment : {
          name  = key
          value = value
        }
      ]

      # Credentials are fetched by the ECS agent from Secrets Manager at task
      # start-up. They are never written into the task definition, so they do
      # not appear in `describe-task-definition` output or in Terraform state.
      secrets = var.inject_db_secret ? [
        {
          name      = "DB_SECRET"
          valueFrom = var.db_secret_arn
        }
      ] : []

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = var.container_name
        }
      }

      # nginx writes its pid file and cache under / at start-up, so the root
      # filesystem cannot be read-only for this placeholder image. A purpose
      # built application image should set this to true.
      readonlyRootFilesystem = false
    }
  ])

  tags = merge(local.tags, {
    Name = local.name
  })
}

resource "aws_ecs_service" "this" {
  name            = local.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  launch_type      = "FARGATE"
  platform_version = "LATEST"

  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  enable_execute_command = var.enable_execute_command

  # Give the container time to boot before the first failed health check can
  # kill it.
  health_check_grace_period_seconds = 60

  wait_for_steady_state = false

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(local.tags, {
    Name = local.name
  })

  # The service cannot be registered with a target group until the listener
  # that forwards to it exists.
  depends_on = [aws_lb_listener.http]
}
