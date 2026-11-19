###############################################################################
# Security groups
#
# The data path is strictly one-directional:
#
#   internet --(alb_ingress_cidrs : alb_listener_port)--> ALB SG
#   ALB SG   --(container_port)----------------------->   ECS SG
#   ECS SG   --(db_port)------------------------------>   RDS SG
#
# The RDS group has no egress rules at all and accepts traffic only from the
# ECS task group - never from the ALB, never from the internet, never from a
# CIDR block. That is what makes the database private in the sense the brief
# asks for: there is no address you can add to a bastion or a laptop that
# would let you reach it.
#
# Rules are declared as individual aws_vpc_security_group_*_rule resources
# rather than inline blocks so that groups can reference each other without
# creating a dependency cycle between the aws_security_group resources.
###############################################################################

resource "aws_security_group" "alb" {
  name_prefix = "${local.name}-alb-"
  description = "Public entry point: accepts client traffic for ${local.name} and forwards it to the ECS tasks."
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name}-alb"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "ecs_service" {
  name_prefix = "${local.name}-ecs-"
  description = "Fargate tasks for ${local.name}. Reachable only from the ALB; allowed out to the database and to AWS APIs."
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name}-ecs"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "${local.name}-rds-"
  description = "RDS instance for ${local.name}. Ingress from the ECS task group only; no egress."
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name}-rds"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# --- ALB ----------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_from_internet" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "Client traffic on port ${var.alb_listener_port} from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = var.alb_listener_port
  to_port           = var.alb_listener_port
  ip_protocol       = "tcp"

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward requests to the ECS tasks on the container port"
  referenced_security_group_id = aws_security_group.ecs_service.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"

  tags = local.tags
}

# --- ECS tasks ----------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs_service.id
  description                  = "Application traffic from the ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_rds" {
  security_group_id            = aws_security_group.ecs_service.id
  description                  = "Database connections to RDS"
  referenced_security_group_id = aws_security_group.rds.id
  from_port                    = var.db_port
  to_port                      = var.db_port
  ip_protocol                  = "tcp"

  tags = local.tags
}

# Egress is deliberately narrow rather than "allow all": 443 covers the ECR
# image pull, CloudWatch Logs and Secrets Manager; 53 covers DNS against the
# VPC resolver. Nothing else is needed by a Fargate task on this path.
resource "aws_vpc_security_group_egress_rule" "ecs_to_aws_apis" {
  security_group_id = aws_security_group.ecs_service.id
  description       = "HTTPS to ECR, CloudWatch Logs and Secrets Manager via the NAT gateway"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "ecs_dns_tcp" {
  security_group_id = aws_security_group.ecs_service.id
  description       = "DNS (TCP) to the VPC resolver"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "ecs_dns_udp" {
  security_group_id = aws_security_group.ecs_service.id
  description       = "DNS (UDP) to the VPC resolver"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"

  tags = local.tags
}

# --- RDS ----------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Database traffic from the ECS task group only"
  referenced_security_group_id = aws_security_group.ecs_service.id
  from_port                    = var.db_port
  to_port                      = var.db_port
  ip_protocol                  = "tcp"

  tags = local.tags
}

# No aws_vpc_security_group_egress_rule for aws_security_group.rds on purpose.
# A security group created by Terraform starts with no egress rules, so the
# instance cannot open outbound connections of its own.
