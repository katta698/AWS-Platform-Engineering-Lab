resource "aws_organizations_organizational_unit" "ou" {
  for_each  = toset(var.ou_names)
  name      = each.value
  parent_id = var.parent_id
  tags      = var.tags
}
