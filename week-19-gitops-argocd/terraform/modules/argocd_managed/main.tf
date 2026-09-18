# Argo CD as an EKS Capability -- AWS runs the controllers, not your cluster.
#
# WHAT IS ACTUALLY DIFFERENT HERE
# Upstream Argo CD is a set of pods you own -- API server, repo-server,
# application controller, redis, dex and more. The capability runs all of that
# in AWS-managed infrastructure outside the cluster. What lands in YOUR cluster
# is the CRDs and an access entry. Nothing schedules on your nodes, so nothing
# competes with workloads for the memory you are paying for.
#
# That is the whole trade in one sentence, and the rest of this file is the
# price of it: you get AWS's operational surface and you give up upstream's
# configuration surface.
#
# THE PREREQUISITE THAT IS NOT NEGOTIABLE
# "AWS Identity Center configured - Required for Argo CD authentication (local
# users are not supported)". There is no admin password to retrieve from a
# Kubernetes secret, which is how every upstream Argo CD tutorial starts. If
# the account has no Identity Center instance, this capability cannot be
# created at all -- it is a hard dependency, not a recommendation.
#
# WHAT THE CAPABILITY CANNOT DO, per the AWS comparison doc
#   - Config Management Plugins (custom manifest generation)
#   - the Notifications controller
#   - any SSO provider other than Identity Center
#   - UI extensions and custom banners
#   - most configuration ConfigMaps (a subset of argocd-cm only)
#   - changing the sync timeout, which is fixed at 120 seconds
# Those are not bugs; they are the boundary of a managed service. They are
# listed here because the decision between this and Helm is made by reading
# that list, not by comparing hourly rates.
#
# COST
#   $0.03 per capability-hour, plus $0.0015 per Argo CD Application-hour.
# Worth holding next to the alternative: upstream is free software that needs
# roughly a t3.small's worth of extra node (+$0.0208/hr) to run in. The two
# numbers are close enough that cost is not the deciding factor -- which is
# itself the finding.

data "aws_iam_policy_document" "capability_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type = "Service"
      # Not eks.amazonaws.com. The capabilities service is a distinct
      # principal, and using the cluster's one fails with "Invalid IAM role".
      identifiers = ["capabilities.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "capability" {
  name               = "${var.name_prefix}-argocd-capability"
  assume_role_policy = data.aws_iam_policy_document.capability_assume.json
  tags               = var.tags
}

# Deliberately no permissions policy attached.
#
# AWS's own guidance: "Argo CD - No IAM permissions required by default."
# They are needed only to read Git credentials from Secrets Manager or to use
# CodeConnections. This week deploys from a public repository over HTTPS, so
# the role holds nothing beyond the ability to be assumed.
#
# Stated plainly because the tempting move is to attach ReadOnlyAccess "just in
# case" and never revisit it. An empty role that works is evidence about what
# the service actually needs; a broad role that works is evidence about
# nothing.

resource "aws_eks_capability" "argocd" {
  cluster_name    = var.cluster_name
  capability_name = var.capability_name
  type            = "ARGOCD"
  role_arn        = aws_iam_role.capability.arn

  # RETAIN leaves the Argo CD custom resources in the cluster if the capability
  # is removed. For this lab the whole cluster is destroyed anyway, so the
  # choice is invisible -- but the alternative would delete every Application
  # on capability removal, which in a real cluster means a teardown of the
  # GitOps controller silently becoming a teardown of everything it deployed.
  delete_propagation_policy = "RETAIN"

  configuration {
    argo_cd {
      aws_idc {
        idc_instance_arn = var.idc_instance_arn
      }

      # The capability requires ONE namespace for its own custom resources.
      # Applications, ApplicationSets and AppProjects must all be created here.
      # This does NOT constrain where workloads land: an Application defined in
      # this namespace can deploy into any namespace on any registered cluster.
      namespace = var.namespace
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-argocd" })
}
