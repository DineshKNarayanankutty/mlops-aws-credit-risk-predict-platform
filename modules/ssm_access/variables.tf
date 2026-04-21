variable "vpc_id" {
  description = "ID of the VPC where the SSM access instance will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs available for the SSM access instance and optional interface endpoints"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) > 0
    error_message = "private_subnet_ids must contain at least one private subnet ID."
  }
}

variable "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS control plane"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the SSM access host"
  type        = string
  default     = "t3.micro"
}

variable "create_vpc_endpoints" {
  description = "Create SSM interface VPC endpoints for private subnets without NAT"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources created by the module"
  type        = map(string)
  default     = {}

  validation {
    condition     = contains(["stage", "prod"], lower(lookup(var.tags, "Environment", "")))
    error_message = "tags must include an Environment tag with value stage or prod for the ssm_access module."
  }
}
