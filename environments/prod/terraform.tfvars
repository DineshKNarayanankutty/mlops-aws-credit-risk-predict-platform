region                          = "ap-south-1"
environment                     = "prod"
cluster_name                    = "mlops-eks-prod"
cluster_version                 = "1.35"
node_instance_type              = "t3.large"
inference_node_instance_type    = "t3.large"
cluster_endpoint_public_access  = false
cluster_endpoint_private_access = true

model_package_group_name  = "mlops-prod-model-package-group"
code_connection_arn       = "REPLACE_WITH_code_connection_arn"
github_full_repository_id = "REPLACE_WITH_GITHUB_ORG_REPO"
github_branch             = "main"
