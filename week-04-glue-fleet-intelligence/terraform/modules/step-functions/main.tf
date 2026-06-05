resource "aws_sfn_state_machine" "fleet_pipeline" {
  name     = "${var.project_name}-fleet-pipeline-${var.environment}"
  role_arn = var.sfn_role_arn

  definition = templatefile("${path.module}/../../../step_functions/state_machine.json", {
    glue_trigger_arn    = var.glue_trigger_lambda_arn
    status_updater_arn  = var.status_updater_lambda_arn
    crawler_name        = var.crawler_name
    etl_job_name        = var.etl_job_name
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/states/${var.project_name}-fleet-pipeline-${var.environment}"
  retention_in_days = 14
  tags              = var.tags
}
