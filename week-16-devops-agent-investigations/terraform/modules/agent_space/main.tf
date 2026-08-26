###############################################################################
# The agent space: a boundary, not a feature toggle.
#
# An agent space defines what an autonomous agent may see and who may talk to
# it. Everything the agent can reach flows from this resource and the
# associations attached to it, which makes it the blast radius rather than a
# container.
#
# WHY awscc AND NOT aws
#
# The hashicorp/aws provider has no aws_devopsagent_* resources. The service
# went GA on 2026-03-31; the provider issue asking for them (#46894) was still
# open when this was written, and a scan of the installed provider binary
# (v6.60.0) finds the string "aws_devopsagent_" as a bare prefix with no
# concrete resource names behind it.
#
# awscc generates its resources from the CloudFormation registry instead, so a
# service is available there as soon as its CFN types are LIVE. Verified on
# 2026-08-26: AWS::DevOpsAgent::AgentSpace, ::Association and ::Service all
# report FULLY_MUTABLE / LIVE, and awscc 1.98.0 exposes six devopsagent
# resources.
#
# The trade is real and worth stating: awscc resources are machine-generated,
# so they carry CloudFormation's naming and shapes rather than the hand-written
# ergonomics of the aws provider, and their documentation is thin. That is the
# price of using a service that is newer than its provider.
#
# NO SPEND CEILING EXISTS HERE
#
# Every other week in this series leaned on a service-enforced limit -- Weeks 14
# and 15 both capped Athena at 10 GB per query at the workgroup level, so a
# mistake was bounded by configuration. The AgentSpace schema has no equivalent:
# Name, Description, KmsKeyArn, Locale, OperatorApp, Tags, and nothing else. No
# budget, no maximum duration, no task cap.
#
# Billing is $0.0083 per agent-second of ACTIVE work. Idle costs nothing
# (verified: a space created and left alone leaves every usage meter at 0.0), so
# the exposure is not the space existing -- it is a task running long. The only
# lever the service offers is a concurrency quota, which bounds how MANY tasks
# run and never how LONG one runs.
#
# So the control here is observation: scripts/measure_usage.sh reads the meter
# before and after anything the agent does.
###############################################################################

resource "awscc_devopsagent_agent_space" "this" {
  name        = var.name
  description = var.description

  # Customer-managed KMS key. create-only -- changing it forces replacement,
  # which is why it is wired through a variable rather than assumed.
  kms_key_arn = var.kms_key_arn

  tags = [for k, v in var.tags : {
    key   = k
    value = v
  }]
}
