# OAM sink — the attachment point cross-account observability data flows into.
resource "aws_oam_sink" "this" {
  name = var.name
}

# Org-scoped trust boundary: any account in the organization may link, but
# only for logs and metrics — future vended accounts join with zero changes.
resource "aws_oam_sink_policy" "this" {
  sink_identifier = aws_oam_sink.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["oam:CreateLink", "oam:UpdateLink"]
      Resource  = "*"
      Condition = {
        StringEquals = {
          "aws:PrincipalOrgID" = var.organization_id
        }
        "ForAllValues:StringEquals" = {
          "oam:ResourceTypes" = ["AWS::CloudWatch::Metric", "AWS::Logs::LogGroup"]
        }
      }
    }]
  })
}
