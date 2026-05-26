###############################################################################
# Module: Auto Scaling Group + Launch Template
# Immutable infrastructure — AMI-based, no SSH, SSM access only
###############################################################################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Launch Template ───────────────────────────────────────────────────────────
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project}-${var.environment}-lt-"
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.ec2_sg_id]

  # No SSH key pair — use SSM Session Manager instead
  # key_name = ""

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 enforced (security)
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true # Detailed CloudWatch monitoring
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/userdata.sh.tpl", {
    project     = var.project
    environment = var.environment
    app_port    = var.app_port
    region      = var.aws_region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.project}-${var.environment}-app"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.project}-${var.environment}-app-volume"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Auto Scaling Group ────────────────────────────────────────────────────────
resource "aws_autoscaling_group" "app" {
  name                      = "${var.project}-${var.environment}-asg"
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = [var.target_group_arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version  # Track version changes → triggers instance refresh
  }

  # Instance refresh for zero-downtime deploys
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 75
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-${var.environment}-asg"
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

# ── Scale-Out Policy (CPU > 70%) ──────────────────────────────────────────────
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.project}-${var.environment}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project}-${var.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale out when CPU > 70% for 2 minutes"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_out.arn]
}

# ── Scale-In Policy (CPU < 30%) ───────────────────────────────────────────────
resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.project}-${var.environment}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project}-${var.environment}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale in when CPU < 30% for 5 minutes"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_in.arn]
}
