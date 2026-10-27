terraform {
  required_version = "~> 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "navil-tfstate-470639361212"
    key          = "terraform.tfstate"
    region       = "us-east-1"
    profile      = "yan428"
    use_lockfile = true
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = var.aws_profile

  allowed_account_ids = ["470639361212"]
}
