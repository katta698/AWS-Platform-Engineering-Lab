output "vpc_id" { value = module.vpc.vpc_id }
output "alb_dns_name" { value = module.alb.alb_dns_name }
output "cloudwatch_dashboard_url" { value = module.cloudwatch.dashboard_url }
output "asg_name" { value = module.asg.asg_name }
output "github_actions_role_arn" { value = module.iam.github_actions_role_arn }
output "sns_topic_arn" { value = module.sns.topic_arn }
output "api_gateway_url" { value = module.api_gateway.api_endpoint }
output "state_machine_arn" { value = module.step_functions.state_machine_arn }
