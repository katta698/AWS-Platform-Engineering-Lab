###############################################################################
# Associations — what the agent can reach.
#
# The agent space is the boundary; associations are what is inside it. Nothing
# the agent investigates and nowhere it reports is implicit -- each is a
# resource here, which is the property that makes the blast radius reviewable
# in a pull request rather than discoverable in a console.
###############################################################################

###############################################################################
# The AWS account it monitors
###############################################################################

# service_id = "aws" is a RESERVED LITERAL and one of the least discoverable
# things in this build.
#
# `service_id` is required on every association, and the obvious reading is that
# it points at an awscc_devopsagent_service resource. It does not, for AWS. The
# ServiceType enum has no "aws" member -- it lists only third-party integrations
# (dynatrace, gitlab, servicenow, pagerduty, and the MCP servers) -- and
# list-services on a fresh account returns empty. So there is nothing to
# reference and no way to create one.
#
# The value is the literal string "aws". That appears in neither the
# CloudFormation schema, the Terraform provider schema, nor the CLI skeleton;
# it was found in AWS's own published Terraform sample.
resource "awscc_devopsagent_association" "aws_account" {
  agent_space_id = module.agent_space.agent_space_id
  service_id     = "aws"

  configuration = {
    aws = {
      account_id         = data.aws_caller_identity.current.account_id
      account_type       = "monitor"
      assumable_role_arn = aws_iam_role.agentspace.arn

      # Empty means the whole account, which is what this lab wants: the agent
      # has to FIND the broken workload rather than be handed it. Pointing it
      # straight at the function would test recall, not diagnosis.
      #
      # In production this is the tightening point. The schema accepts a list of
      # resources (by ARN and type) and a list of tags, so an agent can be scoped
      # to one stack or one tag rather than everything -- and that scoping, not
      # the IAM policy, is the practical blast-radius control.
      resources = []
    }
  }

  depends_on = [module.agent_space]
}

###############################################################################
# ServiceNow — where findings land
#
# An investigation nobody reads is not an investigation. Weeks 1-3 turned a
# ServiceNow ticket into infrastructure; this closes the loop by turning an
# incident back into a ticket, written by the agent.
###############################################################################

resource "awscc_devopsagent_service" "servicenow" {
  service_type = "servicenow"

  service_details = {
    service_now = {
      instance_url = var.servicenow_instance_url

      authorization_config = {
        o_auth_client_credentials = {
          client_id     = var.servicenow_oauth_client_id
          client_secret = var.servicenow_oauth_client_secret
          client_name   = "aws-devops-agent"
        }
      }
    }
  }

  tags = [for k, v in local.tags : {
    key   = k
    value = v
  }]
}

resource "awscc_devopsagent_association" "servicenow" {
  agent_space_id = module.agent_space.agent_space_id
  service_id     = awscc_devopsagent_service.servicenow.service_id

  configuration = {
    service_now = {
      # THE SHORT NAME, NOT THE URL.
      #
      # Registration above takes the full https://<instance>.service-now.com;
      # the association takes the bare instance name. Passing the URL here fails
      # with:
      #
      #   400 GeneralServiceException: instanceId '<url>' does not match the
      #   registered ServiceNow instance
      #
      # which reads like the two do not match -- when in fact they do, and only
      # the format is wrong. Documented by AWS, and worth carrying as a separate
      # variable so the mistake cannot be made by deriving one from the other.
      instance_id = var.servicenow_instance_id

      # Lets ServiceNow push updates back, so a ticket closed by a human is
      # reflected in the agent's view rather than the flow being one-way.
      enable_webhook_updates = true
    }
  }

  depends_on = [awscc_devopsagent_service.servicenow]
}
