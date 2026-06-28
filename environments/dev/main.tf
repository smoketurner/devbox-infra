module "vpc" {
  source = "../../modules/vpc"

  name = "devbox-${local.environment}"
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
}

module "image_builder" {
  source = "../../modules/image-builder"

  name_prefix      = "devbox-${local.environment}"
  build_vpc_id     = module.vpc.vpc_id
  build_subnet_ids = module.vpc.private_subnets

  component_files = [
    "01-base.yml",
    "02-toolchain.yml",
    "03-repos.yml",
    "04-agents.yml",
    "04-devbox.yml.tftpl",
    "04-ssh.yml",
    "05-docker-images.yml.tftpl",
  ]

  # The warming agent (and the test-stage warm-up) request repo-scoped GitHub
  # tokens from the control plane, authenticated by the instance's AWS identity.
  control_plane_url = "https://${var.domain_name}"

  # The test stage exercises the real /workspace mount + warm-up against the booted
  # AMI. The snapshot param is passed by literal name (not
  # module.snapshot_builder.ssm_parameter_name) because snapshot_builder already
  # depends on this module — a module reference here would be a dependency cycle.
  workspace_snapshot_param = "/devbox/workspace-snapshot/latest"

  # Base images pre-pulled into the AMI's /var/lib/docker so first container use is
  # warm. Sizing: the recipe root volume (and pool ebs_volume_size) must hold these.
  docker_images = var.docker_images

  tags = local.common_tags
}

# Periodically builds an encrypted /workspace EBS snapshot (repos cloned near-HEAD,
# source-only) from the golden AMI and publishes its id to SSM. The pool attaches
# it as a second volume; the warming agent fetches the delta to HEAD.
module "snapshot_builder" {
  source = "../../modules/snapshot-builder"

  name_prefix      = "devbox-${local.environment}"
  build_vpc_id     = module.vpc.vpc_id
  build_subnet_ids = module.vpc.private_subnets

  # Build from the same golden AMI the pool runs, so warmed caches match the
  # toolchain (orders after the AMI parameter exists). The automation role needs
  # the AMI's CMK to launch the builder from that encrypted image.
  ami_parameter   = module.image_builder.ssm_parameter_name
  ami_kms_key_arn = module.image_builder.kms_key_arn

  repos = var.workspace_repos

  # The builder's agent requests repo-scoped tokens from the control plane.
  control_plane_url = "https://${var.domain_name}"

  tags = local.common_tags
}

module "pool" {
  source = "../../modules/pool"

  name_prefix = "devbox-${local.environment}"
  pool_id     = "default"

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = []

  instance_type = "t4g.small"

  # Root volume must be >= the AMI's root snapshot, which is 100GB to hold the
  # pre-pulled Docker images (see image_builder recipe volume_size).
  ebs_volume_size = 100

  # Cap the pool: the reconciler sets desired_capacity to
  # min(claimed + POOL_TARGET_WARM_SIZE, max_size). With POOL_TARGET_WARM_SIZE=2,
  # max_size = 1 holds a single warm instance.
  max_size = 1

  # Consume the parameter name from image-builder so Terraform orders the
  # parameter's creation before the launch template's resolve:ssm reference.
  ssm_ami_parameter = module.image_builder.ssm_parameter_name

  # The pool auto-attaches the workspace snapshot as a second volume once the
  # snapshot-builder has published a real snapshot id (until then the parameter is
  # the "none" placeholder and instances launch with /workspace on the root volume).
  # A new snapshot id enters the Launch Template on the next apply; if the volume
  # fails to attach at runtime, the box falls back to /workspace on root (cold).
  workspace_snapshot_ssm_parameter = module.snapshot_builder.ssm_parameter_name

  tags = local.common_tags
}

# Dedicated control-plane VPC: a single dual-stack public subnet with an internet
# gateway. The ECS tasks run here with public IPs (direct egress to DSQL's public
# endpoint and ECR), fronted by a dual-stack NLB. Kept separate from the egress
# VPC, whose proxy/NAT is built for 443-only controlled egress and black-holes the
# DSQL 5432 path.
module "control_plane_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = "devbox-${local.environment}-control-plane"
  cidr = local.cp_vpc_cidr

  azs            = [local.azs[0]]
  public_subnets = local.cp_public_subnets

  enable_nat_gateway      = false
  enable_dns_hostnames    = true
  enable_dns_support      = true
  map_public_ip_on_launch = true

  # Dual-stack so the NLB can serve IPv6 clients. The module assigns the VPC an
  # Amazon /56, carves a /64 for the public subnet, and routes ::/0 to the IGW.
  enable_ipv6                                   = true
  public_subnet_assign_ipv6_address_on_creation = true
  public_subnet_ipv6_prefixes                   = range(length(local.cp_public_subnets))
}

# Control plane: Aurora DSQL + devbox-server on ECS/Fargate. The tasks run in the
# control-plane VPC's public subnet with public IPs and reach DSQL's public
# endpoint directly; an internet-facing NLB (static EIP + TLS) fronts them.
module "control_plane" {
  source = "../../modules/control-plane"

  name_prefix = "devbox-${local.environment}"

  vpc_id             = module.control_plane_vpc.vpc_id
  subnet_ids         = module.control_plane_vpc.public_subnets
  ingress_cidrs      = ["0.0.0.0/0"]
  ingress_ipv6_cidrs = ["::/0"]

  pool_id = "default"

  # Single task in dev. A second task wouldn't double-reconcile — each tick gates
  # on a TTL lock row in DSQL, so only one instance ever acts — it only added
  # API/UI redundancy we don't need here.
  desired_count = 1

  # Terraform issues the ACM cert and Route 53 alias for this hostname.
  domain_name     = var.domain_name
  route53_zone_id = aws_route53_zone.devbox_farm.zone_id

  # GitHub Actions pushes images + deploys via this OIDC-federated role.
  github_repository = "smoketurner/devbox"

  # OIDC endpoints default to Vouch. The confidential dashboard app (redirect URI
  # https://<domain_name>/oauth2/idpresponse) drives the app-side login flow.
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret

  # Server-owned GitHub App token minting: the task role reads the key from SSM and
  # mints repo-scoped tokens for agents authenticated by their AWS web-identity.
  github_app_id             = var.github_app_id
  github_app_key_param_name = aws_ssm_parameter.github_app_private_key.name
  github_app_key_param_arn  = aws_ssm_parameter.github_app_private_key.arn

  # Agents mint web-identity tokens for this audience (= the boxes' DEVBOX_SERVER_URL),
  # and the server trusts these pool/builder role ARNs as agent callers.
  agent_audience = "https://${var.domain_name}"
  pool_role_arns = [module.pool.host_role_arn]
  builder_role_arns = [
    module.snapshot_builder.builder_instance_role_arn,
    module.image_builder.build_instance_role_arn,
  ]
}
