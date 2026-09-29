output "alb_dns_name" { value = aws_lb.this.dns_name }
output "cluster_name" { value = aws_ecs_cluster.this.name }
output "service_name" { value = aws_ecs_service.this.name }
output "alarm_name" { value = aws_cloudwatch_metric_alarm.errors.alarm_name }
output "blue_tg_arn" { value = aws_lb_target_group.blue.arn }
output "green_tg_arn" { value = aws_lb_target_group.green.arn }
