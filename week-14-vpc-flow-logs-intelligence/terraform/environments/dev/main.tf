###############################################################################
# Week 14: VPC Flow Logs + Network Intelligence
#
# Flow logs get switched on for compliance, write to a bucket nobody can read,
# and are never queried again. This builds the layer that makes them answer
# questions:
#
#   VPC (NAT gateway + S3 gateway endpoint + an exposed instance)
#         |
#         |  flow logs, Parquet, hive-partitioned, record version 11
#         v
#   S3 bucket  --(partition projection, no crawler)-->  Glue table
#         |                                                  |
#         |                                          Athena workgroup
#         |                                        (scan ceiling enforced)
#         |                                          /            \
#         v                                 saved queries      analyzer Lambda
#   lifecycle expiry                        (humans, ad hoc)   (hourly, metrics)
#   (the thing that stops                                            |
#    this becoming a                                          CloudWatch alarms
#    permanent bill)                                          (anomaly + static)
#                                                                    |
#                                                                   SNS
#
# The design decision worth carrying away is the S3 destination: $0.25/GB versus
# $0.50/GB to CloudWatch Logs, and Parquet is only offered on the S3 path. One
# field in the flow log configuration halves the ingest bill and enables the
# storage format that makes querying affordable.
#
# On overlap with Week 11: GuardDuty already consumes these same flow logs for
# known-bad-IP detection. It does not give you a queryable table, and it cannot
# tell you which team's traffic drove the NAT bill. That gap is what this builds.
###############################################################################

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-14-dev"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "week14-flowlogs"

  common_tags = {
    Project     = "AWS-Platform-Engineering-Lab"
    Week        = "14"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  #############################################################################
  # The canonical flow log field list.
  #
  # This single list produces BOTH the flow log's custom log_format string and
  # the Glue table's column definitions. That is the entire reason it exists in
  # one place instead of two.
  #
  # Parquet columns are matched to the table schema positionally. If the format
  # string and the schema disagree on order, every query still runs, still
  # succeeds, and returns values from the wrong columns -- srcport under
  # dstport, bytes under packets. Nothing errors. Deriving both from one ordered
  # list makes that class of bug unrepresentable rather than merely unlikely.
  #
  # `region` is deliberately NOT in this list even though it is an available
  # field: it is already a partition key from the hive prefix, and a data column
  # of the same name collides with it.
  #
  # Version column shows which record version introduced each field. Anything
  # marked 8 or above is newer than most published examples of this table.
  #############################################################################
  flow_log_fields = [
    # --- v2: the default format ---
    { field = "version", column = "version", type = "int" },
    { field = "account-id", column = "account_id", type = "string" },
    { field = "interface-id", column = "interface_id", type = "string" },
    { field = "srcaddr", column = "srcaddr", type = "string" },
    { field = "dstaddr", column = "dstaddr", type = "string" },
    { field = "srcport", column = "srcport", type = "int" },
    { field = "dstport", column = "dstport", type = "int" },
    { field = "protocol", column = "protocol", type = "bigint" },
    { field = "packets", column = "packets", type = "bigint" },
    { field = "bytes", column = "bytes", type = "bigint" },
    { field = "start", column = "start", type = "bigint" },
    # `end` is a reserved word in Athena SQL. It stays named `end` to match the
    # AWS field name; queries must quote it as "end".
    { field = "end", column = "end", type = "bigint" },
    { field = "action", column = "action", type = "string" },
    { field = "log-status", column = "log_status", type = "string" },

    # --- v3: VPC/subnet/instance context and TCP flags ---
    { field = "vpc-id", column = "vpc_id", type = "string" },
    { field = "subnet-id", column = "subnet_id", type = "string" },
    { field = "instance-id", column = "instance_id", type = "string" },
    { field = "tcp-flags", column = "tcp_flags", type = "int" },
    { field = "type", column = "type", type = "string" },
    # The pair that stops NAT'd traffic from all appearing to come from the NAT.
    { field = "pkt-srcaddr", column = "pkt_srcaddr", type = "string" },
    { field = "pkt-dstaddr", column = "pkt_dstaddr", type = "string" },

    # --- v4: location ---
    { field = "az-id", column = "az_id", type = "string" },

    # --- v5: service identification, direction, and egress path ---
    { field = "pkt-src-aws-service", column = "pkt_src_aws_service", type = "string" },
    { field = "pkt-dst-aws-service", column = "pkt_dst_aws_service", type = "string" },
    { field = "flow-direction", column = "flow_direction", type = "string" },
    # traffic_path is what makes this a cost tool: 2 = NAT/IGW (billed),
    # 7 = gateway endpoint (free).
    { field = "traffic-path", column = "traffic_path", type = "int" },

    # --- v8: why a reject happened ---
    { field = "reject-reason", column = "reject_reason", type = "string" },

    # --- v11: interface classification, next hop, and embedded tags ---
    { field = "interface-type", column = "interface_type", type = "string" },
    { field = "next-hop-interface-id", column = "next_hop_interface_id", type = "string" },
    { field = "next-hop-vpc-id", column = "next_hop_vpc_id", type = "string" },
    { field = "next-hop-interface-type", column = "next_hop_interface_type", type = "string" },
    # Requires tag_field_specification on the flow log AND ec2:DescribeTags on
    # the delivery role. Missing either yields a column of '-' with no error.
    { field = "instance-tag", column = "instance_tag", type = "string" },
  ]

  # "${version} ${account-id} ${interface-id} ..."
  log_format = join(" ", [for f in local.flow_log_fields : "$${${f.field}}"])

  glue_columns = [for f in local.flow_log_fields : { name = f.column, type = f.type }]

  bucket_name     = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  database_name   = replace("${local.name_prefix}_db", "-", "_")
  table_name      = "flow_logs"
  qualified_table = "\"${local.database_name}\".\"${local.table_name}\""

  # Saved queries, rendered from the .sql files so the SQL stays reviewable as
  # SQL rather than buried in HCL strings.
  named_queries = {
    top-talkers = {
      description = "Highest-volume source/destination pairs, with both observed and original source addresses."
      sql         = templatefile("${path.module}/../../../athena/01_top_talkers.sql", { table = local.qualified_table })
    }
    rejected-traffic = {
      description = "Rejected flows clustered by source and destination. Repetition and spread are the signal, not any single reject."
      sql         = templatefile("${path.module}/../../../athena/02_rejected_traffic.sql", { table = local.qualified_table })
    }
    port-scan-candidates = {
      description = "Sources that were rejected against 20 or more distinct ports on one target."
      sql         = templatefile("${path.module}/../../../athena/03_port_scan_candidates.sql", { table = local.qualified_table })
    }
    nat-cost-attribution = {
      description = "NAT gateway egress bytes attributed to the owning team via the embedded instance tag."
      sql         = templatefile("${path.module}/../../../athena/04_nat_cost_attribution.sql", { table = local.qualified_table })
    }
    traffic-path-contrast = {
      description = "Egress broken down by route taken, showing billed NAT paths against free gateway endpoint paths."
      sql         = templatefile("${path.module}/../../../athena/05_traffic_path_contrast.sql", { table = local.qualified_table })
    }
    next-hop-path-trace = {
      description = "Which intermediate resource handled each flow, using the record version 11 next-hop fields."
      sql         = templatefile("${path.module}/../../../athena/06_next_hop_path_trace.sql", { table = local.qualified_table })
    }
    partition-sanity-check = {
      description = "RUN THIS FIRST. Confirms partition projection resolves and the tag fields populate. Zero rows here means every other query is silently returning nothing."
      sql         = templatefile("${path.module}/../../../athena/07_partition_sanity_check.sql", { table = local.qualified_table })
    }
  }
}

###############################################################################
# Capture layer
#
# Created before the network so the bucket exists for the generator's IAM policy.
###############################################################################

module "flow_logs" {
  source = "../../modules/flow_logs"

  name_prefix              = local.name_prefix
  vpc_id                   = module.network_lab.vpc_id
  bucket_name              = local.bucket_name
  log_format               = local.log_format
  tag_keys                 = var.flow_log_tag_keys
  traffic_type             = "ALL"
  max_aggregation_interval = var.max_aggregation_interval
  log_retention_days       = var.log_retention_days
}

###############################################################################
# Observed network
###############################################################################

module "network_lab" {
  source = "../../modules/network_lab"

  name_prefix             = local.name_prefix
  vpc_cidr                = var.vpc_cidr
  instance_type           = var.instance_type
  enable_exposed_instance = var.enable_exposed_instance
  generator_team_tag      = var.generator_team_tag

  # Constructed rather than taken from the module output, because the flow_logs
  # module needs this module's vpc_id -- referencing the output here would close
  # the cycle. The bucket name is deterministic, so this is safe.
  flow_logs_bucket_arn = "arn:aws:s3:::${local.bucket_name}"
}

###############################################################################
# Query layer
###############################################################################

module "analytics" {
  source = "../../modules/analytics"

  name_prefix             = local.name_prefix
  database_name           = local.database_name
  table_name              = local.table_name
  bucket_name             = module.flow_logs.bucket_name
  bucket_arn              = module.flow_logs.bucket_arn
  columns                 = local.glue_columns
  projection_start_year   = var.projection_start_year
  projection_end_year     = var.projection_end_year
  bytes_scanned_cutoff_gb = var.bytes_scanned_cutoff_gb
  named_queries           = local.named_queries
}

###############################################################################
# Analysis and alerting
###############################################################################

module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix       = local.name_prefix
  alert_email       = var.alert_email
  lambda_source_dir = "${path.module}/../../../lambda/flow_analyzer"
  lambda_build_dir  = "${path.module}/../../../lambda/builds"

  athena_database    = module.analytics.database_name
  athena_table       = module.analytics.table_name
  athena_workgroup   = module.analytics.workgroup_name
  results_bucket_arn = module.flow_logs.bucket_arn

  lookback_hours            = var.lookback_hours
  port_scan_alarm_threshold = var.port_scan_alarm_threshold
  anomaly_detection_stddev  = var.anomaly_detection_stddev
  enable_anomaly_alarms     = var.enable_anomaly_alarms
}
