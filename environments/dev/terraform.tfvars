region                          = "ap-south-1"
environment                     = "dev"
cluster_name                    = "mlops-eks-dev"
cluster_version                 = "1.35"
node_instance_type              = "t3.small"
inference_node_instance_type    = "t3.small"
cluster_endpoint_public_access  = true
cluster_endpoint_private_access = true

model_package_group_name        = "mlops-dev-model-package-group"

github_branch = "main"

