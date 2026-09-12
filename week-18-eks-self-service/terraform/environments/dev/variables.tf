variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "week18-platform"
}

variable "kubernetes_version" {
  description = "Stay in standard support. Extended support is $0.60/hr against $0.10/hr."
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "The single managed node. It exists so the Pod Identity agent has a home."
  type        = string
  default     = "t3.small"
}

variable "ec2_tenant" {
  description = "Tenant whose pods run on EC2 and use Pod Identity."
  type        = string
  default     = "tenant-a"
}

variable "fargate_tenant" {
  description = "Tenant whose pods run on Fargate and therefore must use IRSA."
  type        = string
  default     = "tenant-b"
}

variable "log_retention_days" {
  type    = number
  default = 1
}

variable "cluster_admin_role_arns" {
  description = "Roles granted kubectl admin on the cluster, beyond the creator."
  type        = list(string)
  default = [
    "arn:aws:iam::684346483786:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_1db8f9c8c3680bbd"
  ]
}
