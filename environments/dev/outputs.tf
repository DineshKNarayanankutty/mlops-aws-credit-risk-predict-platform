############################################
# VPC Outputs (always present)
############################################

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

############################################
# EKS Outputs (only if enabled)
############################################

output "eks_cluster_name" {
  value = try(module.eks.cluster_name, null)
}

output "eks_cluster_endpoint" {
  value = try(module.eks.cluster_endpoint, null)
}

############################################
# ECR Outputs (usually present)
############################################

output "ecr_repository_url" {
  value = try(module.ecr.repository_url, null)
}

############################################
# S3 Outputs (check your actual name)
############################################

output "artifact_bucket_name" {
  value = try(
    module.s3.bucket_name,
    module.s3.bucket_id,
    null
  )
}