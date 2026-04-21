variable "region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used in naming and tagging"
  type        = string
  default     = "mlops-platform"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "node_instance_type" {
  description = "EC2 instance type for system node group"
  type        = string
  default     = "t3.medium"
}

variable "inference_node_instance_type" {
  description = "EC2 instance type for inference node group"
  type        = string
  default     = "t3.large"
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to EKS API endpoint"
  type        = bool
  default     = false
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to EKS API endpoint"
  type        = bool
  default     = true
}

# FIX: Restrict public API endpoint to specific CIDRs
variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDRs allowed to reach the public EKS API endpoint"
  type        = list(string)
  default     = []
}

variable "model_package_group_name" {
  description = "SageMaker model package group name"
  type        = string
}

variable "code_connection_arn" {
  description = "ARN of the CodeStar Connection to GitHub"
  type        = string
}

variable "github_full_repository_id" {
  description = "GitHub repository ID (org/repo)"
  type        = string
}

variable "github_branch" {
  description = "GitHub branch to trigger the pipeline"
  type        = string
  default     = "main"
}

variable "inference_namespace" {
  description = "Kubernetes namespace for inference workloads"
  type        = string
  default     = "inference"
}

variable "inference_service_account_name" {
  description = "Kubernetes service account for inference pods"
  type        = string
  default     = "inference-service"
}

variable "alb_controller_namespace" {
  description = "Kubernetes namespace for the ALB controller"
  type        = string
  default     = "kube-system"
}

variable "alb_controller_service_account_name" {
  description = "Kubernetes service account for the ALB controller"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "alb_controller_chart_version" {
  description = "Helm chart version for the AWS Load Balancer Controller"
  type        = string
  default     = "1.11.0"
}

variable "monitoring_namespace" {
  description = "Kubernetes namespace for monitoring components"
  type        = string
  default     = "monitoring"
}

variable "prometheus_chart_version" {
  description = "Helm chart version for Prometheus"
  type        = string
  default     = "25.30.0"
}

variable "grafana_chart_version" {
  description = "Helm chart version for Grafana"
  type        = string
  default     = "8.10.0"
}

variable "metrics_server_chart_version" {
  description = "Helm chart version for metrics-server"
  type        = string
  default     = "3.13.0"
}

variable "model_quality_roc_auc_min" {
  description = "Minimum acceptable ROC-AUC for model promotion gate"
  type        = number
  default     = 0.75
}

variable "enable_in_cluster_addons" {
  description = "Install ALB controller and monitoring Helm charts via Terraform (requires EKS kubeconfig)"
  type        = bool
  default     = false
}
