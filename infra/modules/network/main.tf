###############################################################################
# Network module
#
# Owns the VPC, its subnets and routing, AND the three security groups that
# make up the Internet -> ALB -> ECS -> RDS path.
#
# Why the security groups live here and not in the ecs/rds modules:
# the ALB/ECS/RDS groups reference each other, and the ECS module also consumes
# outputs from the RDS module (the master secret ARN). If the ECS module owned
# the ECS security group that the RDS module depends on, the module graph would
# contain a cycle and Terraform would refuse to build it. Keeping the network
# topology - including who may talk to whom - in one module breaks that cycle
# and keeps the whole data path reviewable in a single file.
###############################################################################

locals {
  name     = "${var.project}-${var.environment}"
  az_count = length(var.availability_zones)

  # Public subnets take the first N /20s, private subnets the next N.
  nat_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 0

  tags = merge(var.tags, {
    Module = "network"
  })
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${local.name}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name}-igw"
  })
}

###############################################################################
# Subnets
###############################################################################

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, var.subnet_newbits, count.index)

  # The ALB gets its public addresses from the load balancer itself; nothing
  # launched into these subnets should get a public IP by default.
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${local.name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, var.subnet_newbits, count.index + local.az_count)

  tags = merge(local.tags, {
    Name = "${local.name}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  })
}

###############################################################################
# NAT gateways - outbound only egress for the private subnets
###############################################################################

resource "aws_eip" "nat" {
  count = local.nat_count

  domain = "vpc"

  tags = merge(local.tags, {
    Name = "${local.name}-nat-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.tags, {
    Name = "${local.name}-nat-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# Routing
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name}-public"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table per AZ, so that each AZ can use its own NAT gateway
# when single_nat_gateway is false.
resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name}-private-${var.availability_zones[count.index]}"
  })
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? local.az_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
