output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (ECS tasks and RDS)."
  value       = aws_subnet.private[*].id
}

output "alb_security_group_id" {
  description = "Security group for the public ALB."
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "Security group for the Fargate tasks."
  value       = aws_security_group.ecs_service.id
}

output "rds_security_group_id" {
  description = "Security group for the RDS instance."
  value       = aws_security_group.rds.id
}

output "nat_gateway_public_ips" {
  description = "Public IPs of the NAT gateways - the stable egress addresses of this environment."
  value       = aws_eip.nat[*].public_ip
}
