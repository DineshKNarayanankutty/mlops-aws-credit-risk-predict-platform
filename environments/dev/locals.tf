data "aws_caller_identity" "current" {}

locals {
  sagemaker_model_artifacts_bucket_name = "${var.project_name}-${var.environment}-model-artifacts-${data.aws_caller_identity.current.account_id}"

  cicd_artifact_bucket_name     = "${var.project_name}-${var.environment}-cicd-artifacts-${data.aws_caller_identity.current.account_id}"
  platform_artifact_bucket_name = "${var.project_name}-${var.environment}-artifacts-${data.aws_caller_identity.current.account_id}"

  training_input_s3_uri = "s3://${local.platform_artifact_bucket_name}/training/input/"

  training_output_s3_uri = "s3://${local.platform_artifact_bucket_name}/training/output/"

  training_data_bucket_name = local.platform_artifact_bucket_name
  training_data_bucket_arn  = "arn:aws:s3:::${local.training_data_bucket_name}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "platform-team"
  }
}

