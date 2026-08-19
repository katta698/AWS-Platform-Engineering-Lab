###############################################################################
# analytics
#
# The query layer, and the part of this build that is not in any AWS document.
#
# AWS publishes two CloudTrail-on-Athena recipes and neither one fits:
#
#   * The partition-projection example covers a SINGLE account in a SINGLE
#     region. It projects one `timestamp` key against
#     AWSLogs/<account-id>/CloudTrail/<region>/.
#
#   * The organization-wide page handles the extra path segment, but only with
#     manual `ALTER TABLE ADD PARTITION` -- one statement per account, per
#     region, per day. It then concedes the point: "in a large organization,
#     using this method ... can be cumbersome. In such a scenario, consider
#     using CloudTrail Lake rather than Athena."
#
# That advice stopped being followable on 2026-05-31, when CloudTrail Lake
# closed to new customers. So the documented options are a table that cannot see
# an organization, or a maintenance chore AWS itself calls cumbersome, or a
# service you can no longer sign up for.
#
# This module takes the third path: partition projection applied to the
# organization trail layout, projecting five keys instead of one.
#
#   AWSLogs/<org-id>/<account-id>/CloudTrail/<region>/<year>/<month>/<day>/
#                    ^^^^^^^^^^^^            ^^^^^^^^  ^^^^^^^^^^^^^^^^^^
#                    enum                    enum      integer projections
#
# The two enums are the trade-off. Dates project infinitely; accounts and
# regions do not, so both are finite lists that need maintaining. See the
# account_ids variable for why that is stated plainly rather than smoothed over.
#
# The failure mode is the one Week 14 taught: a projection template that does not
# match the delivered prefix returns zero rows and reports SUCCEEDED. There is no
# error. Verification has to run a query against known-present data.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_glue_catalog_database" "this" {
  name        = var.database_name
  description = "CloudTrail organization-trail audit forensics for ${var.name_prefix}."
}

locals {
  # Everything up to, but not including, the first projected key.
  table_location = "s3://${var.bucket_name}/AWSLogs/${var.organization_id}"

  # Must reproduce the delivered prefix exactly, including the literal
  # "CloudTrail" segment between the account and the region.
  storage_location_template = "${local.table_location}/$${account}/CloudTrail/$${region}/$${year}/$${month}/$${day}"

  # The CloudTrail event schema. Unlike Week 14's flow logs, this is not derived
  # from anything we configure -- AWS defines it -- so there is no format string
  # to drift against. It is transcribed from the Athena CloudTrail table
  # reference, including the nested userIdentity structure that the MFA and
  # role-session queries depend on.
  columns = [
    { name = "eventversion", type = "string" },
    { name = "useridentity", type = "struct<type:string,principalid:string,arn:string,accountid:string,invokedby:string,accesskeyid:string,username:string,onbehalfof:struct<userid:string,identitystorearn:string>,sessioncontext:struct<attributes:struct<mfaauthenticated:string,creationdate:string>,sessionissuer:struct<type:string,principalid:string,arn:string,accountid:string,username:string>,ec2roledelivery:string,webidfederationdata:struct<federatedprovider:string,attributes:map<string,string>>>>" },
    { name = "eventtime", type = "string" },
    { name = "eventsource", type = "string" },
    { name = "eventname", type = "string" },
    { name = "awsregion", type = "string" },
    { name = "sourceipaddress", type = "string" },
    { name = "useragent", type = "string" },
    { name = "errorcode", type = "string" },
    { name = "errormessage", type = "string" },
    { name = "requestparameters", type = "string" },
    { name = "responseelements", type = "string" },
    { name = "additionaleventdata", type = "string" },
    { name = "requestid", type = "string" },
    { name = "eventid", type = "string" },
    { name = "readonly", type = "string" },
    { name = "resources", type = "array<struct<arn:string,accountid:string,type:string>>" },
    { name = "eventtype", type = "string" },
    { name = "apiversion", type = "string" },
    { name = "recipientaccountid", type = "string" },
    { name = "serviceeventdetails", type = "string" },
    { name = "sharedeventid", type = "string" },
    { name = "vpcendpointid", type = "string" },
    { name = "vpcendpointaccountid", type = "string" },
    { name = "eventcategory", type = "string" },
    { name = "addendum", type = "struct<reason:string,updatedfields:string,originalrequestid:string,originaleventid:string>" },
    { name = "sessioncredentialfromconsole", type = "string" },
    { name = "edgedevicedetails", type = "string" },
    { name = "tlsdetails", type = "struct<tlsversion:string,ciphersuite:string,clientprovidedhostheader:string>" },
  ]
}

resource "aws_glue_catalog_table" "cloudtrail" {
  name          = var.table_name
  database_name = aws_glue_catalog_database.this.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL             = "TRUE"
    classification       = "cloudtrail"
    "projection.enabled" = "true"

    # Accounts and regions are enums because projection has no way to discover
    # them. Dates are computed, so they need no maintenance at all.
    "projection.account.type"   = "enum"
    "projection.account.values" = join(",", var.account_ids)

    "projection.region.type"   = "enum"
    "projection.region.values" = join(",", var.regions)

    "projection.year.type"   = "integer"
    "projection.year.range"  = "${var.projection_start_year},${var.projection_end_year}"
    "projection.year.digits" = "4"

    "projection.month.type"   = "integer"
    "projection.month.range"  = "1,12"
    "projection.month.digits" = "2"

    "projection.day.type"   = "integer"
    "projection.day.range"  = "1,31"
    "projection.day.digits" = "2"

    "storage.location.template" = local.storage_location_template
  }

  storage_descriptor {
    location = local.table_location

    # CloudTrail's own input format, not a generic JSON reader. CloudTrail
    # delivers gzipped JSON with a records wrapper; CloudTrailInputFormat unwraps
    # it. Pointing a plain text input format at these files yields one unusable
    # row per file rather than an error.
    input_format  = "com.amazon.emr.cloudtrail.CloudTrailInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "cloudtrail"
      serialization_library = "org.apache.hive.hcatalog.data.JsonSerDe"
    }

    dynamic "columns" {
      for_each = local.columns

      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }

  # Partition keys are all typed string, including the numeric-looking ones.
  # The projection's `digits` setting supplies the zero-padding that makes the
  # template resolve to a real prefix; typing them int discards the leading zero
  # and the resolved path stops matching anything.
  partition_keys {
    name = "account"
    type = "string"
  }

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
}

###############################################################################
# Athena workgroup
###############################################################################

resource "aws_athena_workgroup" "this" {
  name        = "${var.name_prefix}-wg"
  description = "CloudTrail audit forensics. Enforces a per-query scan ceiling and a fixed results location."
  state       = "ENABLED"

  force_destroy = true

  configuration {
    # Clients cannot redirect results elsewhere or opt out of the scan ceiling.
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
# These are the deliverable. An investigation starts with someone under pressure
# asking "who did this" -- the value is that the SQL already exists.
###############################################################################

resource "aws_athena_named_query" "this" {
  for_each = var.named_queries

  name        = "${var.name_prefix}-${each.key}"
  description = each.value.description
  database    = aws_glue_catalog_database.this.name
  workgroup   = aws_athena_workgroup.this.id
  query       = each.value.sql
}
