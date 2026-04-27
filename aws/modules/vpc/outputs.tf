output "vpc_id" {
  description = "Dedicated VPC ID"
  value       = module.this.vpc_id
}

output "vpc_cidr_block" {
  description = "Dedicated VPC CIDR"
  value       = module.this.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.this.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.this.private_subnets
}
