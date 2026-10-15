# ---------------------------------------------------------------------------
# The switchboard
# ---------------------------------------------------------------------------

# auth_type is set EXPLICITLY on both the network and the service, and that is
# not boilerplate.
#
# In Terraform auth_type is optional on both resources, and the auth policy is
# a separate resource that does not set it. So this is valid, applies cleanly,
# and enforces nothing:
#
#     resource "aws_vpclattice_service" "rates" { name = "rates" }
#     resource "aws_vpclattice_auth_policy" "rates" { ...restrictive... }
#
# The policy attaches, shows up in the console, and is skipped at request time
# because the default auth type is NONE. The only tell is the policy's `state`
# field reading Inactive. Test 5 does exactly this on purpose.
resource "aws_vpclattice_service_network" "this" {
  name      = "${var.name}-net"
  auth_type = "AWS_IAM"
  tags      = var.tags
}

resource "aws_vpclattice_service" "rates" {
  name      = "${var.name}-rates"
  auth_type = var.service_auth_type
  tags      = var.tags
}

resource "aws_vpclattice_service_network_service_association" "rates" {
  service_identifier         = aws_vpclattice_service.rates.id
  service_network_identifier = aws_vpclattice_service_network.this.id
  tags                       = var.tags
}

# Free, and the reason there is no VPC peering anywhere in this build.
resource "aws_vpclattice_service_network_vpc_association" "consumer" {
  vpc_identifier             = aws_vpc.consumer.id
  service_network_identifier = aws_vpclattice_service_network.this.id
  security_group_ids         = [aws_security_group.client.id]
  tags                       = var.tags
}

resource "aws_vpclattice_target_group" "backend" {
  name = "${var.name}-backend"
  type = "LAMBDA"
  tags = var.tags
}

resource "aws_vpclattice_target_group_attachment" "backend" {
  target_group_identifier = aws_vpclattice_target_group.backend.id

  target {
    id = aws_lambda_function.backend.arn
  }
}

resource "aws_vpclattice_listener" "http" {
  name               = "http"
  protocol           = "HTTP"
  port               = 80
  service_identifier = aws_vpclattice_service.rates.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.backend.id
      }
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Layer one: the service network policy
# ---------------------------------------------------------------------------
#
# Scoped to this organisation and this VPC. It says nothing about WHICH caller,
# only where a caller may come from -- the coarse boundary.
resource "aws_vpclattice_auth_policy" "network" {
  resource_identifier = aws_vpclattice_service_network.this.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "SameOrgSameVpcOnly"
      Effect    = "Allow"
      Principal = "*"
      Action    = "vpc-lattice-svcs:Invoke"
      Resource  = "*"
      Condition = {
        StringNotEquals = { "aws:PrincipalType" = "Anonymous" }
        StringEquals    = { "vpc-lattice-svcs:SourceVpc" = aws_vpc.consumer.id }
      }
    }]
  })
}

# ---------------------------------------------------------------------------
# Layer two: the service policy
# ---------------------------------------------------------------------------
#
# The fine boundary, and the one a security group cannot express: a named role,
# and only the GET method. Both callers sit in the same subnet behind the same
# security group; this is the only thing that tells them apart.
# IAM is eventually consistent, and an auth policy naming a brand-new role as a
# Principal is rejected outright rather than retried:
#
#   ValidationException: Policy principal is not found.
#
# The role exists in Terraform state and not yet everywhere IAM needs it. A
# short wait is the documented remedy; there is no "wait for propagation" API.
resource "time_sleep" "iam_propagation" {
  depends_on      = [aws_iam_role.client, aws_iam_role_policy.client]
  create_duration = "20s"
}

resource "aws_vpclattice_auth_policy" "rates" {
  depends_on          = [time_sleep.iam_propagation]
  resource_identifier = aws_vpclattice_service.rates.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "OnlyTheOrdersClientAndOnlyGet"
      Effect = "Allow"
      Principal = {
        AWS = [aws_iam_role.client.arn]
      }
      Action   = "vpc-lattice-svcs:Invoke"
      Resource = "${aws_vpclattice_service.rates.arn}/*"
      Condition = {
        StringEquals = { "vpc-lattice-svcs:RequestMethod" = "GET" }
      }
    }]
  })
}
