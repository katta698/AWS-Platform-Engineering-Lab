# The source account's half of the OAM handshake — sharing is opt-in per
# account by design; this is the opt-in. Runs under the aliased source
# provider passed in from the environment.
resource "aws_oam_link" "this" {
  label_template  = "$AccountName"
  resource_types  = ["AWS::CloudWatch::Metric", "AWS::Logs::LogGroup"]
  sink_identifier = var.sink_arn
}
