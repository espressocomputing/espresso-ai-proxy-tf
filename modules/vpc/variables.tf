variable "vpc_name" {
  description = "VPC resource name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks used by EKS nodes"
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones matching subnet CIDR ordering"
  type        = list(string)
}

variable "tags" {
  description = "Additional tags applied to AWS resources"
  type        = map(string)
  default     = {}
}
