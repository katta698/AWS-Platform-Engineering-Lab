output "state_machine_arn" {
  value = aws_sfn_state_machine.db_provisioning.arn
}

output "state_machine_name" {
  value = aws_sfn_state_machine.db_provisioning.name
}
