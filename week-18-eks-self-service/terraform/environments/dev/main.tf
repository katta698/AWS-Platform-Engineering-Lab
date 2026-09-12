# Week 18 — EKS Cluster Self-Service
#
# Two tenants on one cluster, deliberately different:
#
#   tenant-a   runs on EC2     gets its AWS identity from Pod Identity
#   tenant-b   runs on Fargate gets its AWS identity from IRSA
#
# Not indecision. AWS recommends Pod Identity over IRSA, and also offers Fargate
# so you never manage a node. Do both and nothing works: the Pod Identity agent
# is a privileged DaemonSet and Fargate runs neither DaemonSets nor privileged
# pods. AWS's own answer is to run both mechanisms side by side, which is what
# this does -- so the difference can be seen rather than asserted.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-18-dev"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "aws-platform-engineering-lab"
      Week      = "18"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# The Kubernetes provider authenticates with a token minted from the same AWS
# credentials Terraform is already using. No kubeconfig on disk, nothing to
# rotate, and the run works identically on a laptop or an HCP runner.
#
# The catch worth knowing: this provider is configured from attributes of a
# cluster created in the same run. Terraform evaluates provider config early, so
# a first apply from empty state can need two passes -- the cluster exists after
# the first, and the namespaces land on the second.
provider "kubernetes" {
  host                   = module.platform.cluster_endpoint
  cluster_ca_certificate = base64decode(module.platform.cluster_ca)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.platform.cluster_name]
  }
}

module "platform" {
  source = "../../modules/platform_cluster"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  node_instance_type = var.node_instance_type
  log_retention_days = var.log_retention_days

  # The Fargate profile has to name its namespace up front; the namespace itself
  # is created by the tenant module below.
  fargate_namespace = var.fargate_tenant
}

# ---- tenant-a: EC2 + Pod Identity, the path AWS recommends -------------------
module "tenant_a" {
  source = "../../modules/tenant"

  tenant        = var.ec2_tenant
  account_id    = data.aws_caller_identity.current.account_id
  cluster_name  = module.platform.cluster_name
  compute       = "ec2"
  identity_mode = "pod_identity"
}

# ---- tenant-b: Fargate + IRSA, because Pod Identity cannot run there ----------
module "tenant_b" {
  source = "../../modules/tenant"

  tenant            = var.fargate_tenant
  account_id        = data.aws_caller_identity.current.account_id
  cluster_name      = module.platform.cluster_name
  compute           = "fargate"
  identity_mode     = "irsa"
  oidc_provider_arn = module.platform.oidc_provider_arn
  oidc_provider_url = module.platform.oidc_provider_url
}
