###############################################################################
# VPC — Week 2: Aurora Self-Service Platform
# Three-tier layout: public (NAT/IGW) | private (Lambda) | database (Aurora)
###############################################################################

locals {
  name = "${var.project}-${var.environment}"
  common_tags = merge(var.tags, {
    Module = "vpc"
  })
}

# ── VPC ───────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "${local.name}-vpc" })
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${local.name}-igw" })
}

# ── Public Subnets ────────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-${var.azs[count.index]}"
    Tier = "public"
  })
}

# ── Private Subnets (Lambda tier) ─────────────────────────────────────────────
resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-${var.azs[count.index]}"
    Tier = "private"
  })
}

# ── Database Subnets (Aurora tier — no route to internet) ─────────────────────
resource "aws_subnet" "database" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.database_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name}-database-${var.azs[count.index]}"
    Tier = "database"
  })
}

# ── NAT Gateway ───────────────────────────────────────────────────────────────
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name}-nat-eip" })
}

resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.common_tags, { Name = "${local.name}-nat" })
  depends_on = [aws_internet_gateway.main]
}

# ── Route Tables ──────────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(local.common_tags, { Name = "${local.name}-rt-public" })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name}-rt-private" })
}

resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id
  # No default route — database subnets are fully isolated
  tags = merge(local.common_tags, { Name = "${local.name}-rt-database" })
}

# ── Route Table Associations ──────────────────────────────────────────────────
resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "database" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# ── Security Group: Aurora ─────────────────────────────────────────────────────
# Only accepts PostgreSQL (5432) from the Lambda private tier
resource "aws_security_group" "aurora" {
  name        = "${local.name}-aurora-sg"
  description = "Aurora PostgreSQL - allow 5432 from Lambda tier only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from Lambda SG"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    description = "Allow all outbound (needed for IAM auth token refresh)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-aurora-sg" })
}

# ── Security Group: Lambda ─────────────────────────────────────────────────────
resource "aws_security_group" "lambda" {
  name        = "${local.name}-lambda-sg"
  description = "Lambda functions - allow outbound to Aurora and AWS APIs"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound (Secrets Manager, Step Functions, ServiceNow)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-lambda-sg" })
}

# ── DB Subnet Group ────────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "aurora" {
  name        = "${local.name}-aurora-subnet-group"
  description = "Aurora Serverless v2 - isolated database subnets"
  subnet_ids  = aws_subnet.database[*].id

  tags = merge(local.common_tags, { Name = "${local.name}-aurora-subnet-group" })
}
