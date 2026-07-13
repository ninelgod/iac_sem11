terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  backend "s3" {
    bucket         = "gestorpagosg2-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "gestorpagosg2-terraform-locks"
    encrypt        = true
  }
}

# Provider principal: todo lo que vive en us-east-2 (la región de despliegue del proyecto).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Required for CloudFront WAF (must be us-east-1)
# Provider alias: AWS exige que el WAF de CloudFront (scope CLOUDFRONT) se cree específicamente en us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
