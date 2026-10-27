# The measurement.
#
# Everything here exists to turn the week's claim into a number rather than an
# impression. The control variable itself is NOT here -- reserved concurrency
# is an attribute of aws_lambda_function, not a resource of its own, so it
# lives in the service module where the function is declared.
#
# WHY "Throttles" AND NOT ERRORS OR 5xx
# -------------------------------------
# A throttled invocation is Lambda declining to start the function at all.
# There is no log line, no exception inside the handler, nothing for the
# application to catch. It is invisible from inside the service that suffered
# it -- which is why it needs an alarm rather than a dashboard somebody
# remembers to open.
#
# The API returns 502 to the caller, so from the outside it looks like the
# service crashed. It did not. It was never started.

resource "aws_cloudwatch_metric_alarm" "throttled" {
  for_each = var.function_names

  alarm_name          = "${var.name}-${each.key}-throttled"
  alarm_description   = "Lambda refused to start ${each.key}. Sum over 60s, one datapoint."
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  dimensions          = { FunctionName = each.value }
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  tags                = merge(var.tags, { Service = each.key })
}

# A dashboard, because the finding is a shape over time rather than a single
# number: the neighbours' concurrency climbing, the pool filling, and
# checkout's throttles beginning only once it is full.
resource "aws_cloudwatch_dashboard" "pool" {
  dashboard_name = "${var.name}-concurrency-pool"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 24, height = 8,
        properties = {
          title  = "Concurrent executions by service (the shared pool, filling)"
          region = var.region
          stat   = "Maximum"
          period = 60
          metrics = [
            for k, fn in var.function_names :
            ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", fn, { label = k }]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 8, width = 24, height = 8,
        properties = {
          title  = "Throttles by service (who was refused)"
          region = var.region
          stat   = "Sum"
          period = 60
          metrics = [
            for k, fn in var.function_names :
            ["AWS/Lambda", "Throttles", "FunctionName", fn, { label = k }]
          ]
        }
      }
    ]
  })
}
