module "vpc" {
  source = "../../modules/vpc"

  name = "devbox-${local.environment}"
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets

  tags = local.tags
}

module "egress" {
  source = "../../modules/egress"

  name = "devbox-${local.environment}-egress"
  cidr = local.egress_vpc_cidr

  azs             = local.azs
  private_subnets = local.egress_private_subnets
  public_subnets  = local.egress_public_subnets

  single_nat_gateway = true

  tags = local.tags
}

module "image_builder" {
  source = "../../modules/image-builder"

  name_prefix       = "devbox-${local.environment}"
  environment       = local.environment
  egress_vpc_id     = module.egress.vpc_id
  egress_subnet_ids = module.egress.private_subnets

  component_files = {
    "01-base-updates" = {
      file    = "01-base-updates.yml"
      version = "1.0.0"
      order   = 1
    }
    "02-dev-tools" = {
      file    = "02-dev-tools.yml"
      version = "1.0.0"
      order   = 2
    }
    "03-language-runtimes" = {
      file    = "03-language-runtimes.yml"
      version = "1.0.0"
      order   = 3
    }
    "04-container-tooling" = {
      file    = "04-container-tooling.yml"
      version = "1.0.0"
      order   = 4
    }
    "05-agent-dependencies" = {
      file    = "05-agent-dependencies.yml"
      version = "1.0.0"
      order   = 5
    }
    "06-repo-cloning" = {
      file    = "06-repo-cloning.yml"
      version = "1.0.0"
      order   = 6
    }
    "07-warmup-daemon" = {
      file    = "07-warmup-daemon.yml"
      version = "1.0.0"
      order   = 7
    }
    "08-ssh-config" = {
      file    = "08-ssh-config.yml"
      version = "1.0.0"
      order   = 8
    }
    "09-security-hardening" = {
      file    = "09-security-hardening.yml"
      version = "1.0.0"
      order   = 9
    }
    "99-validation" = {
      file    = "99-validation.yml"
      version = "1.0.0"
      order   = 99
    }
  }

  tags = local.tags
}
