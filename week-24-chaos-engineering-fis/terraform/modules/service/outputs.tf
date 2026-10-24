output "cluster_arn" { value = aws_ecs_cluster.this.arn }
output "cluster_name" { value = aws_ecs_cluster.this.name }
output "service_name" { value = aws_ecs_service.this.name }
output "alb_dns" { value = aws_lb.this.dns_name }
output "target_group_arn_suffix" { value = aws_lb_target_group.this.arn_suffix }
output "load_balancer_arn_suffix" { value = aws_lb.this.arn_suffix }

output "alarm_fast_arn" { value = aws_cloudwatch_metric_alarm.unhealthy_fast.arn }
output "alarm_typical_arn" { value = aws_cloudwatch_metric_alarm.unhealthy_typical.arn }
output "alarm_fast_name" { value = aws_cloudwatch_metric_alarm.unhealthy_fast.alarm_name }
output "alarm_typical_name" { value = aws_cloudwatch_metric_alarm.unhealthy_typical.alarm_name }
