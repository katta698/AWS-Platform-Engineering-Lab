# The platform: a VPC, an EKS control plane, and two kinds of compute under it.
#
# WHY BOTH EC2 AND FARGATE, WHICH LOOKS LIKE INDECISION AND IS NOT
# AWS recommends EKS Pod Identity over IRSA for granting pods AWS permissions.
# AWS also offers Fargate so you never manage a node. Follow both and you get a
# cluster that cannot work: the Pod Identity agent is a privileged DaemonSet,
# and Fargate runs neither DaemonSets nor privileged pods.
#
# The failure is silent, which is what makes it worth the week. The webhook
# still injects the environment variables into a Fargate pod, so it looks
# configured; the credential fetch then times out against an agent that was
# never there. It reads as an IAM misconfiguration for as long as you let it.
#
# AWS's own guidance is to run both: Pod Identity for pods on EC2, IRSA for pods
# on Fargate, in the same cluster. That is what this builds -- one tenant of
# each, so the difference is visible rather than asserted.
#
# WHAT COSTS MONEY HERE, AND IT IS NOT SUBTLE
#   EKS control plane   $0.10/hr   from creation, no free tier
#   NAT gateway         $0.045/hr  from creation
#   one t3.small node   $0.0208/hr on demand
# About $4/day whether or not a pod runs. Unlike the last several weeks of this
# series nothing about this bill is deferred or hidden, which makes it easier to
# manage -- provided teardown is part of the build rather than an afterthought.

locals {
  name = var.cluster_name

  tags = merge(var.tags, {
    Project   = "aws-platform-engineering-lab"
    Week      = "18"
    Component = "eks-self-service"
    ManagedBy = "terraform"
  })
}

# MUST filter by zone type. Without this the data source also returns Local
# Zones -- us-east-1-dfw-1a and friends -- and picking one fails twice over:
# EKS refuses to place a control plane there, and NAT gateways do not exist
# there at all. Both errors arrive at apply time, after the VPC is built, and
# neither mentions Local Zones by name.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

# ------------------------------------------------------------------- network --
# EKS requires subnets in at least two availability zones. Pods run in the
# private subnets; the public subnets exist only to host the NAT gateway.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # EKS requires both; without them nodes cannot resolve the API server
  tags                 = merge(local.tags, { Name = local.name })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${local.name}-igw" })
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = merge(local.tags, {
    Name = "${local.name}-public-${count.index}"
    # Required so EKS can place internet-facing load balancers here.
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = merge(local.tags, {
    Name                              = "${local.name}-private-${count.index}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# ONE NAT gateway, not one per AZ. A second would double the hourly charge to
# buy availability that a same-day demonstration does not need. In production
# this is the wrong trade -- a single NAT is a single AZ failure away from
# breaking egress for every pod in the other subnet.
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${local.name}-nat" })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = merge(local.tags, { Name = "${local.name}-nat" })
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(local.tags, { Name = "${local.name}-public" })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }
  tags = merge(local.tags, { Name = "${local.name}-private" })
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ----------------------------------------------------------------------- iam --
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Fargate pods run under an execution role, which pulls the image and writes
# logs. It is NOT the tenant's identity -- that comes from IRSA on Fargate, or
# Pod Identity on EC2. Conflating the two is a common way to end up granting a
# whole compute platform the permissions one workload needed.
data "aws_iam_policy_document" "fargate_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fargate" {
  name               = "${local.name}-fargate"
  assume_role_policy = data.aws_iam_policy_document.fargate_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "fargate" {
  role       = aws_iam_role.fargate.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# ------------------------------------------------------------------- cluster --
# Created explicitly with a short retention. Control plane logs are what prove
# the isolation test actually happened; they are also the only place a denied
# API call is visible.
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.name}/cluster"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_eks_cluster" "this" {
  name     = local.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  # Staying on a version in standard support is a cost decision as much as a
  # maintenance one: extended support is $0.60/hr, six times the standard rate.
  vpc_config {
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }

  # "audit" is the one that matters here -- it records the cross-tenant call
  # the isolation test is supposed to have denied.
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # API is the modern default: cluster access is granted through EKS access
  # entries rather than by hand-editing the aws-auth ConfigMap, which was the
  # long-standing way to lock yourself out of your own cluster.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]

  tags = local.tags
}

# The add-on that makes Pod Identity work. Without it, associations exist in the
# EKS API and no pod ever receives credentials -- a silent failure that looks
# like an IAM problem.
resource "aws_eks_addon" "pod_identity" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  tags                        = local.tags
}

# ---------------------------------------------------------------- ec2 nodes --
# One small node, on demand. It exists so the Pod Identity agent has somewhere
# to run -- everything else about this cluster could have been serverless.
data "aws_iam_policy_document" "node_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  # A demonstration cluster that scales is a demonstration of scaling, not of
  # tenancy. Fixed at one node so the bill is a straight line.
  update_config {
    max_unavailable = 1
  }

  depends_on = [aws_iam_role_policy_attachment.node]
  tags       = local.tags
}

# -------------------------------------------------------------- fargate --
# The second tenant lands here. No node to manage, and no Pod Identity either.
resource "aws_eks_fargate_profile" "tenant" {
  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "${local.name}-${var.fargate_namespace}"
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = aws_subnet.private[*].id

  selector {
    namespace = var.fargate_namespace
  }

  depends_on = [aws_iam_role_policy_attachment.fargate]
  tags       = local.tags
}

# ------------------------------------------------------------------- irsa --
# IRSA needs an OIDC provider registered in IAM, one per cluster. This is the
# step Pod Identity removes, and the reason IRSA hits a ceiling at 100 clusters
# per account -- that is an IAM limit on OIDC providers, not an EKS one.
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
  tags            = local.tags
}
