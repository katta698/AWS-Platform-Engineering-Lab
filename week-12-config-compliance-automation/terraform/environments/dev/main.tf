###############################################################################
# Week 12: AWS Config Compliance Automation
#
# Blogged and torn down 2026-08-02. The week-specific pieces (conformance
# pack, reporter Lambda/SNS/DLQ, SSM automation role) are destroyed -- see
# the blog post for the full build. module.config_recorder stays deployed
# here deliberately: it's the account's only Config recorder (this Lab's
# own, provisioned after an unrelated project's cleanup deleted the previous
# one on 2026-07-29), and Week 11's Security Hub FSBP controls depend on it
# existing. Treat this workspace from here on as "owns the shared recorder,"
# not "Week 12's own stack" -- future weeks needing Config data depend on
# this recorder, not on re-provisioning their own.
###############################################################################

terraform {
  required_version = ">= 1.10"
  required_providers {
    # Same 6.x line as Week 11 -- aws_config_conformance_pack and
    # aws_config_remediation_configuration are both stable there.
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }

  cloud {
    organization = "Katta"
    workspaces {
      name = "week-12-dev"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project   = "AWS-Platform-Engineering-Lab"
    Week      = "12"
    Component = "config-compliance-automation"
    ManagedBy = "terraform"
  }
}

# This Lab's shared Config recorder -- see the header note above. Kept
# deployed after Week 12's own teardown; future weeks needing Config data
# depend on this, not a new recorder of their own.
module "config_recorder" {
  source      = "../../modules/config_recorder"
  name_prefix = var.name_prefix
  tags        = local.common_tags
}
