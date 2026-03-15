variable "environment" {
  description = "Deployment environment (dev, stage, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name used in resource naming and tagging"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — used in subnet discovery tags"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch (recommended for prod only)"
  type        = bool
  default     = false
}
