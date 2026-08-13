terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project      = "EngineeringIncidentAgent"
      Environment  = "POC"
      Owner        = "Hasitha"
      ExpiresAfter = "2026-08-20"
      ManagedBy    = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
