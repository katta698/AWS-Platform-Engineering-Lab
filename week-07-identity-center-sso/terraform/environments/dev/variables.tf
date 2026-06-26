variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project_name" {
  type    = string
  default = "jay-identity-center-sso"
}

# ── Organizations scope (reuses Week 6's vended OUs) ───────────────────────────
variable "parent_ou_name" {
  description = "Root-level OU that Week 6's vending OUs nest under"
  type        = string
  default     = "Workloads-OU"
}

variable "target_ou_names" {
  description = "Vending OUs (created in Week 6) whose member accounts get SSO assignments"
  type        = list(string)
  default     = ["Sandbox", "Production"]
}

# ── Groups + permission sets ───────────────────────────────────────────────────
variable "groups" {
  description = "Group name => permission set definition"
  type = map(object({
    description        = string
    managed_policy_arn  = string
    session_duration    = string
  }))
  default = {
    ReadOnlyAuditors = {
      description        = "Read-only access for auditors across all vended accounts"
      managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
      session_duration   = "PT1H"
    }
    Engineers = {
      description        = "Day-to-day operator access, scoped below full admin"
      managed_policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
      session_duration   = "PT4H"
    }
    BreakGlassAdmins = {
      description        = "Emergency full-admin access, short session"
      managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
      session_duration   = "PT1H"
    }
  }
}

# ── Test users ──────────────────────────────────────────────────────────────────
variable "users" {
  description = "Username => user attributes + group membership"
  type = map(object({
    given_name  = string
    family_name = string
    email       = string
    group       = string
  }))
  default = {}
}
