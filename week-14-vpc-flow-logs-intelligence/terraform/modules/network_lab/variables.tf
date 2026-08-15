variable "name_prefix" {
  description = "Prefix applied to every resource name in this module."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the observed VPC."
  type        = string
  default     = "10.14.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet. Hosts the NAT gateway and the exposed instance."
  type        = string
  default     = "10.14.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for the private subnet. Hosts the traffic generator."
  type        = string
  default     = "10.14.2.0/24"
}

variable "instance_type" {
  description = "Instance type for both lab instances. t4g.nano is the cheapest Graviton option and is ample for generating flows."
  type        = string
  default     = "t4g.nano"
}

variable "enable_exposed_instance" {
  description = <<-EOT
    Whether to create the internet-reachable instance in the public subnet.

    This instance exists to harvest genuine internet background scanning into REJECT
    flow log records, so the port-scan detection runs against real data instead of a
    synthetic fixture. Its security group denies all inbound traffic -- the rejects are
    produced BY those denials, which is the entire point.

    Set to false to build the analytics layer without any internet-reachable surface.
    The port-scan query still works; it just has far less to find.
  EOT
  type        = bool
  default     = true
}

variable "generator_team_tag" {
  description = <<-EOT
    Value of the `Team` tag on the traffic generator instance.

    This is not decoration. Flow log v11 can embed instance tag VALUES directly into
    each flow record, which is what makes per-team NAT cost attribution possible
    without joining against a resource inventory that is already stale. This tag is
    the thing that ends up in the `instance_tag` column in Athena.
  EOT
  type        = string
  default     = "platform-engineering"
}

variable "exposed_team_tag" {
  description = "Value of the `Team` tag on the exposed instance. Distinct from the generator so the two are separable in query results."
  type        = string
  default     = "edge-demo"
}

variable "flow_logs_bucket_arn" {
  description = "ARN of the flow logs bucket. The generator reads from it through the S3 gateway endpoint, producing the free-path half of the traffic-path contrast."
  type        = string
}
