resource "aws_glue_catalog_database" "fleet" {
  name        = "${var.project_name}_fleet_${var.environment}"
  description = "Fleet intelligence — SSM inventory and patch compliance data"
}

# ── Crawler: raw SSM data → Data Catalog ──────────────────────────────────────
resource "aws_glue_crawler" "fleet" {
  name          = "${var.project_name}-fleet-crawler-${var.environment}"
  role          = var.glue_role_arn
  database_name = aws_glue_catalog_database.fleet.name

  s3_target {
    path = "s3://${var.raw_bucket_name}/ssm/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_EVERYTHING"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
      Tables     = { AddOrUpdateBehavior = "MergeNewColumns" }
    }
  })

  tags = var.tags
}

# ── Glue ETL Job: raw JSON → curated Parquet ──────────────────────────────────
resource "aws_glue_job" "fleet_etl" {
  name         = "${var.project_name}-fleet-etl-${var.environment}"
  role_arn     = var.glue_role_arn
  glue_version = "4.0"

  command {
    name            = "glueetl"
    script_location = "s3://${var.raw_bucket_name}/scripts/fleet_etl.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-job-insights"              = "true"
    "--TempDir"                          = "s3://${var.raw_bucket_name}/tmp/"
    "--SOURCE_BUCKET"                    = var.raw_bucket_name
    "--DEST_BUCKET"                      = var.curated_bucket_name
    "--GLUE_DATABASE"                    = aws_glue_catalog_database.fleet.name
    "--ENVIRONMENT"                      = var.environment
  }

  execution_property {
    max_concurrent_runs = 1
  }

  number_of_workers = 2
  worker_type       = "G.1X"
  timeout           = 30

  tags = var.tags
}

# ── Athena Workgroup ───────────────────────────────────────────────────────────
resource "aws_athena_workgroup" "fleet" {
  name          = "${var.project_name}-fleet-${var.environment}"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.athena_results_bucket_name}/results/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = var.tags
}

# ── Named Athena Queries ───────────────────────────────────────────────────────
resource "aws_athena_named_query" "patch_compliance_summary" {
  name        = "fleet-patch-compliance-summary"
  workgroup   = aws_athena_workgroup.fleet.id
  database    = aws_glue_catalog_database.fleet.name
  description = "Patch compliance summary by environment and status"
  query       = <<-SQL
    SELECT
      environment,
      compliance_status,
      severity,
      COUNT(*) AS instance_count
    FROM fleet_curated
    GROUP BY environment, compliance_status, severity
    ORDER BY instance_count DESC;
  SQL
}

resource "aws_athena_named_query" "non_compliant_instances" {
  name        = "fleet-non-compliant-instances"
  workgroup   = aws_athena_workgroup.fleet.id
  database    = aws_glue_catalog_database.fleet.name
  description = "Instances with critical missing patches"
  query       = <<-SQL
    SELECT
      instance_id,
      instance_name,
      platform_name,
      compliance_status,
      missing_patch_count,
      last_patch_time
    FROM fleet_curated
    WHERE compliance_status = 'NON_COMPLIANT'
    ORDER BY missing_patch_count DESC;
  SQL
}

resource "aws_athena_named_query" "os_inventory" {
  name        = "fleet-os-inventory"
  workgroup   = aws_athena_workgroup.fleet.id
  database    = aws_glue_catalog_database.fleet.name
  description = "OS version distribution across fleet"
  query       = <<-SQL
    SELECT
      platform_name,
      platform_version,
      COUNT(*) AS instance_count
    FROM fleet_curated
    GROUP BY platform_name, platform_version
    ORDER BY instance_count DESC;
  SQL
}
