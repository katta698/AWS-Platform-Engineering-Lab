variable "project_name"               { type = string }
variable "environment"                { type = string }
variable "glue_role_arn"              { type = string }
variable "raw_bucket_name"            { type = string }
variable "curated_bucket_name"        { type = string }
variable "athena_results_bucket_name" { type = string }
variable "tags"                       { type = map(string) default = {} }
