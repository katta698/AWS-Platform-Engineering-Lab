resource "aws_sfn_state_machine" "fargate_provisioning" {
  name     = "${var.project_name}-provisioning-${var.environment}"
  role_arn = var.sfn_role_arn

  definition = templatefile("${path.module}/../../../step_functions/state_machine.json", {
    fargate_provisioner_arn = var.fargate_provisioner_lambda_arn
    status_notifier_arn     = var.status_notifier_lambda_arn
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/states/${var.project_name}-provisioning-${var.environment}"
  retention_in_days = 14
  tags              = var.tags
}
