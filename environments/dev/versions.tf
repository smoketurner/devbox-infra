terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }

  backend "s3" {
    bucket       = "terraform-state-952961969614-us-east-1-an"
    key          = "devbox-infra/dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
