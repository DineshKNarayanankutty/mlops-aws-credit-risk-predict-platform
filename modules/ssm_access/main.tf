data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_vpc" "selected" {
  id = var.vpc_id
}

locals {
  environment      = lower(lookup(var.tags, "Environment", ""))
  project_name     = lookup(var.tags, "Project", "mlops-platform")
  name_prefix      = "${local.environment}-mlops-ssm-access"
  vpc_dns_resolver = "${cidrhost(data.aws_vpc.selected.cidr_block, 2)}/32"
  base_tags = merge(
    {
      Project     = local.project_name
      Environment = local.environment
      ManagedBy   = "Terraform"
    },
    var.tags
  )
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${local.name_prefix}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.base_tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "eks_describe" {
  statement {
    sid    = "DescribeEksCluster"
    effect = "Allow"

    actions = [
      "eks:DescribeCluster"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "eks_describe" {
  name   = "${local.name_prefix}-eks-describe"
  role   = aws_iam_role.this.name
  policy = data.aws_iam_policy_document.eks_describe.json
}

resource "aws_iam_instance_profile" "this" {
  name = "${local.name_prefix}-profile"
  role = aws_iam_role.this.name

  tags = local.base_tags
}

resource "aws_security_group" "instance" {
  name_prefix = "${local.name_prefix}-"
  description = "Security group for SSM access instance"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS TCP to VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [local.vpc_dns_resolver]
  }

  egress {
    description = "DNS UDP to VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [local.vpc_dns_resolver]
  }

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "eks_cluster_https_from_instance" {
  type                     = "ingress"
  description              = "Allow HTTPS from SSM access instance"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = var.eks_cluster_security_group_id
  source_security_group_id = aws_security_group.instance.id
}

resource "aws_security_group" "vpc_endpoints" {
  count = var.create_vpc_endpoints ? 1 : 0

  name_prefix = "${local.name_prefix}-vpce-"
  description = "Security group for SSM interface VPC endpoints"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from SSM access instance"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.instance.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-vpce-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "ssm" {
  count = var.create_vpc_endpoints ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-ssm-vpce"
  })
}

resource "aws_vpc_endpoint" "ec2messages" {
  count = var.create_vpc_endpoints ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-ec2messages-vpce"
  })
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count = var.create_vpc_endpoints ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-ssmmessages-vpce"
  })
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.instance_type
  subnet_id                   = var.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.instance.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 20
  }

  tags = merge(local.base_tags, {
    Name = "${local.name_prefix}-instance"
  })
}
