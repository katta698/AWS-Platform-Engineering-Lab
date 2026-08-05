###############################################################################
# Monitoring -- turns WAF activity into something that reaches a human.
#
# A web ACL with no alarm is a control you have to remember to go and look at.
# The point of this module is that a spike in blocks arrives as an email
# rather than as a graph nobody opened.
#
# Instantiated once per web ACL, because a CloudWatch alarm can only publish
# to an SNS topic in its own region, and the two web ACLs publish metrics in
# different regions.
###############################################################################

locals {
  # CLOUDFRONT-scope metrics carry no Region dimension at all. Merging it in
  # conditionally is what keeps one module usable for both scopes -- a
  # hardcoded Region would silently break every edge alarm.
  metric_dimensions = merge(
    {
      WebACL = var.web_acl_name
      Rule   = "ALL"
    },
    var.metric_region_dimension == null ? {} : { Region = var.metric_region_dimension },
  )
}

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-waf-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

###############################################################################
# Alarms
###############################################################################

# Fires once rules are enforcing. A block spike is either a real attack or a
# false positive that just started rejecting legitimate users -- both warrant
# a look, which is why the threshold is a rate rather than "any block at all".
resource "aws_cloudwatch_metric_alarm" "blocked_requests" {
  alarm_name        = "${var.name_prefix}-blocked-requests"
  alarm_description = "WAF is blocking requests at an elevated rate on ${var.web_acl_name}. Either an attack is in progress or a rule is rejecting legitimate traffic."

  namespace   = "AWS/WAFV2"
  metric_name = "BlockedRequests"
  statistic   = "Sum"
  period      = 300

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.blocked_requests_threshold
  evaluation_periods  = 1

  dimensions = local.metric_dimensions

  # WAF publishes no datapoint when nothing is blocked, rather than a zero.
  # Without this, the alarm would sit in INSUFFICIENT_DATA during exactly the
  # periods when everything is fine.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# The Count-mode counterpart. During the observation phase nothing is blocked,
# so BlockedRequests stays flat at zero and would report "all clear" while
# rules are matching heavily. This alarm is what surfaces that.
resource "aws_cloudwatch_metric_alarm" "counted_requests" {
  alarm_name        = "${var.name_prefix}-counted-requests"
  alarm_description = "WAF rules on ${var.web_acl_name} are matching requests in Count mode. These would have been blocked if the rules were enforcing -- review before flipping to Block."

  namespace   = "AWS/WAFV2"
  metric_name = "CountedRequests"
  statistic   = "Sum"
  period      = 300

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.counted_requests_threshold
  evaluation_periods  = 1

  dimensions = local.metric_dimensions

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = var.tags
}
