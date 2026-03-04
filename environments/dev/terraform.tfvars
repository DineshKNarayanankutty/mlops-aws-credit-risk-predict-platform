region                          = "ap-south-1"
environment                     = "dev"
cluster_name                    = "mlops-eks-dev"
cluster_version                 = "1.35"
node_instance_type              = "t3.small"
inference_node_instance_type    = "t3.small"
cluster_endpoint_public_access  = true
cluster_endpoint_private_access = true

model_package_group_name              = "mlops-dev-model-package-group"
sagemaker_model_artifacts_bucket_name = "${var.project_name}-${var.environment}-model-artifacts-${data.aws_caller_identity.current.account_id}"
cicd_artifact_bucket_name             = "${var.project_name}-${var.environment}-cicd-artifacts-${data.aws_caller_identity.current.account_id}"

github_branch = "main"

training_input_s3_uri  = "s3://${var.cicd_artifact_bucket_name}/training/input/"
training_output_s3_uri = "s3://${var.cicd_artifact_bucket_name}/training/output/"

