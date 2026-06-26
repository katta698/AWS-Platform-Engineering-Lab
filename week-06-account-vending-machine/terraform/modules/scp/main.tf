resource "aws_organizations_policy" "sandbox_guardrail" {
  name        = "sandbox-guardrail-scp"
  description = "Sandbox OU guardrails: deny large/expensive EC2 instance types and restrict to allowed regions"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyLargeInstanceTypes"
        Effect   = "Deny"
        Action   = ["ec2:RunInstances"]
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringLike = {
            "ec2:InstanceType" = var.denied_instance_types
          }
        }
      },
      {
        Sid    = "DenyOutsideAllowedRegions"
        Effect = "Deny"
        NotAction = [
          "iam:*",
          "organizations:*",
          "route53:*",
          "budgets:*",
          "support:*",
          "sts:*",
          "cloudfront:*",
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = var.allowed_regions
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "sandbox_guardrail" {
  policy_id = aws_organizations_policy.sandbox_guardrail.id
  target_id = var.sandbox_ou_id
}
