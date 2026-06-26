###############################################################################
# IAM Identity Center module
# Creates one permission set + one Identity Store group per entry in
# var.groups, assigns each permission set to its group across every account
# in var.target_account_ids, and provisions test users into their groups.
#
# Prerequisite (manual, no Terraform resource exists for this): IAM Identity
# Center must already be enabled in the management account console.
###############################################################################

resource "aws_ssoadmin_permission_set" "this" {
  for_each = var.groups

  name             = each.key
  description      = each.value.description
  instance_arn     = var.instance_arn
  session_duration = each.value.session_duration
  tags             = var.tags
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = var.groups

  instance_arn       = var.instance_arn
  managed_policy_arn = each.value.managed_policy_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
}

resource "aws_identitystore_group" "this" {
  for_each = var.groups

  identity_store_id = var.identity_store_id
  display_name      = each.key
  description       = each.value.description
}

resource "aws_identitystore_user" "this" {
  for_each = var.users

  identity_store_id = var.identity_store_id
  display_name      = "${each.value.given_name} ${each.value.family_name}"
  user_name         = each.key

  name {
    given_name  = each.value.given_name
    family_name = each.value.family_name
  }

  emails {
    value   = each.value.email
    primary = true
  }
}

resource "aws_identitystore_group_membership" "this" {
  for_each = var.users

  identity_store_id = var.identity_store_id
  group_id          = aws_identitystore_group.this[each.value.group].group_id
  member_id         = aws_identitystore_user.this[each.key].user_id
}

# Cross product of (group x target account) — AWS provisions the actual IAM
# role (AWSReservedSSO_<permission-set-name>_*) into each target account
# automatically once this assignment exists.
locals {
  assignments = {
    for pair in setproduct(keys(var.groups), var.target_account_ids) :
    "${pair[0]}-${pair[1]}" => {
      group_name = pair[0]
      account_id = pair[1]
    }
  }
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.assignments

  instance_arn       = var.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.group_name].arn

  principal_id   = aws_identitystore_group.this[each.value.group_name].group_id
  principal_type = "GROUP"

  target_id   = each.value.account_id
  target_type = "AWS_ACCOUNT"
}
