terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Optional: uncomment to store state remotely in S3 (recommended for real projects)
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "solomon-app/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Fetch current AWS account ID and region dynamically
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
