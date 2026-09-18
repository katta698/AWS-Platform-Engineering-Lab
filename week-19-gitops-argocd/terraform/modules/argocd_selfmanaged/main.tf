# Upstream Argo CD, installed by Helm, running on nodes you pay for.
#
# This is the version every tutorial shows, and it is here as the control in an
# experiment rather than as a straw man. It is the only one of the two that can
# use Config Management Plugins, the Notifications controller, a non-Identity
# Center SSO provider, or a sync timeout other than 120 seconds.
#
# WHAT IT COSTS, WHICH IS NOT ZERO EVEN THOUGH THE SOFTWARE IS FREE
# The chart installs a StatefulSet and several Deployments -- the API server,
# repo-server, application controller, redis, dex, and the ApplicationSet and
# Notifications controllers. The exact pod count is deliberately not asserted
# here; it is read off the cluster after deploy and published from that.
#
# What matters is that all of it is scheduled onto your nodes. A t3.small has
# 2 GB and is already carrying kube-system, so this is most of the reason the
# cluster in this week runs a t3.medium. That +$0.0208/hr node delta is the
# real price of "free", and it is the number to hold against the capability's
# $0.03/hr.
#
# VERSION PINNING
# chart 10.9.1 -> Argo CD v3.5.3, released 2026-09-14. Pinned rather than
# floating: an unpinned chart makes a rebuild six months from now a different
# experiment, and this module exists to be compared against something.

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "lab.week"                     = "19"
    }
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Argo CD's own readiness is slow on a small node -- the application
  # controller waits on redis, which waits on scheduling. Without wait the
  # apply returns before anything is usable and the next step fails
  # confusingly.
  wait    = true
  timeout = 900

  values = [yamlencode({
    global = {
      # Keep everything on the one node group. No tolerations, so if the node
      # cannot fit Argo CD the pods stay Pending and say so, rather than
      # landing somewhere unexpected and hiding the capacity problem.
      nodeSelector = {}
    }

    # A public Git repo over HTTPS needs no credentials, which keeps the
    # comparison honest: both installs read the same repository the same way.
    configs = {
      params = {
        # insecure: the server terminates TLS at the load balancer in a real
        # deployment. Here it is reached by port-forward only -- see below.
        "server.insecure" = true
      }
    }

    server = {
      # Deliberately NOT a LoadBalancer.
      #
      # An internet-facing NLB or ALB here would add both cost and an exposed
      # Argo CD API for the life of the lab. The managed capability gets a URL
      # from AWS with Identity Center in front of it; matching that properly
      # would mean an ALB plus OIDC, which is a different week's build.
      #
      # So this one is reached with `kubectl port-forward`. That asymmetry is
      # itself a finding worth reporting rather than papering over: the managed
      # option arrives with authenticated ingress solved, and the self-managed
      # option leaves it to you.
      service = {
        type = "ClusterIP"
      }
    }
  })]

  depends_on = [kubernetes_namespace.argocd]
}
