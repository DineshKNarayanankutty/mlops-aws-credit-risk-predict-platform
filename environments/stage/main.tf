module "vpc" {
  source               = "../../modules/vpc"
  environment          = var.environment
  project_name         = var.project_name
  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_vpc_flow_logs = local.enable_vpc_flow_logs
  tags                 = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  environment                          = var.environment
  cluster_name                         = var.cluster_name
  cluster_version                      = var.cluster_version
  vpc_id                               = module.vpc.vpc_id
  private_subnets                      = module.vpc.private_subnets
  node_instance_type                   = local.system_node_instance_type
  inference_node_instance_type         = local.inference_node_instance_type
  enable_spot_node_group               = local.enable_spot_nodes
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_private_access      = var.cluster_endpoint_private_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  tags                                 = local.common_tags
}

module "ecr" {
  source          = "../../modules/ecr"
  repository_name = local.ecr_repository_name
  environment     = var.environment
  project_name    = var.project_name
  tags            = local.common_tags
}

module "s3" {
  source      = "../../modules/s3"
  bucket_name = local.platform_artifact_bucket_name
  tags        = local.common_tags
}

module "sagemaker" {
  source = "../../modules/sagemaker"

  environment                 = var.environment
  model_package_group_name    = var.model_package_group_name
  model_artifacts_bucket_name = local.sagemaker_model_artifacts_bucket_name
  ecr_repository_arn          = module.ecr.repository_arn
  tags                        = local.common_tags
}

module "iam" {
  source = "../../modules/iam"

  environment                         = var.environment
  cluster_name                        = module.eks.cluster_name
  oidc_provider_arn                   = module.eks.oidc_provider_arn
  oidc_provider_url                   = module.eks.oidc_provider
  ecr_repository_arn                  = module.ecr.repository_arn
  artifact_bucket_name                = local.cicd_artifact_bucket_name
  model_artifacts_bucket_arn          = module.sagemaker.model_artifacts_bucket_arn
  model_artifacts_kms_key_arn         = module.sagemaker.model_artifacts_kms_key_arn
  training_data_bucket_arn            = local.training_data_bucket_arn
  code_connection_arn                 = var.code_connection_arn
  inference_namespace                 = var.inference_namespace
  inference_service_account_name      = var.inference_service_account_name
  alb_controller_namespace            = var.alb_controller_namespace
  alb_controller_service_account_name = var.alb_controller_service_account_name
  codebuild_eks_cluster_name          = module.eks.cluster_name
  tags                                = local.common_tags
}

module "cicd" {
  source = "../../modules/cicd"

  environment                 = var.environment
  artifact_bucket_name        = local.cicd_artifact_bucket_name
  codebuild_role_arn          = module.iam.codebuild_role_arn
  codepipeline_role_arn       = module.iam.codepipeline_role_arn
  code_connection_arn         = var.code_connection_arn
  github_full_repository_id   = var.github_full_repository_id
  github_branch               = var.github_branch
  ecr_repository_url          = module.ecr.repository_url
  sagemaker_training_role_arn = module.iam.sagemaker_training_role_arn
  training_input_s3_uri       = local.training_input_s3_uri
  training_output_s3_uri      = local.training_output_s3_uri
  eks_cluster_name            = module.eks.cluster_name
  inference_namespace         = var.inference_namespace
  k8s_deployment_name         = "credit-risk-api"
  k8s_container_name          = "credit-risk-api"
  model_quality_roc_auc_min   = var.model_quality_roc_auc_min
  tags                        = local.common_tags
}

module "alb_controller" {
  count  = local.enable_alb_controller ? 1 : 0
  source = "../../modules/alb_controller"

  cluster_name              = module.eks.cluster_name
  region                    = var.region
  vpc_id                    = module.vpc.vpc_id
  oidc_provider_arn         = module.eks.oidc_provider_arn
  oidc_provider_url         = module.eks.oidc_provider
  namespace                 = var.alb_controller_namespace
  service_account_name      = var.alb_controller_service_account_name
  chart_version             = var.alb_controller_chart_version
  create_irsa_role          = false
  existing_irsa_role_arn    = module.iam.alb_controller_role_arn
  backend_security_group_id = module.eks.alb_backend_security_group_id
  tags                      = local.common_tags

  depends_on = [module.eks]
}

module "monitoring" {
  count  = local.enable_monitoring ? 1 : 0
  source = "../../modules/monitoring"

  cluster_name                 = module.eks.cluster_name
  namespace                    = var.monitoring_namespace
  enable_prometheus            = local.monitoring_enable_prometheus
  enable_grafana               = local.monitoring_enable_grafana
  enable_metrics_server        = local.monitoring_enable_metrics_server
  enable_container_insights    = local.monitoring_enable_container_insights
  log_retention_in_days        = local.monitoring_log_retention_in_days
  prometheus_chart_version     = var.prometheus_chart_version
  grafana_chart_version        = var.grafana_chart_version
  metrics_server_chart_version = var.metrics_server_chart_version
  tags                         = local.common_tags

  depends_on = [module.alb_controller]
}
