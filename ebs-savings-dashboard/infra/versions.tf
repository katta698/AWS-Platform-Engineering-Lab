terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Default provider — management account
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ebs-savings-dashboard"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

# CUR reports must be created in us-east-1 regardless of primary region
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "ebs-savings-dashboard"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

# CloudFront WAF must be created in us-east-1
provider "aws" {
  alias  = "waf"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "ebs-savings-dashboard"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}
