# Week 23 -- Service networking with VPC Lattice
#
# The goal: one service that only a named identity can call, where the check
# happens before the request reaches any code.
#
# A security group cannot express "only the orders service may call rates" --
# it can only say "this IP range may connect". Both Lambdas here sit in the
# same subnet behind the same security group. The only thing that differs is
# which IAM role signs the request, and that is the whole point.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}

# ---------------------------------------------------------------------------
# The consumer network
# ---------------------------------------------------------------------------
#
# No internet gateway and no NAT gateway. The client reaches the service over
# the service network association, which is free; a NAT would have cost more
# per hour than everything else here combined.

resource "aws_vpc" "consumer" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name}-consumer" })
}

resource "aws_subnet" "consumer" {
  count = var.subnet_count

  vpc_id            = aws_vpc.consumer.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.tags, { Name = "${var.name}-consumer-${count.index}" })
}

# zone-type matters. This account has an opted-in Local Zone
# (us-east-1-dfw-1a), which describe-availability-zones returns alongside the
# ordinary ones. A subnet landed in it and Lambda refused to attach:
#
#   InvalidParameterValueException: The provided subnets contain availability
#   zone Lambda doesn't support.
#
# Filtering on zone-type keeps this to standard AZs and is region-portable --
# excluding the zone by name would only fix this account.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

# Deliberately permissive, and deliberately shared by both callers. If the
# security group were doing the authorisation, both would get the same answer.
resource "aws_security_group" "client" {
  name        = "${var.name}-client"
  description = "Shared by both callers on purpose -- it cannot tell them apart."
  vpc_id      = aws_vpc.consumer.id

  # INBOUND, not outbound, and that is not a typo.
  #
  # This security group is attached to the service network VPC association, and
  # AWS is explicit about the direction: "For traffic to flow from client VPCs
  # to the services associated with the service network, you must create
  # inbound rules for the listener ports and listener protocols", with the VPC
  # CIDR as the source.
  #
  # It reads backwards -- the client is making an outbound call -- and an
  # egress-only group produces no error at all. Requests simply time out, which
  # looks like a routing problem rather than a firewall one.
  ingress {
    description = "Clients in this VPC reaching the service network listener."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Anywhere inside the VPC and out to the service network."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}
