###############################################################################
# network_lab
#
# The VPC that gets observed. Every resource here exists to produce a specific,
# identifiable shape of traffic in the flow logs -- this is the data source for
# the whole week, not incidental scaffolding.
#
# The traffic shapes it deliberately produces:
#
#   generator -> internet    via NAT gateway     -> traffic_path 2, and BILLED at
#                                                   $0.045/GB processed
#   generator -> S3          via gateway endpoint -> traffic_path 7, and FREE
#   internet  -> exposed     denied by the SG     -> action REJECT
#
# The first two are the same instance reaching two AWS-adjacent destinations by
# two different routes with wildly different costs. That contrast is what makes
# `traffic-path` a cost tool rather than only a security field, and it is the
# single most useful thing in this build.
###############################################################################

data "aws_region" "current" {}

# Amazon Linux 2023, arm64 -- resolved live rather than hardcoded, because a
# pinned AMI ID rots the moment AWS publishes a new build and is region-locked.
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

###############################################################################
# VPC, subnets, routing
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-igw" }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${var.name_prefix}-public" }
}

# Deliberately in the SAME AZ as the public subnet. A cross-AZ NAT path would add
# $0.02/GB of inter-AZ transfer on top of NAT processing, which would muddy the
# cost story this build is trying to tell clearly.
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = { Name = "${var.name_prefix}-private" }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "${var.name_prefix}-nat-eip" }
}

# The most expensive resource in this build: $0.045/hr just to exist, plus
# $0.045 per GB processed. It is here because NAT egress is the line item real
# teams cannot attribute to an owner, and attributing it is the point of the week.
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = { Name = "${var.name_prefix}-nat" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name_prefix}-public-rt" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = { Name = "${var.name_prefix}-private-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

###############################################################################
# S3 gateway endpoint -- the free path
#
# Gateway endpoints cost nothing: no hourly charge, no per-GB charge. Traffic to
# S3 through this endpoint bypasses the NAT gateway entirely and therefore skips
# the $0.045/GB processing fee. In the flow logs it shows up as traffic_path 7
# instead of 2. Same destination service, two routes, one of them free.
###############################################################################

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.name_prefix}-s3-endpoint" }
}

###############################################################################
# Security groups
#
# The exposed instance's security group is the mechanism that CREATES the REJECT
# records this week analyses. It has no ingress rules at all, so every unsolicited
# packet the internet sends at its public IP is dropped and logged as REJECT.
# Removing these denials would not "harden" anything -- it would delete the signal.
###############################################################################

resource "aws_security_group" "generator" {
  name        = "${var.name_prefix}-generator-sg"
  description = "Traffic generator: egress only, no inbound."
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-generator-sg" }
}

resource "aws_vpc_security_group_egress_rule" "generator_all" {
  security_group_id = aws_security_group.generator.id
  description       = "Outbound to anywhere -- this is what produces the NAT and endpoint flows."
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "exposed" {
  name        = "${var.name_prefix}-exposed-sg"
  description = "Internet-reachable instance. NO ingress rules by design -- every inbound packet is dropped and logged as REJECT."
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-exposed-sg" }
}

# Egress only. There is deliberately no ingress rule resource in this file for
# the exposed instance -- absence of ingress is the feature.
resource "aws_vpc_security_group_egress_rule" "exposed_all" {
  security_group_id = aws_security_group.exposed.id
  description       = "Outbound only. Needed for SSM agent registration and package updates."
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

###############################################################################
# Instance role -- SSM Session Manager access, no SSH key, no inbound port 22
###############################################################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name_prefix}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Read-only on the flow logs bucket. The generator lists it on a loop purely so
# there is steady, identifiable S3-bound traffic taking the gateway endpoint path.
data "aws_iam_policy_document" "generator_s3_read" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetObject"]
    resources = [var.flow_logs_bucket_arn, "${var.flow_logs_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "generator_s3_read" {
  name   = "${var.name_prefix}-generator-s3-read"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.generator_s3_read.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name_prefix}-instance-profile"
  role = aws_iam_role.instance.name
}

###############################################################################
# Instances
###############################################################################

locals {
  # Runs every minute via systemd timer. Half the calls go to the internet
  # through the NAT gateway; half go to S3 through the free gateway endpoint.
  # Both are then distinguishable in Athena by traffic_path.
  generator_user_data = <<-EOT
    #!/bin/bash
    set -eux

    dnf install -y awscli-2 || dnf install -y aws-cli || true

    cat > /usr/local/bin/generate-traffic.sh <<'SCRIPT'
    #!/bin/bash
    # NAT-bound traffic: leaves via the NAT gateway, billed per GB, traffic_path 2.
    for url in https://checkip.amazonaws.com https://aws.amazon.com/ https://www.google.com/; do
      curl -s -m 10 -o /dev/null "$url" || true
    done

    # Endpoint-bound traffic: leaves via the S3 gateway endpoint, free, traffic_path 7.
    aws s3 ls "s3://${var.name_prefix}-placeholder" --region ${data.aws_region.current.region} >/dev/null 2>&1 || true
    aws s3 ls --region ${data.aws_region.current.region} >/dev/null 2>&1 || true
    SCRIPT
    chmod +x /usr/local/bin/generate-traffic.sh

    cat > /etc/systemd/system/generate-traffic.service <<'UNIT'
    [Unit]
    Description=Flow log traffic generator
    [Service]
    Type=oneshot
    ExecStart=/usr/local/bin/generate-traffic.sh
    UNIT

    cat > /etc/systemd/system/generate-traffic.timer <<'TIMER'
    [Unit]
    Description=Run the flow log traffic generator every minute
    [Timer]
    OnBootSec=60
    OnUnitActiveSec=60
    [Install]
    WantedBy=timers.target
    TIMER

    systemctl daemon-reload
    systemctl enable --now generate-traffic.timer
  EOT
}

resource "aws_instance" "generator" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.generator.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  user_data              = local.generator_user_data

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted   = true
    volume_size = 8
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.name_prefix}-generator"
    # Read directly into each flow log record by the tag_field_specification in
    # the flow_logs module. This is the column NAT spend gets attributed to.
    Team = var.generator_team_tag
    Role = "traffic-generator"
  }
}

resource "aws_instance" "exposed" {
  count = var.enable_exposed_instance ? 1 : 0

  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.exposed.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted   = true
    volume_size = 8
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.name_prefix}-exposed"
    Team = var.exposed_team_tag
    Role = "reject-signal-source"
  }
}
