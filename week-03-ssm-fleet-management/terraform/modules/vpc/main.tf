###############################################################################
# VPC + SSM VPC Endpoints
# Private subnets only — instances reach SSM without NAT or internet gateway
# Required endpoints: ssm, ssmmessages, ec2messages, s3 (gateway), logs
###############################################################################

data "aws_availability_zones" "available" { state = "available" }
data "aws_region" "current" {}

# Use SSM endpoint service to discover which AZs actually support it.
# Some us-east-1 AZs (e.g. us-east-1e) don't support interface endpoints.
data "aws_vpc_endpoint_service" "ssm" {
  service      = "ssm"
  service_type = "Interface"
}

locals {
  # Intersect available AZs with AZs that support the SSM endpoint
  supported_azs = tolist(setintersection(
    toset(data.aws_availability_zones.available.names),
    toset(data.aws_vpc_endpoint_service.ssm.availability_zones)
  ))
  azs = slice(local.supported_azs, 0, min(2, length(local.supported_azs)))
}

# ── VPC ───────────────────────────────────────────────────────────────────────
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.project}-${var.environment}-vpc" }
}

# ── Subnets ───────────────────────────────────────────────────────────────────
resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.project}-${var.environment}-private-${local.azs[count.index]}" }
}

# ── Route table (private - local only) ───────────────────────────────────────
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-${var.environment}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ── Security group for VPC endpoints ─────────────────────────────────────────
resource "aws_security_group" "endpoints" {
  name        = "${var.project}-${var.environment}-endpoints-sg"
  description = "Allow HTTPS from VPC to SSM endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-endpoints-sg" }
}

# ── Security group for EC2 fleet ──────────────────────────────────────────────
resource "aws_security_group" "ec2" {
  name        = "${var.project}-${var.environment}-ec2-sg"
  description = "EC2 fleet - outbound only, no inbound SSH"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-ec2-sg" }
}

# ── SSM Interface endpoints ───────────────────────────────────────────────────
locals {
  interface_endpoints = ["ssm", "ssmmessages", "ec2messages", "logs"]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.project}-${var.environment}-ep-${each.key}" }
}

# ── S3 Gateway endpoint (for SSM agent patches + inventory) ──────────────────
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.project}-${var.environment}-ep-s3" }
}
