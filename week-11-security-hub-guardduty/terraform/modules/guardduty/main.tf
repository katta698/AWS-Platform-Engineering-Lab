###############################################################################
# GuardDuty — active-threat detection.
#
# Foundational detection only: it analyzes CloudTrail management events, VPC
# Flow Logs, and DNS queries with no extra data-source cost. Extended Threat
# Detection (multi-stage attack correlation) is auto-enabled at $0 for every
# GuardDuty account — we get it just by turning the detector on.
#
# Protection plans (S3, EKS, Runtime, Malware, RDS, Lambda) are deliberately
# NOT enabled — each is a separate opt-in cost and this lab only needs the
# foundational threat signal to demonstrate the notify path. They would be added
# as aws_guardduty_detector_feature resources (the `datasources` block on the
# detector is deprecated).
###############################################################################

resource "aws_guardduty_detector" "this" {
  enable                       = true
  finding_publishing_frequency = var.finding_publishing_frequency

  tags = var.tags
}
