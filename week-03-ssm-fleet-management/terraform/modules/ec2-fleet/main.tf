###############################################################################
# EC2 Fleet Module
# - Launch template with SSM agent, no SSH key pair
# - Auto Scaling Group across private subnets
# - Tagged for patch groups and SSM inventory
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

data "aws_region" "current" {}

resource "aws_launch_template" "fleet" {
  name_prefix            = "${var.project}-${var.environment}-"
  image_id               = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  # No key_name — access via SSM Session Manager only

  iam_instance_profile {
    name = var.instance_profile_name
  }

  # Explicitly use gp2 — gp3 is not supported in all us-east-1 AZs
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp2"
      volume_size           = 30
      delete_on_termination = true
      encrypted             = true
    }
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.ec2_sg_id]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 enforced
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Install and start SSM agent (pre-installed on AL2023 but ensure running)
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    # Install CloudWatch agent
    yum install -y amazon-cloudwatch-agent

    # Tag instance OS for patch group targeting
    INSTANCE_ID=$(TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600") && \
      curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/instance-id)

    aws ec2 create-tags \
      --region ${data.aws_region.current.name} \
      --resources $INSTANCE_ID \
      --tags \
        Key=PatchGroup,Value=${var.project}-${var.environment}-linux \
        Key=ManagedBy,Value=ssm-fleet-${var.environment} \
        Key=OS,Value=AmazonLinux2023
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name       = "${var.project}-${var.environment}-fleet"
      PatchGroup = "${var.project}-${var.environment}-linux"
      ManagedBy  = "ssm-fleet-${var.environment}"
      OS         = "AmazonLinux2023"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.project}-${var.environment}-fleet-volume"
    }
  }

  tags = { Name = "${var.project}-${var.environment}-launch-template" }
}

resource "aws_autoscaling_group" "fleet" {
  name                = "${var.project}-${var.environment}-fleet-asg"
  desired_capacity    = var.desired_capacity
  min_size            = var.min_size
  max_size            = var.max_size
  vpc_zone_identifier = var.private_subnet_ids

  launch_template {
    id      = aws_launch_template.fleet.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "${var.project}-${var.environment}-fleet"
    propagate_at_launch = true
  }

  tag {
    key                 = "PatchGroup"
    value               = "${var.project}-${var.environment}-linux"
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "ssm-fleet-${var.environment}"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
