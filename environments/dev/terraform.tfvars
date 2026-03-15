region                          = "ap-south-1"
environment                     = "dev"
cluster_name                    = "mlops-eks-dev"
cluster_version                 = "1.35"
node_instance_type              = "t3.medium"
inference_node_instance_type    = "t3.large"
cluster_endpoint_public_access  = true
cluster_endpoint_private_access = true
# FIX: Restrict public API to your corporate/VPN IP range
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

model_package_group_name  = "mlops-dev-model-package-group"
github_branch             = "main"
model_quality_roc_auc_min = 0.70
