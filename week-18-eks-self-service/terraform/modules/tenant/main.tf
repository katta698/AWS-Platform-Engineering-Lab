# One tenant: a namespace that is actually a boundary, and an AWS identity that
# reaches exactly one bucket.
#
# A NAMESPACE ON ITS OWN ISOLATES NOTHING
# It is a label. It does not limit CPU or memory, it does not stop a pod talking
# to a pod in another namespace, and it has no bearing on AWS permissions. Each
# of those is a separate object that has to be created deliberately:
#
#   ResourceQuota   -> the ceiling. Without it one tenant can starve the rest
#   NetworkPolicy   -> Kubernetes allows all pod-to-pod traffic by default
#   Pod Identity    -> or IRSA. The AWS identity, scoped to this tenant's bucket
#
# TWO IDENTITY MECHANISMS, CHOSEN BY WHERE THE POD RUNS
# Pod Identity is what AWS recommends, and it cannot work on Fargate: its agent
# is a privileged DaemonSet and Fargate runs neither. So this module takes a
# flag. EC2 tenants get Pod Identity; Fargate tenants get IRSA. Both end at the
# same place -- a pod holding credentials for one bucket -- by different routes.

locals {
  bucket = "${var.name_prefix}-${var.tenant}-${var.account_id}"

  tags = merge(var.tags, {
    Project   = "aws-platform-engineering-lab"
    Week      = "18"
    Tenant    = var.tenant
    ManagedBy = "terraform"
  })
}

# ------------------------------------------------------------ the boundary --
resource "kubernetes_namespace" "this" {
  metadata {
    name = var.tenant
    labels = {
      tenant  = var.tenant
      compute = var.compute
    }
  }
}

# The actual ceiling. A tenant without one can request every core in the
# cluster, and Kubernetes will happily let it.
resource "kubernetes_resource_quota" "this" {
  metadata {
    name      = "${var.tenant}-quota"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = var.cpu_request_limit
      "requests.memory" = var.memory_request_limit
      "limits.cpu"      = var.cpu_limit
      "limits.memory"   = var.memory_limit
      "pods"            = var.max_pods
    }
  }
}

# Kubernetes defaults to allowing every pod to reach every other pod, in any
# namespace. This denies ingress from anywhere except this tenant's own
# namespace, which is what most people assume a namespace already did.
resource "kubernetes_network_policy" "deny_cross_tenant" {
  metadata {
    name      = "${var.tenant}-deny-cross-namespace"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = { tenant = var.tenant }
        }
      }
    }
  }
}

# ----------------------------------------------------------- the resource --
resource "aws_s3_bucket" "this" {
  bucket        = local.bucket
  force_destroy = true # a lab tenant; teardown must not need a manual empty
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ------------------------------------------------------------- the identity --
# Scoped to this tenant's bucket and nothing else. This is the statement the
# isolation test is trying to defeat: tenant-b's pod asking for tenant-a's
# bucket must be denied here, not by convention.
data "aws_iam_policy_document" "tenant" {
  statement {
    sid       = "OwnBucketOnly"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid       = "OwnObjectsOnly"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }
}

# The trust policy is where the two mechanisms actually differ.
#
# Pod Identity trusts one EKS service principal, and a session tag carries the
# cluster, namespace and service account. The same role works in another cluster
# with no edit.
#
# IRSA trusts this cluster's OIDC provider and matches the service account by a
# string in the token subject. Reusing the role in a second cluster means
# editing this document -- which is the limit that Pod Identity was built to
# remove.
data "aws_iam_policy_document" "assume_pod_identity" {
  count = var.identity_mode == "pod_identity" ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "assume_irsa" {
  count = var.identity_mode == "irsa" ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # Without the :sub condition any service account in the cluster could
    # assume this role. Without :aud the token audience is unchecked. Both are
    # easy to omit and neither failure is visible until someone tries.
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.tenant}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "tenant" {
  name = "${var.name_prefix}-${var.tenant}"
  assume_role_policy = var.identity_mode == "pod_identity" ? (
    data.aws_iam_policy_document.assume_pod_identity[0].json
  ) : data.aws_iam_policy_document.assume_irsa[0].json
  tags = local.tags
}

resource "aws_iam_role_policy" "tenant" {
  name   = "${var.tenant}-own-bucket-only"
  role   = aws_iam_role.tenant.id
  policy = data.aws_iam_policy_document.tenant.json
}

# IRSA needs the role ARN annotated onto the service account; Pod Identity does
# not, because the association lives in the EKS API instead.
resource "kubernetes_service_account" "this" {
  metadata {
    name      = var.service_account_name
    namespace = kubernetes_namespace.this.metadata[0].name

    annotations = var.identity_mode == "irsa" ? {
      "eks.amazonaws.com/role-arn" = aws_iam_role.tenant.arn
    } : {}
  }
}

# The Pod Identity half: a mapping held by EKS, with nothing inside the cluster
# pointing at an IAM ARN.
resource "aws_eks_pod_identity_association" "this" {
  count = var.identity_mode == "pod_identity" ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = kubernetes_namespace.this.metadata[0].name
  service_account = kubernetes_service_account.this.metadata[0].name
  role_arn        = aws_iam_role.tenant.arn
  tags            = local.tags
}
