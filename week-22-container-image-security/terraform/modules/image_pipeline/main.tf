# Week 22 -- Container image security pipeline
#
# The goal in one sentence: no image can be deployed unless this pipeline
# signed it and a scanner cleared it, and both facts are provable afterwards.
#
# Three controls, each doing a different job:
#   1. Managed signing  -- provenance. WHO pushed this image.
#   2. Enhanced scanning -- safety. WHAT KNOWN FLAWS does it contain.
#   3. The gate          -- enforcement. Neither of the above blocks anything
#                           on its own; signing writes a signature and
#                           scanning writes a finding. Something has to act.

# Resolved at run time, never written into the repo. The account ID is not a
# secret, but it is an identifier and there is no reason to commit it.
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------------------
# The registry
# ---------------------------------------------------------------------------

# IMMUTABLE is a security control, not a convenience setting. With mutable
# tags, an image approved as v1.2.3 can be quietly replaced by a different
# image under the same tag after it passed review -- the scan result and the
# signature then describe something that is no longer there.
resource "aws_ecr_repository" "app" {
  name                 = "${var.filter_prefix}-app"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # lab only: lets terraform destroy remove images too

  image_scanning_configuration {
    scan_on_push = true
  }

  # AES256 is ECR's own key. A customer-managed KMS key would add a second
  # lock independent of IAM and an audit trail of every decrypt, for
  # ~$1/month. See README "What production does differently".
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

# A second repository deliberately OUTSIDE the filter, to prove the filter is
# real. If this one also ends up signed and scanned, the filter is decorative
# and the cost controls built on it do not hold.
resource "aws_ecr_repository" "outside_filter" {
  name         = "outside-filter-${var.name}"
  force_delete = true

  tags = merge(var.tags, { Purpose = "control-group" })
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after ${var.untagged_expiry_days} day(s) -- they cannot be deployed but are still re-scanned and billed."
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = var.untagged_expiry_days
      }
      action = { type = "expire" }
    }]
  })
}

# ---------------------------------------------------------------------------
# Control 1: provenance -- AWS Signer + ECR managed signing
# ---------------------------------------------------------------------------

# Notation-OCI-SHA384-ECDSA is the only OCI-targeted platform Signer offers
# (verified with `aws signer list-signing-platforms`; its category is
# "External", the others are AWS-specific).
#
# There is no KMS key here and no place to put one: for container signing,
# Signer generates and holds the key material itself. You control who may ask
# it to sign -- the signer:SignPayload permission below -- but never touch the
# key. That is a trust decision, not an absence of one.
#
# name_prefix, not name: the API accepts only [a-zA-Z0-9_] in profile names,
# so hyphens are rejected.
resource "aws_signer_signing_profile" "images" {
  name_prefix = "wk22_"
  platform_id = "Notation-OCI-SHA384-ECDSA"

  signature_validity_period {
    value = var.signature_validity_months
    type  = "MONTHS"
  }

  tags = var.tags
}

# Registry-scoped singleton: one signing configuration per account per region.
# There is no aws_ecr_signing_configuration in the AWS provider -- the pull
# request adding it (#47527) was still open against 6.67.0 -- so this goes
# through Cloud Control, which has AWS::ECR::SigningConfiguration.
resource "awscc_ecr_signing_configuration" "registry" {
  rules = [{
    signing_profile_arn = aws_signer_signing_profile.images.arn
    repository_filters = [{
      filter      = "${var.filter_prefix}-*"
      filter_type = "WILDCARD_MATCH"
    }]
  }]
}

# ---------------------------------------------------------------------------
# Control 2: safety -- Amazon Inspector enhanced scanning
# ---------------------------------------------------------------------------

# Inspector is a separate service with its own bill, switched on per resource
# type. ECR only, deliberately: enabling EC2 or Lambda scanning here would
# scan everything else in the account.
resource "aws_inspector2_enabler" "ecr" {
  account_ids    = [local.account_id]
  resource_types = ["ECR"]
}

# Enhanced scanning replaces ECR's own scanner with Inspector. SCAN_ON_PUSH
# rather than CONTINUOUS_SCAN: continuous re-scans every retained image each
# time the CVE database updates, which is the right production choice and the
# wrong one for a lab that exists for a few hours.
resource "aws_ecr_registry_scanning_configuration" "registry" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "SCAN_ON_PUSH"
    repository_filter {
      filter      = "${var.filter_prefix}-*"
      filter_type = "WILDCARD"
    }
  }

  depends_on = [aws_inspector2_enabler.ecr]
}

# ---------------------------------------------------------------------------
# Control 3: enforcement -- the gate
# ---------------------------------------------------------------------------
#
# Signing and scanning are both passive. Signer writes a signature; Inspector
# writes findings. Neither stops a deployment. The gate is the part that acts,
# and it is the only part of this week that is not a managed feature.

resource "aws_sns_topic" "quarantine" {
  name = "${var.name}-quarantine"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.quarantine.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# excludes matters: a stray __pycache__ in the source directory changes
# output_base64sha256, which changes source_code_hash, which redeploys the
# function for no reason -- and differs between machines.
data "archive_file" "gate" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/builds/image_gate.zip"

  excludes = ["__pycache__", "*.pyc", "*.pyo"]
}

resource "aws_iam_role" "gate" {
  name = "${var.name}-gate"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# Scoped to the two repositories this week creates and the one topic it
# publishes to. No Resource = "*" except where the API genuinely has no
# resource to scope to.
resource "aws_iam_role_policy" "gate" {
  name = "${var.name}-gate"
  role = aws_iam_role.gate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadAndRetagImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:DescribeImageSigningStatus",
          "ecr:PutImage",
          "ecr:BatchDeleteImage",
        ]
        Resource = [
          aws_ecr_repository.app.arn,
          aws_ecr_repository.outside_filter.arn,
        ]
      },
      {
        Sid      = "ReadFindings"
        Effect   = "Allow"
        Action   = ["inspector2:ListFindings"]
        Resource = "*" # ListFindings is not resource-scopable
      },
      {
        Sid      = "Notify"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.quarantine.arn
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.gate.arn}:*"
      },
    ]
  })
}

# Created explicitly rather than letting Lambda create it implicitly, so it
# carries a retention period and is removed by destroy. An implicitly created
# log group retains forever and survives the teardown.
resource "aws_cloudwatch_log_group" "gate" {
  name              = "/aws/lambda/${var.name}-gate"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_lambda_function" "gate" {
  function_name = "${var.name}-gate"
  role          = aws_iam_role.gate.arn
  handler       = "handler.handler"
  runtime       = "python3.13"
  timeout       = 30

  filename         = data.archive_file.gate.output_path
  source_code_hash = data.archive_file.gate.output_base64sha256

  environment {
    variables = {
      BLOCKING_SEVERITIES = join(",", var.blocking_severities)
      SNS_TOPIC_ARN       = aws_sns_topic.quarantine.arn
      QUARANTINE_PREFIX   = "quarantined"
    }
  }

  depends_on = [aws_cloudwatch_log_group.gate]
  tags       = var.tags
}

# Inspector emits "Inspector2 Scan" with scan-status INITIAL_SCAN_COMPLETE
# once it finishes an image. The event carries finding-severity-counts,
# image-digest and image-tags -- everything the gate needs, so it does not
# have to call back for the verdict in the common case.
resource "aws_cloudwatch_event_rule" "scan_complete" {
  name        = "${var.name}-scan-complete"
  description = "Fire the image gate when Inspector finishes scanning a pushed image."

  event_pattern = jsonencode({
    source        = ["aws.inspector2"]
    "detail-type" = ["Inspector2 Scan"]
    detail = {
      "scan-status" = ["INITIAL_SCAN_COMPLETE"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "gate" {
  rule      = aws_cloudwatch_event_rule.scan_complete.name
  target_id = "image-gate"
  arn       = aws_lambda_function.gate.arn
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.gate.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scan_complete.arn
}

# A gate that stops working silently is worse than no gate: pushes keep
# succeeding and nothing is enforced. This alarms on the gate erroring at all.
resource "aws_cloudwatch_metric_alarm" "gate_errors" {
  alarm_name          = "${var.name}-gate-errors"
  alarm_description   = "The image gate failed to run. Images may be unenforced."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.gate.function_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.quarantine.arn]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# The builder
# ---------------------------------------------------------------------------
#
# Images are built here rather than on a laptop, and that is not a convenience.
# ECR managed signing signs with the identity of whoever pushed -- the console
# says so in as many words: "ECR will sign the image using the IAM credentials
# of the entity that pushed the image." Push from a laptop and the signature
# attests to a laptop, which is the thing image signing exists to replace. Push
# from a build role and "signed by my pipeline" is literally true.

resource "aws_cloudwatch_log_group" "build" {
  name              = "/aws/codebuild/${var.name}-build"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_iam_role" "build" {
  name = "${var.name}-build"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "build" {
  name = "${var.name}-build"
  role = aws_iam_role.build.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*" # GetAuthorizationToken has no resource to scope to
      },
      {
        Sid    = "PushImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
        ]
        Resource = [
          aws_ecr_repository.app.arn,
          aws_ecr_repository.outside_filter.arn,
        ]
      },
      {
        # Without this the push still succeeds and the image is simply NOT
        # signed -- managed signing fails quietly rather than rejecting the
        # push. A build role that can push but not sign produces unsigned
        # images and no error.
        Sid      = "SignImages"
        Effect   = "Allow"
        Action   = ["signer:SignPayload"]
        Resource = aws_signer_signing_profile.images.arn
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.build.arn}:*"
      },
    ]
  })
}

locals {
  # Passed as environment variables because the project has no source
  # repository. The files on disk stay the single definition of each image.
  dockerfiles = {
    CLEAN_B64    = base64encode(file("${var.docker_dir}/clean/Dockerfile"))
    VULN_OS_B64  = base64encode(file("${var.docker_dir}/vuln-os/Dockerfile"))
    VULN_LIB_B64 = base64encode(file("${var.docker_dir}/vuln-lib/Dockerfile"))
    REQS_B64     = base64encode(file("${var.docker_dir}/vuln-lib/requirements.txt"))
  }
}

resource "aws_codebuild_project" "build" {
  name         = "${var.name}-build"
  description  = "Builds and pushes the three Week 22 test images, signing as the build role."
  service_role = aws_iam_role.build.arn

  artifacts { type = "NO_ARTIFACTS" }

  environment {
    compute_type = var.build_compute_type
    image        = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"
    # Required to run a Docker daemon inside the build.
    privileged_mode = true

    dynamic "environment_variable" {
      for_each = local.dockerfiles
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }

    environment_variable {
      name  = "REPO_URL"
      value = aws_ecr_repository.app.repository_url
    }

    environment_variable {
      name  = "OUTSIDE_REPO_URL"
      value = aws_ecr_repository.outside_filter.repository_url
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = <<-SPEC
      version: 0.2
      phases:
        pre_build:
          commands:
            - REGISTRY=$${REPO_URL%%/*}
            - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REGISTRY
            - STAMP=$(date -u +%Y%m%d-%H%M%S)
            - echo "tag suffix $STAMP"
            - mkdir -p b/clean b/vuln-os b/vuln-lib
            - echo "$CLEAN_B64"    | base64 -d > b/clean/Dockerfile
            - echo "$VULN_OS_B64"  | base64 -d > b/vuln-os/Dockerfile
            - echo "$VULN_LIB_B64" | base64 -d > b/vuln-lib/Dockerfile
            - echo "$REQS_B64"     | base64 -d > b/vuln-lib/requirements.txt
        build:
          commands:
            - |
              for img in clean vuln-os vuln-lib; do
                echo "=== building $img ==="
                docker build --platform linux/amd64 -t "$REPO_URL:$img-$STAMP" "b/$img"
                echo "=== pushing $img at $(date -u +%H:%M:%S)Z ==="
                docker push "$REPO_URL:$img-$STAMP"
              done
            # The control group: same image, a repository the filters do not
            # match. If this one comes back signed or scanned, the filters are
            # decoration and every cost control resting on them is void.
            - docker tag "$REPO_URL:clean-$STAMP" "$OUTSIDE_REPO_URL:clean-$STAMP"
            - docker push "$OUTSIDE_REPO_URL:clean-$STAMP"
        post_build:
          commands:
            - echo "STAMP=$STAMP"
    SPEC
  }

  tags = var.tags
}
