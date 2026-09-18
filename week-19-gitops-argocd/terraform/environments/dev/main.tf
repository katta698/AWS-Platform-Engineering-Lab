# Week 19 -- GitOps on EKS, two ways, on one cluster.
#
#   argocd        the EKS Capability for Argo CD. AWS runs the controllers
#                 outside the cluster, authenticated by Identity Center.
#   argocd-self   upstream Argo CD installed by Helm, running on the node.
#
# Both read the same Git repository and deploy the same application, so the
# differences that show up are differences between the two approaches and not
# between two setups. That is the entire design of the week: a comparison is
# only worth reading if the only variable is the thing being compared.
#
# The obvious expectation going in is that the managed one costs more and does
# less. It does do less -- the unsupported-feature list is real and specific.
# Whether it costs more is the part worth measuring rather than assuming:
# $0.03/hr for the capability against a node that has to be one size larger to
# hold seven pods it would not otherwise carry.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      # aws_eks_capability needs a recent provider. 6.64.0 was current when
      # this was written; ~> 6.0 would silently resolve to something without
      # the resource and fail with an unhelpful "invalid resource type".
      source  = "hashicorp/aws"
      version = ">= 6.60, < 7.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-19-dev"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "aws-platform-engineering-lab"
      Week      = "19"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# Identity Center is a hard prerequisite for the managed capability -- it
# supports no other authentication method. Read rather than created: the
# instance already exists in this account and is not this week's to manage.
#
# Looked up by data source instead of pasted as a literal so the config carries
# no account-specific identifier, and so a missing instance fails at plan time
# with a clear error rather than at apply with "Invalid IAM role".
data "aws_ssoadmin_instances" "this" {}

# The Kubernetes and Helm providers authenticate with a token minted from the
# AWS credentials Terraform already holds. No kubeconfig on disk, and the run
# behaves the same on a laptop or an HCP runner.
#
# The catch, which cost Week 18 a run: these providers are configured from
# attributes of a cluster created in the same apply. Terraform evaluates
# provider configuration early, so a first apply from empty state can need two
# passes -- the cluster exists after the first, the in-cluster resources land
# on the second.
provider "kubernetes" {
  host                   = module.platform.cluster_endpoint
  cluster_ca_certificate = base64decode(module.platform.cluster_ca)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.platform.cluster_name]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.platform.cluster_endpoint
    cluster_ca_certificate = base64decode(module.platform.cluster_ca)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.platform.cluster_name]
    }
  }
}

module "platform" {
  source = "../../modules/platform_cluster"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  node_instance_type = var.node_instance_type
  log_retention_days = var.log_retention_days

  # Without this the only cluster admin is HCP's runner role, and kubectl from
  # a laptop gets "the server has asked for the client to provide credentials".
  # Week 18 learned that by being locked out of a cluster it had just created.
  cluster_admin_role_arns = var.cluster_admin_role_arns
}

# ---- the managed path: AWS runs Argo CD ---------------------------------
module "argocd_managed" {
  source = "../../modules/argocd_managed"

  cluster_name     = module.platform.cluster_name
  name_prefix      = var.cluster_name
  idc_instance_arn = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  namespace        = var.managed_namespace
}

# ---- the self-managed path: you run Argo CD ------------------------------
#
# depends_on on the node group, not just the cluster: Helm will happily install
# against a control plane with no capacity, and then wait 900 seconds for pods
# that can never be scheduled. Failing at the node group is clearer than
# failing at a chart timeout.
module "argocd_selfmanaged" {
  source = "../../modules/argocd_selfmanaged"

  namespace     = var.selfmanaged_namespace
  chart_version = var.argocd_chart_version

  depends_on = [module.platform]
}
