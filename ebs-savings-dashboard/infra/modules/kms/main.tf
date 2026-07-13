data "aws_iam_policy_document" "kms_base" {
  # Root account always has full access (prevents key from being unmanageable)
  statement {
    sid       = "RootFullAccess"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "cur" {
  description             = "${var.prefix} — CUR S3 bucket"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_base.json
}
resource "aws_kms_alias" "cur" {
  name          = "alias/${var.prefix}-cur"
  target_key_id = aws_kms_key.cur.key_id
}

resource "aws_kms_key" "athena" {
  description             = "${var.prefix} — Athena results"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_base.json
}
resource "aws_kms_alias" "athena" {
  name          = "alias/${var.prefix}-athena"
  target_key_id = aws_kms_key.athena.key_id
}

resource "aws_kms_key" "lambda" {
  description             = "${var.prefix} — Lambda env vars"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_base.json
}
resource "aws_kms_alias" "lambda" {
  name          = "alias/${var.prefix}-lambda"
  target_key_id = aws_kms_key.lambda.key_id
}

resource "aws_kms_key" "frontend_logs" {
  description             = "${var.prefix} — CloudFront access logs"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_base.json
}
resource "aws_kms_alias" "frontend_logs" {
  name          = "alias/${var.prefix}-frontend-logs"
  target_key_id = aws_kms_key.frontend_logs.key_id
}
