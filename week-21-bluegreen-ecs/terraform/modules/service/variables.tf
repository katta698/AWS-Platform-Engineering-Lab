variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "image" {
  type        = string
  description = "ECR Public, so no credentials and no Docker Hub rate limit."
  default     = "public.ecr.aws/docker/library/busybox:latest"
}

variable "container_name" {
  type    = string
  default = "app"
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "app_version" {
  type        = string
  description = "Served as the response body. Changing it is what makes a new deployment."
  default     = "v1"
}

variable "serve_root" {
  type        = bool
  description = "false writes no index.html, so / returns 404 and the alarm breaches. This is the deliberately bad version."
  default     = true
}

variable "task_cpu" {
  type    = string
  default = "256"
}

variable "task_memory" {
  type    = string
  default = "512"
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "bake_time_in_minutes" {
  type        = number
  description = "How long the old task set stays alive after cutover. Rollback inside this window is a pointer flip."
  default     = 5
}

variable "log_retention_days" {
  type    = number
  default = 1
}

variable "tags" {
  type    = map(string)
  default = {}
}
