###############################################################################
# Module: Security Groups
# Principle of Least Privilege — separate SGs per tier
###############################################################################

# ── ALB Security Group ───────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb-sg"
  description = "Allow HTTPS inbound to ALB from internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP redirect"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-alb-sg"
    Tier = "public"
  })
}

# ── EC2/ASG Security Group ───────────────────────────────────────────────────
resource "aws_security_group" "ec2" {
  name        = "${var.project}-${var.environment}-ec2-sg"
  description = "Allow traffic only from ALB SG - no direct internet access"
  vpc_id      = var.vpc_id

  ingress {
    description     = "App port from ALB only"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound (for OS updates, SSM)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-ec2-sg"
    Tier = "private"
  })
}

# ── VPC Endpoints Security Group ─────────────────────────────────────────────
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project}-${var.environment}-vpce-sg"
  description = "SG for SSM/S3/CW VPC endpoints - no NAT needed"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from EC2"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-vpce-sg"
  })
}
