data "aws_caller_identity" "current" {}

locals {
  # ── Identity flags ────────────────────────────────────────────────
  is_dev   = var.environment == "dev"
  is_stage = var.environment == "stage"
  is_prod  = var.environment == "prod"

  # ── Feature flags ─────────────────────────────────────────────────
  # dev:   minimal footprint — no monitoring, no flow logs, no spot
  # stage: monitoring stack on, no flow logs, no spot
  # prod:  everything on
  enable_alb_controller     = true
  enable_monitoring         = !local.is_dev
  enable_vpc_flow_logs      = local.is_prod
  enable_spot_nodes         = local.is_prod
  enable_advanced_alerting  = local.is_prod
  enable_waf                = local.is_prod

  # ── Monitoring sub-flags (only meaningful when enable_monitoring=true) ──
  monitoring_enable_prometheus         = local.enable_monitoring
  monitoring_enable_grafana            = local.enable_monitoring
  monitoring_enable_metrics_server     = local.enable_monitoring
  monitoring_enable_container_insights = local.enable_monitoring
  monitoring_log_retention_in_days     = local.is_prod ? 30 : local.is_stage ? 14 : 7

  # ── Node sizing ───────────────────────────────────────────────────
  # EKS module's internal profile already handles dev/stage sizing.
  # These values are authoritative for prod (passed through to module).
  system_node_instance_type    = local.is_prod ? "m6i.large" : local.is_stage ? "t3.large" : "t3.medium"
  inference_node_instance_type = local.is_prod ? "c6i.xlarge" : "t3.large"

  # ── Resource naming ───────────────────────────────────────────────
  ecr_repository_name = "${var.project_name}-${var.environment}-inference"

  sagemaker_model_artifacts_bucket_name = "${var.project_name}-${var.environment}-model-artifacts-${data.aws_caller_identity.current.account_id}"
  cicd_artifact_bucket_name             = "${var.project_name}-${var.environment}-cicd-artifacts-${data.aws_caller_identity.current.account_id}"
  platform_artifact_bucket_name         = "${var.project_name}-${var.environment}-artifacts-${data.aws_caller_identity.current.account_id}"

  training_input_s3_uri  = "s3://${local.platform_artifact_bucket_name}/training/input/"
  training_output_s3_uri = "s3://${local.platform_artifact_bucket_name}/training/output/"

  training_data_bucket_name = local.platform_artifact_bucket_name
  training_data_bucket_arn  = "arn:aws:s3:::${local.training_data_bucket_name}"

  # ── Common tags ───────────────────────────────────────────────────
  common_tags = {
    Project              = var.project_name
    Environment          = var.environment
    ManagedBy            = "Terraform"
    Owner                = "platform-team"
    MonitoringEnabled    = tostring(local.enable_monitoring)
    SpotNodesEnabled     = tostring(local.enable_spot_nodes)
    VpcFlowLogsEnabled   = tostring(local.enable_vpc_flow_logs)
    AdvancedAlertsEnabled = tostring(local.enable_advanced_alerting)
    WafEnabled           = tostring(local.enable_waf)
  }
}
