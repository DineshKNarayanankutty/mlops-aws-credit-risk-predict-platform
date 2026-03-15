data "aws_caller_identity" "current" {}

locals {
  artifact_access_log_bucket_name = "${var.artifact_bucket_name}-access-logs"
  base_tags = merge(
    {
      Project     = lookup(var.tags, "Project", "mlops-platform")
      ManagedBy   = "Terraform"
      Environment = var.environment
    },
    var.tags
  )
  resolved_training_image_uri = coalesce(var.training_image_uri, "${var.ecr_repository_url}:latest")
}

# ── KMS key for CI/CD artifact encryption ──────────────────────────
data "aws_iam_policy_document" "artifacts_kms" {
  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCICDServiceRoles"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.codebuild_role_arn, var.codepipeline_role_arn]
    }
    actions = [
      "kms:Decrypt", "kms:DescribeKey", "kms:Encrypt",
      "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext",
      "kms:ReEncryptFrom", "kms:ReEncryptTo"
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "artifacts" {
  description             = "KMS key for CI/CD artifacts (${var.environment})"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.artifacts_kms.json
  tags                    = local.base_tags
}

resource "aws_kms_alias" "artifacts" {
  name          = "alias/cicd/${var.environment}/artifacts"
  target_key_id = aws_kms_key.artifacts.key_id
}

# ── S3 artifact bucket (with access logging + TLS enforcement) ──────
resource "aws_s3_bucket" "artifacts" {
  bucket        = var.artifact_bucket_name
  force_destroy = var.force_destroy
  tags          = merge(local.base_tags, { Purpose = "codepipeline-artifacts" })
}

resource "aws_s3_bucket" "artifacts_log" {
  bucket        = local.artifact_access_log_bucket_name
  force_destroy = var.force_destroy
  tags          = merge(local.base_tags, { Purpose = "codepipeline-artifact-access-logs" })
}

resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_ownership_controls" "artifacts_log" {
  bucket = aws_s3_bucket.artifacts_log.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "artifacts_log" {
  bucket                  = aws_s3_bucket.artifacts_log.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_versioning" "artifacts_log" {
  bucket = aws_s3_bucket.artifacts_log.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.artifacts.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts_log" {
  bucket = aws_s3_bucket.artifacts_log.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.artifacts.arn
    }
    bucket_key_enabled = true
  }
}

data "aws_iam_policy_document" "artifact_bucket_tls" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "artifact_bucket_tls" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.artifact_bucket_tls.json
}

data "aws_iam_policy_document" "artifact_bucket_log_delivery" {
  statement {
    sid    = "S3ServerAccessLogsPolicy"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.artifacts_log.arn}/access-logs/*"]
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.artifacts.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "artifact_bucket_log_delivery" {
  bucket = aws_s3_bucket.artifacts_log.id
  policy = data.aws_iam_policy_document.artifact_bucket_log_delivery.json
}

resource "aws_s3_bucket_logging" "artifacts" {
  bucket        = aws_s3_bucket.artifacts.id
  target_bucket = aws_s3_bucket.artifacts_log.id
  target_prefix = "access-logs/"
  depends_on    = [aws_s3_bucket_policy.artifact_bucket_log_delivery]
}

# ── Stage 1: Build & Push image ─────────────────────────────────────
resource "aws_codebuild_project" "build_and_push" {
  name         = "${var.environment}-mlops-build-image"
  description  = "Build inference image and push to ECR"
  service_role = var.codebuild_role_arn

  artifacts { type = "CODEPIPELINE" }

  # FIX: Added CodeBuild cache to speed up Docker layer pulls
  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE"]
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-EOT
      version: 0.2
      phases:
        pre_build:
          commands:
            - ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
            - IMAGE_TAG=$${CODEBUILD_RESOLVED_SOURCE_VERSION:0:7}
            - IMAGE_URI=${var.ecr_repository_url}:$${IMAGE_TAG}
            - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin ${split("/", var.ecr_repository_url)[0]}
        build:
          commands:
            - docker build -f docker/Dockerfile -t $${IMAGE_URI} .
            - docker tag $${IMAGE_URI} ${var.ecr_repository_url}:latest
        post_build:
          commands:
            - docker push $${IMAGE_URI}
            - docker push ${var.ecr_repository_url}:latest
            # FIX: Export ImageDetail.json so downstream stages consume the URI deterministically
            - printf '{"ImageURI":"%s"}' "$${IMAGE_URI}" > imageDetail.json
      artifacts:
        files:
          - imageDetail.json
          - '**/*'
      secondary-artifacts:
        ImageDetails:
          files:
            - imageDetail.json
    EOT
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                       = var.codebuild_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }

  encryption_key = aws_kms_key.artifacts.arn
  tags           = local.base_tags
}

# ── Stage 2: Trigger SageMaker training ─────────────────────────────
resource "aws_codebuild_project" "trigger_training" {
  name         = "${var.environment}-mlops-trigger-training"
  description  = "Trigger SageMaker training job and wait for completion"
  service_role = var.codebuild_role_arn

  artifacts { type = "CODEPIPELINE" }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-EOT
      version: 0.2
      phases:
        build:
          commands:
            - TRAINING_JOB_NAME=${var.environment}-training-$(date +%s)
            - |
              aws sagemaker create-training-job \
                --region $AWS_DEFAULT_REGION \
                --training-job-name "$${TRAINING_JOB_NAME}" \
                --algorithm-specification TrainingImage=${local.resolved_training_image_uri},TrainingInputMode=File \
                --role-arn ${var.sagemaker_training_role_arn} \
                --input-data-config '[{"ChannelName":"training","DataSource":{"S3DataSource":{"S3DataType":"S3Prefix","S3Uri":"${var.training_input_s3_uri}","S3DataDistributionType":"FullyReplicated"}}}]' \
                --output-data-config '{"S3OutputPath":"${var.training_output_s3_uri}"}' \
                --resource-config '{"InstanceType":"${var.training_instance_type}","InstanceCount":${var.training_instance_count},"VolumeSizeInGB":${var.training_volume_size_gb}}' \
                --stopping-condition '{"MaxRuntimeInSeconds":${var.training_max_runtime_seconds}}'
            # FIX C-06: Poll until training completes (was fire-and-forget before)
            - echo "Waiting for training job $${TRAINING_JOB_NAME} to complete..."
            - |
              while true; do
                STATUS=$(aws sagemaker describe-training-job \
                  --training-job-name "$${TRAINING_JOB_NAME}" \
                  --query 'TrainingJobStatus' --output text)
                echo "Status: $${STATUS}"
                case "$${STATUS}" in
                  Completed) echo "Training complete."; break ;;
                  Failed|Stopped)
                    REASON=$(aws sagemaker describe-training-job \
                      --training-job-name "$${TRAINING_JOB_NAME}" \
                      --query 'FailureReason' --output text)
                    echo "Training failed: $${REASON}"; exit 1 ;;
                  *) sleep 60 ;;
                esac
              done
            # Write job name for downstream stages
            - echo "$${TRAINING_JOB_NAME}" > training_job_name.txt
            # Download and surface metrics.json
            - |
              OUTPUT_PATH="${var.training_output_s3_uri}$${TRAINING_JOB_NAME}/output/"
              aws s3 cp "$${OUTPUT_PATH}output.tar.gz" /tmp/output.tar.gz 2>/dev/null || \
              aws s3 cp "${var.training_output_s3_uri}$${TRAINING_JOB_NAME}/output/output.tar.gz" /tmp/output.tar.gz
              cd /tmp && tar xzf output.tar.gz 2>/dev/null || true
              if [ -f /tmp/metrics.json ]; then
                cp /tmp/metrics.json metrics.json
              else
                echo '{"roc_auc":null,"accuracy":null}' > metrics.json
              fi
      artifacts:
        files:
          - training_job_name.txt
          - metrics.json
          - '**/*'
    EOT
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                       = var.codebuild_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false
  }

  encryption_key = aws_kms_key.artifacts.arn
  tags           = local.base_tags
}

# ── Stage 3: Validate model quality before deploying ────────────────
# FIX C-06: Quality gate — pipeline fails if ROC-AUC is below threshold.
resource "aws_codebuild_project" "validate_model" {
  name         = "${var.environment}-mlops-validate-model"
  description  = "Assert model quality metrics pass the promotion threshold"
  service_role = var.codebuild_role_arn

  artifacts { type = "CODEPIPELINE" }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-EOT
      version: 0.2
      phases:
        build:
          commands:
            - |
              python3 - << 'PYEOF'
              import json, sys
              with open("metrics.json") as f:
                  metrics = json.load(f)
              roc_auc = metrics.get("roc_auc")
              threshold = ${var.model_quality_roc_auc_min}
              print(f"ROC-AUC: {roc_auc}  Threshold: {threshold}")
              if roc_auc is None:
                  print("ERROR: roc_auc missing from metrics.json"); sys.exit(1)
              if roc_auc < threshold:
                  print(f"ERROR: ROC-AUC {roc_auc:.4f} below threshold {threshold}"); sys.exit(1)
              print("Model quality gate PASSED")
              PYEOF
      artifacts:
        files:
          - '**/*'
    EOT
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                       = var.codebuild_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false
  }

  encryption_key = aws_kms_key.artifacts.arn
  tags           = local.base_tags
}

# ── Stage 4: Deploy to EKS ───────────────────────────────────────────
# FIX C-06: Added missing deploy stage — was completely absent before.
resource "aws_codebuild_project" "deploy_to_eks" {
  name         = "${var.environment}-mlops-deploy-eks"
  description  = "Update Kubernetes deployment with new image and wait for rollout"
  service_role = var.codebuild_role_arn

  artifacts { type = "CODEPIPELINE" }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-EOT
      version: 0.2
      phases:
        install:
          commands:
            # FIX: Pin kubectl to specific version + verify checksum
            - KUBECTL_VERSION="${var.kubectl_version}"
            - curl -sSLO "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
            - curl -sSLO "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
            - echo "$(cat kubectl.sha256) kubectl" | sha256sum --check
            - chmod +x kubectl && mv kubectl /usr/local/bin/kubectl
        pre_build:
          commands:
            - IMAGE_URI=$(python3 -c "import json; d=json.load(open('imageDetail.json')); print(d['ImageURI'])")
            - echo "Deploying image $${IMAGE_URI}"
            - aws eks update-kubeconfig --name ${var.eks_cluster_name} --region $AWS_DEFAULT_REGION
        build:
          commands:
            # FIX: kubectl set image with explicit container reference (removed deprecated --record)
            - |
              kubectl set image deployment/${var.k8s_deployment_name} \
                ${var.k8s_container_name}=$${IMAGE_URI} \
                -n ${var.inference_namespace}
            - |
              kubectl rollout status deployment/${var.k8s_deployment_name} \
                -n ${var.inference_namespace} \
                --timeout=300s
            - echo "Rollout complete."
      artifacts:
        files:
          - '**/*'
    EOT
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                       = var.codebuild_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false
  }

  encryption_key = aws_kms_key.artifacts.arn
  tags           = local.base_tags
}

# ── CodePipeline with all 5 stages ──────────────────────────────────
resource "aws_codepipeline" "this" {
  name     = coalesce(var.pipeline_name, "${var.environment}-mlops-pipeline")
  role_arn = var.codepipeline_role_arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
    encryption_key {
      id   = aws_kms_key.artifacts.arn
      type = "KMS"
    }
  }

  stage {
    name = "Source"
    action {
      name             = "SourceFromGitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]
      configuration = {
        ConnectionArn    = var.code_connection_arn
        FullRepositoryId = var.github_full_repository_id
        BranchName       = var.github_branch
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "BuildAndPushImage"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      configuration    = { ProjectName = aws_codebuild_project.build_and_push.name }
    }
  }

  stage {
    name = "Train"
    action {
      name             = "TriggerAndWaitForTraining"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["BuildOutput"]
      output_artifacts = ["TrainOutput"]
      configuration    = { ProjectName = aws_codebuild_project.trigger_training.name }
    }
  }

  stage {
    name = "QualityGate"
    action {
      name            = "ValidateModelMetrics"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["TrainOutput"]
      output_artifacts = ["QualityOutput"]
      configuration   = { ProjectName = aws_codebuild_project.validate_model.name }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "DeployToEKS"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["QualityOutput", "BuildOutput"]
      configuration = {
        ProjectName          = aws_codebuild_project.deploy_to_eks.name
        PrimarySource        = "QualityOutput"
      }
    }
  }

  tags = local.base_tags
}
