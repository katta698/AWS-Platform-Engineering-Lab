###############################################################################
# Aurora Serverless v2 — PostgreSQL 16
# Pattern: shared cluster, database-per-tenant isolation
# Scales: 0.5 → 16 ACUs automatically based on load
###############################################################################

data "aws_region" "current" {}

locals {
  name        = "${var.project}-${var.environment}"
  common_tags = merge(var.tags, { Module = "aurora" })
}

# ── Cluster Parameter Group ───────────────────────────────────────────────────
# DBA-tuned: log DDL statements, connections, lock waits
resource "aws_rds_cluster_parameter_group" "main" {
  name        = "${local.name}-aurora-pg16"
  family      = "aurora-postgresql16"
  description = "Custom parameter group for ${local.name} Aurora PostgreSQL 16"

  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
  parameter {
    name  = "log_statement"
    value = "ddl"
  }
  parameter {
    name  = "log_lock_waits"
    value = "1"
  }
  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Log queries > 1 second
  }
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  tags = local.common_tags
}

# ── Enhanced Monitoring IAM Role ──────────────────────────────────────────────
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "${local.name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ── Aurora Cluster ─────────────────────────────────────────────────────────────
resource "aws_rds_cluster" "main" {
  cluster_identifier        = "${local.name}-aurora"
  engine                    = "aurora-postgresql"
  engine_mode               = "provisioned" # Required for Serverless v2
  engine_version            = "16.6"
  database_name             = var.database_name
  master_username           = var.master_username
  master_password           = var.master_password
  db_subnet_group_name      = var.db_subnet_group_name
  vpc_security_group_ids    = [var.aurora_security_group_id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  # Serverless v2 scaling configuration
  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  # Backup & maintenance
  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot        = true

  # Security
  storage_encrypted = true
  deletion_protection = false # Set true in prod

  # Data API — required for RDS Query Editor in AWS Console
  enable_http_endpoint = true

  # Lab settings — fast teardown
  skip_final_snapshot = true
  apply_immediately   = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(local.common_tags, { Name = "${local.name}-aurora" })
}

# ── Aurora Serverless v2 Writer Instance ──────────────────────────────────────
resource "aws_rds_cluster_instance" "writer" {
  identifier          = "${local.name}-aurora-instance-1"
  cluster_identifier  = aws_rds_cluster.main.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.main.engine
  engine_version      = aws_rds_cluster.main.engine_version

  # Observability — free tier thresholds
  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_days
  monitoring_role_arn                   = aws_iam_role.rds_enhanced_monitoring.arn
  monitoring_interval                   = 60 # Enhanced monitoring every 60s

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = merge(local.common_tags, { Name = "${local.name}-aurora-writer", Role = "writer" })
}

# ── Aurora Serverless v2 Reader Instance ──────────────────────────────────────
# Provides read-only endpoint for reporting queries — scales independently
resource "aws_rds_cluster_instance" "reader" {
  identifier          = "${local.name}-aurora-instance-2"
  cluster_identifier  = aws_rds_cluster.main.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.main.engine
  engine_version      = aws_rds_cluster.main.engine_version

  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_days
  monitoring_role_arn                   = aws_iam_role.rds_enhanced_monitoring.arn
  monitoring_interval                   = 60

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = merge(local.common_tags, { Name = "${local.name}-aurora-reader", Role = "reader" })
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name}-aurora-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Aurora CPU > 80% for 10 minutes"
  alarm_actions       = [var.alert_sns_topic_arn]

  dimensions = { DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier }
  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "connections_high" {
  alarm_name          = "${local.name}-aurora-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 200 # Alert before connection pool exhaustion
  alarm_description   = "Aurora connections > 200"
  alarm_actions       = [var.alert_sns_topic_arn]

  dimensions = { DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier }
  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "freeable_memory_low" {
  alarm_name          = "${local.name}-aurora-memory-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 256000000 # 256 MB
  alarm_description   = "Aurora freeable memory < 256 MB"
  alarm_actions       = [var.alert_sns_topic_arn]

  dimensions = { DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier }
  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "replica_lag" {
  alarm_name          = "${local.name}-aurora-replica-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuroraReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 1000 # 1 second lag
  alarm_description   = "Aurora replica lag > 1 second"
  alarm_actions       = [var.alert_sns_topic_arn]

  dimensions = { DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier }
  tags = local.common_tags
}

# ── CloudWatch Dashboard ──────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "aurora" {
  dashboard_name = "${local.name}-aurora"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title   = "CPU Utilization"
          region  = data.aws_region.current.name
          metrics = [["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", aws_rds_cluster.main.cluster_identifier]]
          period  = 60, stat = "Average", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title   = "Database Connections"
          region  = data.aws_region.current.name
          metrics = [["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", aws_rds_cluster.main.cluster_identifier]]
          period  = 60, stat = "Average", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title   = "Freeable Memory"
          region  = data.aws_region.current.name
          metrics = [["AWS/RDS", "FreeableMemory", "DBClusterIdentifier", aws_rds_cluster.main.cluster_identifier]]
          period  = 60, stat = "Average", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title   = "Replica Lag (ms)"
          region  = data.aws_region.current.name
          metrics = [["AWS/RDS", "AuroraReplicaLag", "DBClusterIdentifier", aws_rds_cluster.main.cluster_identifier]]
          period  = 60, stat = "Average", view = "timeSeries"
        }
      }
    ]
  })
}
