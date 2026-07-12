###############################################################################
# Module: ECS Cluster
# One shared Fargate cluster for every self-service ticket. FARGATE_SPOT is
# available as a capacity provider but not the default — tickets opt in per
# service if the workload can tolerate interruption.
###############################################################################

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-cluster-${var.environment}"
  })
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}
