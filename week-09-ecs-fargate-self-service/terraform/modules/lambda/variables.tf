variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "webhook_receiver_role_arn" {
  type = string
}

variable "fargate_provisioner_role_arn" {
  type = string
}

variable "status_notifier_role_arn" {
  type = string
}

variable "state_machine_arn" {
  type = string
}

variable "hmac_secret_param" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "cluster_arn" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "ecs_tasks_sg_id" {
  type = string
}

variable "ecs_task_execution_role_arn" {
  type = string
}

variable "alb_listener_arn" {
  type = string
}

variable "alb_dns_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "snow_instance_param" {
  type = string
}

variable "snow_user_param" {
  type = string
}

variable "snow_password_param" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
