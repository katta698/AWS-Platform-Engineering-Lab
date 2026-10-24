output "role_arn" { value = aws_iam_role.fis.arn }
output "log_group" { value = aws_cloudwatch_log_group.fis.name }

output "experiment_ids" {
  description = "Experiment label -> template id, for scripts/run-experiment.sh"
  value = merge(
    { recovery = aws_fis_experiment_template.recovery.id },
    { for k, v in aws_fis_experiment_template.guarded : k => v.id }
  )
}
