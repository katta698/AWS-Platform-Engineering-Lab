###############################################################################
# analytics
#
# The query layer: a Glue table that knows where the logs are without anything
# ever crawling them, an Athena workgroup with a hard spend ceiling, and the
# saved queries that are the actual deliverable for a team on call.
#
# Why partition projection instead of a Glue crawler:
#
#   Flow log prefixes are perfectly deterministic -- region, year, month, day,
#   hour, all knowable in advance. A crawler would pay DPU-time on a schedule to
#   rediscover a structure we can simply state, and would lag behind new
#   partitions until its next run. Projection computes partitions at query time
#   from the template below: no schedule, no DPU charge, no lag, nothing to fail
#   overnight.
#
#   The trade-off is real: projection cannot adapt to a schema it was not told
#   about. That is fine here and would be wrong for genuinely unknown data.
#
#   The failure mode is the thing to respect. If the template does not match the
#   real prefixes character for character, every query returns zero rows and
#   reports success. There is no error to notice. It must be verified by running
#   a query against known-present data, not by reading the config back.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_glue_catalog_database" "this" {
  name        = var.database_name
  description = "VPC flow log analytics for ${var.name_prefix}."
}

locals {
  # Everything up to, but not including, the first projected partition key.
  table_location = "s3://${var.bucket_name}/AWSLogs/aws-account-id=${data.aws_caller_identity.current.account_id}/aws-service=vpcflowlogs"

  # Must reproduce the delivered prefix exactly. Compare against the layout
  # documented for hive_compatible_partitions + per_hour_partition.
  storage_location_template = "${local.table_location}/aws-region=$${region}/year=$${year}/month=$${month}/day=$${day}/hour=$${hour}"
}

resource "aws_glue_catalog_table" "flow_logs" {
  name          = var.table_name
  database_name = aws_glue_catalog_database.this.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL             = "TRUE"
    classification       = "parquet"
    "projection.enabled" = "true"

    # Region is an enum of exactly the regions logs are delivered from. Listing
    # regions that produce no logs only enlarges the search space.
    "projection.region.type"   = "enum"
    "projection.region.values" = data.aws_region.current.region

    "projection.year.type"   = "integer"
    "projection.year.range"  = "${var.projection_start_year},${var.projection_end_year}"
    "projection.year.digits" = "4"

    "projection.month.type"   = "integer"
    "projection.month.range"  = "1,12"
    "projection.month.digits" = "2"

    "projection.day.type"   = "integer"
    "projection.day.range"  = "1,31"
    "projection.day.digits" = "2"

    "projection.hour.type"   = "integer"
    "projection.hour.range"  = "0,23"
    "projection.hour.digits" = "2"

    "storage.location.template" = local.storage_location_template
  }

  storage_descriptor {
    location      = local.table_location
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "parquet"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"

      parameters = {
        "serialization.format" = 1
      }
    }

    dynamic "columns" {
      for_each = var.columns

      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }

  # Partition columns are typed string even where the projection type is integer.
  # The projection's `digits` setting handles zero-padding; declaring these as int
  # loses the leading zero and stops the template resolving to a real prefix.
  partition_keys {
    name = "region"
    type = "string"
  }

  partition_keys {
    name = "year"
    type = "string"
  }

  partition_keys {
    name = "month"
    type = "string"
  }

  partition_keys {
    name = "day"
    type = "string"
  }

  partition_keys {
    name = "hour"
    type = "string"
  }
}

###############################################################################
# Athena workgroup
#
# The bytes-scanned cutoff is the only thing standing between this table and an
# unbounded bill. Athena has no default spend limit; a SELECT * across every
# partition is a valid query that costs whatever it costs.
###############################################################################

resource "aws_athena_workgroup" "this" {
  name        = "${var.name_prefix}-wg"
  description = "Flow log analysis. Enforces a per-query scan ceiling and a fixed results location."
  state       = "ENABLED"

  # Removes the workgroup on destroy even with query history attached.
  force_destroy = true

  configuration {
    # Clients cannot silently redirect results elsewhere or opt out of the cutoff.
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    bytes_scanned_cutoff_per_query = var.bytes_scanned_cutoff_gb * 1024 * 1024 * 1024

    result_configuration {
      output_location = "s3://${var.bucket_name}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = { Name = "${var.name_prefix}-wg" }
}

###############################################################################
# Saved queries
#
# These are the deliverable a real team uses. An on-call engineer opens the
# Athena console, picks one, and has an answer -- no SQL written under pressure.
###############################################################################

resource "aws_athena_named_query" "this" {
  for_each = var.named_queries

  name        = "${var.name_prefix}-${each.key}"
  description = each.value.description
  database    = aws_glue_catalog_database.this.name
  workgroup   = aws_athena_workgroup.this.id
  query       = each.value.sql
}
