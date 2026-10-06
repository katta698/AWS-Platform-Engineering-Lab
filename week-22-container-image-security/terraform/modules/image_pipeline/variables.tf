variable "name" {
  description = "Name prefix for every resource in this module."
  type        = string
}

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default     = {}
}

variable "filter_prefix" {
  description = <<-DESC
    Repository name wildcard that decides which repositories get signed and
    scanned. Deliberately narrow: a registry-wide rule would also sign and
    scan unrelated repositories in this account, including the CDK asset
    repository, and Inspector bills per image.
  DESC
  type        = string
}

variable "signature_validity_months" {
  description = "How long a generated signature stays valid."
  type        = number
  default     = 12
}

variable "untagged_expiry_days" {
  description = <<-DESC
    Untagged images are deleted after this many days. Under continuous
    scanning every retained image is re-scanned each time the CVE database
    updates, so images nobody can deploy are a recurring charge, not a
    one-off.
  DESC
  type        = number
  default     = 1
}

variable "blocking_severities" {
  description = "Finding severities that cause an image to be quarantined."
  type        = list(string)
  default     = ["CRITICAL", "HIGH"]
}

variable "lambda_source_dir" {
  description = "Path to the gate Lambda source directory."
  type        = string
}

variable "alert_email" {
  description = <<-DESC
    Where quarantine notices go. Left empty by default so the address is
    never committed; set it as a workspace variable.
  DESC
  type        = string
  default     = ""
}
