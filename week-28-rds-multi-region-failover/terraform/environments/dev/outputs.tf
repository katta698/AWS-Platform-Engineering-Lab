output "primary_identifier" {
  description = "The writable instance, us-east-1."
  value       = aws_db_instance.primary.identifier
}

output "replica_identifier" {
  description = "The cross-region replica, us-west-2. Standalone once promoted."
  value       = aws_db_instance.replica.identifier
}

output "replica_arn" {
  description = "What the Region switch plan promotes."
  value       = aws_db_instance.replica.arn
}

output "writer_function" {
  description = "Invoked by scripts/run_failover.py to generate write load."
  value       = aws_lambda_function.writer.function_name
}

output "plan_arn" {
  description = "The Region switch plan, or empty when it was not created."
  value       = try(aws_arcregionswitch_plan.failover[0].arn, "")
}
