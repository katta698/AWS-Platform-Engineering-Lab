output "asg_name"              { value = aws_autoscaling_group.app.name }
output "asg_arn"               { value = aws_autoscaling_group.app.arn }
output "launch_template_id"    { value = aws_launch_template.app.id }
output "launch_template_version" { value = aws_launch_template.app.latest_version }
