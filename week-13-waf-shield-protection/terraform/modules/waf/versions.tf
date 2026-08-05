terraform {
  required_version = ">= 1.10"

  required_providers {
    # Declared explicitly because the caller passes an aliased provider into
    # this module (us-east-1 for the CLOUDFRONT-scope instantiation). Without
    # this block Terraform infers the requirement and warns on every init.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
