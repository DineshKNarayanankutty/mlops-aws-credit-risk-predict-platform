locals {
  base_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.tags
  )

  target_az_count = lookup(
    {
      dev   = 2
      stage = 2
      prod  = 3
    },
    var.environment,
    3
  )

  az_count = min(
    local.target_az_count,
    length(data.aws_availability_zones.available.names),
    length(var.public_subnet_cidrs),
    length(var.private_subnet_cidrs)
  )

  selected_public_subnet_cidrs  = slice(var.public_subnet_cidrs, 0, local.az_count)
  selected_private_subnet_cidrs = slice(var.private_subnet_cidrs, 0, local.az_count)

  nat_gateway_count = var.environment == "prod" ? local.az_count : 1
  nat_per_az        = var.environment == "prod"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  lifecycle {
    precondition {
      condition     = local.az_count == local.target_az_count
      error_message = "Insufficient AZs or subnet CIDRs for ${var.environment}. Provide at least ${local.target_az_count} public and private CIDRs in this region."
    }
  }

  tags = merge(local.base_tags, { Name = "mlops-${var.environment}-vpc" })
}

data "aws_availability_zones" "available" {}

# ── Public Subnets ──────────────────────────────────────────────────
# FIX C-07: Added kubernetes.io/role/elb tag so ALB Controller can
#            discover public subnets for internet-facing ALBs.
resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.selected_public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.base_tags, {
    Name                     = "mlops-${var.environment}-public-${count.index}"
    "kubernetes.io/role/elb" = "1"
    # Required by EKS for subnet auto-discovery
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# ── Private Subnets ─────────────────────────────────────────────────
# FIX C-07: Added kubernetes.io/role/internal-elb tag for internal ALBs.
resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.selected_private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.base_tags, {
    Name                              = "mlops-${var.environment}-private-${count.index}"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# ── Internet Gateway ────────────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.base_tags, { Name = "mlops-${var.environment}-igw" })
}

# ── NAT Gateway (single for dev/stage, per-AZ for prod) ────────────
resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"
  tags   = merge(local.base_tags, { Name = "mlops-${var.environment}-nat-eip-${count.index}" })
}

resource "aws_nat_gateway" "nat" {
  count         = local.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[local.nat_per_az ? count.index : 0].id
  tags          = merge(local.base_tags, { Name = "mlops-${var.environment}-nat-${count.index}" })
}

# ── Public Route Table ──────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.base_tags, { Name = "mlops-${var.environment}-public-rt" })
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Private Route Table ─────────────────────────────────────────────
resource "aws_route_table" "private" {
  count  = local.nat_per_az ? local.az_count : 1
  vpc_id = aws_vpc.main.id
  tags   = merge(local.base_tags, { Name = "mlops-${var.environment}-private-rt-${count.index}" })
}

resource "aws_route" "private_nat_access" {
  count                  = local.nat_gateway_count
  route_table_id         = aws_route_table.private[local.nat_per_az ? count.index : 0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[count.index].id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[local.nat_per_az ? count.index : 0].id
}

# ── VPC Flow Logs ───────────────────────────────────────────────────
# FIX: Added VPC Flow Logs for compliance and incident response.
resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = var.enable_vpc_flow_logs ? 1 : 0
  name              = "/aws/vpc/flow-logs/${var.environment}"
  retention_in_days = var.environment == "prod" ? 90 : 14
  tags              = local.base_tags
}

resource "aws_iam_role" "flow_logs" {
  count              = var.enable_vpc_flow_logs ? 1 : 0
  name               = "mlops-${var.environment}-vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume[0].json
  tags               = local.base_tags
}

data "aws_iam_policy_document" "flow_logs_assume" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  count  = var.enable_vpc_flow_logs ? 1 : 0
  name   = "flow-logs-policy"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "main" {
  count           = var.enable_vpc_flow_logs ? 1 : 0
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
  tags            = merge(local.base_tags, { Name = "mlops-${var.environment}-flow-log" })
}

# ── VPC Endpoints ───────────────────────────────────────────────────
# FIX: Added VPC endpoints to eliminate NAT Gateway costs for
#      S3/ECR/STS traffic and improve security (traffic stays in AWS backbone).

data "aws_region" "current" {}

# S3 Gateway endpoint (free)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(
    aws_route_table.public[*].id,
    aws_route_table.private[*].id
  )
  tags = merge(local.base_tags, { Name = "mlops-${var.environment}-s3-endpoint" })
}

# ECR API Interface endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = merge(local.base_tags, { Name = "mlops-${var.environment}-ecr-api-endpoint" })
}

# ECR DKR Interface endpoint (for image layer pulls)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = merge(local.base_tags, { Name = "mlops-${var.environment}-ecr-dkr-endpoint" })
}

# STS Interface endpoint (needed for IRSA token exchange)
resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = merge(local.base_tags, { Name = "mlops-${var.environment}-sts-endpoint" })
}

# CloudWatch Logs endpoint (so nodes can push logs without NAT)
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = merge(local.base_tags, { Name = "mlops-${var.environment}-logs-endpoint" })
}

# Shared security group for all Interface endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "mlops-${var.environment}-vpc-endpoints-"
  description = "Allow HTTPS from within the VPC to Interface VPC Endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.base_tags, { Name = "mlops-${var.environment}-vpc-endpoints-sg" })

  lifecycle {
    create_before_destroy = true
  }
}
