###############################################################################
# Module: IAM
# EC2 instance role — SSM access (no SSH keys needed), S3 read, CW logs
###############################################################################

# ── EC2 Instance Role ────────────────────────────────────────────────────────
resource "aws_iam_role" "ec2_instance" {
  name               = "${var.project}-${var.environment}-ec2-role"
  description        = "Role assumed by EC2 instances - least-privilege"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-ec2-role"
  })
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ── Attach AWS Managed Policies ──────────────────────────────────────────────
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ── Custom Inline Policy — S3 read for app artifacts ────────────────────────
resource "aws_iam_role_policy" "ec2_custom" {
  name = "${var.project}-${var.environment}-ec2-custom-policy"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ArtifactRead"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.artifact_bucket_name}",
          "arn:aws:s3:::${var.artifact_bucket_name}/*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/app/${var.project}-${var.environment}*"
      },
      {
        Sid    = "SSMParameterRead"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:*:*:parameter/${var.project}/${var.environment}/*"
      }
    ]
  })
}

# ── Instance Profile ─────────────────────────────────────────────────────────
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2_instance.name

  tags = var.tags
}

# ── GitHub Actions OIDC Role (for CI/CD — no long-lived keys) ───────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint (stable — update if GitHub rotates)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions" {
  name        = "${var.project}-${var.environment}-github-actions-role"
  description = "Role assumed by GitHub Actions via OIDC - no static keys"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-github-actions-role"
  })
}

resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "terraform-deploy-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.tf_state_bucket}",
          "arn:aws:s3:::${var.tf_state_bucket}/*"
        ]
      },
      {
        Sid    = "DynamoDBLock"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:*:*:table/${var.tf_lock_table}"
      },
      {
        Sid    = "InfrastructureProvisioning"
        Effect = "Allow"
        Action = [
          "ec2:*", "elasticloadbalancing:*", "autoscaling:*",
          "iam:PassRole", "iam:GetRole", "iam:CreateRole", "iam:DeleteRole",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy",
          "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:GetInstanceProfile", "iam:TagInstanceProfile", "iam:UntagInstanceProfile",
          "iam:TagRole", "iam:UntagRole",
          "iam:CreateOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider", "iam:TagOpenIDConnectProvider",
          "logs:*", "cloudwatch:*", "sns:*",
          "lambda:*", "states:*", "apigateway:*",
          "ssm:*"
        ]
        Resource = "*"
      }
    ]
  })
}
