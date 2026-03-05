data "aws_caller_identity" "current" {}

locals {
  sagemaker_model_artifacts_bucket_name = "${var.project_name}-${var.environment}-model-artifacts-${data.aws_caller_identity.current.account_id}"
  cicd_artifact_bucket_name             = "${var.project_name}-${var.environment}-cicd-artifacts-${data.aws_caller_identity.current.account_id}"

  training_input_s3_uri  = "s3://${local.cicd_artifact_bucket_name}/training/input/"
  training_output_s3_uri = "s3://${local.cicd_artifact_bucket_name}/training/output/"

  training_data_bucket_name = local.cicd_artifact_bucket_name
  training_data_bucket_arn  = "arn:aws:s3:::${local.training_data_bucket_name}"

  enable_alb_controller                = true
  enable_monitoring                    = true
  monitoring_enable_container_insights = false
  monitoring_log_retention_in_days     = 14

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "platform-team"
  }
}
