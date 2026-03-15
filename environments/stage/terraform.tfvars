region                               = "ap-south-1"
environment                          = "stage"
cluster_name                         = "mlops-eks-stage"
cluster_version                      = "1.35"
node_instance_type                   = "t3.medium"
inference_node_instance_type         = "t3.large"
cluster_endpoint_public_access       = false
cluster_endpoint_private_access      = true
cluster_endpoint_public_access_cidrs = []
enable_in_cluster_addons             = false

model_package_group_name  = "mlops-stage-model-package-group"
github_branch             = "main"
model_quality_roc_auc_min = 0.75
